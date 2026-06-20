#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
HOSTED_REPO="${2:-}"
UNAME_S="$(uname -s 2>/dev/null || true)"
IS_WINDOWS_BASH=0
case "$UNAME_S" in
  MINGW*|MSYS*|CYGWIN*) IS_WINDOWS_BASH=1 ;;
esac
REPO_PATH="$(cd "$REPO_PATH" && pwd)"
REPO_LABEL="$(basename "$REPO_PATH")"

redact_path() {
  local text="$1"
  local result="$text"
  for prefix in "$REPO_PATH" "${GITHUB_OPTIMIZATION_ROOT:-}" "${USERPROFILE:-}" "${HOME:-}" "${TMPDIR:-}" "/tmp"; do
    [[ -n "$prefix" ]] || continue
    result="${result//$prefix/<REDACTED_PATH>}"
  done
  printf '%s' "$result"
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

json_project() {
  local mode="$1"
  local py
  local input
  local input_file
  local status
  py="$(json_python)" || return 1
  input="$(cat)"
  input_file="$(mktemp)"
  printf '%s' "$input" >"$input_file"
  set +e
  "$py" - "$mode" "$input_file" <<'PY'
import json
import sys

mode = sys.argv[1]
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    obj = json.load(fh)

if mode == "repo":
    out = {
        "description": obj.get("description"),
        "topics": obj.get("topics"),
        "homepage": obj.get("homepage"),
        "visibility": obj.get("visibility"),
        "has_issues": obj.get("has_issues"),
        "default_branch": obj.get("default_branch"),
    }
elif mode == "community":
    out = {
        "health_percentage": obj.get("health_percentage"),
        "files": obj.get("files"),
    }
elif mode == "security":
    out = obj.get("security_and_analysis")
elif mode == "runs":
    out = []
    for item in (obj.get("workflow_runs") or [])[:3]:
        out.append(
            {
                "name": item.get("name"),
                "event": item.get("event"),
                "status": item.get("status"),
                "conclusion": item.get("conclusion"),
                "head_branch": item.get("head_branch"),
                "html_url": item.get("html_url"),
            }
        )
else:
    raise SystemExit(2)

json.dump(out, sys.stdout, separators=(",", ":"))
PY
  status=$?
  set -e
  rm -f "$input_file"
  return "$status"
}

json_list_run_ids() {
  local py
  local input_file
  py="$(json_python)" || return 1
  input_file="$(mktemp)"
  cat >"$input_file"
  "$py" - "$input_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)

for item in (obj.get("workflow_runs") or [])[:3]:
    run_id = item.get("id")
    if run_id is not None:
        print(run_id)
PY
  local status=$?
  rm -f "$input_file"
  return "$status"
}

json_extract_total_count() {
  local py
  local input_file
  py="$(json_python)" || return 1
  input_file="$(mktemp)"
  cat >"$input_file"
  "$py" - "$input_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)

value = obj.get("total_count")
if value is None:
    raise SystemExit(1)
print(value)
PY
  local status=$?
  rm -f "$input_file"
  return "$status"
}

json_extract_default_branch() {
  local py
  local input_file
  py="$(json_python)" || return 1
  input_file="$(mktemp)"
  cat >"$input_file"
  "$py" - "$input_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)

value = obj.get("default_branch")
if value:
    print(value)
PY
  local status=$?
  rm -f "$input_file"
  return "$status"
}

json_project_runs_with_jobs() {
  local py
  local runs_file="$1"
  local jobs_file="$2"
  local branch_filters_file="$3"
  local evidence_scope="$4"
  local default_branch="$5"
  local selected_workflow_path="${6:-}"
  local workflow_selection="${7:-all_runs_fallback}"
  py="$(json_python)" || return 1
  "$py" - "$runs_file" "$jobs_file" "$branch_filters_file" "$evidence_scope" "$default_branch" "$selected_workflow_path" "$workflow_selection" <<'PY'
import json
import sys
from datetime import datetime

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    runs_obj = json.load(fh)
with open(sys.argv[2], "r", encoding="utf-8") as fh:
    jobs_map = json.load(fh)
with open(sys.argv[3], "r", encoding="utf-8") as fh:
    branch_filters_map = json.load(fh)
evidence_scope = sys.argv[4]
default_branch = sys.argv[5] or None
selected_workflow_path = sys.argv[6] or None
workflow_selection = sys.argv[7] or "all_runs_fallback"

def parse_dt(value):
    if not value:
        return None
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return None

projected = []
for item in (runs_obj.get("workflow_runs") or [])[:3]:
    run_id = item.get("id")
    run_id_key = str(run_id) if run_id is not None else ""
    jobs_value = jobs_map.get(run_id_key, "__missing__")
    jobs_total = None if jobs_value == "__missing__" else jobs_value
    has_branch_filters = bool(branch_filters_map.get(run_id_key))
    start = parse_dt(item.get("run_started_at") or item.get("created_at"))
    end = parse_dt(item.get("updated_at") or item.get("completed_at"))
    duration_seconds = None
    if start and end:
        duration_seconds = max(int((end - start).total_seconds()), 0)

    signals = []
    conclusion = item.get("conclusion")
    if jobs_total == 0:
        signals.append("no_jobs_recorded")
    if conclusion == "startup_failure":
        signals.append("startup_failure")
    if conclusion in {"failure", "startup_failure", "cancelled"} and jobs_total == 0:
        signals.append("startup_failure_candidate")
    if duration_seconds is not None and duration_seconds <= 10 and jobs_total == 0:
        signals.append("near_zero_duration")
    if has_branch_filters and jobs_total == 0:
        signals.append("branch_filter_candidate")
    if run_id is not None and jobs_value == "__missing__":
        signals.append("jobs_api_blocked")

    classification = "unknown"
    deduped_signals = list(dict.fromkeys(signals))
    if "jobs_api_blocked" in deduped_signals:
        classification = "unknown"
    elif "branch_filter_candidate" in deduped_signals:
        classification = "branch_filter_candidate"
    elif "startup_failure_candidate" in deduped_signals:
        classification = "startup_failure_candidate"
    elif item.get("status") and item.get("status") != "completed" and not conclusion:
        classification = "in_progress"
    elif conclusion == "success":
        classification = "pass"
    elif conclusion in {"neutral", "skipped"}:
        classification = "non_blocking"
    elif conclusion:
        classification = "hard_failure"

    r02_assessment = "review"
    r02_reason = "default_branch_scope_missing"
    if evidence_scope == "default_branch":
        if classification == "pass":
            r02_assessment = "pass"
            r02_reason = "latest_default_branch_run_green"
        elif classification == "hard_failure":
            r02_assessment = "blocked"
            r02_reason = "latest_default_branch_run_failed"
        elif classification == "branch_filter_candidate":
            r02_reason = "branch_filter_candidate_requires_confirmation"
        elif classification == "startup_failure_candidate":
            r02_reason = "startup_failure_candidate_requires_confirmation"
        elif classification == "in_progress":
            r02_reason = "default_branch_run_in_progress"
        elif classification == "non_blocking":
            r02_reason = "default_branch_run_non_green_non_blocking"
        else:
            r02_reason = "insufficient_ci_evidence"

    projected.append(
        {
            "name": item.get("name"),
            "event": item.get("event"),
            "status": item.get("status"),
            "conclusion": conclusion,
            "path": item.get("path"),
            "run_attempt": item.get("run_attempt"),
            "run_started_at": item.get("run_started_at"),
            "updated_at": item.get("updated_at"),
            "duration_seconds": duration_seconds,
            "jobs_total": jobs_total,
            "evidence_scope": evidence_scope,
            "default_branch": default_branch,
            "classification": classification,
            "r02_assessment": r02_assessment,
            "r02_reason": r02_reason,
            "signals": deduped_signals or None,
            "head_branch": item.get("head_branch"),
            "html_url": item.get("html_url"),
            "selected_workflow_path": selected_workflow_path,
            "workflow_selection": workflow_selection,
        }
    )

json.dump(projected, sys.stdout, separators=(",", ":"))
PY
}

select_primary_ci_workflow() {
  local py
  py="$(json_python)" || return 1
  "$py" - "$REPO_PATH" <<'PY'
from pathlib import Path
import re
import sys

repo = Path(sys.argv[1])
workflow_dir = repo / ".github" / "workflows"
if not workflow_dir.is_dir():
    raise SystemExit(0)

manifest_path = repo / "audit.manifest.yml"
if manifest_path.is_file():
    try:
        manifest_text = manifest_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        manifest_text = manifest_path.read_text(encoding="utf-8", errors="ignore")
    override_match = re.search(r"(?m)^primary_ci_workflow:\s*(.+)$", manifest_text)
    if override_match:
        override_value = override_match.group(1).strip().strip('"').strip("'").strip()
        normalized_override = override_value.replace("/", "\\").lstrip("\\")
        if normalized_override and (repo / normalized_override).is_file():
            print(f'{normalized_override.replace("\\", "/")}|manifest_override')
            raise SystemExit(0)

workflow_files = sorted(
    [p for p in workflow_dir.iterdir() if p.is_file() and p.suffix.lower() in {".yml", ".yaml"}],
    key=lambda p: p.name.lower(),
)
if not workflow_files:
    raise SystemExit(0)

def score_candidate(relative_path: str, text: str) -> int:
    normalized = relative_path.replace("\\", "/").strip("/").lower()
    score = 0
    if normalized in {".github/workflows/ci.yml", ".github/workflows/ci.yaml"}:
        return 1000
    if re.search(r"/ci\.ya?ml$", normalized):
        score += 900
    elif re.search(r"/(tests?|build|verify|checks?|validate|pipeline)\.ya?ml$", normalized):
        score += 700
    if re.search(r"(^|/)(codeql|dependabot|scorecards|pages)\.ya?ml$", normalized):
        score -= 800

    name_match = re.search(r'(?im)^\s*name\s*:\s*["\']?(?P<name>[^"\']+?)["\']?\s*$', text or "")
    if name_match:
        workflow_name = name_match.group("name").strip()
        if re.search(r"(?i)\bci\b", workflow_name):
            score += 500
        elif re.search(r"(?i)\b(test|build|verify|check|validate)\b", workflow_name):
            score += 350
        if re.search(r"(?i)\b(codeql|dependabot|scorecards|pages)\b", workflow_name):
            score -= 600

    if re.search(r"(?im)^\s*(push|pull_request)\s*:", text or ""):
        score += 100

    return score

descriptors = []
for workflow_file in workflow_files:
    relative_fs = str(Path(".github") / "workflows" / workflow_file.name)
    api_path = relative_fs.replace("\\", "/")
    try:
        workflow_text = workflow_file.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        workflow_text = workflow_file.read_text(encoding="utf-8", errors="ignore")
    descriptors.append(
        {
            "relative_path": relative_fs,
            "api_path": api_path,
            "score": score_candidate(relative_fs, workflow_text),
        }
    )

for descriptor in descriptors:
    if re.fullmatch(r"(?i)\.github/workflows/ci\.ya?ml", descriptor["api_path"]):
        print(f'{descriptor["api_path"]}|explicit_ci_filename')
        raise SystemExit(0)

ranked = sorted(descriptors, key=lambda item: (-item["score"], item["api_path"].lower()))
if ranked and ranked[0]["score"] > 0:
    reason = "single_local_workflow" if len(descriptors) == 1 else "heuristic_local_workflow"
    print(f'{ranked[0]["api_path"]}|{reason}')
PY
}

select_hosted_primary_ci_workflow() {
  local workflows_json="$1"
  local py
  py="$(json_python)" || return 1
  "$py" - "$workflows_json" <<'PY'
import json
import re
import sys

obj = json.loads(sys.argv[1])
workflows = obj.get("workflows") or []
if not workflows:
    raise SystemExit(0)

def score_candidate(relative_path: str, workflow_name: str, state: str) -> int:
    normalized = relative_path.replace("\\", "/").strip("/").lower()
    score = 0
    if normalized in {".github/workflows/ci.yml", ".github/workflows/ci.yaml"}:
        score += 1000
    elif re.search(r"/ci\.ya?ml$", normalized):
        score += 900
    elif re.search(r"/(tests?|build|verify|checks?|validate|pipeline)\.ya?ml$", normalized):
        score += 700
    if re.search(r"(^|/)(codeql|dependabot|scorecards|pages)\.ya?ml$", normalized):
        score -= 800

    if workflow_name:
        if re.search(r"(?i)\bci\b", workflow_name):
            score += 500
        elif re.search(r"(?i)\b(test|build|verify|check|validate|pipeline)\b", workflow_name):
            score += 350
        if re.search(r"(?i)\b(codeql|dependabot|scorecards|pages)\b", workflow_name):
            score -= 600

    if (state or "").lower() == "active":
        score += 25
    return score

descriptors = []
for workflow in workflows:
    path = str(workflow.get("path") or "").split("@", 1)[0].strip().strip("/").replace("/", "\\")
    if not path:
        continue
    descriptors.append(
        {
            "api_path": path.replace("\\", "/"),
            "score": score_candidate(path, str(workflow.get("name") or ""), str(workflow.get("state") or "")),
        }
    )

if not descriptors:
    raise SystemExit(0)

ranked = sorted(descriptors, key=lambda item: (-item["score"], item["api_path"].lower()))
if ranked and ranked[0]["score"] > 0:
    print(f'{ranked[0]["api_path"]}|hosted_workflow_inventory')
PY
}

json_filter_runs_by_workflow_path() {
  local py
  local runs_file="$1"
  local workflow_path="$2"
  py="$(json_python)" || return 1
  "$py" - "$runs_file" "$workflow_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    runs_obj = json.load(fh)

target = (sys.argv[2] or "").replace("\\", "/").strip("/").lower()
filtered = []
for item in runs_obj.get("workflow_runs") or []:
    path = str(item.get("path") or "").split("@", 1)[0].strip().strip("/").replace("\\", "/").lower()
    if path == target:
        filtered.append(item)

runs_obj["workflow_runs"] = filtered
json.dump(runs_obj, sys.stdout, separators=(",", ":"))
PY
}

workflow_run_local_path() {
  local path_text="${1:-}"
  local normalized=""
  [[ -n "$path_text" ]] || return 1
  normalized="${path_text%%@*}"
  normalized="${normalized#"${normalized%%[![:space:]]*}"}"
  normalized="${normalized%"${normalized##*[![:space:]]}"}"
  normalized="${normalized#/}"
  normalized="${normalized#\\}"
  [[ -n "$normalized" ]] || return 1
  printf '%s\n' "$normalized"
}

workflow_has_branch_filters() {
  local relative_path="${1:-}"
  local workflow_path=""
  [[ -n "$relative_path" ]] || return 1
  workflow_path="$REPO_PATH/$relative_path"
  [[ -f "$workflow_path" ]] || return 1
  grep -Eqi '^[[:space:]]*branches(-ignore)?[[:space:]]*:' "$workflow_path"
}

git_safe() {
  git -c core.excludesFile=/dev/null -c core.quotepath=false -c "safe.directory=$REPO_PATH" "$@"
}

cd "$REPO_PATH"

gh_auth_required() {
  local text="${1:-}"
  if [[ -z "$text" ]]; then
    return 1
  fi
  printf '%s' "$text" | grep -Eqi 'gh auth login|GH_TOKEN|authentication required'
}

github_api() {
  local path="$1"
  local gh_output=""
  local gh_status=0
  local gh_stderr=""
  local gh_stderr_file=""
  local gh_retry_dir=""
  if command -v gh >/dev/null 2>&1; then
    gh_stderr_file="$(mktemp)"
    set +e
    gh_output="$(gh api "$path" 2>"$gh_stderr_file")"
    gh_status=$?
    set -e
    gh_stderr="$(cat "$gh_stderr_file" 2>/dev/null || true)"
    rm -f "$gh_stderr_file"
    gh_stderr_file=""
    if [[ "$gh_status" -ne 0 ]] \
      && [[ -z "${GH_CONFIG_DIR:-}" ]] \
      && printf '%s' "$gh_stderr" | grep -Eq 'failed to load config|failed to read configuration|config\.yml: Access is denied'; then
      gh_retry_dir="$(mktemp -d)"
      set +e
      gh_output="$(GH_CONFIG_DIR="$gh_retry_dir" gh api "$path" 2>"$gh_retry_dir/stderr.log")"
      gh_status=$?
      set -e
      gh_stderr="$(cat "$gh_retry_dir/stderr.log" 2>/dev/null || true)"
      rm -rf "$gh_retry_dir"
      gh_retry_dir=""
    fi
    if [[ "$gh_status" -eq 0 ]]; then
      printf '%s\n' "$gh_output"
      return 0
    fi
    if printf '%s' "$gh_output" | grep -Eq '"status"[[:space:]]*:[[:space:]]*"?404"?' ; then
      return 4
    fi
    if gh_auth_required "$gh_stderr"; then
      if [[ "${GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK:-0}" == "1" ]]; then
        return 2
      fi
    fi
    if [[ "${GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK:-0}" == "1" ]]; then
      return 2
    fi
  fi
  if [[ "${GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK:-0}" == "1" ]]; then
    return 2
  fi
  if command -v curl >/dev/null 2>&1; then
    local body_file
    local status
    body_file="$(mktemp)"
    status="$(curl -sS -L -H "User-Agent: github-optimization-audit" -o "$body_file" -w "%{http_code}" "https://api.github.com/$path" 2>/dev/null || true)"
    case "$status" in
      2??)
        cat "$body_file"
        rm -f "$body_file"
        return 0
        ;;
      404)
        rm -f "$body_file"
        return 4
        ;;
      *)
        rm -f "$body_file"
        ;;
    esac
  fi
  return 2
}

