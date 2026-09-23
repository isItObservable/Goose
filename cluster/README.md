# Provision a cluster

This tutorial runs on **any** conformant Kubernetes cluster. Pick whatever fits
your environment — you only need `kubectl` pointed at a cluster and enough
capacity to run Goose, two collectors, and the operators.

## Option A — local (fastest to try)

```bash
# kind
kind create cluster --name goose

# …or k3s / k3d / minikube — all work
```

Good for kicking the tyres. Note that your Ollama host must still be reachable
from inside the cluster (for kind/k3d that usually means using your machine's LAN
IP in `OLLAMA_BASE_URL`, not `localhost`).

## Option B — managed (EKS / GKE / AKS)

Provision with your usual tooling (`eksctl`, `gcloud`, `az`), then point
`kubectl` at it. Everything else in this repo is portable.

## Option C — self-hosted with Cluster API (Proxmox, vSphere, bare metal)

If you run your own virtualisation, [Cluster API](https://cluster-api.sigs.k8s.io/)
gives you declarative, reproducible clusters. The high-level flow:

1. **Carve non-overlapping IP ranges** for the control-plane VIP, the worker
   pool, a load-balancer pool (e.g. MetalLB), and any DHCP reserve. See
   [`values.env.example`](values.env.example) for the shape — fill in ranges that
   fit **your** network.
2. **Render** your infrastructure provider's manifests from those values.
3. **Apply** them to a management cluster and let the provider create the
   workload cluster.
4. **Pull the kubeconfig** and point `kubectl` at the new cluster.

The specifics depend on your infrastructure provider (CAPMOX for Proxmox, CAPV
for vSphere, etc.); follow that provider's guide. This repo intentionally keeps
no infrastructure-specific values — copy `values.env.example` to `values.env`
(git-ignored) and put your own network there.

## Verify

```bash
kubectl cluster-info
kubectl get nodes
```

Once nodes are `Ready`, continue with [`../k8s/operators/`](../k8s/operators/)
(or `make operators`).
