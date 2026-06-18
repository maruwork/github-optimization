#!/usr/bin/env bash
set -euo pipefail

SHELF="${GITHUB_OPTIMIZATION_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
failures=0

run_pass() {
  local name="$1"
  shift
  echo "TEST: $name"
  if "$@"; then
    echo "  PASS"
  else
    echo "  FAIL"
    failures=$((failures + 1))
  fi
}

run_exit() {
  local name="$1"
  local expected="$2"
  shift 2
  echo "TEST: $name"
  set +e
  "$@"
  local code=$?
  set -e
  if [[ "$code" -eq "$expected" ]]; then
    echo "  PASS"
  else
    echo "  FAIL: expected exit $expected, got $code"
    failures=$((failures + 1))
  fi
}

FIXTURE="$SHELF/scripts/tests/fixtures/minimal-docs-repo"
TRACKED_IGNORED="$SHELF/scripts/tests/fixtures/tracked-ignored-repo"
DELTA_DRY_RUN_SLUG="delta-orchestrator-dry-run"
FIXTURE_SLUG="minimal-docs-repo"
SHELF_DRY_RUN_SLUG="shelf-orchestrator-dry-run"

cleanup_generated() {
  rm -rf \
    "$SHELF/audits/$DELTA_DRY_RUN_SLUG" \
    "$SHELF/audits/$FIXTURE_SLUG" \
    "$SHELF/audits/$SHELF_DRY_RUN_SLUG" \
    "$FIXTURE/.git" \
    "$TRACKED_IGNORED/.git" \
    "$TRACKED_IGNORED/local-only.secret" \
    "$SHELF/scripts/tests/fixtures/quickstart-isolated-repo/out"
}

fixture_git() {
  git -C "$1" -c "safe.directory=$1" "${@:2}"
}

cleanup_generated

run_pass "validate-regulation-index" bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
run_exit "check-tracked-files on shelf" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$SHELF"
run_exit "check-tracked-files on fixture" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$FIXTURE"
run_exit "check-gitignore-consistency on shelf" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$SHELF"
run_exit "check-gitignore-consistency on fixture" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$FIXTURE"
if [[ ! -d "$TRACKED_IGNORED/.git" ]]; then
  printf '%s' 'fixture-secret=tracked-but-ignored' >"$TRACKED_IGNORED/local-only.secret"
  fixture_git "$TRACKED_IGNORED" init
  fixture_git "$TRACKED_IGNORED" add README.md LICENSE SECURITY.md .gitignore
  fixture_git "$TRACKED_IGNORED" add -f local-only.secret
  fixture_git "$TRACKED_IGNORED" -c user.email=fixture@test -c user.name=fixture commit -m "init tracked-ignored fixture"
fi
run_exit "check-gitignore-consistency blocked tracked-ignored fixture" 1 \
  bash "$SHELF/scripts/check-gitignore-consistency.sh" "$TRACKED_IGNORED"
echo "TEST: collect-audit-evidence completes transcript and exits blocked after blocked gitignore"
set +e
evidence_out="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$TRACKED_IGNORED" 2>&1)"
evidence_code=$?
set -e
if [[ "$evidence_code" -eq 1 ]] && echo "$evidence_out" | grep -q "=== Root Files ==="; then
  if echo "$evidence_out" | grep -Eq "result: BLOCKED \(execution environment .*gitleaks"; then
    echo "  FAIL: gitleaks execution-environment artifact must be SKIPPED or scored from another transcript"
    failures=$((failures + 1))
  else
    echo "  PASS"
  fi
else
  echo "  FAIL: expected exit 1 and Root Files section, got exit $evidence_code"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence treats gitleaks access-denied artifact as skipped"
fake_gitleaks="$(mktemp)"
cat >"$fake_gitleaks" <<'EOF'
#!/usr/bin/env bash
echo "Access is denied" >&2
exit 2
EOF
chmod +x "$fake_gitleaks"
set +e
access_denied_out="$(GITLEAKS_CMD="$fake_gitleaks" bash "$SHELF/scripts/collect-audit-evidence.sh" "$FIXTURE" 2>&1)"
access_denied_code=$?
set -e
rm -f "$fake_gitleaks"
if [[ "$access_denied_code" -eq 0 ]] \
  && echo "$access_denied_out" | grep -Fq "result: SKIPPED (execution environment denied gitleaks execution; use direct gitleaks transcript for G-01 scoring)"; then
  echo "  PASS"
