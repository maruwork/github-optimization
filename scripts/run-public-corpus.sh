#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SHELF="$(cd "$SCRIPTS_DIR/.." && pwd)"
CORPUS_PATH="${CORPUS_PATH:-$SCRIPTS_DIR/corpus/public-r02-corpus.json}"
WORK_ROOT=""
KEEP_REPOS=0
ENTRY_IDS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus)
      CORPUS_PATH="$2"
      shift 2
      ;;
    --work-root)
      WORK_ROOT="$2"
      shift 2
      ;;
    --entry)
      ENTRY_IDS+=("$2")
      shift 2
      ;;
    --keep-repos)
      KEEP_REPOS=1
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$CORPUS_PATH" ]]; then
  echo "Corpus file not found: $CORPUS_PATH" >&2
  exit 1
fi

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

parse_corpus_entries() {
  local py
  py="$(json_python)" || return 1
  "$py" - "$CORPUS_PATH" "${ENTRY_IDS[@]}" <<'PY'
import json
import sys

corpus_path = sys.argv[1]
selected = {value.lower() for value in sys.argv[2:]}
with open(corpus_path, "r", encoding="utf-8") as fh:
    obj = json.load(fh)

for entry in obj.get("entries") or []:
    entry_id = str(entry.get("id") or "")
    if selected and entry_id.lower() not in selected:
        continue
    fields = [
        entry_id,
        str(entry.get("repo") or ""),
        str(entry.get("expected_workflow_selection") or ""),
        str(entry.get("expected_selected_workflow_path") or ""),
        str(entry.get("notes") or ""),
    ]
    print("\t".join(field.replace("\t", " ") for field in fields))
PY
}

extract_latest_ci_summary() {
  local evidence_file="$1"
  local py
  py="$(json_python)" || return 1
  "$py" - "$evidence_file" <<'PY'
import json
import sys

primary_workflow = ""
primary_selection = ""
latest_row = None

with open(sys.argv[1], "r", encoding="utf-8", errors="ignore") as fh:
    for raw_line in fh:
        line = raw_line.rstrip("\r\n")
        if line.startswith("primary_ci_workflow:"):
            primary_workflow = line.split(":", 1)[1].strip()
            continue
        if line.startswith("primary_ci_selection:"):
            primary_selection = line.split(":", 1)[1].strip()
            continue
        trimmed = line.strip()
        if not trimmed or (not trimmed.startswith("{") and not trimmed.startswith("[")):
            continue
        try:
            parsed = json.loads(trimmed)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, list) and parsed and isinstance(parsed[0], dict) and "r02_assessment" in parsed[0]:
            latest_row = parsed[0]
            break
        if isinstance(parsed, dict) and "r02_assessment" in parsed:
            latest_row = parsed
            break

summary = {
    "primary_ci_workflow": primary_workflow,
    "primary_ci_selection": primary_selection,
    "selected_workflow_path": "",
    "workflow_selection": "",
    "classification": "",
    "r02_assessment": "",
    "r02_reason": "",
    "evidence_scope": "",
    "default_branch": "",
    "html_url": "",
}
if latest_row:
    summary["selected_workflow_path"] = str(latest_row.get("selected_workflow_path") or "")
    summary["workflow_selection"] = str(latest_row.get("workflow_selection") or "")
    summary["classification"] = str(latest_row.get("classification") or "")
    summary["r02_assessment"] = str(latest_row.get("r02_assessment") or "")
    summary["r02_reason"] = str(latest_row.get("r02_reason") or "")
    summary["evidence_scope"] = str(latest_row.get("evidence_scope") or "")
    summary["default_branch"] = str(latest_row.get("default_branch") or "")
    summary["html_url"] = str(latest_row.get("html_url") or "")
if not summary["selected_workflow_path"] and primary_workflow and primary_workflow != "none":
    summary["selected_workflow_path"] = primary_workflow
if not summary["workflow_selection"] and primary_selection:
    summary["workflow_selection"] = primary_selection
print(json.dumps(summary, separators=(",", ":")))
PY
}

if [[ -z "$WORK_ROOT" ]]; then
  WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/github-optimization-public-corpus-XXXXXX")"
  CREATED_WORK_ROOT=1
else
  mkdir -p "$WORK_ROOT"
  CREATED_WORK_ROOT=0
fi

ENTRIES_RAW="$(parse_corpus_entries)"
if [[ -z "$ENTRIES_RAW" ]]; then
  echo "No corpus entries selected." >&2
  exit 1
fi

RESULTS_FILE="$(mktemp)"
FAILURES=0

echo "=== Public GitHub Corpus ==="
echo "Corpus: $CORPUS_PATH"
echo "Work root: $WORK_ROOT"

