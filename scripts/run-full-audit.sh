#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <repo-path> [hosted-repo] [audit-mode] [audit-phase] [audit-slug]" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

REPO_PATH="$1"
HOSTED_REPO="${2:-}"
AUDIT_MODE="${3:-release}"
AUDIT_PHASE="${4:-pre-public}"
AUDIT_SLUG="${5:-${AUDIT_SLUG:-}}"
SKIP_SHELF_VALIDATION="${SKIP_SHELF_VALIDATION:-0}"

if [[ ! -d "$REPO_PATH" ]]; then
  echo "Repository path not found: $REPO_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -n "${GITHUB_OPTIMIZATION_ROOT:-}" ]]; then
  SHELF="$GITHUB_OPTIMIZATION_ROOT"
elif [[ -d "$REPO_PATH/../common/github-optimization" ]]; then
  SHELF="$(cd "$REPO_PATH/../common/github-optimization" && pwd)"
else
  SHELF="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"

if [[ -n "$AUDIT_SLUG" ]]; then
  SLUG="$(echo "$AUDIT_SLUG" | tr '[:upper:]' '[:lower:]')"
else
  SLUG="$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]')"
fi

AUDIT_DIR="$SHELF/audits/$SLUG"
REPORT_PATH="$AUDIT_DIR/audit-report.md"
REPORT_REL="audits/$SLUG/audit-report.md"

echo "=== Full Audit Orchestrator ==="
echo "Shelf: $SHELF"
echo "Repository: $REPO_PATH"
echo "Audit slug: $SLUG"
echo "Hosted: $HOSTED_REPO"
echo "Audit mode: $AUDIT_MODE"
echo "Audit phase: $AUDIT_PHASE"

if [[ "$SKIP_SHELF_VALIDATION" != "1" ]]; then
  echo
  bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
fi

mkdir -p "$AUDIT_DIR"
TEMPLATE_PATH="$SHELF/templates/audit-report.md.template"

if [[ ! -f "$REPORT_PATH" || "${FORCE_SCAFFOLD:-0}" == "1" ]]; then
  cp "$TEMPLATE_PATH" "$REPORT_PATH"
  echo "Scaffolded: $REPORT_REL"
else
  echo "Existing report kept: $REPORT_REL"
fi

echo
echo "=== Machine Evidence ==="
set +e
bash "$SHELF/scripts/collect-audit-evidence.sh" "$REPO_PATH" "$HOSTED_REPO"
EVIDENCE_EXIT=$?
set -e

echo
echo "=== Agent Steps Remaining ==="
echo "1. Read REGULATION_INDEX.md and complete G-21 full file read in target repository"
echo "2. Paste machine evidence into $REPORT_REL"
echo "3. Score Tier 1 gates G-01..G-22 (PUBLIC_PREP_GATE.md)"
if [[ "$AUDIT_MODE" == "release" || "$AUDIT_MODE" == "strict-product" ]]; then
  echo "4. Score Tier 2 gates R-01..R-14 (RELEASE_QUALITY_GATE.md)"
fi
if [[ "$AUDIT_MODE" == "strict-product" ]]; then
  echo "5. Score Tier 3 gates P-01..P-10 (PRODUCT_READINESS_GATE.md)"
fi
echo "6. Apply AUDIT_PHASE_POLICY.md for phase=$AUDIT_PHASE"
echo "7. Write audits/$SLUG/publication-decision-record.md when phase=pre-public (G-20)"
echo "8. If R-02 blocked with accepted risk, write audits/$SLUG/accepted-risk-record.md"
echo "9. Assign final label via FULL_AUDIT_VERDICT.md"
echo
echo "Read: AUDIT_RUNBOOK.md, RE_AUDIT_POLICY.md, OUTPUT_PATHS.md"

if [[ "$EVIDENCE_EXIT" -ne 0 ]]; then
  echo
  echo "orchestrator: evidence script exited $EVIDENCE_EXIT (review output before scoring gates)"
  exit "$EVIDENCE_EXIT"
fi

echo
echo "orchestrator: scaffold and evidence complete; agent judgment steps remain"
exit 0