#!/usr/bin/env bash
# Review a pull request with the Goose PR-reviewer recipe (GitHub MCP).
# Usage: ./scripts/08-review-pr.sh [pr-number]   # empty = latest open PR
source "$(dirname "$0")/lib/common.sh"
need kubectl
require_env GITHUB_TOKEN
REPO="${DEMO_REPO:-isItObservable/Goose}"
PR="${1:-}"
POD="$(kubectl -n "${NAMESPACE}" get pod -l app.kubernetes.io/name=goose -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$POD" ]] || die "no goose pod found — run: make deploy-goose"
log "Reviewing PR ${PR:-(latest open)} on ${REPO}…"
kubectl -n "${NAMESPACE}" exec -it "$POD" -- \
  goose run --recipe /recipes/05-pr-review.yaml \
    --params repo="${REPO}" pr="${PR}"
log "Review posted. Open the PR on GitHub to see it."
