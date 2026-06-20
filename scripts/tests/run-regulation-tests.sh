#!/usr/bin/env bash
set -euo pipefail

SHELF="${GITHUB_OPTIMIZATION_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
failures=0
SUITE="all"

if [[ "${1:-}" == "--suite" ]]; then
  SUITE="${2:-}"
  shift 2
fi

case "$SUITE" in
  all|ci-selection|orchestrator) ;;
  *)
    echo "usage: $0 [--suite all|ci-selection|orchestrator]" >&2
    exit 2
    ;;
esac

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

init_tracked_ignored() {
  rm -rf "$TRACKED_IGNORED/.git"
  rm -f "$TRACKED_IGNORED/local-only.secret"
  printf '%s' 'fixture-secret=tracked-but-ignored' >"$TRACKED_IGNORED/local-only.secret"
  fixture_git "$TRACKED_IGNORED" init
  fixture_git "$TRACKED_IGNORED" add README.md LICENSE SECURITY.md .gitignore
  fixture_git "$TRACKED_IGNORED" add -f local-only.secret
  fixture_git "$TRACKED_IGNORED" -c user.email=fixture@test -c user.name=fixture commit -m "init tracked-ignored fixture"
}

init_minimal_docs_fixture() {
  rm -rf "$FIXTURE/.git"
  fixture_git "$FIXTURE" init >/dev/null
  fixture_git "$FIXTURE" add README.md LICENSE SECURITY.md .gitignore
  fixture_git "$FIXTURE" -c user.email=fixture@test -c user.name=fixture commit -m "init minimal docs fixture" >/dev/null
}

FIXTURE="$SHELF/scripts/tests/fixtures/minimal-docs-repo"
TRACKED_IGNORED="$SHELF/scripts/tests/fixtures/tracked-ignored-repo"
DELTA_DRY_RUN_SLUG="delta-orchestrator-dry-run"
FIXTURE_SLUG="minimal-docs-repo"
SHELF_DRY_RUN_SLUG="shelf-orchestrator-dry-run"
BLOCKED_FULL_AUDIT_SLUG="tracked-ignored-orchestrator-dry-run"
REMOTE_SLUG_DRY_RUN_SLUG="remote-slug-fixture"

cleanup_generated() {
  rm -rf \
    "$SHELF/audits/$DELTA_DRY_RUN_SLUG" \
    "$SHELF/audits/$FIXTURE_SLUG" \
    "$SHELF/audits/$SHELF_DRY_RUN_SLUG" \
    "$SHELF/audits/$BLOCKED_FULL_AUDIT_SLUG" \
    "$SHELF/audits/$REMOTE_SLUG_DRY_RUN_SLUG" \
    "$FIXTURE/.git" \
    "$TRACKED_IGNORED/.git" \
    "$TRACKED_IGNORED/local-only.secret" \
    "$SHELF/scripts/tests/fixtures/quickstart-isolated-repo/out"
}

fixture_git() {
  git -C "$1" -c "safe.directory=$1" "${@:2}"
}

suite_enabled() {
  local target="$1"
  [[ "$SUITE" == "all" || "$SUITE" == "$target" ]]
}

cleanup_generated
init_minimal_docs_fixture

if [[ "$SUITE" == "all" ]]; then
run_pass "validate-regulation-index" bash "$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
run_exit "check-tracked-files on shelf" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$SHELF"
run_exit "check-tracked-files on fixture" 0 bash "$SHELF/scripts/check-tracked-files.sh" "$FIXTURE"
run_exit "check-gitignore-consistency on shelf" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$SHELF"
run_exit "check-gitignore-consistency on fixture" 0 bash "$SHELF/scripts/check-gitignore-consistency.sh" "$FIXTURE"
init_tracked_ignored
run_exit "check-gitignore-consistency blocked tracked-ignored fixture" 1 \
  bash "$SHELF/scripts/check-gitignore-consistency.sh" "$TRACKED_IGNORED"
echo "TEST: collect-audit-evidence completes transcript and exits blocked after blocked gitignore"
init_tracked_ignored
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
echo "TEST: collect-audit-evidence redacts local absolute paths"
set +e
redact_out="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$SHELF" 2>&1)"
redact_code=$?
set -e
if [[ "$redact_code" -eq 0 ]] \
  && [[ "$redact_out" != *"$SHELF"* ]] \
  && [[ -z "${HOME:-}" || "$redact_out" != *"$HOME"* ]] \
  && [[ -z "${TMPDIR:-}" || "$redact_out" != *"${TMPDIR%/}"* ]]; then
  echo "  PASS"
else
  echo "  FAIL: local absolute path leaked or collector failed"
  printf '%s\n' "$redact_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence handles non-ASCII tracked paths in large-file scan"
unicode_fixture="$(mktemp -d)"
printf '%s\n' "fixture" >"$unicode_fixture/README.md"
printf '%s\n' "fixture" >"$unicode_fixture/LICENSE"
printf '%s\n' "fixture" >"$unicode_fixture/SECURITY.md"
printf '' >"$unicode_fixture/.gitignore"
unicode_large="$unicode_fixture/TëstLarge.bin"
head -c 512100 /dev/zero >"$unicode_large"
fixture_git "$unicode_fixture" init >/dev/null
fixture_git "$unicode_fixture" add README.md LICENSE SECURITY.md .gitignore "TëstLarge.bin"
fixture_git "$unicode_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init unicode fixture" >/dev/null
set +e
unicode_out="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$unicode_fixture" 2>&1)"
unicode_code=$?
set -e
rm -rf "$unicode_fixture"
if [[ "$unicode_code" -eq 0 ]] \
  && echo "$unicode_out" | grep -Fq 'TëstLarge.bin 512100' \
  && ! echo "$unicode_out" | grep -Fq 'Illegal characters in path'; then
  echo "  PASS"
else
  echo "  FAIL: expected unicode large-file evidence without quoted-path failure"
  printf '%s\n' "$unicode_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence distinguishes ABSENT issue templates and NO_RUNS CI"
hosted_fixture="$(mktemp -d)"
mkdir -p "$hosted_fixture/.github/workflows"
printf '%s\n' "fixture" >"$hosted_fixture/README.md"
printf '%s\n' "fixture" >"$hosted_fixture/LICENSE"
printf '%s\n' "fixture" >"$hosted_fixture/SECURITY.md"
printf '' >"$hosted_fixture/.gitignore"
printf '%s\n' "name: ci" >"$hosted_fixture/.github/workflows/ci.yml"
fixture_git "$hosted_fixture" init >/dev/null
fixture_git "$hosted_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$hosted_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init hosted fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/compat)
    printf '%s\n' '{"description":"fixture repo","topics":[],"homepage":"","visibility":"public","has_issues":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/compat/community/profile)
    printf '%s\n' '{"health_percentage":100,"files":{"issue_template":null}}'
    ;;
  repos/example/compat/contents/.github/ISSUE_TEMPLATE/bug_report.md)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/compat/contents/.github/ISSUE_TEMPLATE/feature_request.md)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/compat/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/compat/actions/runs?per_page=3)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
  *)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
