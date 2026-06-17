#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
HOSTED_REPO="${2:-}"

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
git rev-parse HEAD
git describe --tags --always 2>/dev/null || true
echo "Tracked files: $(git ls-files | wc -l | tr -d ' ')"

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
done < <(git ls-files)
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
  .github/workflows/regulation-tests.yml
do
  if [[ -f "$f" ]]; then echo "$f: true"; else echo "$f: false"; fi
done

section "Gitleaks"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --no-banner 2>&1 | tail -n 3
else
  echo "gitleaks: not installed"
fi

if [[ -f pytest.ini || -d tests ]]; then
  section "Pytest"
  python -m pytest -q 2>&1 | tail -n 5
fi

if [[ -n "$HOSTED_REPO" ]] && command -v gh >/dev/null 2>&1; then
  section "Hosted Metadata"
  gh api "repos/$HOSTED_REPO" --jq '{description, topics: .topics, homepage, visibility}'
  gh api "repos/$HOSTED_REPO/community/profile" --jq '{health_percentage}'
  gh api "repos/$HOSTED_REPO" --jq '.security_and_analysis'
  section "Latest CI"
  gh run list -R "$HOSTED_REPO" --limit 3
fi

QUICKSTART_SCRIPT="$(cd "$(dirname "$0")" && pwd)/run-audit-quickstart.sh"
if [[ -f "$QUICKSTART_SCRIPT" ]]; then
  section "Quickstart"
  bash "$QUICKSTART_SCRIPT" "$REPO_PATH" || true
fi