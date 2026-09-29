#!/usr/bin/env bash
# Publish the two Goose observability dashboards to Dynatrace via dtctl.
#
# The dashboards are stored as dtctl document YAML (see dashboards/*.yaml).
# Because the files carry no 'id' field, `dtctl apply` CREATEs a fresh
# dashboard with an auto-generated ID on whatever tenant your dtctl context
# points at — safe to run against any environment.
#
# Prereqs:
#   - dtctl installed and on PATH (https://github.com/dynatrace/dtctl)
#   - a dtctl context with document write scope for your environment.
#     Select it with DTCTL_CONTEXT, or rely on your current context.
source "$(dirname "$0")/lib/common.sh"
need dtctl

CTX_ARG=()
[[ -n "${DTCTL_CONTEXT:-}" ]] && CTX_ARG=(--context "${DTCTL_CONTEXT}")

for f in goose-engine-health goose-agent-efficiency; do
  log "Applying dashboard '${f}'…"
  dtctl "${CTX_ARG[@]}" apply -f "${REPO_ROOT}/dashboards/${f}.yaml" \
    || warn "failed to apply ${f}"
done
log "Dashboards applied. Open Dynatrace → Dashboards to view them."