hosted_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$hosted_fixture" example/compat 2>&1)"
hosted_code=$?
set -e
rm -rf "$hosted_fixture" "$fake_gh_dir"
if [[ "$hosted_code" -eq 0 ]] \
  && echo "$hosted_out" | grep -Fq '"description":"fixture repo"' \
  && echo "$hosted_out" | grep -Fq '"health_percentage":100' \
  && echo "$hosted_out" | grep -Fq '"secret_scanning":{"status":"enabled"}' \
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"ABSENT"' \
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"ABSENT"' \
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/config.yml","result":"ABSENT"' \
  && ! echo "$hosted_out" | grep -Eq '"permissions":|"updated_at":|"total_count":' \
  && echo "$hosted_out" | grep -Fq 'result: NO_RUNS (workflow files exist but the GitHub Actions runs API returned 0 runs)'; then
  echo "  PASS"
else
  echo "  FAIL: expected ABSENT issue-template evidence and NO_RUNS CI state"
  printf '%s\n' "$hosted_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence does not treat gh auth-required retry failures as ABSENT"
auth_required_fixture="$(mktemp -d)"
printf '%s\n' "fixture" >"$auth_required_fixture/README.md"
printf '%s\n' "fixture" >"$auth_required_fixture/LICENSE"
printf '%s\n' "fixture" >"$auth_required_fixture/SECURITY.md"
printf '' >"$auth_required_fixture/.gitignore"
fixture_git "$auth_required_fixture" init >/dev/null
fixture_git "$auth_required_fixture" add README.md LICENSE SECURITY.md .gitignore
fixture_git "$auth_required_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init auth required fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
if [[ -z "${GH_CONFIG_DIR:-}" ]]; then
  printf '%s\n' 'warning: failed to load config: open <GH_CONFIG_DIR>/config.yml: Access is denied.' >&2
  printf '%s\n' 'failed to create root command: failed to read configuration: open <GH_CONFIG_DIR>/config.yml: Access is denied.' >&2
  exit 1
fi
printf '%s\n' 'To get started with GitHub CLI, please run:  gh auth login' >&2
printf '%s\n' 'Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token.' >&2
exit 4
EOF
chmod +x "$fake_gh_dir/gh"
set +e
auth_required_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$auth_required_fixture" example/auth-required 2>&1)"
auth_required_code=$?
set -e
rm -rf "$auth_required_fixture" "$fake_gh_dir"
if [[ "$auth_required_code" -eq 1 ]] \
  && echo "$auth_required_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: hosted metadata unavailable)' \
  && echo "$auth_required_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"API_BLOCKED"' \
  && echo "$auth_required_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"API_BLOCKED"' \
  && echo "$auth_required_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/config.yml","result":"API_BLOCKED"' \
  && echo "$auth_required_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: hosted issue-template lookup unavailable)' \
  && echo "$auth_required_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: latest CI metadata unavailable)' \
  && ! echo "$auth_required_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"ABSENT"'; then
  echo "  PASS"
else
  echo "  FAIL: expected auth-required retry to stay API_BLOCKED"
  printf '%s\n' "$auth_required_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks hosted issue templates as NOT_APPLICABLE when issues are disabled"
disabled_fixture="$(mktemp -d)"
printf '%s\n' "fixture" >"$disabled_fixture/README.md"
printf '%s\n' "fixture" >"$disabled_fixture/LICENSE"
printf '%s\n' "fixture" >"$disabled_fixture/SECURITY.md"
printf '' >"$disabled_fixture/.gitignore"
fixture_git "$disabled_fixture" init >/dev/null
fixture_git "$disabled_fixture" add README.md LICENSE SECURITY.md .gitignore
fixture_git "$disabled_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init disabled fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/issues-disabled)
    printf '%s\n' '{"description":"issues disabled fixture","topics":[],"homepage":"","visibility":"public","has_issues":false,"security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/issues-disabled/community/profile)
    printf '%s\n' '{"health_percentage":80,"files":{"issue_template":null}}'
    ;;
  repos/example/issues-disabled/actions/runs?per_page=3)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
disabled_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$disabled_fixture" example/issues-disabled 2>&1)"
disabled_code=$?
set -e
rm -rf "$disabled_fixture" "$fake_gh_dir"
if [[ "$disabled_code" -eq 0 ]] \
  && echo "$disabled_out" | grep -Fq '"has_issues":false' \
  && echo "$disabled_out" | grep -Fq 'result: NOT_APPLICABLE (issues disabled)' \
  && echo "$disabled_out" | grep -Fq 'result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)'; then
  echo "  PASS"
else
  echo "  FAIL: expected NOT_APPLICABLE issue-template evidence for issues-disabled repo"
  printf '%s\n' "$disabled_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence preserves PASS and ABSENT issue-template evidence when runs exist"
partial_fixture="$(mktemp -d)"
mkdir -p "$partial_fixture/.github/workflows"
printf '%s\n' "fixture" >"$partial_fixture/README.md"
printf '%s\n' "fixture" >"$partial_fixture/LICENSE"
printf '%s\n' "fixture" >"$partial_fixture/SECURITY.md"
printf '' >"$partial_fixture/.gitignore"
printf '%s\n' "name: ci" >"$partial_fixture/.github/workflows/ci.yml"
fixture_git "$partial_fixture" init >/dev/null
fixture_git "$partial_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$partial_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init partial fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/partial)
    printf '%s\n' '{"description":"partial template fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/partial/community/profile)
    printf '%s\n' '{"health_percentage":95,"files":{"issue_template":{}}}'
    ;;
  repos/example/partial/contents/.github/ISSUE_TEMPLATE/bug_report.md)
    printf '%s\n' '{"path":".github/ISSUE_TEMPLATE/bug_report.md"}'
    ;;
  repos/example/partial/contents/.github/ISSUE_TEMPLATE/feature_request.md)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/partial/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"path":".github/ISSUE_TEMPLATE/config.yml"}'
    ;;
  repos/example/partial/actions/runs/123/jobs?per_page=1)
    printf '%s\n' '{"total_count":4}'
    ;;
  repos/example/partial/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":123,"name":"CI","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/1"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
partial_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$partial_fixture" example/partial 2>&1)"
partial_code=$?
set -e
rm -rf "$partial_fixture" "$fake_gh_dir"
if [[ "$partial_code" -eq 0 ]] \
  && echo "$partial_out" | grep -Fq '"path":".github/ISSUE_TEMPLATE/bug_report.md","requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"PASS"' \
  && echo "$partial_out" | grep -Fq '"path":null,"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"ABSENT"' \
  && echo "$partial_out" | grep -Fq '"path":".github/ISSUE_TEMPLATE/config.yml","requested":".github/ISSUE_TEMPLATE/config.yml","result":"PASS"' \
  && echo "$partial_out" | grep -Fq '"name":"CI","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","duration_seconds":150,"jobs_total":4,"evidence_scope":"default_branch","default_branch":"main","classification":"pass","r02_assessment":"pass","r02_reason":"latest_default_branch_run_green","signals":null,"head_branch":"main","html_url":"https://example.test/runs/1"' \
  && ! echo "$partial_out" | grep -Eq 'result: (NO_RUNS|NOT_CONFIGURED)'; then
  echo "  PASS"
else
  echo "  FAIL: expected mixed PASS/ABSENT issue-template evidence and workflow run JSON"
  printf '%s\n' "$partial_out"
  failures=$((failures + 1))
fi
fi

