#!/usr/bin/env bash
# Deploy the OTLP secret + the two collectors (logs DaemonSet + gateway StatefulSet).
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env DT_ENVIRONMENT_URL DT_INGEST_TOKEN

log "Ensuring namespace '${NAMESPACE}'…"
kubectl apply -f "${REPO_ROOT}/k8s/namespace.yaml"

log "Creating the collector Secret (goose-otel)…"
kubectl -n "${NAMESPACE}" create secret generic goose-otel \
  --from-literal=DT_ENVIRONMENT_URL="${DT_ENVIRONMENT_URL}" \
  --from-literal=DT_INGEST_TOKEN="${DT_INGEST_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying RBAC for the logs collector…"
kubectl apply -f "${REPO_ROOT}/k8s/collector/rbac.yaml"

log "Applying the collectors…"
kubectl apply -f "${REPO_ROOT}/k8s/collector/otel-collector-gateway.yaml"
kubectl apply -f "${REPO_ROOT}/k8s/collector/otel-collector-logs.yaml"

log "Waiting for the gateway to be ready…"
kubectl -n "${NAMESPACE}" rollout status statefulset/otel-gateway-collector --timeout=120s || \
  warn "gateway not ready yet — check: kubectl -n ${NAMESPACE} get opentelemetrycollector"

log "Collectors deployed. Continue with: make deploy-goose"
