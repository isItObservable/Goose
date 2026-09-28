#!/usr/bin/env bash
# Deploy goosetown (orchestration + dashboard) in its own namespace.
# The image (ghcr.io/isitobservable/goosetown) is built by
# .github/workflows/build-goosetown-image.yaml on push.
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env OLLAMA_BASE_URL OLLAMA_MODEL

GT_NS="${GOOSETOWN_NAMESPACE:-goosetown}"

log "Ensuring namespace '${GT_NS}'…"
kubectl get ns "${GT_NS}" >/dev/null 2>&1 || kubectl create ns "${GT_NS}"

log "Copying goose-secrets into '${GT_NS}' (Ollama creds)…"
kubectl -n "${NAMESPACE}" get secret goose-secrets -o yaml 2>/dev/null \
  | sed "s/namespace: ${NAMESPACE}/namespace: ${GT_NS}/" \
  | kubectl apply -f - || warn "could not copy goose-secrets — create it in ${GT_NS} manually"

log "Creating the recipes ConfigMap (hot-reloadable, no image rebuild)…"
kubectl -n "${GT_NS}" create configmap goosetown-recipes \
  --from-file=01-simple-agent.yaml="${REPO_ROOT}/recipes/01-simple-agent.yaml" \
  --from-file=02-dynatrace-mcp.yaml="${REPO_ROOT}/recipes/02-dynatrace-mcp.yaml" \
  --from-file=03-github-mcp.yaml="${REPO_ROOT}/recipes/03-github-mcp.yaml" \
  --from-file=04-bmad-crew.yaml="${REPO_ROOT}/recipes/04-bmad-crew.yaml" \
  --from-file=05-pr-review.yaml="${REPO_ROOT}/recipes/05-pr-review.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying the goosetown deployment + service…"
kubectl apply -f "${REPO_ROOT}/k8s/goosetown/deployment.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/goosetown/service.yaml"

kubectl -n "${GT_NS}" rollout status deploy/goosetown --timeout=120s || \
  warn "goosetown not ready yet — check: kubectl -n ${GT_NS} logs deploy/goosetown"

log "Goosetown dashboard: kubectl -n ${GT_NS} get svc goosetown-ui"
log "Launch the orchestrator:  kubectl -n ${GT_NS} exec -it deploy/goosetown -- goose session"
