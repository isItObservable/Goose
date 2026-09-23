# Shared helpers for the deploy scripts. Source this at the top of each script.
# shellcheck shell=bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Load .env if present so scripts pick up your parameters automatically.
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/.env"
  set +a
fi

: "${NAMESPACE:=goose}"

log()  { printf '\033[36m▸ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

require_env() {
  local missing=0 v
  for v in "$@"; do
    if [[ -z "${!v:-}" || "${!v:-}" == *CHANGE_ME* || "${!v:-}" == *YOUR_* || "${!v:-}" == *your-* ]]; then
      warn "environment variable '$v' is unset or still a placeholder"
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]] || die "fill in the missing values in .env (copy from .env.example)"
}