if [[ "$SUITE" == "all" || "$SUITE" == "ci-selection" ]]; then
echo "TEST: collect-audit-evidence prefers the CI workflow over newer non-CI runs on the default branch"
ci_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$ci_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$ci_selection_fixture/README.md"
printf '%s\n' "fixture" >"$ci_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$ci_selection_fixture/SECURITY.md"
printf '' >"$ci_selection_fixture/.gitignore"
printf '%s\n' "name: ci" >"$ci_selection_fixture/.github/workflows/ci.yml"
fixture_git "$ci_selection_fixture" init >/dev/null
fixture_git "$ci_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$ci_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init ci selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/ci-selection)
    printf '%s\n' '{"description":"ci selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/ci-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/ci-selection/actions/workflows/ci.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":900,"name":"CI","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/900"}]}'
    ;;
  repos/example/ci-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":901,"name":"Dependabot Updates","event":"dynamic","status":"completed","conclusion":"failure","path":"dynamic/dependabot/dependabot-updates","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:03:05Z","head_branch":"main","html_url":"https://example.test/runs/901"},{"id":900,"name":"CI","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/900"}]}'
    ;;
  repos/example/ci-selection/actions/runs/900/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
ci_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$ci_selection_fixture" example/ci-selection 2>&1)"
ci_selection_code=$?
set -e
rm -rf "$ci_selection_fixture" "$fake_gh_dir"
if [[ "$ci_selection_code" -eq 0 ]] \
  && echo "$ci_selection_out" | grep -Fq '"name":"CI"' \
  && echo "$ci_selection_out" | grep -Fq '"jobs_total":2' \
  && echo "$ci_selection_out" | grep -Fq '"classification":"pass"' \
  && echo "$ci_selection_out" | grep -Fq '"html_url":"https://example.test/runs/900"' \
  && ! echo "$ci_selection_out" | grep -Fq 'https://example.test/runs/901'; then
  echo "  PASS"
else
  echo "  FAIL: expected workflow-scoped CI selection"
  printf '%s\n' "$ci_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence selects a non-ci-named primary workflow when it is the only local CI candidate"
verify_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$verify_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$verify_selection_fixture/README.md"
printf '%s\n' "fixture" >"$verify_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$verify_selection_fixture/SECURITY.md"
printf '' >"$verify_selection_fixture/.gitignore"
cat >"$verify_selection_fixture/.github/workflows/verify.yml" <<'EOF'
name: Verify
on:
  push:
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - run: echo verify
EOF
fixture_git "$verify_selection_fixture" init >/dev/null
fixture_git "$verify_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/verify.yml
fixture_git "$verify_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init verify selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/verify-selection)
    printf '%s\n' '{"description":"verify selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/verify-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/verify-selection/actions/workflows/verify.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":905,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/905"}]}'
    ;;
  repos/example/verify-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":906,"name":"CodeQL","event":"schedule","status":"completed","conclusion":"failure","path":"/.github/workflows/codeql.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:03:05Z","head_branch":"main","html_url":"https://example.test/runs/906"},{"id":905,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/905"}]}'
    ;;
  repos/example/verify-selection/actions/runs/905/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
verify_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$verify_selection_fixture" example/verify-selection 2>&1)"
verify_selection_code=$?
set -e
rm -rf "$verify_selection_fixture" "$fake_gh_dir"
if [[ "$verify_selection_code" -eq 0 ]] \
  && echo "$verify_selection_out" | grep -Fq '"name":"Verify"' \
  && echo "$verify_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/verify.yml","workflow_selection":"single_local_workflow"' \
  && ! echo "$verify_selection_out" | grep -Fq 'https://example.test/runs/906'; then
  echo "  PASS"
else
  echo "  FAIL: expected non-ci-named workflow selection"
  printf '%s\n' "$verify_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence prefers the heuristic primary workflow over non-ci analysis workflows"
heuristic_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$heuristic_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$heuristic_selection_fixture/README.md"
printf '%s\n' "fixture" >"$heuristic_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$heuristic_selection_fixture/SECURITY.md"
printf '' >"$heuristic_selection_fixture/.gitignore"
cat >"$heuristic_selection_fixture/.github/workflows/verify.yml" <<'EOF'
name: Verify
on:
  push:
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - run: echo verify
EOF
cat >"$heuristic_selection_fixture/.github/workflows/codeql.yml" <<'EOF'
name: CodeQL
on:
  schedule:
    - cron: '0 0 * * 0'
EOF
fixture_git "$heuristic_selection_fixture" init >/dev/null
fixture_git "$heuristic_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/verify.yml .github/workflows/codeql.yml
fixture_git "$heuristic_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init heuristic selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/heuristic-selection)
    printf '%s\n' '{"description":"heuristic selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/heuristic-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/heuristic-selection/actions/workflows/verify.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":915,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/915"}]}'
    ;;
  repos/example/heuristic-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":916,"name":"CodeQL","event":"schedule","status":"completed","conclusion":"failure","path":"/.github/workflows/codeql.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:03:05Z","head_branch":"main","html_url":"https://example.test/runs/916"},{"id":915,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/915"}]}'
    ;;
  repos/example/heuristic-selection/actions/runs/915/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
heuristic_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$heuristic_selection_fixture" example/heuristic-selection 2>&1)"
heuristic_selection_code=$?
set -e
rm -rf "$heuristic_selection_fixture" "$fake_gh_dir"
if [[ "$heuristic_selection_code" -eq 0 ]] \
  && echo "$heuristic_selection_out" | grep -Fq '"name":"Verify"' \
  && echo "$heuristic_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/verify.yml","workflow_selection":"heuristic_local_workflow"' \
  && ! echo "$heuristic_selection_out" | grep -Fq 'https://example.test/runs/916'; then
  echo "  PASS"
else
  echo "  FAIL: expected heuristic workflow selection"
  printf '%s\n' "$heuristic_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence prefers run-tests over typecheck in heuristic selection"
run_tests_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$run_tests_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$run_tests_selection_fixture/README.md"
printf '%s\n' "fixture" >"$run_tests_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$run_tests_selection_fixture/SECURITY.md"
printf '' >"$run_tests_selection_fixture/.gitignore"
cat >"$run_tests_selection_fixture/.github/workflows/run-tests.yml" <<'EOF'
name: Tests
on:
  push:
jobs:
  tests:
    runs-on: ubuntu-latest
    steps:
      - run: echo tests
EOF
cat >"$run_tests_selection_fixture/.github/workflows/typecheck.yml" <<'EOF'
name: Type Check
on:
  push:
jobs:
  typecheck:
    runs-on: ubuntu-latest
    steps:
      - run: echo typecheck
EOF
fixture_git "$run_tests_selection_fixture" init >/dev/null
fixture_git "$run_tests_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/run-tests.yml .github/workflows/typecheck.yml
fixture_git "$run_tests_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init run-tests selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/run-tests-selection)
    printf '%s\n' '{"description":"run tests selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/run-tests-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/run-tests-selection/actions/workflows/run-tests.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":935,"name":"Tests","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/run-tests.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/run-tests-selection/actions/workflows/typecheck.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":936,"name":"Type Check","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/typecheck.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/936"}]}'
    ;;
  repos/example/run-tests-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":936,"name":"Type Check","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/typecheck.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/936"},{"id":935,"name":"Tests","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/run-tests.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/run-tests-selection/actions/runs/935/jobs?per_page=1|repos/example/run-tests-selection/actions/runs/936/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
