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

cleanup_generated() {
  rm -rf \
    "$SHELF/audits/$DELTA_DRY_RUN_SLUG" \
    "$SHELF/audits/$FIXTURE_SLUG" \
    "$SHELF/audits/$SHELF_DRY_RUN_SLUG" \
    "$SHELF/audits/$BLOCKED_FULL_AUDIT_SLUG" \
    "$FIXTURE/.git" \
    "$TRACKED_IGNORED/.git" \
    "$TRACKED_IGNORED/local-only.secret" \
    "$SHELF/scripts/tests/fixtures/quickstart-isolated-repo/out"
}

fixture_git() {
  git -C "$1" -c "safe.directory=$1" "${@:2}"
}

cleanup_generated
init_minimal_docs_fixture

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
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/bug_report.md","result":"ABSENT"' \
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/feature_request.md","result":"ABSENT"' \
  && echo "$hosted_out" | grep -Fq '"requested":".github/ISSUE_TEMPLATE/config.yml","result":"ABSENT"' \
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
  printf '%s\n' 'warning: failed to load config: open C:\Users\sandbox\AppData\Roaming\GitHub CLI\config.yml: Access is denied.' >&2
  printf '%s\n' 'failed to create root command: failed to read configuration: open C:\Users\sandbox\AppData\Roaming\GitHub CLI\config.yml: Access is denied.' >&2
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
    printf '%s\n' '{"description":"partial template fixture","topics":[],"homepage":"","visibility":"public","has_issues":true,"security_and_analysis":{"secret_scanning":{"status":"enabled"}}}'
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
  repos/example/partial/actions/runs?per_page=3)
    printf '%s\n' '{"workflow_runs":[{"name":"CI","event":"push","status":"completed","conclusion":"success","head_branch":"main","html_url":"https://example.test/runs/1"}]}'
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
  && echo "$partial_out" | grep -Fq '"name":"CI","event":"push","status":"completed","conclusion":"success","head_branch":"main","html_url":"https://example.test/runs/1"' \
  && ! echo "$partial_out" | grep -Eq 'result: (NO_RUNS|NOT_CONFIGURED)'; then
  echo "  PASS"
else
  echo "  FAIL: expected mixed PASS/ABSENT issue-template evidence and workflow run JSON"
  printf '%s\n' "$partial_out"
  failures=$((failures + 1))
fi
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
PRESENT_HEAD="$(git -C "$SHELF" -c "safe.directory=$SHELF" rev-parse HEAD)"
# v1.1.4 -> present always includes audit.manifest.yml change (v1.1.5); stable across future commits
MANIFEST_PRIOR_HEAD="$(git -C "$SHELF" -c "safe.directory=$SHELF" rev-parse "v1.1.4^{commit}")"
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
