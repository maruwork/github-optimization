#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
MANIFEST_PATH="${2:-$REPO_PATH/audit.manifest.yml}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "audit.manifest.yml: missing"
  echo "quickstart automation: skipped — agent must derive commands from README.md and execute them"
  exit 2
fi

echo "=== Quickstart Manifest ==="
echo "Manifest: $MANIFEST_PATH"

WORKDIR="$(awk -F': *' '/^workdir:/{print $2; exit}' "$MANIFEST_PATH" | tr -d ' \"')"
WORKDIR="${WORKDIR:-in-place}"

RUN_ROOT="$REPO_PATH"
TEMP_ROOT=""
if [[ "$WORKDIR" == "isolated" ]]; then
  TEMP_ROOT="$(mktemp -d -t audit-quickstart.XXXXXX)"
  cp -a "$REPO_PATH/." "$TEMP_ROOT/"
  RUN_ROOT="$TEMP_ROOT"
  echo "Isolated workdir: $RUN_ROOT"
else
  echo "In-place workdir: $RUN_ROOT"
fi

failures=0
ran=0

while IFS= read -r block; do
  id="$(printf '%s\n' "$block" | awk -F': *' '/^  id:/{print $2; exit}')"
  cmd="$(printf '%s\n' "$block" | awk -F': *' '/^  run:/{print $2; exit}')"
  expect_exit="$(printf '%s\n' "$block" | awk -F': *' '/^  expect_exit:/{print $2; exit}')"
  expect_exit="${expect_exit:-0}"

  [[ -z "$id" || -z "$cmd" ]] && continue
  [[ "$cmd" =~ ^\<.*\>$ ]] && continue

  echo
  echo "=== quickstart:$id ==="
  echo "run: $cmd"
  set +e
  (cd "$RUN_ROOT" && bash -lc "$cmd")
  code=$?
  set -e
  ran=$((ran + 1))
  if [[ "$code" -ne "$expect_exit" ]]; then
    echo "result: FAIL (exit $code, expected $expect_exit)"
    failures=$((failures + 1))
  else
    echo "result: PASS"
  fi
done < <(awk 'BEGIN{RS="- id:"} NR>1 {print "- id:" $0}' "$MANIFEST_PATH")

[[ -n "$TEMP_ROOT" ]] && rm -rf "$TEMP_ROOT"

echo
echo "=== Quickstart Summary ==="
echo "commands run: $ran"
echo "failures: $failures"

if [[ "$ran" -eq 0 ]]; then
  exit 2
fi
if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
exit 0