resolve_existing_path() {
  local candidate="$1"
  local resolved=""
  if command -v realpath >/dev/null 2>&1; then
    resolved="$(realpath "$candidate" 2>/dev/null || true)"
  fi
  if [[ -z "$resolved" ]]; then
    resolved="$(readlink "$candidate" 2>/dev/null || true)"
  fi
  if [[ -z "$resolved" ]]; then
    resolved="$(readlink -f "$candidate" 2>/dev/null || true)"
  fi
  if [[ -n "$resolved" && -e "$resolved" && ! -d "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  if [[ -e "$candidate" && ! -d "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

resolve_gitleaks() {
  if [[ -n "${GITLEAKS_CMD:-}" && -x "$GITLEAKS_CMD" ]]; then
    printf '%s\n' "$GITLEAKS_CMD"
    return 0
  fi
  local -a candidate_roots=()
  local candidate
  local resolved
  local windows_path
  local normalized
  for windows_path in "${LOCALAPPDATA:-}" "${USERPROFILE:-}" "${HOME:-}"; do
    [[ -n "$windows_path" ]] || continue
    normalized="${windows_path//\\//}"
    if [[ "$normalized" =~ ^([A-Za-z]):/(.*)$ ]]; then
      normalized="/${BASH_REMATCH[1],,}/${BASH_REMATCH[2]}"
    fi
    normalized="${normalized%/}"
    [[ -n "$normalized" ]] || continue
    case "$normalized" in
      */AppData/Local)
        candidate_roots+=("$normalized")
        ;;
      *)
        candidate_roots+=("$normalized/AppData/Local")
        ;;
    esac
  done
  for windows_path in "${candidate_roots[@]}"; do
    for candidate in \
      "$windows_path/Microsoft/WinGet/Links/gitleaks.exe" \
      "$windows_path"/Microsoft/WinGet/Packages/*/gitleaks.exe
    do
      [[ -e "$candidate" ]] || continue
      resolved="$(resolve_existing_path "$candidate" || true)"
      [[ -n "$resolved" && -x "$resolved" ]] || continue
      printf '%s\n' "$resolved"
      return 0
    done
  done
  if command -v gitleaks >/dev/null 2>&1; then
    resolved="$(resolve_existing_path "$(command -v gitleaks)" || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi
  if command -v gitleaks.exe >/dev/null 2>&1; then
    resolved="$(resolve_existing_path "$(command -v gitleaks.exe)" || true)"
    if [[ -n "$resolved" && -x "$resolved" ]]; then
      printf '%s\n' "$resolved"
      return 0
    fi
  fi
  return 1
}

section() {
  echo
  echo "=== $1 ==="
}

collector_blocked=0
blocked() {
  collector_blocked=1
  echo "result: BLOCKED $1"
}

section "Repository"
echo "Repository: $REPO_LABEL"
if [[ -n "$HOSTED_REPO" ]]; then
  echo "Hosted: $HOSTED_REPO"
fi
echo "collector: scripts/collect-audit-evidence.sh"
echo "working directory: repository root"

section "Git"
echo "command: git rev-parse HEAD"
git_safe rev-parse HEAD
echo "command: git describe --tags --always"
git_safe describe --tags --always 2>/dev/null || true
echo "command: git ls-files | wc -l"
echo "Tracked files: $(git_safe ls-files | wc -l | tr -d ' ')"

SCREEN_SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-tracked-files.sh"
if [[ -f "$SCREEN_SCRIPT" ]]; then
  set +e
  bash "$SCREEN_SCRIPT" "$REPO_PATH"
  screen_code=$?
  set -e
  if [[ "$screen_code" -ne 0 ]]; then
    collector_blocked=1
  fi
fi

GITIGNORE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-gitignore-consistency.sh"
if [[ -f "$GITIGNORE_SCRIPT" ]]; then
  set +e
  bash "$GITIGNORE_SCRIPT" "$REPO_PATH"
  gitignore_code=$?
  set -e
  if [[ "$gitignore_code" -ne 0 ]]; then
    collector_blocked=1
  fi
fi

section "Large Tracked Files (>512KB)"
found=0
while IFS= read -r f; do
  if [[ -f "$f" ]]; then
    size=$(wc -c <"$f" | tr -d ' ')
    if [[ "$size" -gt 512000 ]]; then
      echo "$f $size"
      found=1
    fi
  fi
done < <(git_safe ls-files)
if [[ "$found" -eq 0 ]]; then echo "none"; fi

section "Root Files"
for f in README.md LICENSE SECURITY.md CODE_OF_CONDUCT.md CHANGELOG.md CONTRIBUTING.md SUPPORT.md; do
  if [[ -f "$f" ]]; then echo "$f: true"; else echo "$f: false"; fi
done

PRIMARY_CI_WORKFLOW_PATH=""
PRIMARY_CI_WORKFLOW_REASON="all_runs_fallback"
PRIMARY_CI_WORKFLOW_ID=""
if primary_ci_workflow_line="$(select_primary_ci_workflow 2>/dev/null || true)" && [[ -n "$primary_ci_workflow_line" ]]; then
  PRIMARY_CI_WORKFLOW_PATH="${primary_ci_workflow_line%%|*}"
  PRIMARY_CI_WORKFLOW_REASON="${primary_ci_workflow_line#*|}"
  PRIMARY_CI_WORKFLOW_ID="${PRIMARY_CI_WORKFLOW_PATH##*/}"
fi
if [[ -z "$PRIMARY_CI_WORKFLOW_PATH" && -n "$HOSTED_REPO" ]]; then
  workflows_json="$(github_api "repos/$HOSTED_REPO/actions/workflows" 2>/dev/null || true)"
  if [[ -n "$workflows_json" ]]; then
    if hosted_primary_ci_line="$(select_hosted_primary_ci_workflow "$workflows_json" 2>/dev/null || true)" && [[ -n "$hosted_primary_ci_line" ]]; then
      PRIMARY_CI_WORKFLOW_PATH="${hosted_primary_ci_line%%|*}"
      PRIMARY_CI_WORKFLOW_REASON="${hosted_primary_ci_line#*|}"
      PRIMARY_CI_WORKFLOW_ID="${PRIMARY_CI_WORKFLOW_PATH##*/}"
    fi
  fi
fi

section "GitHub Files"
for f in \
  .github/ISSUE_TEMPLATE/bug_report.md \
  .github/ISSUE_TEMPLATE/feature_request.md \
  .github/ISSUE_TEMPLATE/config.yml \
  .github/PULL_REQUEST_TEMPLATE.md \
  .github/dependabot.yml \
  .github/workflows/ci.yml \
  .github/workflows/codeql.yml
do
  if [[ -f "$f" ]]; then echo "$f: true"; else echo "$f: false"; fi
done
if [[ -n "$PRIMARY_CI_WORKFLOW_PATH" ]]; then
  echo "primary_ci_workflow: $PRIMARY_CI_WORKFLOW_PATH"
  echo "primary_ci_selection: $PRIMARY_CI_WORKFLOW_REASON"
else
  echo "primary_ci_workflow: none"
  echo "primary_ci_selection: all_runs_fallback"
fi

section "Gitleaks"
if GITLEAKS_CMD="$(resolve_gitleaks)"; then
  echo "command: gitleaks detect --source . --no-banner"
  echo "resolved: $(redact_path "$GITLEAKS_CMD")"
  set +e
  gitleaks_output="$("$GITLEAKS_CMD" detect --source . --no-banner 2>&1)"
  gitleaks_code=$?
  set -e
  printf '%s\n' "$gitleaks_output" | tail -n 3
  echo "exit code: $gitleaks_code"
  case "$gitleaks_code" in
    0) echo "result: PASS" ;;
    1) blocked "(gitleaks findings)" ;;
    *)
      if [[ "$IS_WINDOWS_BASH" -eq 1 ]] && printf '%s' "$gitleaks_output" | grep -q "Is a directory"; then
        echo "result: SKIPPED (Windows Git Bash cannot score G-01 from WinGet gitleaks path; use collect-audit-evidence.ps1)"
      elif [[ "$IS_WINDOWS_BASH" -eq 1 ]] && printf '%s' "$gitleaks_output" | grep -q "Access is denied"; then
        echo "result: SKIPPED (execution environment denied gitleaks execution; use direct gitleaks transcript for G-01 scoring)"
      elif printf '%s' "$gitleaks_output" | grep -q "Is a directory"; then
        blocked "(execution environment exposed the resolved gitleaks path as a directory)"
      elif printf '%s' "$gitleaks_output" | grep -q "Access is denied"; then
        echo "result: SKIPPED (execution environment denied gitleaks execution; use direct gitleaks transcript for G-01 scoring)"
      else
        blocked "(gitleaks execution failed)"
      fi
      ;;
  esac
