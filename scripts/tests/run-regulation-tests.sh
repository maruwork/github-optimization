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

run_pass "validate-regulation-index" bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
run_exit "run-audit-quickstart missing manifest exits 2" 2 bash "$SHELF/scripts/run-audit-quickstart.sh" "$SHELF"

for tpl in \
  accepted-risk-record.md.template \
  audit-report.md.template \
  tier2-defer-record.md.template \
  audit.manifest.yml.template
do
  run_pass "template exists: $tpl" test -f "$SHELF/templates/$tpl"
done

for policy in \
  RE_AUDIT_POLICY.md \
  AUDIT_PHASE_POLICY.md \
  MULTI_REPO_ORCHESTRATION.md \
  TOOL_REVIEW_CADENCE.md
do
  run_pass "policy exists: $policy" test -f "$SHELF/$policy"
done

FIXTURE="$SHELF/scripts/tests/fixtures/minimal-docs-repo"
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

SHELF_SLUG="github-optimization"
rm -f "$SHELF/audits/$SHELF_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on shelf root" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$SHELF" "" public-prep pre-public "$SHELF_SLUG"
run_pass "shelf audit-report scaffolded" test -f "$SHELF/audits/$SHELF_SLUG/audit-report.md"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "regulation-tests: PASS"
  exit 0
fi

echo "regulation-tests: FAIL ($failures)"
exit 1