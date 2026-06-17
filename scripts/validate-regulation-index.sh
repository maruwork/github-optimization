#!/usr/bin/env bash
set -euo pipefail

SHELF_PATH="${1:-${GITHUB_OPTIMIZATION_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}}"
INDEX="$SHELF_PATH/regulation/REGULATION_INDEX.md"

if [[ ! -f "$INDEX" ]]; then
  echo "regulation/REGULATION_INDEX.md not found at $SHELF_PATH" >&2
  exit 1
fi

declare -a REQUIRED=()
in_required=0

while IFS= read -r line; do
  if [[ "$line" == "## Required"* ]]; then
    in_required=1
    continue
  fi
  if [[ "$line" == "## Excluded"* ]]; then
    break
  fi
  if [[ "$in_required" -eq 1 && "$line" =~ ^-[[:space:]]+\`([^\`]+)\` ]]; then
    path="${BASH_REMATCH[1]}"
    if [[ "$path" != *"**"* && "$path" != all\ * ]]; then
      REQUIRED+=("$path")
    fi
  fi
done <"$INDEX"

while IFS= read -r -d '' f; do
  REQUIRED+=("templates/$(basename "$f")")
done < <(find "$SHELF_PATH/templates" -maxdepth 1 -name '*.template' -print0)

failures=0
declare -A SEEN=()
for rel in "${REQUIRED[@]}"; do
  [[ -n "${SEEN[$rel]:-}" ]] && continue
  SEEN[$rel]=1
  if [[ ! -e "$SHELF_PATH/$rel" ]]; then
    echo "FAIL: missing required file: $rel"
    failures=$((failures + 1))
  fi
done

GATE_FILE="$SHELF_PATH/regulation/gates/GATE_REGISTRY.md"
if [[ -f "$GATE_FILE" ]]; then
  for prefix in G R P; do
    max=22
    [[ "$prefix" == "R" ]] && max=14
    [[ "$prefix" == "P" ]] && max=10
    for ((i = 1; i <= max; i++)); do
      id=$(printf '%s-%02d' "$prefix" "$i")
      if ! grep -q "| $id " "$GATE_FILE"; then
        echo "FAIL: GATE_REGISTRY missing row: $id"
        failures=$((failures + 1))
      fi
    done
  done
else
  echo "FAIL: missing regulation/gates/GATE_REGISTRY.md"
  failures=$((failures + 1))
fi

unique_count=${#SEEN[@]}
echo "=== Regulation Index Validation ==="
echo "Shelf: $SHELF_PATH"
echo "Required paths checked: $unique_count"

if [[ "$failures" -eq 0 ]]; then
  echo "result: PASS"
  exit 0
fi

echo "result: FAIL ($failures issues)"
exit 1