run_tests_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$run_tests_selection_fixture" example/run-tests-selection 2>&1)"
run_tests_selection_code=$?
set -e
rm -rf "$run_tests_selection_fixture" "$fake_gh_dir"
if [[ "$run_tests_selection_code" -eq 0 ]] \
  && echo "$run_tests_selection_out" | grep -Fq '"name":"Tests"' \
  && echo "$run_tests_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/run-tests.yml","workflow_selection":"heuristic_local_workflow"'; then
  echo "  PASS"
else
  echo "  FAIL: expected run-tests workflow selection"
  printf '%s\n' "$run_tests_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence prefers go test workflow over govulncheck in heuristic selection"
go_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$go_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$go_selection_fixture/README.md"
printf '%s\n' "fixture" >"$go_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$go_selection_fixture/SECURITY.md"
printf '' >"$go_selection_fixture/.gitignore"
cat >"$go_selection_fixture/.github/workflows/go.yml" <<'EOF'
name: Unit and Integration Tests
on:
  push:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo test
EOF
cat >"$go_selection_fixture/.github/workflows/govulncheck.yml" <<'EOF'
name: Go Vulnerability Check
on:
  push:
jobs:
  govulncheck:
    runs-on: ubuntu-latest
    steps:
      - run: echo govulncheck
EOF
fixture_git "$go_selection_fixture" init >/dev/null
fixture_git "$go_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/go.yml .github/workflows/govulncheck.yml
fixture_git "$go_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init go selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/go-selection)
    printf '%s\n' '{"description":"go selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/go-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/go-selection/actions/workflows/go.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":945,"name":"Unit and Integration Tests","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/go.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/945"}]}'
    ;;
  repos/example/go-selection/actions/workflows/govulncheck.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":946,"name":"Go Vulnerability Check","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/govulncheck.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/946"}]}'
    ;;
  repos/example/go-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":946,"name":"Go Vulnerability Check","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/govulncheck.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/946"},{"id":945,"name":"Unit and Integration Tests","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/go.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/945"}]}'
    ;;
  repos/example/go-selection/actions/runs/945/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  repos/example/go-selection/actions/runs/946/jobs?per_page=1)
    printf '%s\n' '{"total_count":1}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
go_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$go_selection_fixture" example/go-selection 2>&1)"
go_selection_code=$?
set -e
rm -rf "$go_selection_fixture" "$fake_gh_dir"
if [[ "$go_selection_code" -eq 0 ]] \
  && echo "$go_selection_out" | grep -Fq '"name":"Unit and Integration Tests"' \
  && echo "$go_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/go.yml","workflow_selection":"heuristic_local_workflow"'; then
  echo "  PASS"
else
  echo "  FAIL: expected go.yml workflow selection"
  printf '%s\n' "$go_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence prefers main workflow over spell-check in heuristic selection"
spell_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$spell_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$spell_selection_fixture/README.md"
printf '%s\n' "fixture" >"$spell_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$spell_selection_fixture/SECURITY.md"
printf '' >"$spell_selection_fixture/.gitignore"
cat >"$spell_selection_fixture/.github/workflows/workflow.yml" <<'EOF'
name: Main workflow
on:
  push:
  pull_request:
EOF
cat >"$spell_selection_fixture/.github/workflows/spell-check.yml" <<'EOF'
name: Spell Check
on: [pull_request]
EOF
fixture_git "$spell_selection_fixture" init >/dev/null
fixture_git "$spell_selection_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/workflow.yml .github/workflows/spell-check.yml
fixture_git "$spell_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init spell selection fixture" >/dev/null
set +e
spell_selection_out="$(bash "$SHELF/scripts/collect-audit-evidence.sh" "$spell_selection_fixture" 2>&1)"
spell_selection_code=$?
set -e
rm -rf "$spell_selection_fixture" "$fake_gh_dir"
if [[ "$spell_selection_code" -eq 0 ]] \
  && echo "$spell_selection_out" | grep -Fq 'primary_ci_workflow: .github/workflows/workflow.yml' \
  && echo "$spell_selection_out" | grep -Fq 'primary_ci_selection: heuristic_local_workflow' \
  && ! echo "$spell_selection_out" | grep -Fq 'primary_ci_workflow: .github/workflows/spell-check.yml'; then
  echo "  PASS"
else
  echo "  FAIL: expected main workflow over spell-check"
  printf '%s\n' "$spell_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence honors audit manifest primary_ci_workflow override"
manifest_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$manifest_selection_fixture/.github/workflows"
printf '%s\n' "fixture" >"$manifest_selection_fixture/README.md"
printf '%s\n' "fixture" >"$manifest_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$manifest_selection_fixture/SECURITY.md"
printf '' >"$manifest_selection_fixture/.gitignore"
cat >"$manifest_selection_fixture/audit.manifest.yml" <<'EOF'
version: 1
primary_ci_workflow: .github/workflows/release-gate.yml
workdir: in-place
commands:
  - id: noop
    run_windows: echo ok
    run_unix: echo ok
    expect_exit: 0
EOF
cat >"$manifest_selection_fixture/.github/workflows/release-gate.yml" <<'EOF'
name: Ship Window
on:
  workflow_dispatch:
EOF
cat >"$manifest_selection_fixture/.github/workflows/codeql.yml" <<'EOF'
name: CodeQL
on:
  schedule:
    - cron: '0 0 * * 0'
EOF
fixture_git "$manifest_selection_fixture" init >/dev/null
fixture_git "$manifest_selection_fixture" add README.md LICENSE SECURITY.md .gitignore audit.manifest.yml .github/workflows/release-gate.yml .github/workflows/codeql.yml
fixture_git "$manifest_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init manifest selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/manifest-selection)
    printf '%s\n' '{"description":"manifest selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/manifest-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/manifest-selection/actions/workflows/release-gate.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":925,"name":"Ship Window","event":"workflow_dispatch","status":"completed","conclusion":"success","path":"/.github/workflows/release-gate.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/925"}]}'
    ;;
  repos/example/manifest-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":926,"name":"CodeQL","event":"schedule","status":"completed","conclusion":"failure","path":"/.github/workflows/codeql.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:03:05Z","head_branch":"main","html_url":"https://example.test/runs/926"},{"id":925,"name":"Ship Window","event":"workflow_dispatch","status":"completed","conclusion":"success","path":"/.github/workflows/release-gate.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/925"}]}'
    ;;
  repos/example/manifest-selection/actions/runs/925/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
manifest_selection_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$manifest_selection_fixture" example/manifest-selection 2>&1)"
manifest_selection_code=$?
set -e
rm -rf "$manifest_selection_fixture" "$fake_gh_dir"
if [[ "$manifest_selection_code" -eq 0 ]] \
  && echo "$manifest_selection_out" | grep -Fq '"name":"Ship Window"' \
  && echo "$manifest_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/release-gate.yml","workflow_selection":"manifest_override"' \
  && ! echo "$manifest_selection_out" | grep -Fq 'https://example.test/runs/926'; then
  echo "  PASS"
else
  echo "  FAIL: expected manifest override workflow selection"
  printf '%s\n' "$manifest_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence falls back to hosted workflow inventory when no local CI workflow is present"
