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

run_pass "validate-regulation-index" bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
run_exit "check-tracked-files on shelf" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$SHELF"
run_exit "check-tracked-files on fixture" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$FIXTURE"
run_exit "check-gitignore-consistency on shelf" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$SHELF"
run_exit "check-gitignore-consistency on fixture" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$FIXTURE"
TRACKED_IGNORED="$SHELF/scripts/tests/fixtures/tracked-ignored-repo"
if [[ ! -d "$TRACKED_IGNORED/.git" ]]; then
  git -C "$TRACKED_IGNORED" init
  git -C "$TRACKED_IGNORED" add README.md LICENSE SECURITY.md .gitignore
  git -C "$TRACKED_IGNORED" add -f AGENTS.md
  git -C "$TRACKED_IGNORED" -c user.email=fixture@test -c user.name=fixture commit -m "init tracked-ignored fixture"
fi
run_exit "check-gitignore-consistency blocked tracked-ignored fixture" 1 \
  bash "$SHELF/scripts/check-gitignore-consistency.sh" "$TRACKED_IGNORED"
echo "TEST: collect-audit-evidence completes after blocked gitignore"
set +e
evidence_out="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$TRACKED_IGNORED" 2>&1)"
evidence_code=$?
set -e
if [[ "$evidence_code" -eq 0 ]] && echo "$evidence_out" | grep -q "=== Root Files ==="; then
  echo "  PASS"
else
  echo "  FAIL: expected exit 0 and Root Files section, got exit $evidence_code"
  failures=$((failures + 1))
fi
PRESENT_HEAD="$(git -C "$SHELF" rev-parse HEAD)"
# v1.1.4 → present always includes audit.manifest.yml change (v1.1.5); stable across future commits
MANIFEST_PRIOR_HEAD="$(git -C "$SHELF" rev-parse "v1.1.4^{commit}")"
SKIP_SHELF_VALIDATION=1 run_exit "run-delta-audit allowed (no changes)" 0 \
  bash "$SHELF/scripts/run-delta-audit.sh" "$SHELF" "" release github-optimization "$PRESENT_HEAD"
SKIP_SHELF_VALIDATION=1 run_exit "run-delta-audit invalidates manifest change" 2 \
  bash "$SHELF/scripts/run-delta-audit.sh" "$SHELF" "" release github-optimization "$MANIFEST_PRIOR_HEAD"
run_exit "run-audit-quickstart missing manifest exits 2" 2 bash "$SHELF/scripts/run-audit-quickstart.sh" "$FIXTURE"
QUICKSTART_FIXTURE="$SHELF/scripts/tests/fixtures/quickstart-manifest-repo"
run_exit "run-audit-quickstart with manifest exits 0" 0 bash "$SHELF/scripts/run-audit-quickstart.sh" "$QUICKSTART_FIXTURE"
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
  git -C "$FIXTURE" init
  git -C "$FIXTURE" add README.md LICENSE SECURITY.md .gitignore
  git -C "$FIXTURE" -c user.email=fixture@test -c user.name=fixture commit -m "init minimal docs fixture"
fi

FIXTURE_SLUG="minimal-docs-repo"
rm -f "$SHELF/audits/$FIXTURE_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on fixture" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$FIXTURE" "" public-prep pre-public "$FIXTURE_SLUG"
run_pass "fixture audit-report scaffolded" test -f "$SHELF/audits/$FIXTURE_SLUG/audit-report.md"

# Dedicated dry-run slug - never delete audits/github-optimization/ (real dogfood output).
SHELF_DRY_RUN_SLUG="shelf-orchestrator-dry-run"
rm -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on shelf root" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$SHELF" "" public-prep pre-public "$SHELF_DRY_RUN_SLUG"
run_pass "shelf orchestrator dry-run report scaffolded" test -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "regulation-tests: PASS"
  exit 0
fi

echo "regulation-tests: FAIL ($failures)"
exit 1