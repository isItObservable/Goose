#!/usr/bin/env bash
# Run the goosetown BMAD-style crew.
source "$(dirname "$0")/lib/common.sh"
need kubectl
GOAL="${1:-Add a /healthz endpoint to the sample service and open a PR.}"
POD="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=goose -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || die "no goose pod found — run: make deploy-goose"
log "Launching the crew (goal: ${GOAL})…"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/04-bmad-crew.yaml --params goal="${GOAL}"
log "Crew finished. Watch the agent-efficiency dashboard for the span tree."
