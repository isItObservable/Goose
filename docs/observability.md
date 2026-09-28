# Observing Goose with OpenTelemetry & Dynatrace

Goose emits **native OpenTelemetry** — traces and metrics — with **no code
changes**. You turn it on with the standard `OTEL_*` environment variables, point
it at a collector, and the signals flow. This document is the deep-dive: how the
signals are shaped, how we collect and clean them, the three gotchas, and how the
two dashboards are built.

> Pin note: signals in this tutorial were verified against **Goose v1.52.0**
> (`ghcr.io/aaif-goose/goose:latest`). The originally-pinned
> `ghcr.io/block/goose:1.46.0` does **not exist** (404) — the image moved to the
> `aaif-goose` org, and the last version tag (`1.37`) **panics on OTLP export**
> (goose#9494: BatchSpanProcessor has no Tokio reactor). Attribute and metric
> names can shift between versions — re-check against your pinned version if a
> dashboard tile comes up empty.

---

## 1. Turning telemetry on

The Goose deployment (`k8s/goose/deployment.yaml`) carries this env block:

```yaml
- name: OTEL_EXPORTER_OTLP_ENDPOINT
  value: "http://otel-gateway-collector.observability.svc.cluster.local:4318"
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
| `goose.session_starts` | Number of sessions started (emitted at session open). |
| `goose.cli_commands` | Number of CLI commands invoked (emitted at invocation). |

> **No p95 from Goose directly.** Because Goose emits sums and not histograms,
> you cannot get a percentile latency straight from its metrics. If you need
> percentiles, derive them from span durations (below) or compute them in the
> backend from raw spans.

> ⚠️ **Why the metrics can look "absent" (verified live).** All `goose.*` metrics
> are **session-scoped monotonic counters** emitted via `tracing`'s
> `monotonic_counter` field syntax, and each fires on a *specific* code path:
>
> - `goose.session_starts` + `goose.cli_commands` — emitted **at session open /
>   command invocation** (`crates/goose-cli/src/cli.rs`).
> - `goose.session_completions` / `session_duration_ms` / `session_tokens` —
>   emitted **only at session completion** (`log_session_completion`), and
>   `session_tokens` additionally only when `total_tokens > 0` (the LLM must
>   report usage).
> - `goose.tool_calls` / `tool_completions` — emitted **only when tools are
>   actually invoked**.
>
> Consequence: an **idle `goose serve`** (no ACP clients connected, no sessions
> run) emits **none** of these — the `cumulativetodelta` collector processor is
> *not* the culprit (verified: counters like `cli_commands`/`session_starts` flow
> straight through to Grail). The engine-health tiles stay empty until a real
> session runs to completion (and uses tools). For a demo, drive at least one
> full session with a tool call; the counters will appear.

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

---

## 6. Per-role breakdown & the ACP trace-continuity check

The ACP-deployed BMAD crew (`recipes/bmad/` + `k8s/goose/bmad/`) runs each role
as its own Goose agent with its own `OTEL_SERVICE_NAME` — `goose-conductor`,
`goose-researcher`, `goose-planner`, `goose-executor`, `goose-reviewer` — which
arrives on every span as the `service.name` resource attribute. The
**agent-efficiency** dashboard surfaces this two ways:

- a **`service`** dashboard variable and a **"p95 span duration by role"** tile,
  so each crew role is independently visible; and
- a **"Trace composition — roles per trace"** tile:

  ```
  fetch spans
  | filter isNotNull(trace.id) and isNotNull(service.name)
  | summarize roles = collectDistinct(service.name), spans = count(), by:{ trace.id }
  | fieldsAdd role_count = arraySize(roles)
  | sort role_count desc, spans desc
  ```

  This is the single-trace check. If the Conductor forwards the W3C
  `traceparent` across each ACP hop, one crew run is **one** distributed trace and
  the tile shows a `trace.id` with `role_count > 1` (all five roles under one
  trace). If it does not, each role is its own trace and every `role_count == 1`.

### ⚠️ Gotcha 4 — Goose v1.52.0 ships ACP-over-HTTP/WS, but still does NOT forward `traceparent`

Re-verified against **Goose v1.52.0** (`ghcr.io/aaif-goose/goose:latest`) by
reading the shipped source. The old "stdio-only" verdict is half-stale; the
`traceparent` verdict is unchanged and now backed by source evidence:

1. **Network ACP dispatch — NOW SHIPS.** `goose serve` starts an ACP agent
   server over **HTTP and WebSocket** (`--host`/`--port`, default
   `127.0.0.1:3284`; `--dangerously-unauthenticated` or `GOOSE_SERVER__SECRET_KEY`
   for auth). This is the endpoint the `k8s/goose/bmad/` Services (`ACP_*_URL`)
   assume. (The old `goose acp` subcommand still exists and remains stdio-only;
   `goose serve` is the network path.)
2. **`traceparent` forwarding — STILL MISSING.** Goose registers the W3C
   propagator (`crates/goose/src/otel/otlp.rs`: `global::set_text_map_propagator(TraceContextPropagator::new())`),
   but the ACP transport never applies it. `crates/goose/src/acp/transport/mod.rs`
   builds the server from plain `axum` + `tower_http::cors`, and the client side
   uses the external `agent_client_protocol_http` (rmcp) crate — there is **no
   `opentelemetry_http` instrumentation, no `tower-http` `TraceLayer`, and no
   `inject()`/`extract()` of trace context** anywhere in the codebase (zero hits
   for `traceparent`, `trace_context`, or `opentelemetry_http`). The Conductor
   therefore does **not** inject `traceparent` (or the ACP
   [meta-propagation RFD](https://agentclientprotocol.com/rfds/meta-propagation)'s
   `_meta.traceparent`) into dispatches, and the role server does not extract one.

**Verdict:** the README §7 fallback stance holds. Each ACP role is its own
`service.name` but remains its own trace — the *Trace composition* tile shows
`role_count == 1`, never `5`. Keep the in-process `make crew`
(`recipes/04-bmad-crew.yaml`) as the working default. The ACP form is unblocked
only when Goose wires the OTel propagator into the ACP HTTP transport (or injects
`_meta.traceparent` client-side). Until then there is no "works from" version for
a single distributed trace across a network ACP hop, and no dashboard change is
needed — the tile flips `role_count == 1` → `5` automatically when it lands.

> ⚠️ **Manifest note:** `k8s/goose/bmad/` was authored against v1.46.0 and must be
> updated for v1.52.0 — image `ghcr.io/aaif-goose/goose:latest`, command
> `goose serve --host 0.0.0.0 --port 4000` (not `goose acp`), plus
> `GOOSE_SERVER__SECRET_KEY`. See `k8s/goose/bmad/`.

### ⚠️ Gotcha 5 — the goosetown UI crew is one `service.name`; per-role split is by session, not service

The Goose Town map crew (`recipes/04-bmad-crew.yaml`, driven from the chat UI)
is the **in-process** BMAD crew: the Conductor spawns the five
delegates via `sub_recipes` / the summon `delegate` tool. Verified against
**Goose v1.52.0** by reading the source: subagents run as in-process `tokio`
tasks (`crates/goose/src/agents/subagent_handler.rs`), and the OTel `Resource`
— including `service.name` — is built **once at process start** from a single
`OTEL_SERVICE_NAME` (`crates/goose/src/otel/otlp.rs::create_resource`, default
`"goose"`). There is no per-subagent resource.

**Consequence:** you **cannot** give each in-process delegate its own
`OTEL_SERVICE_NAME`. All five BMAD delegates spawned by the chat crew share the
pod's `service.name` (`goose-goosetown`). So on the map/chat path, per-role
breakdown is by **session / delegate name** (`bmad-analyst`, `bmad-pm`,
`bmad-architect`, `bmad-dev`, `bmad-qa` — which is also what lights the geese on
the map, via `inferRole`), **not** by `service.name`.

**If you need true per-role `service.name`** (e.g. to drive the agent-efficiency
`service` variable and "p95 by role" tile in §6), run the **ACP crew** instead
(`recipes/bmad/conductor.yaml` + `k8s/goose/bmad/`): each role is a separate
Goose process with its own `OTEL_SERVICE_NAME`. That crew is board-run and
write-capable; the goosetown UI crew is intentionally read-only and optimised for
the live map demo, not for per-service dashboards. Same trade as Gotcha 4:
in-process is the working default; the per-service form needs separate processes.