hosted_selection_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
hosted_selection_call_log="$(mktemp)"
printf '%s\n' "fixture" >"$hosted_selection_fixture/README.md"
printf '%s\n' "fixture" >"$hosted_selection_fixture/LICENSE"
printf '%s\n' "fixture" >"$hosted_selection_fixture/SECURITY.md"
printf '' >"$hosted_selection_fixture/.gitignore"
fixture_git "$hosted_selection_fixture" init >/dev/null
fixture_git "$hosted_selection_fixture" add README.md LICENSE SECURITY.md .gitignore
fixture_git "$hosted_selection_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init hosted selection fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
printf '%s\n' "${2:-}" >>"$HOSTED_SELECTION_CALL_LOG"
case "${2:-}" in
  repos/example/hosted-selection)
    printf '%s\n' '{"description":"hosted selection fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/hosted-selection/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/hosted-selection/actions/workflows)
    printf '%s\n' '{"total_count":2,"workflows":[{"name":"CodeQL","path":"/.github/workflows/codeql.yml","state":"active"},{"name":"Verify","path":"/.github/workflows/verify.yml","state":"active"}]}'
    ;;
  repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/hosted-selection/actions/workflows/verify.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":935,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/hosted-selection/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":936,"name":"CodeQL","event":"schedule","status":"completed","conclusion":"failure","path":"/.github/workflows/codeql.yml","run_attempt":1,"run_started_at":"2026-06-20T10:03:00Z","updated_at":"2026-06-20T10:03:05Z","head_branch":"main","html_url":"https://example.test/runs/936"},{"id":935,"name":"Verify","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/verify.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/hosted-selection/actions/runs/935/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
hosted_selection_out="$(PATH="$fake_gh_dir:$PATH" HOSTED_SELECTION_CALL_LOG="$hosted_selection_call_log" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$hosted_selection_fixture" example/hosted-selection 2>&1)"
hosted_selection_code=$?
set -e
hosted_selection_workflow_calls="$(grep -Fxc 'repos/example/hosted-selection/actions/workflows' "$hosted_selection_call_log" || true)"
rm -rf "$hosted_selection_fixture" "$fake_gh_dir"
rm -f "$hosted_selection_call_log"
if [[ "$hosted_selection_code" -eq 0 ]] \
  && echo "$hosted_selection_out" | grep -Fq 'primary_ci_workflow: .github/workflows/verify.yml' \
  && echo "$hosted_selection_out" | grep -Fq 'primary_ci_selection: hosted_workflow_inventory' \
  && echo "$hosted_selection_out" | grep -Fq '"name":"Verify"' \
  && echo "$hosted_selection_out" | grep -Fq '"selected_workflow_path":".github/workflows/verify.yml","workflow_selection":"hosted_workflow_inventory"' \
  && [[ "$hosted_selection_workflow_calls" -eq 1 ]] \
  && ! echo "$hosted_selection_out" | grep -Fq 'https://example.test/runs/936'; then
  echo "  PASS"
else
  echo "  FAIL: expected hosted workflow inventory selection"
  printf '%s\n' "$hosted_selection_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence upgrades zero-run local heuristic to hosted workflow inventory"
hosted_override_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$hosted_override_fixture/.github/workflows"
printf '%s\n' "fixture" >"$hosted_override_fixture/README.md"
printf '%s\n' "fixture" >"$hosted_override_fixture/LICENSE"
printf '%s\n' "fixture" >"$hosted_override_fixture/SECURITY.md"
printf '' >"$hosted_override_fixture/.gitignore"
cat >"$hosted_override_fixture/.github/workflows/macos.yml" <<'EOF'
name: Test fzf on macOS
on:
  push:
    branches: [ main ]
EOF
cat >"$hosted_override_fixture/.github/workflows/linux.yml" <<'EOF'
name: build
on:
  push:
    branches: [ main ]
EOF
fixture_git "$hosted_override_fixture" init >/dev/null
fixture_git "$hosted_override_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/macos.yml .github/workflows/linux.yml
fixture_git "$hosted_override_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init hosted override fixture" >/dev/null
hosted_override_call_log="$(mktemp)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
printf '%s\n' "${2:-}" >>"$HOSTED_OVERRIDE_CALL_LOG"
case "${2:-}" in
  repos/example/hosted-override)
    printf '%s\n' '{"description":"hosted override fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/hosted-override/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/hosted-override/actions/workflows)
    printf '%s\n' '{"total_count":2,"workflows":[{"name":"Test fzf on macOS","path":"/.github/workflows/macos.yml","state":"disabled_manually"},{"name":"build","path":"/.github/workflows/linux.yml","state":"active"}]}'
    ;;
  repos/example/hosted-override/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/hosted-override/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/hosted-override/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/hosted-override/actions/workflows/macos.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
  repos/example/hosted-override/actions/workflows/linux.yml/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":935,"name":"build","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/linux.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/hosted-override/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":935,"name":"build","event":"push","status":"completed","conclusion":"success","path":"/.github/workflows/linux.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:30Z","head_branch":"main","html_url":"https://example.test/runs/935"}]}'
    ;;
  repos/example/hosted-override/actions/runs/935/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
hosted_override_out="$(PATH="$fake_gh_dir:$PATH" HOSTED_OVERRIDE_CALL_LOG="$hosted_override_call_log" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$hosted_override_fixture" example/hosted-override 2>&1)"
hosted_override_code=$?
set -e
rm -rf "$hosted_override_fixture" "$fake_gh_dir"
rm -f "$hosted_override_call_log"
if [[ "$hosted_override_code" -eq 0 ]] \
  && echo "$hosted_override_out" | grep -Fq '"selected_workflow_path":".github/workflows/linux.yml","workflow_selection":"hosted_workflow_inventory"' \
  && ! echo "$hosted_override_out" | grep -Fq '"selected_workflow_path":".github/workflows/macos.yml"'; then
  echo "  PASS"
else
  echo "  FAIL: expected hosted override after zero-run local heuristic"
  printf '%s\n' "$hosted_override_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks branch-filter candidates for zero-job runs with filtered workflows"
branch_filter_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$branch_filter_fixture/.github/workflows"
printf '%s\n' "fixture" >"$branch_filter_fixture/README.md"
printf '%s\n' "fixture" >"$branch_filter_fixture/LICENSE"
printf '%s\n' "fixture" >"$branch_filter_fixture/SECURITY.md"
printf '' >"$branch_filter_fixture/.gitignore"
cat >"$branch_filter_fixture/.github/workflows/ci.yml" <<'EOF'
name: ci
on:
  push:
    branches:
      - main
EOF
fixture_git "$branch_filter_fixture" init >/dev/null
fixture_git "$branch_filter_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$branch_filter_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init branch filter fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/branch-filter)
    printf '%s\n' '{"description":"branch filter fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/branch-filter/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/branch-filter/actions/runs/321/jobs?per_page=1)
    printf '%s\n' '{"total_count":0}'
    ;;
  repos/example/branch-filter/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":321,"name":"CI","event":"push","status":"completed","conclusion":"startup_failure","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:00:03Z","head_branch":"main","html_url":"https://example.test/runs/321"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
branch_filter_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$branch_filter_fixture" example/branch-filter 2>&1)"
branch_filter_code=$?
set -e
rm -rf "$branch_filter_fixture" "$fake_gh_dir"
if [[ "$branch_filter_code" -eq 0 ]] \
  && echo "$branch_filter_out" | grep -Fq '"path":"/.github/workflows/ci.yml"' \
  && echo "$branch_filter_out" | grep -Fq '"jobs_total":0' \
  && echo "$branch_filter_out" | grep -Fq '"evidence_scope":"default_branch","default_branch":"main"' \
  && echo "$branch_filter_out" | grep -Fq '"classification":"branch_filter_candidate"' \
  && echo "$branch_filter_out" | grep -Fq '"r02_assessment":"review","r02_reason":"branch_filter_candidate_requires_confirmation"' \
  && echo "$branch_filter_out" | grep -Fq '"signals":["no_jobs_recorded","startup_failure","startup_failure_candidate","near_zero_duration","branch_filter_candidate"]'; then
  echo "  PASS"