else
  echo "gitleaks: unavailable"
  if [[ "$IS_WINDOWS_BASH" -eq 1 ]]; then
    echo "result: SKIPPED (Windows Git Bash cannot score G-01; use collect-audit-evidence.ps1)"
  else
    blocked "(G-01 cannot pass without a baseline gitleaks transcript)"
  fi
fi

if [[ -f pytest.ini || -d tests ]]; then
  section "Pytest"
  set +e
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pytest -q 2>&1 | tail -n 5
  elif command -v python >/dev/null 2>&1; then
    python -m pytest -q 2>&1 | tail -n 5
  else
    echo "python: not installed"
  fi
  set -e
fi

if [[ -n "$HOSTED_REPO" ]]; then
  section "Hosted Metadata"
  echo "commands: repos/$HOSTED_REPO ; repos/$HOSTED_REPO/community/profile ; repos/$HOSTED_REPO security_and_analysis"
  set +e
  repo_json="$(github_api "repos/$HOSTED_REPO" 2>/dev/null)"
  repo_status=$?
  community_json="$(github_api "repos/$HOSTED_REPO/community/profile" 2>/dev/null)"
  community_status=$?
  security_json="$(github_api "repos/$HOSTED_REPO" 2>/dev/null)"
  security_status=$?
  if [[ "$repo_status" -eq 0 && "$community_status" -eq 0 && "$security_status" -eq 0 ]]; then
    projected_repo="$(printf '%s' "$repo_json" | json_project repo)"
    projected_community="$(printf '%s' "$community_json" | json_project community)"
    projected_security="$(printf '%s' "$security_json" | json_project security)"
    printf '%s\n' "$projected_repo"
    printf '%s\n' "$projected_community"
    printf '%s\n' "$projected_security"
  else
    blocked "(API_BLOCKED: hosted metadata unavailable)"
  fi
  section "Hosted Issue Templates"
  echo "commands: contents/.github/ISSUE_TEMPLATE/{bug_report.md,feature_request.md,config.yml}"
  if printf '%s' "$repo_json" | tr -d '[:space:]' | grep -q '"has_issues":false'; then
    echo "result: NOT_APPLICABLE (issues disabled)"
  else
    issue_api_blocked=0
    for issue_path in \
      ".github/ISSUE_TEMPLATE/bug_report.md" \
      ".github/ISSUE_TEMPLATE/feature_request.md" \
      ".github/ISSUE_TEMPLATE/config.yml"
    do
      issue_json="$(github_api "repos/$HOSTED_REPO/contents/$issue_path" 2>/dev/null)"
      issue_status=$?
      if [[ "$issue_status" -eq 0 ]]; then
        printf '{"path":"%s","requested":"%s","result":"PASS"}\n' \
          "$(printf '%s' "$issue_json" | tr -d '\r\n' | sed -n 's/.*"path":"\([^"]*\)".*/\1/p')" \
          "$issue_path"
      elif [[ "$issue_status" -eq 4 ]]; then
        printf '{"path":null,"requested":"%s","result":"ABSENT"}\n' "$issue_path"
      else
        issue_api_blocked=1
        printf '{"path":null,"requested":"%s","result":"API_BLOCKED"}\n' "$issue_path"
      fi
    done
    if [[ "$issue_api_blocked" -ne 0 ]]; then
      blocked "(API_BLOCKED: hosted issue-template lookup unavailable)"
    fi
  fi
  section "Latest CI"
  echo "command: gh run list -R $HOSTED_REPO --limit 3 (or public actions runs API fallback)"
  default_branch="$(printf '%s' "$repo_json" | json_extract_default_branch 2>/dev/null || true)"
  if [[ -n "$PRIMARY_CI_WORKFLOW_PATH" && -n "$default_branch" ]]; then
    runs_api_path="repos/$HOSTED_REPO/actions/workflows/$PRIMARY_CI_WORKFLOW_ID/runs?branch=$default_branch"
    evidence_scope="default_branch"
  elif [[ -n "$PRIMARY_CI_WORKFLOW_PATH" ]]; then
    runs_api_path="repos/$HOSTED_REPO/actions/workflows/$PRIMARY_CI_WORKFLOW_ID/runs?per_page=3"
    evidence_scope="recent_runs"
  elif [[ -n "$default_branch" ]]; then
    runs_api_path="repos/$HOSTED_REPO/actions/runs?branch=$default_branch"
    evidence_scope="default_branch"
  else
    runs_api_path="repos/$HOSTED_REPO/actions/runs?per_page=3"
    evidence_scope="recent_runs"
  fi
  runs_json="$(github_api "$runs_api_path" 2>/dev/null)"
  runs_status=$?
  if [[ "$runs_status" -ne 0 && -n "$PRIMARY_CI_WORKFLOW_PATH" ]]; then
    if [[ -n "$default_branch" ]]; then
      fallback_runs_api_path="repos/$HOSTED_REPO/actions/runs?branch=$default_branch"
      evidence_scope="default_branch"
    else
      fallback_runs_api_path="repos/$HOSTED_REPO/actions/runs?per_page=3"
      evidence_scope="recent_runs"
    fi
    runs_json="$(github_api "$fallback_runs_api_path" 2>/dev/null)"
    runs_status=$?
  fi
  workflow_files_present=0
  if compgen -G ".github/workflows/*" >/dev/null 2>&1; then
    workflow_files_present=1
  fi
  if [[ "$runs_status" -eq 0 ]]; then
    compact_runs="$(printf '%s' "$runs_json" | tr -d '\r\n[:space:]')"
    if printf '%s' "$compact_runs" | grep -q '"workflow_runs":\[\]'; then
      if [[ "$workflow_files_present" -eq 1 ]]; then
        echo "result: NO_RUNS (workflow files exist but the GitHub Actions runs API returned 0 runs)"
      else
        echo "result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)"
      fi
    else
      runs_file="$(mktemp)"
      jobs_file="$(mktemp)"
      branch_filters_file="$(mktemp)"
      if [[ -n "$PRIMARY_CI_WORKFLOW_PATH" ]]; then
        raw_runs_file="${runs_file}.raw"
        printf '%s' "$runs_json" >"$raw_runs_file"
        if ! json_filter_runs_by_workflow_path "$raw_runs_file" "$PRIMARY_CI_WORKFLOW_PATH" >"$runs_file"; then
          rm -f "$raw_runs_file" "$runs_file" "$jobs_file" "$branch_filters_file"
          blocked "(API_BLOCKED: latest CI metadata unavailable)"
          set -e
          exit 1
        fi
        rm -f "$raw_runs_file"
      else
        printf '%s' "$runs_json" >"$runs_file"
      fi
      printf '{}' >"$jobs_file"
      printf '{}' >"$branch_filters_file"
      filtered_runs_json="$(cat "$runs_file")"
      if run_ids="$(printf '%s' "$filtered_runs_json" | json_list_run_ids 2>/dev/null)"; then
        while IFS= read -r run_id; do
          [[ -n "$run_id" ]] || continue
          jobs_json="$(github_api "repos/$HOSTED_REPO/actions/runs/$run_id/jobs?per_page=1" 2>/dev/null)"
          jobs_status=$?
          [[ "$jobs_status" -eq 0 ]] || continue
          jobs_total="$(printf '%s' "$jobs_json" | json_extract_total_count 2>/dev/null || true)"
          [[ -n "$jobs_total" ]] || continue
          jobs_file_tmp="$(mktemp)"
          py_update="$(json_python)"
          "$py_update" - "$jobs_file" "$jobs_file_tmp" "$run_id" "$jobs_total" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)
obj[str(sys.argv[3])] = int(sys.argv[4])
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(obj, fh, separators=(",", ":"))
PY
          mv "$jobs_file_tmp" "$jobs_file"
        done <<< "$run_ids"
      fi
      while IFS='|' read -r run_id run_path; do
        [[ -n "$run_id" && -n "$run_path" ]] || continue
        normalized_run_path="$(workflow_run_local_path "$run_path" || true)"
        [[ -n "$normalized_run_path" ]] || continue
        if workflow_has_branch_filters "$normalized_run_path"; then
          branch_filters_tmp="$(mktemp)"
          py_update="$(json_python)"
          "$py_update" - "$branch_filters_file" "$branch_filters_tmp" "$run_id" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)
