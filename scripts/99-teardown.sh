#!/usr/bin/env bash
# Remove the crew, Goose, collectors and namespace. Leaves the operators.
source "$(dirname "$0")/lib/common.sh"
need kubectl
log "Deleting Goose + collectors in namespace '${NAMESPACE}'…"
# ACP BMAD crew (per-role Deployments + Services), if it was deployed.
for role in conductor researcher planner executor reviewer; do
  kubectl delete -f "${REPO_ROOT}/k8s/goose/bmad/${role}.yaml" --ignore-not-found
done
kubectl delete -f "${REPO_ROOT}/k8s/goose/deployment.yaml" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/k8s/collector/otel-collector-gateway.yaml" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/k8s/collector/otel-collector-logs.yaml" --ignore-not-found
kubectl delete -f "${REPO_ROOT}/k8s/collector/rbac.yaml" --ignore-not-found
kubectl -n "${NAMESPACE}" delete configmap goose-config goose-recipes --ignore-not-found
kubectl -n "${NAMESPACE}" delete secret goose-secrets goose-otel --ignore-not-found
kubectl delete namespace "${NAMESPACE}" --ignore-not-found
log "Teardown complete. To remove operators: helm uninstall them in their namespaces."