else
  echo "  FAIL: expected branch_filter_candidate signal"
  printf '%s\n' "$branch_filter_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks hard failures as blocked for R-02 on default branch"
hard_failure_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$hard_failure_fixture/.github/workflows"
printf '%s\n' "fixture" >"$hard_failure_fixture/README.md"
printf '%s\n' "fixture" >"$hard_failure_fixture/LICENSE"
printf '%s\n' "fixture" >"$hard_failure_fixture/SECURITY.md"
printf '' >"$hard_failure_fixture/.gitignore"
printf '%s\n' "name: ci" >"$hard_failure_fixture/.github/workflows/ci.yml"
fixture_git "$hard_failure_fixture" init >/dev/null
fixture_git "$hard_failure_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$hard_failure_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init hard failure fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/hard-failure)
    printf '%s\n' '{"description":"hard failure fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/hard-failure/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/hard-failure/actions/runs/654/jobs?per_page=1)
    printf '%s\n' '{"total_count":3}'
    ;;
  repos/example/hard-failure/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":654,"name":"CI","event":"push","status":"completed","conclusion":"failure","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/654"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
hard_failure_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$hard_failure_fixture" example/hard-failure 2>&1)"
hard_failure_code=$?
set -e
rm -rf "$hard_failure_fixture" "$fake_gh_dir"
if [[ "$hard_failure_code" -eq 0 ]] \
  && echo "$hard_failure_out" | grep -Fq '"jobs_total":3' \
  && echo "$hard_failure_out" | grep -Fq '"classification":"hard_failure"' \
  && echo "$hard_failure_out" | grep -Fq '"r02_assessment":"blocked","r02_reason":"latest_default_branch_run_failed"'; then
  echo "  PASS"
else
  echo "  FAIL: expected hard-failure R-02 mapping"
  printf '%s\n' "$hard_failure_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks startup-failure candidates for manual review on default branch"
startup_failure_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$startup_failure_fixture/.github/workflows"
printf '%s\n' "fixture" >"$startup_failure_fixture/README.md"
printf '%s\n' "fixture" >"$startup_failure_fixture/LICENSE"
printf '%s\n' "fixture" >"$startup_failure_fixture/SECURITY.md"
printf '' >"$startup_failure_fixture/.gitignore"
printf '%s\n' "name: ci" >"$startup_failure_fixture/.github/workflows/ci.yml"
fixture_git "$startup_failure_fixture" init >/dev/null
fixture_git "$startup_failure_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$startup_failure_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init startup failure fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/startup-failure)
    printf '%s\n' '{"description":"startup failure fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/startup-failure/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/startup-failure/actions/runs/701/jobs?per_page=1)
    printf '%s\n' '{"total_count":0}'
    ;;
  repos/example/startup-failure/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":701,"name":"CI","event":"push","status":"completed","conclusion":"startup_failure","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:00:02Z","head_branch":"main","html_url":"https://example.test/runs/701"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
startup_failure_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$startup_failure_fixture" example/startup-failure 2>&1)"
startup_failure_code=$?
set -e
rm -rf "$startup_failure_fixture" "$fake_gh_dir"
if [[ "$startup_failure_code" -eq 0 ]] \
  && echo "$startup_failure_out" | grep -Fq '"jobs_total":0' \
  && echo "$startup_failure_out" | grep -Fq '"classification":"startup_failure_candidate"' \
  && echo "$startup_failure_out" | grep -Fq '"r02_assessment":"review","r02_reason":"startup_failure_candidate_requires_confirmation"' \
  && echo "$startup_failure_out" | grep -Fq '"signals":["no_jobs_recorded","startup_failure","startup_failure_candidate","near_zero_duration"]'; then
  echo "  PASS"
else
  echo "  FAIL: expected startup_failure_candidate signal"
  printf '%s\n' "$startup_failure_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks in-progress default-branch runs for manual review"
in_progress_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$in_progress_fixture/.github/workflows"
printf '%s\n' "fixture" >"$in_progress_fixture/README.md"
printf '%s\n' "fixture" >"$in_progress_fixture/LICENSE"
printf '%s\n' "fixture" >"$in_progress_fixture/SECURITY.md"
printf '' >"$in_progress_fixture/.gitignore"
printf '%s\n' "name: ci" >"$in_progress_fixture/.github/workflows/ci.yml"
fixture_git "$in_progress_fixture" init >/dev/null
fixture_git "$in_progress_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$in_progress_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init in progress fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/in-progress)
    printf '%s\n' '{"description":"in progress fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/in-progress/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/in-progress/actions/runs/702/jobs?per_page=1)
    printf '%s\n' '{"total_count":1}'
    ;;
  repos/example/in-progress/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":702,"name":"CI","event":"push","status":"in_progress","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:01:00Z","head_branch":"main","html_url":"https://example.test/runs/702"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
in_progress_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$in_progress_fixture" example/in-progress 2>&1)"
in_progress_code=$?
set -e
rm -rf "$in_progress_fixture" "$fake_gh_dir"
if [[ "$in_progress_code" -eq 0 ]] \
  && echo "$in_progress_out" | grep -Fq '"jobs_total":1' \
  && echo "$in_progress_out" | grep -Fq '"classification":"in_progress"' \
  && echo "$in_progress_out" | grep -Fq '"r02_assessment":"review","r02_reason":"default_branch_run_in_progress"'; then
  echo "  PASS"
else
  echo "  FAIL: expected in_progress classification"
  printf '%s\n' "$in_progress_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks non-blocking default-branch runs for manual review"
non_blocking_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$non_blocking_fixture/.github/workflows"
printf '%s\n' "fixture" >"$non_blocking_fixture/README.md"
printf '%s\n' "fixture" >"$non_blocking_fixture/LICENSE"
printf '%s\n' "fixture" >"$non_blocking_fixture/SECURITY.md"
printf '' >"$non_blocking_fixture/.gitignore"
printf '%s\n' "name: ci" >"$non_blocking_fixture/.github/workflows/ci.yml"
fixture_git "$non_blocking_fixture" init >/dev/null
fixture_git "$non_blocking_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$non_blocking_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init non blocking fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/non-blocking)
    printf '%s\n' '{"description":"non blocking fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/non-blocking/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/non-blocking/actions/runs/703/jobs?per_page=1)
    printf '%s\n' '{"total_count":2}'
    ;;
  repos/example/non-blocking/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":703,"name":"CI","event":"push","status":"completed","conclusion":"skipped","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:02:00Z","head_branch":"main","html_url":"https://example.test/runs/703"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
non_blocking_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$non_blocking_fixture" example/non-blocking 2>&1)"
non_blocking_code=$?
set -e
rm -rf "$non_blocking_fixture" "$fake_gh_dir"
if [[ "$non_blocking_code" -eq 0 ]] \
  && echo "$non_blocking_out" | grep -Fq '"jobs_total":2' \
  && echo "$non_blocking_out" | grep -Fq '"classification":"non_blocking"' \
  && echo "$non_blocking_out" | grep -Fq '"r02_assessment":"review","r02_reason":"default_branch_run_non_green_non_blocking"'; then
  echo "  PASS"