obj[str(sys.argv[3])] = True
with open(sys.argv[2], "w", encoding="utf-8") as fh:
    json.dump(obj, fh, separators=(",", ":"))
PY
          mv "$branch_filters_tmp" "$branch_filters_file"
        fi
      done < <(
        py_list="$(json_python)"
        "$py_list" - "$runs_file" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    obj = json.load(fh)

for item in (obj.get("workflow_runs") or [])[:3]:
    run_id = item.get("id")
    path = item.get("path")
    if run_id is None or not path:
        continue
    print(f"{run_id}|{str(path).split('@', 1)[0].strip()}")
PY
      )
      json_project_runs_with_jobs "$runs_file" "$jobs_file" "$branch_filters_file" "$evidence_scope" "$default_branch" "$PRIMARY_CI_WORKFLOW_PATH" "$PRIMARY_CI_WORKFLOW_REASON"
      printf '\n'
      rm -f "$runs_file" "$jobs_file" "$branch_filters_file"
    fi
  else
    blocked "(API_BLOCKED: latest CI metadata unavailable)"
  fi
  set -e
fi

MANIFEST_PATH="$REPO_PATH/audit.manifest.yml"
QUICKSTART_SCRIPT="$(cd "$(dirname "$0")" && pwd)/run-audit-quickstart.sh"
if [[ -f "$MANIFEST_PATH" && -f "$QUICKSTART_SCRIPT" ]]; then
  section "Quickstart"
  echo "command: bash scripts/run-audit-quickstart.sh <repo>"
  set +e
  bash "$QUICKSTART_SCRIPT" "$REPO_PATH"
  qs_code=$?
  set -e
  if [[ "$qs_code" -ne 0 ]]; then
    exit "$qs_code"
  fi
fi

if [[ "$collector_blocked" -ne 0 ]]; then
  exit 1
fi
