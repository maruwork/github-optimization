#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
HOSTED_REPO="${2:-}"

git_safe() {
  git -c core.excludesFile=/dev/null -c "safe.directory=$REPO_PATH" "$@"
}

github_api() {
  local path="$1"
  if command -v gh >/dev/null 2>&1; then
    gh api "$path"
    return $?
  fi
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -H "User-Agent: github-optimization-audit" "https://api.github.com/$path"
    return $?
  fi
  return 127
}

resolve_gitleaks() {
  if command -v gitleaks >/dev/null 2>&1; then
    command -v gitleaks
    return 0
  fi
  if command -v gitleaks.exe >/dev/null 2>&1; then
    command -v gitleaks.exe
    return 0
  fi
  local candidate
  for candidate in /mnt/c/Users/*/AppData/Local/Microsoft/WinGet/Links/gitleaks.exe; do
    [[ -x "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

section() {
  echo
  echo "=== $1 ==="
}

cd "$REPO_PATH"

section "Repository"
echo "Path: $REPO_PATH"
if [[ -n "$HOSTED_REPO" ]]; then
  echo "Hosted: $HOSTED_REPO"
fi

section "Git"
git_safe rev-parse HEAD
git_safe describe --tags --always 2>/dev/null || true
echo "Tracked files: $(git_safe ls-files | wc -l | tr -d ' ')"

SCREEN_SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-tracked-files.sh"
if [[ -f "$SCREEN_SCRIPT" ]]; then
  set +e
  bash "$SCREEN_SCRIPT" "$REPO_PATH"
  set -e
fi

GITIGNORE_SCRIPT="$(cd "$(dirname "$0")" && pwd)/check-gitignore-consistency.sh"
if [[ -f "$GITIGNORE_SCRIPT" ]]; then
  set +e
  bash "$GITIGNORE_SCRIPT" "$REPO_PATH"
  set -e
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
  set +e
  "$GITLEAKS_CMD" detect --source . --no-banner 2>&1 | tail -n 3
  gitleaks_code=${PIPESTATUS[0]}
  set -e
  echo "exit code: $gitleaks_code"
  case "$gitleaks_code" in
    0) echo "result: PASS" ;;
    1) echo "result: BLOCKED (gitleaks findings)" ;;
    *) echo "result: BLOCKED (gitleaks execution failed)" ;;
  esac
else
  echo "gitleaks: unavailable"
  echo "result: BLOCKED (G-01 cannot pass without a baseline gitleaks transcript)"
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
  set +e
  github_api "repos/$HOSTED_REPO"
  github_api "repos/$HOSTED_REPO/community/profile"
  github_api "repos/$HOSTED_REPO"
  section "Hosted Issue Templates"
  github_api "repos/$HOSTED_REPO/contents/.github/ISSUE_TEMPLATE/bug_report.md"
  github_api "repos/$HOSTED_REPO/contents/.github/ISSUE_TEMPLATE/feature_request.md"
  github_api "repos/$HOSTED_REPO/contents/.github/ISSUE_TEMPLATE/config.yml"
  section "Latest CI"
  if command -v gh >/dev/null 2>&1; then
    gh run list -R "$HOSTED_REPO" --limit 3
  else
    github_api "repos/$HOSTED_REPO/actions/runs?per_page=3"
  fi
  set -e
fi

MANIFEST_PATH="$REPO_PATH/audit.manifest.yml"
QUICKSTART_SCRIPT="$(cd "$(dirname "$0")" && pwd)/run-audit-quickstart.sh"
if [[ -f "$MANIFEST_PATH" && -f "$QUICKSTART_SCRIPT" ]]; then
  section "Quickstart"
  set +e
  bash "$QUICKSTART_SCRIPT" "$REPO_PATH"
  qs_code=$?
  set -e
  if [[ "$qs_code" -ne 0 ]]; then
    exit "$qs_code"
  fi
fi
