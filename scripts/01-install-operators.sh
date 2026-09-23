#!/usr/bin/env bash
# Install the OpenTelemetry Operator and the Dynatrace Operator + scoped DynaKube.
source "$(dirname "$0")/lib/common.sh"
need kubectl; need helm; need envsubst
require_env DT_ENVIRONMENT_URL DT_API_TOKEN DT_INGEST_TOKEN

log "Installing cert-manager (webhook TLS for the OTel Operator)…"
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set crds.enabled=true --wait

log "Installing the OpenTelemetry Operator (contrib collector image)…"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system --create-namespace \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib" --wait

log "Installing the Dynatrace Operator…"
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable >/dev/null 2>&1 || true
helm repo update >/dev/null
helm upgrade --install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace --create-namespace --atomic

log "Creating the DynaKube tokens secret…"
kubectl -n dynatrace create secret generic goose-dynakube \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --from-literal=dataIngestToken="${DT_INGEST_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -

log "Applying the scoped DynaKube…"
envsubst < "${REPO_ROOT}/k8s/operators/dynakube.yaml" | kubectl apply -f -

log "Operators installed. Continue with: make deploy-collector"