else
  echo "  FAIL: expected non_blocking classification"
  printf '%s\n' "$non_blocking_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence marks jobs-api-blocked runs as unknown for manual review"
unknown_fixture="$(mktemp -d)"
fake_gh_dir="$(mktemp -d)"
mkdir -p "$unknown_fixture/.github/workflows"
printf '%s\n' "fixture" >"$unknown_fixture/README.md"
printf '%s\n' "fixture" >"$unknown_fixture/LICENSE"
printf '%s\n' "fixture" >"$unknown_fixture/SECURITY.md"
printf '' >"$unknown_fixture/.gitignore"
printf '%s\n' "name: ci" >"$unknown_fixture/.github/workflows/ci.yml"
fixture_git "$unknown_fixture" init >/dev/null
fixture_git "$unknown_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$unknown_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init unknown fixture" >/dev/null
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/unknown)
    printf '%s\n' '{"description":"unknown fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"default_branch":"main","security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/unknown/community/profile)
    printf '%s\n' '{"health_percentage":90,"files":{"issue_template":null}}'
    ;;
  repos/example/unknown/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/unknown/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/unknown/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 4
    ;;
  repos/example/unknown/actions/runs/704/jobs?per_page=1)
    exit 1
    ;;
  repos/example/unknown/actions/runs?branch=main)
    printf '%s\n' '{"workflow_runs":[{"id":704,"name":"CI","event":"push","status":"completed","conclusion":"failure","path":"/.github/workflows/ci.yml","run_attempt":1,"run_started_at":"2026-06-20T10:00:00Z","updated_at":"2026-06-20T10:04:00Z","head_branch":"main","html_url":"https://example.test/runs/704"}]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
unknown_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$unknown_fixture" example/unknown 2>&1)"
unknown_code=$?
set -e
rm -rf "$unknown_fixture" "$fake_gh_dir"
if [[ "$unknown_code" -eq 0 ]] \
  && echo "$unknown_out" | grep -Fq '"jobs_total":null' \
  && echo "$unknown_out" | grep -Fq '"classification":"unknown"' \
  && echo "$unknown_out" | grep -Fq '"r02_assessment":"review","r02_reason":"insufficient_ci_evidence"' \
  && echo "$unknown_out" | grep -Fq '"signals":["jobs_api_blocked"]'; then
  echo "  PASS"
else
  echo "  FAIL: expected unknown classification"
  printf '%s\n' "$unknown_out"
  failures=$((failures + 1))
fi
fi

if [[ "$SUITE" == "all" ]]; then
echo "TEST: collect-audit-evidence records API_BLOCKED when hosted issue templates cannot be fetched"
issue_blocked_fixture="$(mktemp -d)"
printf '%s\n' "fixture" >"$issue_blocked_fixture/README.md"
printf '%s\n' "fixture" >"$issue_blocked_fixture/LICENSE"
printf '%s\n' "fixture" >"$issue_blocked_fixture/SECURITY.md"
printf '' >"$issue_blocked_fixture/.gitignore"
fixture_git "$issue_blocked_fixture" init >/dev/null
fixture_git "$issue_blocked_fixture" add README.md LICENSE SECURITY.md .gitignore
fixture_git "$issue_blocked_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init issue api blocked fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/issue-api-blocked)
    printf '%s\n' '{"description":"issue api blocked fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/issue-api-blocked/community/profile)
    printf '%s\n' '{"health_percentage":100,"files":{"issue_template":null}}'
    ;;
  repos/example/issue-api-blocked/actions/runs?per_page=3)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
issue_blocked_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$issue_blocked_fixture" example/issue-api-blocked 2>&1)"
issue_blocked_code=$?
set -e
rm -rf "$issue_blocked_fixture" "$fake_gh_dir"
if [[ "$issue_blocked_code" -eq 1 ]] \
  && echo "$issue_blocked_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"API_BLOCKED"' \
  && echo "$issue_blocked_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"API_BLOCKED"' \
  && echo "$issue_blocked_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/config.yml","result":"API_BLOCKED"' \
  && echo "$issue_blocked_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: hosted issue-template lookup unavailable)'; then
  echo "  PASS"
else
  echo "  FAIL: expected API_BLOCKED issue-template evidence"
  printf '%s\n' "$issue_blocked_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence records API_BLOCKED when latest CI cannot be fetched"
runs_blocked_fixture="$(mktemp -d)"
mkdir -p "$runs_blocked_fixture/.github/workflows"
printf '%s\n' "fixture" >"$runs_blocked_fixture/README.md"
printf '%s\n' "fixture" >"$runs_blocked_fixture/LICENSE"
printf '%s\n' "fixture" >"$runs_blocked_fixture/SECURITY.md"
printf '' >"$runs_blocked_fixture/.gitignore"
printf '%s\n' "name: ci" >"$runs_blocked_fixture/.github/workflows/ci.yml"
fixture_git "$runs_blocked_fixture" init >/dev/null
fixture_git "$runs_blocked_fixture" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
fixture_git "$runs_blocked_fixture" -c user.email=fixture@test -c user.name=fixture commit -m "init runs api blocked fixture" >/dev/null
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/runs-api-blocked)
    printf '%s\n' '{"description":"runs api blocked fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
    ;;
  repos/example/runs-api-blocked/community/profile)
    printf '%s\n' '{"health_percentage":100,"files":{"issue_template":null}}'
    ;;
  repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/bug_report.md)
    exit 4
    ;;
  repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/feature_request.md)
    exit 4
    ;;
  repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/config.yml)
    exit 4
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
runs_blocked_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$runs_blocked_fixture" example/runs-api-blocked 2>&1)"
runs_blocked_code=$?
set -e
rm -rf "$runs_blocked_fixture" "$fake_gh_dir"
if [[ "$runs_blocked_code" -eq 1 ]] \
  && echo "$runs_blocked_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: latest CI metadata unavailable)' \
  && ! echo "$runs_blocked_out" | grep -Eq 'result: (NO_RUNS|NOT_CONFIGURED)'; then
  echo "  PASS"
else
  echo "  FAIL: expected API_BLOCKED latest CI evidence"
  printf '%s\n' "$runs_blocked_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence records API_BLOCKED when hosted metadata cannot be fetched"
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$fake_gh_dir/gh"
set +e
blocked_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$FIXTURE" example/blocked 2>&1)"
blocked_code=$?
set -e
rm -rf "$fake_gh_dir"
if [[ "$blocked_code" -eq 1 ]] \
  && echo "$blocked_out" | grep -Fq 'result: BLOCKED (API_BLOCKED: hosted metadata unavailable)'; then
  echo "  PASS"
else
  echo "  FAIL: expected API_BLOCKED hosted metadata line"
  printf '%s\n' "$blocked_out"
  failures=$((failures + 1))
fi
echo "TEST: collect-audit-evidence treats gh 404 issue-template responses as absent"
fake_gh_dir="$(mktemp -d)"
cat >"$fake_gh_dir/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" != "api" ]]; then
  exit 1
