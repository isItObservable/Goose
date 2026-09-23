#!/usr/bin/env bash
# Publish the two Dynatrace dashboards via the Dynatrace API.
#
# Uses the Documents API (dashboards are documents). Needs a token with
# document scopes (documents:documents:write). Set DT_DOC_TOKEN or reuse
# DT_API_TOKEN if it carries the scope.
source "$(dirname "$0")/lib/common.sh"
need curl
require_env DT_ENVIRONMENT_URL
TOKEN="${DT_DOC_TOKEN:-${DT_API_TOKEN:-}}"
[[ -n "$TOKEN" ]] || die "set DT_DOC_TOKEN (or DT_API_TOKEN) with documents:documents:write"

for f in goose-engine-health goose-agent-efficiency; do
  name="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['dashboardMetadata']['name'])" "${REPO_ROOT}/dashboards/${f}.json" 2>/dev/null || echo "$f")"
  log "Publishing dashboard '${name}'…"
  curl -sS -X POST "${DT_ENVIRONMENT_URL}/platform/document/v1/documents" \
    -H "Authorization: Api-Token ${TOKEN}" \
    -F "content=@${REPO_ROOT}/dashboards/${f}.json;type=application/json" \
    -F "name=${name}" \
    -F "type=dashboard" \
    -o /dev/null -w "  → HTTP %{http_code}\n" || warn "failed to publish ${f}"
done
log "Dashboards published. Open Dynatrace → Dashboards to view them."
