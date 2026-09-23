#!/usr/bin/env bash
# Deploy Goose: namespace + secrets + config/recipes ConfigMaps + deployment.
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env OLLAMA_BASE_URL OLLAMA_MODEL DT_ENVIRONMENT_URL

log "Ensuring namespace '${NAMESPACE}'…"
kubectl apply -f "${REPO_ROOT}/k8s/namespace.yaml"

log "Creating the Goose Secret (goose-secrets)…"
kubectl -n "${NAMESPACE}" create secret generic goose-secrets \
  --from-literal=OLLAMA_BASE_URL="${OLLAMA_BASE_URL}" \
  --from-literal=OLLAMA_MODEL="${OLLAMA_MODEL}" \
  --from-literal=GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
  --from-literal=DT_ENVIRONMENT_URL="${DT_ENVIRONMENT_URL}" \
  --from-literal=DT_MCP_TOKEN="${DT_MCP_TOKEN:-}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Creating config + recipes ConfigMaps from the repo…"
kubectl -n "${NAMESPACE}" create configmap goose-config \
  --from-file=config.yaml="${REPO_ROOT}/config/goose-config.yaml" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${NAMESPACE}" create configmap goose-recipes \
  --from-file="${REPO_ROOT}/recipes/" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying the Goose deployment…"
kubectl apply -f "${REPO_ROOT}/k8s/goose/deployment.yaml"
kubectl -n "${NAMESPACE}" rollout status deploy/goose --timeout=120s || \
  warn "goose not ready yet — check: kubectl -n ${NAMESPACE} logs deploy/goose"

log "Goose deployed. Continue with: make simple-agent"
