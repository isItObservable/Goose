# Dynatrace Operator

We install the [Dynatrace Operator](https://github.com/Dynatrace/dynatrace-operator)
and a **scoped DynaKube** — Kubernetes monitoring + the API/ingest routing we
need for OTLP, but **no full-stack OneAgent**. The goal is to observe the *agent*,
and the OTLP path plus Kubernetes monitoring is sufficient.

## Install (Helm)

```bash
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update

helm upgrade --install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace --create-namespace \
  --atomic
```

## Create the tokens secret

The DynaKube reads its tokens from a Secret named after it (`goose-dynakube`).
Create it from your `.env` values:

```bash
kubectl -n dynatrace create secret generic goose-dynakube \
  --from-literal=apiToken="${DT_API_TOKEN}" \
  --from-literal=dataIngestToken="${DT_INGEST_TOKEN}"
```

## Apply the DynaKube

```bash
envsubst < k8s/operators/dynakube.yaml | kubectl apply -f -
```

(`scripts/01-install-operators.sh` does all of the above for you.)

## Verify

```bash
kubectl -n dynatrace get dynakube
kubectl -n dynatrace rollout status deploy/dynatrace-operator
```

Wait for the DynaKube to report `Running` before deploying Goose.
