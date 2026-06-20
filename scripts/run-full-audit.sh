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
REPO_LABEL="$(basename "$REPO_PATH")"

git_safe() {
  git -C "$REPO_PATH" -c core.excludesFile=/dev/null -c "safe.directory=$REPO_PATH" "$@"
}

extract_repo_name_from_remote() {
  local remote_url="${1:-}"
  local normalized=""
  local leaf=""
  [[ -n "$remote_url" ]] || return 1
  normalized="${remote_url%/}"
  normalized="${normalized%.git}"
  normalized="${normalized//\\//}"
  normalized="${normalized##*:}"
  leaf="${normalized##*/}"
  [[ -n "$leaf" ]] || return 1
  printf '%s\n' "$leaf"
}

resolve_audit_slug() {
  local explicit_slug="${1:-}"
  local remote_name=""
  local remote_url=""
  local remote_slug=""
  local top_level=""

  if [[ -n "$explicit_slug" ]]; then
    printf '%s\n' "$(echo "$explicit_slug" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi

  for remote_name in origin $(git_safe remote 2>/dev/null); do
    [[ -n "$remote_name" ]] || continue
    remote_url="$(git_safe remote get-url "$remote_name" 2>/dev/null || true)"
    remote_slug="$(extract_repo_name_from_remote "$remote_url" || true)"
    if [[ -n "$remote_slug" ]]; then
      printf '%s\n' "$(echo "$remote_slug" | tr '[:upper:]' '[:lower:]')"
      return 0
    fi
  done

  top_level="$(git_safe rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$top_level" ]]; then
    printf '%s\n' "$(basename "$top_level" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi

  printf '%s\n' "$(basename "$REPO_PATH" | tr '[:upper:]' '[:lower:]')"
}

SLUG="$(resolve_audit_slug "$AUDIT_SLUG")"

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

json_python() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

set_report_latest_ci_summary() {
  local path="$1"
  local evidence_file="$2"
  local py
  local summary_file
  py="$(json_python)" || return 0
  summary_file="$(mktemp)"
  if ! "$py" - "$evidence_file" "$summary_file" <<'PY'
import json
import sys

evidence_path = sys.argv[1]
summary_path = sys.argv[2]
row = None
primary_ci_workflow = ""
primary_ci_selection = ""

with open(evidence_path, "r", encoding="utf-8") as fh:
    for raw_line in fh:
        line = raw_line.strip()
        if line.startswith("primary_ci_workflow:"):
            primary_ci_workflow = line.split(":", 1)[1].strip()
            continue
        if line.startswith("primary_ci_selection:"):
            primary_ci_selection = line.split(":", 1)[1].strip()
            continue
        if not line or not line.startswith(("{", "[")):
            continue
        try:
            parsed = json.loads(line)
        except Exception:
            continue
        if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict) and "r02_assessment" in parsed[0]:
            row = parsed[0]
            break
        if isinstance(parsed, dict) and "r02_assessment" in parsed:
            row = parsed
            break

def value(key, fallback=""):
    if row is None:
        return fallback
    result = row.get(key)
    return fallback if result is None else str(result)

lines = {
    "- evidence scope:": value("evidence_scope"),
    "- default branch:": value("default_branch"),
    "- selected workflow path:": value("selected_workflow_path", primary_ci_workflow if primary_ci_workflow != "none" else ""),
    "- workflow selection:": value("workflow_selection", primary_ci_selection),
    "- latest evaluated run URL or ID:": value("html_url") or value("id"),
    "- collector classification:": value("classification"),
    "- collector provisional assessment:": value("r02_assessment"),
    "- collector reason:": value("r02_reason"),
}

if not row and not lines["- selected workflow path:"] and not lines["- workflow selection:"]:
    raise SystemExit(1)

with open(summary_path, "w", encoding="utf-8") as fh:
    for key, val in lines.items():
        fh.write(f"{key} {val}\n")
PY
  then
    rm -f "$summary_file"
    return 0
  fi
  awk -v summary="$summary_file" '
    BEGIN {
      while ((getline line < summary) > 0) {
        split(line, parts, ":")
        prefix = parts[1] ":"
        sub(/^[^:]*:[[:space:]]*/, "", line)
        values[prefix] = line
      }
      close(summary)
    }
    /^- evidence scope:/ { print "- evidence scope: " values["- evidence scope:"]; next }
    /^- default branch:/ { print "- default branch: " values["- default branch:"]; next }
    /^- selected workflow path:/ { print "- selected workflow path: " values["- selected workflow path:"]; next }
    /^- workflow selection:/ { print "- workflow selection: " values["- workflow selection:"]; next }
    /^- latest evaluated run URL or ID:/ { print "- latest evaluated run URL or ID: " values["- latest evaluated run URL or ID:"]; next }
    /^- collector classification:/ { print "- collector classification: " values["- collector classification:"]; next }
    /^- collector provisional assessment:/ { print "- collector provisional assessment: " values["- collector provisional assessment:"]; next }
    /^- collector reason:/ { print "- collector reason: " values["- collector reason:"]; next }
    { print }
  ' "$path" >"$path.tmp" && mv "$path.tmp" "$path"
  rm -f "$summary_file"
}

prepare_audit_dir() {
  if [[ "$AUDIT_DIR" == "$SHELF"/audits/* ]]; then
    (cd "$SHELF" && mkdir -p "audits/$SLUG")
  else
    mkdir -p "$AUDIT_DIR"
  fi
}

echo "=== Full Audit Orchestrator ==="
echo "Shelf: $(basename "$SHELF")"
echo "Repository: $REPO_LABEL"
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
  EVIDENCE_FILE="$(mktemp)"
  printf '```text\n%s\n```\n' "$EVIDENCE_OUTPUT" >"$BODY_FILE"
  printf '%s\n' "$EVIDENCE_OUTPUT" >"$EVIDENCE_FILE"
  set_report_machine_evidence "$REPORT_PATH" "$BODY_FILE"
  set_report_latest_ci_summary "$REPORT_PATH" "$EVIDENCE_FILE"
  rm -f "$BODY_FILE"
  rm -f "$EVIDENCE_FILE"
fi

echo
echo "=== Agent Steps Remaining ==="
echo "1. Read regulation/REGULATION_INDEX.md and complete G-21 full file read in target repository"
echo "2. Complete Read Exceptions and Read Coverage in $REPORT_REL"
echo "3. Fill Evidence Index, Local Command Transcripts, Hosted Transcripts, Quickstart Transcript, and Latest CI Assessment (R-02) in $REPORT_REL"
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
