#!/usr/bin/env bash
# Run the simple single-recipe agent inside the Goose pod.
source "$(dirname "$0")/lib/common.sh"
need kubectl
TOPIC="${1:-OpenTelemetry}"
POD="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=goose -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || die "no goose pod found — run: make deploy-goose"
log "Running recipe 01-simple-agent.yaml (topic=${TOPIC})…"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/01-simple-agent.yaml --params topic="${TOPIC}"
log "Done. Check the gateway + Dynatrace for spans/metrics."
