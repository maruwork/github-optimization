#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
cd "$REPO_PATH"
REPO_PATH="$(pwd)"

declare -a findings=()

add_finding() {
  findings+=("$2|$3|$1|$4")
}

recommended=(
  "__pycache__/"
  "*.pyc"
  ".pytest_cache/"
  ".env"
  "AGENTS.md"
  "CLAUDE.md"
  ".claudeignore"
)

if [[ ! -f .gitignore ]]; then
  add_finding ".gitignore" "missing-file" "review" "No root .gitignore file"
  gitignore_text=""
else
  gitignore_text="$(cat .gitignore)"
fi

for pattern in "${recommended[@]}"; do
  if [[ -n "$gitignore_text" ]] && ! grep -Fq "$pattern" .gitignore 2>/dev/null; then
    add_finding "$pattern" "missing-recommended-rule" "review" "Recommended public-prep ignore rule not present in .gitignore"
  fi
done

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  rule="$(git check-ignore -v "$rel" 2>/dev/null | head -n 1 || true)"
  add_finding "$rel" "tracked-but-ignored" "blocked" "Tracked file matches ignore rule: ${rule:-unknown}"
done < <(git ls-files -ci --exclude-standard 2>/dev/null || true)

echo "=== Gitignore Consistency ==="
echo "Repository: $REPO_PATH"
echo "Tracked files: $(git ls-files | wc -l | tr -d ' ')"

blocked=0
review=0
for row in "${findings[@]:-}"; do
  IFS='|' read -r severity category path reason <<< "$row"
  [[ "$severity" == blocked ]] && blocked=$((blocked + 1))
  [[ "$severity" == review ]] && review=$((review + 1))
done

if [[ ${#findings[@]} -eq 0 ]]; then
  echo "Findings: none"
  echo "result: PASS"
  exit 0
fi

echo "Findings: ${#findings[@]} (blocked: $blocked, review: $review)"
for row in "${findings[@]}"; do
  IFS='|' read -r severity category path reason <<< "$row"
  echo "[$severity/$category] $path — $reason"
done

if [[ "$blocked" -gt 0 ]]; then
  echo "result: BLOCKED"
  exit 1
fi

echo "result: PASS_WITH_REVIEW"
exit 0