# Goose observability dashboards

Two Dynatrace dashboards for the Goose fleet, stored as **dtctl document YAML**
(the format produced by `dtctl get dashboard <id> -o yaml`). They are the source
of truth — edit the YAML, then re-apply.

| File | What it shows |
|------|---------------|
| [`goose-engine-health.yaml`](goose-engine-health.yaml) | Fleet KPIs: token flow, session duration, tool-call health (`goose.tool_completions / goose.tool_calls`), session throughput, and pod CPU/memory. *"Is the engine healthy and how hard is it working?"* |
| [`goose-agent-efficiency.yaml`](goose-agent-efficiency.yaml) | Per-agent economics via `gen_ai.agent.name` joined to token/tool spans by `trace.id`: tokens per agent, tool hot/cold ranking, and a per-agent scorecard. *"Who spends the tokens, and which tools/models dominate?"* |

## Deploy

Install [`dtctl`](https://github.com/dynatrace/dtctl) and select a context with
document write scope for your environment, then:

```bash
dtctl apply -f dashboards/goose-engine-health.yaml
dtctl apply -f dashboards/goose-agent-efficiency.yaml
```

Or deploy both at once with the tutorial script:

```bash
scripts/07-apply-dashboards.sh          # uses your current dtctl context
DTCTL_CONTEXT=my-tenant scripts/07-apply-dashboards.sh
```

The files carry **no `id` field**, so `dtctl apply` CREATEs a fresh dashboard
with an auto-generated ID on whatever tenant your context points at. To update a
dashboard in place instead, re-export it with `dtctl get dashboard <id> -o yaml`
(that export keeps the `id`) and apply that.

## Requirements

The tiles query telemetry produced by the Goose OTel collector pipeline
(see [`../docs/observability.md`](../docs/observability.md)):

- **traces** — `gen_ai.*` spans (agent name, model, token usage, operation name)
- **metrics** — `goose.*` counters (`session_tokens`, `tool_calls`,
  `tool_completions`, `session_completions`, `session_duration_ms`)
- **pod metrics** — `dt.kubernetes.container.cpu_usage` /
  `dt.kubernetes.container.memory_working_set`, filtered to the `goose` and
  `goosetown` namespaces

All tiles default to a `now()-7d` window.