while IFS=$'\t' read -r entry_id repo expected_selection expected_path notes; do
  [[ -n "$entry_id" ]] || continue
  clone_path="$WORK_ROOT/$entry_id"
  rm -rf "$clone_path"

  echo
  echo "TEST: $entry_id ($repo)"
  if ! git clone --depth 1 "https://github.com/$repo.git" "$clone_path" >/tmp/github-optimization-clone.out 2>/tmp/github-optimization-clone.err; then
    echo "  FAIL: clone failed"
    FAILURES=$((FAILURES + 1))
    printf '{"id":"%s","repo":"%s","result":"FAIL","failure_reason":"clone_failed"}\n' "$entry_id" "$repo" >>"$RESULTS_FILE"
    continue
  fi

  evidence_file="$(mktemp)"
  set +e
  bash "$SCRIPTS_DIR/collect-audit-evidence.sh" "$clone_path" "$repo" >"$evidence_file" 2>&1
  collector_exit=$?
  set -e

  summary_json="$(extract_latest_ci_summary "$evidence_file")"
  workflow_selection="$(SUMMARY_JSON="$summary_json" "$(json_python)" - <<'PY'
import json, os
print(json.loads(os.environ["SUMMARY_JSON"]).get("workflow_selection", ""))
PY
)"
  selected_workflow_path="$(SUMMARY_JSON="$summary_json" "$(json_python)" - <<'PY'
import json, os
print(json.loads(os.environ["SUMMARY_JSON"]).get("selected_workflow_path", ""))
PY
)"
  classification="$(SUMMARY_JSON="$summary_json" "$(json_python)" - <<'PY'
import json, os
print(json.loads(os.environ["SUMMARY_JSON"]).get("classification", ""))
PY
)"
  r02_assessment="$(SUMMARY_JSON="$summary_json" "$(json_python)" - <<'PY'
import json, os
print(json.loads(os.environ["SUMMARY_JSON"]).get("r02_assessment", ""))
PY
)"

  mismatches=()
  [[ -n "$workflow_selection" ]] || mismatches+=("missing workflow_selection")
  [[ -n "$selected_workflow_path" ]] || mismatches+=("missing selected_workflow_path")
  if [[ -n "$expected_selection" && "$expected_selection" != "$workflow_selection" ]]; then
    mismatches+=("workflow_selection expected '$expected_selection' got '$workflow_selection'")
  fi
  if [[ -n "$expected_path" && "$expected_path" != "$selected_workflow_path" ]]; then
    mismatches+=("selected_workflow_path expected '$expected_path' got '$selected_workflow_path'")
  fi

  echo "  collector exit: $collector_exit"
  echo "  workflow selection: $workflow_selection"
  echo "  selected workflow: $selected_workflow_path"
  [[ -n "$classification" ]] && echo "  classification: $classification"
  [[ -n "$r02_assessment" ]] && echo "  r02 assessment: $r02_assessment"

  result="PASS"
  if [[ "${#mismatches[@]}" -gt 0 ]]; then
    result="FAIL"
    FAILURES=$((FAILURES + 1))
    for mismatch in "${mismatches[@]}"; do
      echo "  mismatch: $mismatch"
    done
  else
    echo "  PASS"
  fi

  SUMMARY_JSON="$summary_json" NOTES="$notes" RESULT="$result" ENTRY_ID="$entry_id" REPO="$repo" COLLECTOR_EXIT="$collector_exit" "$(json_python)" - <<'PY' >>"$RESULTS_FILE"
import json
import os

summary = json.loads(os.environ["SUMMARY_JSON"])
summary.update(
    {
        "id": os.environ["ENTRY_ID"],
        "repo": os.environ["REPO"],
        "result": os.environ["RESULT"],
        "collector_exit_code": int(os.environ["COLLECTOR_EXIT"]),
        "notes": os.environ["NOTES"],
    }
)
print(json.dumps(summary, separators=(",", ":")))
PY

  rm -f "$evidence_file"
done <<< "$ENTRIES_RAW"

echo
echo "=== Corpus Summary ==="
if [[ -s "$RESULTS_FILE" ]]; then
  "$(json_python)" - "$RESULTS_FILE" <<'PY'
import json
import sys

rows = []
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))
print(json.dumps(rows, separators=(",", ":")))
PY
else
  echo "[]"
fi

rm -f "$RESULTS_FILE" /tmp/github-optimization-clone.out /tmp/github-optimization-clone.err
if [[ "$KEEP_REPOS" -ne 1 && "${CREATED_WORK_ROOT:-0}" -eq 1 ]]; then
  rm -rf "$WORK_ROOT"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  exit 1
fi
exit 0
