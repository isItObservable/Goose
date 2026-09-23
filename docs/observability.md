# Observing Goose with OpenTelemetry & Dynatrace

Goose emits **native OpenTelemetry** — traces and metrics — with **no code
changes**. You turn it on with the standard `OTEL_*` environment variables, point
it at a collector, and the signals flow. This document is the deep-dive: how the
signals are shaped, how we collect and clean them, the three gotchas, and how the
two dashboards are built.

> Pin note: signals in this tutorial were verified against **Goose v1.46.0**.
> Attribute and metric names can shift between versions — re-check against your
> pinned version if a dashboard tile comes up empty.

---

## 1. Turning telemetry on

The Goose deployment (`k8s/goose/deployment.yaml`) carries this env block:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-gateway-collector.goose.svc.cluster.local:4318"
- name: OTEL_EXPORTER_OTLP_PROTOCOL
  value: "http/protobuf"
- name: OTEL_SERVICE_NAME
  value: "goose"
```

That's it. No SDK, no wrapper, no instrumentation library.

### ⚠️ Gotcha 1 — OTLP/HTTP only, port 4318 (never 4317)

Goose has **no gRPC exporter**. The endpoint above is the collector's
**HTTP** receiver on `4318`, and the protocol is `http/protobuf`. If you point
Goose at `4317` (gRPC) you will get **silence** — no error that's obvious, just no
data. Every collector receiver in this repo listens on `4318` for exactly this
reason.

### ⚠️ Gotcha 2 — `GOOSE_TELEMETRY_ENABLED` ≠ OpenTelemetry

There is a separate flag, `GOOSE_TELEMETRY_ENABLED`, that controls Goose's
**product analytics** (anonymous usage stats sent to the project). It has
**nothing** to do with your OTLP pipeline. Setting it does not send traces to
your collector; unsetting it does not stop them. Your OTLP data is governed
entirely by the `OTEL_*` variables above. (The CrewAI episode hit the identical
trap with CrewAI's "native telemetry" — same lesson.)

---

## 2. The collection tier

Two collectors, both declared as `OpenTelemetryCollector` CRs and managed by the
OpenTelemetry Operator.

### Gateway collector — `StatefulSet` (traces + metrics)

`k8s/collector/otel-collector-gateway.yaml`. Pipeline:

```
receivers:  otlp (http :4318)
processors: transform/redact  →  cumulativetodelta  →  batch
exporters:  otlphttp (Dynatrace)
```

- **`otlp` receiver, HTTP 4318** — the endpoint Goose exports to.
- **`transform/redact`** — drops prompt-carrying attributes (see Gotcha 3).
- **`cumulativetodelta`** — Goose emits cumulative sums (and no histograms).
  Dynatrace/Grail charts delta metrics cleanly, so we convert. Same pattern used
  in the Kagent and CrewAI episodes.
- **`otlphttp` exporter** — forwards to Dynatrace using the environment URL +
  ingest token (from the DynaKube's `dynatrace-api` / `metrics-ingest`).

A `StatefulSet` (not a `Deployment`) gives the gateway a stable identity and a
durable sending queue on the ingest path.

### ⚠️ Gotcha 3 — redact prompt content before export

Goose spans can carry raw prompt text in attributes such as `user_message`,
`trace_input`, and `input`. You do **not** want that in your observability
backend. The gateway drops them **before** export:

```yaml
processors:
  transform/redact:
    error_mode: ignore
    trace_statements:
      - context: span
        statements:
          - delete_key(attributes, "user_message")
          - delete_key(attributes, "trace_input")
          - delete_key(attributes, "input")
```

This mirrors the Kagent episode's leaked-token fix: never export whole
user/model content; strip it at the collector.

### Logs collector — `DaemonSet` (pod logs)

`k8s/collector/otel-collector-logs.yaml`. A `filelog` receiver tails
`/var/log/pods/**` on every node, enriches with Kubernetes attributes, and
exports to Dynatrace via `otlphttp`. `DaemonSet` mode = one collector per node.

---

## 3. The signals Goose emits

### Metrics (cumulative sums — no histograms)

| Metric | Meaning |
|---|---|
| `goose.session_tokens` | Context size of the **final** call in a session (not total tokens consumed). |
| `goose.session_duration_ms` | Wall-clock duration of a session. |
| `goose.tool_calls` | Number of tool invocations. |
| `goose.tool_completions` | Number of tool invocations that completed. |
| `goose.session_completions` | Number of sessions completed. |

> **No p95 from Goose directly.** Because Goose emits sums and not histograms,
> you cannot get a percentile latency straight from its metrics. If you need
> percentiles, derive them from span durations (below) or compute them in the
> backend from raw spans.

### Traces (the gen_ai span tree)

Goose emits a `gen_ai` span hierarchy:

```
invoke_agent
└── chat
    └── execute_tool
```

Key attributes carried on these spans:

- `gen_ai.operation.name` — e.g. `chat`, `execute_tool`.
- `gen_ai.request.model` — the model used (e.g. your Ollama model).
- `gen_ai.conversation.id` — ties the spans of one session together.

These give you per-tool latency, which model handled a step, and the flow of a
session — the raw material for the **agent-efficiency** dashboard.

---

## 4. The two dashboards

Both live in [`../dashboards/`](../dashboards/) as Dynatrace dashboard JSON and
are published by `scripts/07-apply-dashboards.sh`.

### `goose-engine-health.json`

Built from the metrics above: token usage, session duration, tool-call vs
tool-completion counts, session throughput. Answers *"is the engine healthy and
how hard is it working?"*

### `goose-agent-efficiency.json`

Built from the `gen_ai` span tree: per-tool latency, model attribution, and
session flow via `gen_ai.conversation.id`. Answers *"where is the agent spending
time, and which tools/models dominate?"*

---

## 5. Verifying the pipeline

```bash
# collectors healthy?
kubectl -n "$NAMESPACE" get opentelemetrycollector
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=otel-gateway-collector

# gateway receiving? (watch for accepted spans/metrics)
kubectl -n "$NAMESPACE" logs statefulset/otel-gateway-collector | grep -i -E "accepted|refused"

# run a session, then confirm data in Dynatrace
goose run --recipe recipes/01-simple-agent.yaml
```

If a session runs but Dynatrace shows nothing, walk the three gotchas in order:
wrong port (4317 vs 4318), wrong flag (`GOOSE_TELEMETRY_ENABLED` instead of
`OTEL_*`), or a receiver/exporter misconfig in the gateway.
