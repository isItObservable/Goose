#!/usr/bin/env bash
# Optional: provision a cluster. This tutorial is cluster-agnostic — see
# cluster/README.md. This script just checks you have a working cluster.
source "$(dirname "$0")/lib/common.sh"
need kubectl
log "Checking cluster connectivity…"
kubectl cluster-info >/dev/null || die "kubectl is not pointed at a working cluster (see cluster/README.md)"
kubectl get nodes
log "Cluster reachable. Continue with: make operators"
