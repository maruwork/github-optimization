#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:?repo path required}"
MANIFEST_PATH="${2:-$REPO_PATH/audit.manifest.yml}"

if [[ ! -f "$MANIFEST_PATH" ]]; then
  echo "audit.manifest.yml: missing"
  echo "quickstart automation: skipped - agent must derive commands from README.md and execute them"
  exit 2
fi

trim_manifest_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

resolve_cmd() {
  local block="$1"
  local cmd
  cmd="$(printf '%s\n' "$block" | awk -F': *' '/^[[:space:]]+run_unix:/{print $2; exit}')"
  if [[ -n "$cmd" ]]; then
    echo "$cmd"
    return 0
  fi
  cmd="$(printf '%s\n' "$block" | awk -F': *' '/^[[:space:]]+run:/{print $2; exit}')"
  if [[ -n "$cmd" ]]; then
    echo "$cmd"
    return 0
  fi
  return 1
}

echo "=== Quickstart Manifest ==="
echo "Manifest: $MANIFEST_PATH"

WORKDIR="$(awk -F': *' '/^workdir:/{print $2; exit}' "$MANIFEST_PATH")"
WORKDIR="$(trim_manifest_value "$WORKDIR")"
WORKDIR="${WORKDIR:-in-place}"

declare -a ENV_KEYS=()
declare -a ENV_VALUES=()
declare -a ASSERT_PATHS=()
section=""
while IFS= read -r line; do
  if [[ "$line" =~ ^[^[:space:]] ]]; then
    case "$line" in
      env:*) section="env" ;;
      assertions:*) section="assertions" ;;
      *) section="" ;;
    esac
    continue
  fi

  if [[ "$section" == "env" ]] && [[ "$line" =~ ^[[:space:]]{2}([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:[[:space:]]*(.+)[[:space:]]*$ ]]; then
    ENV_KEYS+=("${BASH_REMATCH[1]}")
    ENV_VALUES+=("$(trim_manifest_value "${BASH_REMATCH[2]}")")
    continue
  fi

  if [[ "$section" == "assertions" ]] && [[ "$line" =~ ^[[:space:]]{4}path_exists:[[:space:]]*(.+)[[:space:]]*$ ]]; then
    ASSERT_PATHS+=("$(trim_manifest_value "${BASH_REMATCH[1]}")")
  fi
done < "$MANIFEST_PATH"

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
assertions_run=0

while IFS= read -r -d '' block; do
  [[ -z "$block" ]] && continue
  id="$(printf '%s\n' "$block" | sed -n '1s/^- id: *//p')"
  cmd="$(resolve_cmd "$block" || true)"
  expect_exit="$(printf '%s\n' "$block" | awk -F': *' '/^[[:space:]]+expect_exit:/{print $2; exit}')"
  expect_exit="${expect_exit:-0}"

  [[ -z "$id" || -z "$cmd" ]] && continue
  [[ "$cmd" =~ ^\<.*\>$ ]] && continue

  echo
  echo "=== quickstart:$id ==="
  echo "run: $cmd"
  cmd_env=()
  for idx in "${!ENV_KEYS[@]}"; do
    cmd_env+=("${ENV_KEYS[$idx]}=${ENV_VALUES[$idx]}")
  done
  set +e
  (cd "$RUN_ROOT" && env "${cmd_env[@]}" bash -lc "$cmd")
  code=$?
  set -e
  ran=$((ran + 1))
  if [[ "$code" -ne "$expect_exit" ]]; then
    echo "result: FAIL (exit $code, expected $expect_exit)"
    failures=$((failures + 1))
  else
    echo "result: PASS"
  fi
done < <(awk 'BEGIN{RS="- id:"} NR>1 {printf "- id:%s\0", $0}' "$MANIFEST_PATH")

for path in "${ASSERT_PATHS[@]}"; do
  echo
  echo "=== assertion:path_exists:$path ==="
  assertions_run=$((assertions_run + 1))
  if [[ -e "$RUN_ROOT/$path" ]]; then
    echo "result: PASS"
  else
    echo "result: FAIL (missing path)"
    failures=$((failures + 1))
  fi
done

[[ -n "$TEMP_ROOT" ]] && rm -rf "$TEMP_ROOT"

echo
echo "=== Quickstart Summary ==="
echo "commands run: $ran"
echo "assertions run: $assertions_run"
echo "failures: $failures"

if [[ "$ran" -eq 0 ]]; then
  exit 2
fi
if [[ "$failures" -gt 0 ]]; then
  exit 1
fi
exit 0
