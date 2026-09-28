# OpenTelemetry Operator

We deploy collectors as `OpenTelemetryCollector` custom resources and let the
[OpenTelemetry Operator](https://github.com/open-telemetry/opentelemetry-operator)
manage the underlying `DaemonSet` / `StatefulSet` workloads.

## Install (Helm)

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

helm upgrade --install opentelemetry-operator \
  open-telemetry/opentelemetry-operator \
  --namespace opentelemetry-operator-system --create-namespace \
  --set "manager.collectorImage.repository=otel/opentelemetry-collector-contrib"
```

> We set the collector image to **contrib** because our collectors use the
> `filelog`, `cumulativetodelta`, and `transform` components, which live in the
> contrib distribution.

The Operator needs cert-manager (its default webhook TLS source). If you don't
have it:

```bash
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true
```

## Verify

```bash
kubectl -n opentelemetry-operator-system rollout status deploy/opentelemetry-operator
```

Once the Operator is `Available`, apply the collectors in
[`../collector/`](../collector/) (or run `make deploy-collector`).
