#!/usr/bin/env bash
# Enable the Dynatrace + GitHub MCP extensions and demo each recipe.
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env DT_ENVIRONMENT_URL DT_MCP_TOKEN GITHUB_TOKEN
POD="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=goose -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || die "no goose pod found — run: make deploy-goose"
log "Demo: Dynatrace MCP recipe…"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/02-dynatrace-mcp.yaml \
    --params question="List any open problems in the last 2 hours."
log "Demo: GitHub MCP recipe…"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/03-github-mcp.yaml \
    --params repo="${DEMO_REPO:-isItObservable/Goose}" task="Summarise the open issues."
log "MCPs wired. Continue with: make crew"
