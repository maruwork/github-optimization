#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <repo-path> [hosted-repo] [audit-mode] [audit-slug] [prior-head]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

REPO_PATH="$1"
HOSTED_REPO="${2:-}"
AUDIT_MODE="${3:-release}"
AUDIT_SLUG="${4:-}"
PRIOR_HEAD="${5:-}"
ALLOW_LARGE_DELTA="${ALLOW_LARGE_DELTA:-0}"
SKIP_SHELF_VALIDATION="${SKIP_SHELF_VALIDATION:-0}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "Repository path not found: $REPO_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "${GITHUB_OPTIMIZATION_ROOT:-}" ]]; then
  SHELF="$GITHUB_OPTIMIZATION_ROOT"
elif [[ -d "$REPO_PATH/../github-optimization" ]]; then
  SHELF="$(cd "$REPO_PATH/../github-optimization" && pwd)"
else
  SHELF="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"
SLUG="${AUDIT_SLUG:-$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]')}"
AUDIT_DIR="$SHELF/audits/$SLUG"
REPORT_PATH="$AUDIT_DIR/audit-report.md"
DELTA_PATH="$AUDIT_DIR/delta-audit-record.md"

parse_prior_head() {
  local file="$1"
  local line
  line="$(grep -E '^- HEAD:|^HEAD:' "$file" | head -n 1 || true)"
  if [[ "$line" =~ ([0-9a-f]{7,40}) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

echo "=== Delta Audit Orchestrator ==="
echo "Shelf: $SHELF"
echo "Repository: $REPO_PATH"
echo "Audit slug: $SLUG"
echo "Audit mode: $AUDIT_MODE"

if [[ "$SKIP_SHELF_VALIDATION" != "1" ]]; then
  echo
  bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
fi

if [[ -z "$PRIOR_HEAD" ]]; then
  [[ -f "$REPORT_PATH" ]] || { echo "Prior audit report not found: $REPORT_PATH" >&2; exit 1; }
  PRIOR_HEAD="$(parse_prior_head "$REPORT_PATH")" || { echo "Could not parse prior HEAD from report" >&2; exit 1; }
fi

cd "$REPO_PATH"
PRESENT_HEAD="$(git rev-parse HEAD)"
PRIOR_FULL="$(git rev-parse "$PRIOR_HEAD")"
PRIOR_COUNT="$(git ls-tree -r --name-only "$PRIOR_FULL" | wc -l | tr -d ' ')"
PRESENT_COUNT="$(git ls-files | wc -l | tr -d ' ')"
DELTA_PERCENT="$(awk -v prior="$PRIOR_COUNT" -v present="$PRESENT_COUNT" \
  'BEGIN{d=present-prior; if (d<0) d=-d; printf "%.1f", (prior ? 100*d/prior : 100)}')"

mapfile -t CHANGED < <(git diff --name-only "$PRIOR_FULL" "$PRESENT_HEAD")
mapfile -t UNTRACKED < <(git ls-files --others --exclude-standard)

invalidations=()
OVER20="$(awk -v d="$DELTA_PERCENT" 'BEGIN{print (d>20)?1:0}')"
if [[ "$OVER20" == "1" && "$ALLOW_LARGE_DELTA" != "1" ]]; then
  invalidations+=("inventory delta ${DELTA_PERCENT}% exceeds 20%")
fi

for p in "${CHANGED[@]}"; do
  [[ -z "$p" ]] && continue
  case "$p" in
    LICENSE|SECURITY.md|audit.manifest.yml|.github/workflows/*)
      invalidations+=("sensitive path changed: $p")
      ;;
  esac
done

if [[ -f "$REPORT_PATH" ]]; then
  blockers_line="$(grep -E '^Open Blockers:' "$REPORT_PATH" | tail -n 1 || true)"
  if [[ -n "$blockers_line" && ! "$blockers_line" =~ ^Open\ Blockers:[[:space:]]*0[[:space:]]*$ ]]; then
    invalidations+=("prior audit reports open Blockers")
  fi
fi

DELTA_MODE="allowed"
[[ ${#invalidations[@]} -gt 0 ]] && DELTA_MODE="upgrade-to-full"

mkdir -p "$AUDIT_DIR"
cp "$SHELF/templates/delta-audit-record.md.template" "$DELTA_PATH"

echo
echo "=== Delta Summary ==="
echo "Prior HEAD: $PRIOR_FULL"
echo "Present HEAD: $PRESENT_HEAD"
echo "Prior tracked count: $PRIOR_COUNT"
echo "Present tracked count: $PRESENT_COUNT"
echo "Inventory delta: ${DELTA_PERCENT}%"
echo "Changed tracked paths: ${#CHANGED[@]}"
for p in "${CHANGED[@]}"; do
  [[ -n "$p" ]] && echo "  M $p"
done
if [[ ${#UNTRACKED[@]} -gt 0 ]]; then
  echo "New untracked (non-ignored): ${#UNTRACKED[@]}"
  for p in "${UNTRACKED[@]:0:20}"; do echo "  ? $p"; done
fi
echo "Delta mode: $DELTA_MODE"
if [[ ${#invalidations[@]} -gt 0 ]]; then
  echo "Invalidation reasons:"
  for r in "${invalidations[@]}"; do echo "  - $r"; done
fi

echo
echo "Scaffolded: audits/$SLUG/delta-audit-record.md"
echo
echo "=== Machine Evidence ==="
bash "$SHELF/scripts/collect-audit-evidence.sh" "$REPO_PATH" "$HOSTED_REPO"

echo
echo "=== Agent Steps Remaining ==="
if [[ "$DELTA_MODE" == "upgrade-to-full" ]]; then
  echo "1. Delta invalid - run scripts/run-full-audit.sh for full re-audit"
else
  echo "1. Read regulation/execution/RE_AUDIT_POLICY.md delta rules"
  echo "2. G-21 full read only changed paths + dependency cone listed above"
  echo "3. Rescore gates affected by the change set; carry forward others only when allowed"
  echo "4. Update audits/$SLUG/audit-report.md and fill delta-audit-record.md"
fi
echo "5. Refresh R-02, R-09 when audit mode is release or strict-product"

if [[ "$DELTA_MODE" == "upgrade-to-full" ]]; then
  exit 2
fi
exit 0