else
  echo "  FAIL: expected SKIPPED access-denied gitleaks artifact, got exit $access_denied_code"
  failures=$((failures + 1))
fi
PRESENT_HEAD="$(git -C "$SHELF" rev-parse HEAD)"
# v1.1.4 -> present always includes audit.manifest.yml change (v1.1.5); stable across future commits
MANIFEST_PRIOR_HEAD="$(git -C "$SHELF" rev-parse "v1.1.4^{commit}")"
SKIP_SHELF_VALIDATION=1 run_exit "run-delta-audit allowed (no changes)" 0 \
  bash "$SHELF/scripts/run-delta-audit.sh" "$SHELF" "" release "$DELTA_DRY_RUN_SLUG" "$PRESENT_HEAD"
SKIP_SHELF_VALIDATION=1 run_exit "run-delta-audit invalidates manifest change" 2 \
  bash "$SHELF/scripts/run-delta-audit.sh" "$SHELF" "" release "$DELTA_DRY_RUN_SLUG" "$MANIFEST_PRIOR_HEAD"
run_exit "run-audit-quickstart missing manifest exits 2" 2 bash "$SHELF/scripts/run-audit-quickstart.sh" "$FIXTURE"
QUICKSTART_FIXTURE="$SHELF/scripts/tests/fixtures/quickstart-manifest-repo"
run_exit "run-audit-quickstart with manifest exits 0" 0 bash "$SHELF/scripts/run-audit-quickstart.sh" "$QUICKSTART_FIXTURE"
echo "TEST: run-audit-quickstart isolated env/assertions unix"
ISOLATED_FIXTURE="$SHELF/scripts/tests/fixtures/quickstart-isolated-repo"
rm -rf "$ISOLATED_FIXTURE/out"
set +e
isolated_out="$(bash "$SHELF/scripts/run-audit-quickstart.sh" "$ISOLATED_FIXTURE" 2>&1)"
isolated_code=$?
set -e
if [[ "$isolated_code" -eq 0 ]] \
  && echo "$isolated_out" | grep -Fq "=== quickstart:write-env ===" \
  && echo "$isolated_out" | grep -Fq "=== quickstart:legacy-run ===" \
  && echo "$isolated_out" | grep -Fq "=== assertion:path_exists:out/env.txt ===" \
  && echo "$isolated_out" | grep -Fq "assertions run: 1" \
  && [[ ! -e "$ISOLATED_FIXTURE/out/env.txt" ]]; then
  echo "  PASS"
else
  echo "  FAIL: expected isolated env/assertions flow to pass"
  failures=$((failures + 1))
fi
run_exit "run-audit-quickstart shelf manifest unix" 0 bash "$SHELF/scripts/run-audit-quickstart.sh" "$SHELF"

for tpl in \
  accepted-risk-record.md.template \
  audit-report.md.template \
  tier2-defer-record.md.template \
  audit.manifest.yml.template \
  delta-audit-record.md.template
do
  run_pass "template exists: $tpl" test -f "$SHELF/templates/$tpl"
done

for policy in \
  regulation/execution/RE_AUDIT_POLICY.md \
  regulation/execution/AUDIT_PHASE_POLICY.md \
  regulation/execution/MULTI_REPO_ORCHESTRATION.md \
  regulation/reference/TOOL_REVIEW_CADENCE.md
do
  run_pass "policy exists: $policy" test -f "$SHELF/$policy"
done

if [[ ! -d "$FIXTURE/.git" ]]; then
  fixture_git "$FIXTURE" init
  fixture_git "$FIXTURE" add README.md LICENSE SECURITY.md .gitignore
  fixture_git "$FIXTURE" -c user.email=fixture@test -c user.name=fixture commit -m "init minimal docs fixture"
fi

rm -f "$SHELF/audits/$FIXTURE_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on fixture" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$FIXTURE" "" public-prep pre-public "$FIXTURE_SLUG"
run_pass "fixture audit-report scaffolded" test -f "$SHELF/audits/$FIXTURE_SLUG/audit-report.md"

# Dedicated dry-run slug - never delete audits/github-optimization/ (real dogfood output).
rm -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on shelf root" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$SHELF" "" public-prep pre-public "$SHELF_DRY_RUN_SLUG"
run_pass "shelf orchestrator dry-run report scaffolded" test -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"

cleanup_generated

echo
if [[ "$failures" -eq 0 ]]; then
  echo "regulation-tests: PASS"
  exit 0
fi

echo "regulation-tests: FAIL ($failures)"
exit 1
