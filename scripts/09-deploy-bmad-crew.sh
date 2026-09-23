#!/usr/bin/env bash
# Deploy the BMAD crew over ACP: one Deployment + Service per role, then launch
# the Conductor (the ACP client) with a goal.
#
# This is the DEPLOYED, multi-agent form of the crew. The in-process form
# (recipes/04-bmad-crew.yaml via `make crew`) remains the working default; this
# script is the ACP upgrade path. See README §7.
#
#   make bmad-crew-acp                       # default goal
#   ./scripts/09-deploy-bmad-crew.sh "Your goal here"
#
# Assumes `make deploy-goose` already ran (it created the goose-secrets Secret
# and the goose-config / goose-recipes ConfigMaps that these pods reuse).
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env OLLAMA_BASE_URL OLLAMA_MODEL

GOAL="${1:-Add a /healthz endpoint to the sample service and open a PR.}"
ROLES=(conductor researcher planner executor reviewer)

log "Ensuring namespace '${NAMESPACE}'…"
kubectl apply -f "${REPO_ROOT}/k8s/namespace.yaml"

# The crew pods mount the goose-recipes ConfigMap; refresh it so recipes/bmad/
# is present even if deploy-goose ran before these recipes existed.
log "Refreshing the goose-recipes ConfigMap (includes recipes/bmad/)…"
kubectl -n "${NAMESPACE}" create configmap goose-recipes \
  --from-file="${REPO_ROOT}/recipes/" \
  --from-file="${REPO_ROOT}/recipes/bmad/" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying the per-role Deployments + Services…"
for role in "${ROLES[@]}"; do
  kubectl apply -f "${REPO_ROOT}/k8s/goose/bmad/${role}.yaml"
done

log "Waiting for the crew to be ready…"
for role in "${ROLES[@]}"; do
  kubectl -n "${NAMESPACE}" rollout status "deploy/goose-${role}" --timeout=120s || \
    warn "goose-${role} not ready yet — check: kubectl -n ${NAMESPACE} logs deploy/goose-${role}"
done

log "Launching the crew via the Conductor (goal: ${GOAL})…"
POD="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=goose-conductor -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || die "no goose-conductor pod found — check the rollout above"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/bmad/conductor.yaml --params goal="${GOAL}"

log "Crew launched. Watch the agent-efficiency dashboard: each role appears as"
log "its own service (goose-conductor → goose-researcher → …) in ONE trace."
