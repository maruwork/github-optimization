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
elif [[ -d "$REPO_PATH/../github-optimization" ]]; then
  SHELF="$(cd "$REPO_PATH/../github-optimization" && pwd)"
else
  SHELF="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

REPO_PATH="$(cd "$REPO_PATH" && pwd)"

if [[ -n "$AUDIT_SLUG" ]]; then
  SLUG="$(echo "$AUDIT_SLUG" | tr '[:upper:]' '[:lower:]')"
else
  SLUG="$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]')"
fi

if [[ ! "$SLUG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ || "$SLUG" == *..* ]]; then
  echo "Invalid audit slug: $SLUG" >&2
  exit 2
fi

AUDIT_DIR="$SHELF/audits/$SLUG"
REPORT_PATH="$AUDIT_DIR/audit-report.md"
REPORT_REL="audits/$SLUG/audit-report.md"

set_report_machine_evidence() {
  local path="$1"
  local body_file="$2"
  awk -v body="$body_file" '
    BEGIN {
      in_block = 0
      while ((getline line < body) > 0) body_text = body_text line "\n"
      close(body)
    }
    /^<!-- GO_MACHINE_EVIDENCE_START -->$/ {
      print
      printf "%s", body_text
      in_block = 1
      next
    }
    /^<!-- GO_MACHINE_EVIDENCE_END -->$/ {
      in_block = 0
      print
      next
    }
    !in_block { print }
  ' "$path" >"$path.tmp" && mv "$path.tmp" "$path"
}

prepare_audit_dir() {
  if [[ "$AUDIT_DIR" == "$SHELF"/audits/* ]]; then
    (cd "$SHELF" && mkdir -p "audits/$SLUG")
  else
    mkdir -p "$AUDIT_DIR"
  fi
}

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

prepare_audit_dir
TEMPLATE_PATH="$SHELF/templates/audit-report.md.template"

REPORT_IS_FINAL=0
if [[ -f "$REPORT_PATH" ]] && grep -qE '^Status:[[:space:]]*Final[[:space:]]*$' "$REPORT_PATH"; then
  REPORT_IS_FINAL=1
fi

if [[ "${FORCE_SCAFFOLD:-0}" == "1" && "$REPORT_IS_FINAL" == "1" ]]; then
  echo "Refusing to overwrite Final audit report: $REPORT_REL (back up first or edit in place)" >&2
  exit 1
fi

if [[ ! -f "$REPORT_PATH" || "${FORCE_SCAFFOLD:-0}" == "1" ]]; then
  cp "$TEMPLATE_PATH" "$REPORT_PATH"
  echo "Scaffolded: $REPORT_REL"
else
  echo "Existing report kept: $REPORT_REL"
fi

echo
echo "=== Machine Evidence ==="
set +e
EVIDENCE_OUTPUT="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$REPO_PATH" "$HOSTED_REPO" 2>&1)"
EVIDENCE_EXIT=$?
set -e
printf '%s\n' "$EVIDENCE_OUTPUT"
if [[ -f "$REPORT_PATH" ]]; then
  BODY_FILE="$(mktemp)"
  printf '```text\n%s\n```\n' "$EVIDENCE_OUTPUT" >"$BODY_FILE"
  set_report_machine_evidence "$REPORT_PATH" "$BODY_FILE"
  rm -f "$BODY_FILE"
fi

echo
echo "=== Agent Steps Remaining ==="
echo "1. Read regulation/REGULATION_INDEX.md and complete G-21 full file read in target repository"
echo "2. Complete Read Exceptions and Read Coverage in $REPORT_REL"
echo "3. Fill Evidence Index, Local Command Transcripts, Hosted Transcripts, and Quickstart Transcript in $REPORT_REL"
echo "4. Score Tier 1 gates G-01..G-22 (regulation/gates/PUBLIC_PREP_GATE.md)"
if [[ "$AUDIT_MODE" == "release" || "$AUDIT_MODE" == "strict-product" ]]; then
  echo "5. Score Tier 2 gates R-01..R-14 (regulation/gates/RELEASE_QUALITY_GATE.md)"
fi
if [[ "$AUDIT_MODE" == "strict-product" ]]; then
  echo "6. Score Tier 3 gates P-01..P-10 (regulation/gates/PRODUCT_READINESS_GATE.md)"
fi
echo "7. Apply regulation/execution/AUDIT_PHASE_POLICY.md for phase=$AUDIT_PHASE"
echo "8. Write audits/$SLUG/publication-decision-record.md when phase=pre-public (G-20)"
echo "9. If R-02 blocked with accepted risk, write audits/$SLUG/accepted-risk-record.md"
echo "10. Assign final label via regulation/gates/FULL_AUDIT_VERDICT.md"
echo
echo "Read: regulation/execution/AUDIT_RUNBOOK.md, regulation/execution/RE_AUDIT_POLICY.md, regulation/shelf/OUTPUT_PATHS.md"

if [[ "$EVIDENCE_EXIT" -ne 0 ]]; then
  echo
  echo "orchestrator: machine evidence captured; collector exit $EVIDENCE_EXIT reflects target findings or quickstart failures (review before scoring gates)"
fi

echo
echo "orchestrator: scaffold and evidence complete; agent judgment steps remain"
exit 0