fi
case "${2:-}" in
  repos/example/repo)
    printf '%s\n' '{"description":"fixture","topics":[],"homepage":"","visibility":"public","has_issues":true}'
    ;;
  repos/example/repo/community/profile)
    printf '%s\n' '{"health_percentage":100,"files":{}}'
    ;;
  repos/example/repo/actions/runs?per_page=3)
    printf '%s\n' '{"workflow_runs":[]}'
    ;;
  repos/example/repo/contents/.github/ISSUE_TEMPLATE/bug_report.md|repos/example/repo/contents/.github/ISSUE_TEMPLATE/feature_request.md|repos/example/repo/contents/.github/ISSUE_TEMPLATE/config.yml)
    printf '%s\n' '{"message":"Not Found","status":"404"}'
    exit 1
    ;;
  *)
    exit 1
    ;;
esac
EOF
chmod +x "$fake_gh_dir/gh"
set +e
gh_404_out="$(PATH="$fake_gh_dir:$PATH" GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK=1 bash "$SHELF/scripts/collect-audit-evidence.sh" "$FIXTURE" example/repo 2>&1)"
gh_404_code=$?
set -e
rm -rf "$fake_gh_dir"
if [[ "$gh_404_code" -eq 0 ]] \
  && echo "$gh_404_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"ABSENT"' \
  && echo "$gh_404_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"ABSENT"' \
  && echo "$gh_404_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/config.yml","result":"ABSENT"' \
  && echo "$gh_404_out" | grep -Fq 'result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)' \
  && ! echo "$gh_404_out" | grep -q 'API_BLOCKED'; then
  echo "  PASS"
else
  echo "  FAIL: expected gh 404 issue-template responses to be ABSENT"
  printf '%s\n' "$gh_404_out"
  failures=$((failures + 1))
fi
fi

if suite_enabled "orchestrator"; then
PRESENT_HEAD="$(git -C "$SHELF" -c "safe.directory=$SHELF" rev-parse HEAD)"
# v1.1.4 -> present always includes audit.manifest.yml change (v1.1.5); stable across future commits
MANIFEST_PRIOR_HEAD="$(git -C "$SHELF" -c "safe.directory=$SHELF" rev-parse "v1.1.4^{commit}")"
SKIP_SHELF_VALIDATION=1 run_exit "run-delta-audit allowed (no changes)" 0 \
  bash "$SHELF/scripts/run-delta-audit.sh" "$SHELF" "" release "$DELTA_DRY_RUN_SLUG" "$PRESENT_HEAD"
echo "TEST: delta audit record captures latest CI section and machine evidence"
if [[ -f "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md" ]] \
  && grep -Fq '### Latest CI Assessment (`R-02`)' "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md" \
  && grep -Fq -- '- selected workflow path: .github/workflows/ci.yml' "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md" \
  && grep -Fq -- '- workflow selection: explicit_ci_filename' "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md" \
  && grep -Fq 'reviewer confirmation checklist when collector provisional assessment is `review`:' "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md" \
  && grep -Fq '=== Repository ===' "$SHELF/audits/$DELTA_DRY_RUN_SLUG/delta-audit-record.md"; then
  echo "  PASS"
else
  echo "  FAIL: expected delta scaffold with latest CI section and machine evidence"
  failures=$((failures + 1))
fi
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
echo "TEST: full audit report captures latest CI section and machine evidence"
if [[ -f "$SHELF/audits/$FIXTURE_SLUG/audit-report.md" ]] \
  && grep -Fq '### Latest CI Assessment (`R-02`)' "$SHELF/audits/$FIXTURE_SLUG/audit-report.md" \
  && grep -Fq 'reviewer confirmation checklist when collector provisional assessment is `review`:' "$SHELF/audits/$FIXTURE_SLUG/audit-report.md" \
  && grep -Fq '=== Repository ===' "$SHELF/audits/$FIXTURE_SLUG/audit-report.md"; then
  echo "  PASS"
else
  echo "  FAIL: expected full audit scaffold with latest CI section and machine evidence"
  failures=$((failures + 1))
fi

echo "TEST: run-full-audit preserves blocked machine evidence but exits 0"
init_tracked_ignored
set +e
blocked_full_out="$(bash "$SHELF/scripts/run-full-audit.sh" "$TRACKED_IGNORED" "" public-prep pre-public "$BLOCKED_FULL_AUDIT_SLUG" 2>&1)"
blocked_full_code=$?
set -e
if [[ "$blocked_full_code" -eq 0 ]] \
  && echo "$blocked_full_out" | grep -Fq 'orchestrator: machine evidence captured; collector exit 1 reflects target findings or quickstart failures (review before scoring gates)' \
  && [[ -f "$SHELF/audits/$BLOCKED_FULL_AUDIT_SLUG/audit-report.md" ]]; then
  echo "  PASS"
else
  echo "  FAIL: expected blocked evidence to be preserved with orchestrator exit 0"
  printf '%s\n' "$blocked_full_out"
  failures=$((failures + 1))
fi

echo "TEST: run-full-audit prefers remote repository name for slug"
remote_slug_repo="$(mktemp -d)"
printf '%s\n' "fixture" >"$remote_slug_repo/README.md"
printf '%s\n' "fixture" >"$remote_slug_repo/LICENSE"
printf '%s\n' "fixture" >"$remote_slug_repo/SECURITY.md"
printf '' >"$remote_slug_repo/.gitignore"
fixture_git "$remote_slug_repo" init >/dev/null
fixture_git "$remote_slug_repo" add README.md LICENSE SECURITY.md .gitignore
fixture_git "$remote_slug_repo" -c user.email=fixture@test -c user.name=fixture commit -m "init remote slug fixture" >/dev/null
fixture_git "$remote_slug_repo" remote add origin https://github.com/example/remote-slug-fixture.git
set +e
remote_slug_out="$(SKIP_SHELF_VALIDATION=1 bash "$SHELF/scripts/run-full-audit.sh" "$remote_slug_repo" "" public-prep pre-public 2>&1)"
remote_slug_code=$?
set -e
rm -rf "$remote_slug_repo"
if [[ "$remote_slug_code" -eq 0 ]] \
  && echo "$remote_slug_out" | grep -Fq 'Audit slug: remote-slug-fixture' \
  && [[ -f "$SHELF/audits/$REMOTE_SLUG_DRY_RUN_SLUG/audit-report.md" ]]; then
  echo "  PASS"
else
  echo "  FAIL: expected remote-derived audit slug"
  printf '%s\n' "$remote_slug_out"
  failures=$((failures + 1))
fi

# Dedicated dry-run slug - never delete audits/github-optimization/ (real dogfood output).
rm -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"
run_exit "run-full-audit dry-run on shelf root" 0 \
  bash "$SHELF/scripts/run-full-audit.sh" "$SHELF" "" public-prep pre-public "$SHELF_DRY_RUN_SLUG"
run_pass "shelf orchestrator dry-run report scaffolded" test -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"
echo "TEST: shelf audit report carries latest CI workflow summary"
if [[ -f "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md" ]] \
  && grep -Fq -- '- selected workflow path: .github/workflows/ci.yml' "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md" \
  && grep -Fq -- '- workflow selection: explicit_ci_filename' "$SHELF/audits/$SHELF_DRY_RUN_SLUG/audit-report.md"; then
  echo "  PASS"
else
  echo "  FAIL: expected audit report to carry latest CI workflow summary"
  failures=$((failures + 1))
fi
fi

cleanup_generated

echo
if [[ "$failures" -eq 0 ]]; then
  echo "regulation-tests: PASS"
  exit 0
fi

echo "regulation-tests: FAIL ($failures)"
exit 1
