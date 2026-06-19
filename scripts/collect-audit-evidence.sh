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
  py="$(json_python)" || return 1
  input="$(cat)"
  JSON_PROJECT_INPUT="$input" "$py" - "$mode" <<'PY'
import json
import os
import sys

mode = sys.argv[1]
obj = json.loads(os.environ["JSON_PROJECT_INPUT"])

if mode == "repo":
    out = {
        "description": obj.get("description"),
        "topics": obj.get("topics"),
        "homepage": obj.get("homepage"),
        "visibility": obj.get("visibility"),
        "has_issues": obj.get("has_issues"),
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
  runs_json="$(github_api "repos/$HOSTED_REPO/actions/runs?per_page=3" 2>/dev/null)"
  runs_status=$?
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
      printf '%s' "$runs_json" | json_project runs
      printf '\n'
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
