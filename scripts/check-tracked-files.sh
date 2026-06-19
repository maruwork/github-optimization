#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
VERBOSE="${VERBOSE:-0}"

cd "$REPO_PATH"
REPO_PATH="$(pwd)"
REPO_LABEL="$(basename "$REPO_PATH")"

git_safe() {
  git -c core.excludesFile=/dev/null -c "safe.directory=$REPO_PATH" "$@"
}

is_shelf=0
[[ -f regulation/REGULATION_INDEX.md ]] && is_shelf=1

shelf_allowed() {
  case "$1" in
    audits/README.md|docs/governance/README.md)
      return 0 ;;
    *) return 1 ;;
  esac
}

declare -a findings=()

add_finding() {
  local path="$1" category="$2" severity="$3" reason="$4"
  if [[ "$is_shelf" -eq 1 ]] && shelf_allowed "$path"; then
    return 0
  fi
  findings+=("$severity|$category|$path|$reason")
}

while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  norm="${rel//\\//}"

  if [[ "$norm" =~ ^(AGENTS|CLAUDE)\.md$ ]]; then
    add_finding "$norm" "developer-only" "blocked" "AI control file must not be tracked"
    continue
  fi
  if [[ "$norm" == *.claudeignore ]]; then
    add_finding "$norm" "developer-only" "blocked" "AI ignore file must not be tracked"
    continue
  fi
  if [[ "$norm" == *__pycache__/* ]]; then
    add_finding "$norm" "cache-artifact" "blocked" "Python cache directory must not be tracked"
    continue
  fi
  if [[ "$norm" == *.pyc ]]; then
    add_finding "$norm" "cache-artifact" "blocked" "Compiled Python artifact must not be tracked"
    continue
  fi
  if [[ "$norm" == *".pytest_cache/"* || "$norm" == .pytest_cache/* ]]; then
    add_finding "$norm" "cache-artifact" "blocked" "Pytest cache must not be tracked"
    continue
  fi
  if [[ "$norm" == .env ]]; then
    add_finding "$norm" "secret-risk" "blocked" "Environment file must not be tracked"
    continue
  fi
  if [[ "$norm" =~ ^(design|roadmap|tasks)/ ]]; then
    add_finding "$norm" "internal-management" "blocked" "Shelf build history must not be tracked"
    continue
  fi
  if [[ "$is_shelf" -eq 0 && "$norm" == audits/* ]]; then
    add_finding "$norm" "audit-in-product" "blocked" "Audit outputs belong in github-optimization/audits/<slug>/"
    continue
  fi
  if [[ "$norm" =~ ^docs/governance/ && "$norm" != docs/governance/README.md ]]; then
    if [[ "$is_shelf" -eq 1 ]]; then
      add_finding "$norm" "governance-in-shelf" "blocked" "Filled governance records belong in audits/<slug>/ on the regulation shelf"
    else
      add_finding "$norm" "governance-in-product" "blocked" "Governance audit records belong on the regulation shelf"
    fi
    continue
  fi
  if [[ "$norm" =~ ^(common|index|archive|workspace)/ ]]; then
    add_finding "$norm" "internal-management-candidate" "review" "Typical internal-management path; confirm user-facing intent"
    continue
  fi
done < <(git_safe ls-files)

root_count=0
while IFS= read -r rel; do
  [[ -z "$rel" ]] && continue
  [[ "$rel" != */* ]] && root_count=$((root_count + 1))
done < <(git_safe ls-files)

if [[ "$root_count" -gt 12 ]]; then
  add_finding "(root)" "root-clutter" "review" "Root has ${root_count} tracked entries; confirm each is user-facing or GitHub-standard"
fi

echo "=== Tracked File Screening ==="
echo "Repository: $REPO_LABEL"
if [[ "$is_shelf" -eq 1 ]]; then echo "Mode: regulation-shelf"; else echo "Mode: product"; fi
echo "Tracked files: $(git_safe ls-files | wc -l | tr -d ' ')"

blocked=0
review=0
for row in "${findings[@]:-}"; do
  IFS='|' read -r severity category path reason <<< "$row"
  [[ "$severity" == blocked ]] && blocked=$((blocked + 1))
  [[ "$severity" == review ]] && review=$((review + 1))
done

if [[ ${#findings[@]} -eq 0 ]]; then
  echo "Suspicious tracked files: none"
  echo "result: PASS"
  exit 0
fi

echo "Suspicious tracked files: ${#findings[@]} (blocked: $blocked, review: $review)"
for row in "${findings[@]}"; do
  IFS='|' read -r severity category path reason <<< "$row"
  echo "[$severity/$category] $path - $reason"
done

if [[ "$VERBOSE" == 1 ]]; then
  echo
  echo "All tracked files:"
  git_safe ls-files | sed 's/^/  /'
fi

if [[ "$blocked" -gt 0 ]]; then
  echo "result: BLOCKED"
  exit 1
fi

echo "result: PASS_WITH_REVIEW"
exit 0
