param(
    [ValidateSet("all", "ci-selection", "orchestrator")]
    [string]$Suite = "all"
)

$ErrorActionPreference = "Stop"

$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) {
    $env:GITHUB_OPTIMIZATION_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$failures = 0

function Invoke-TestGit {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoPath,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )
    & git -C $RepoPath -c "safe.directory=$RepoPath" @GitArgs
}

function Assert-Pass([string]$name, [scriptblock]$block) {
    Write-Output "TEST: $name"
    try {
        $null = & $block
        Write-Output "  PASS"
    } catch {
        Write-Output "  FAIL: $($_.Exception.Message)"
        $script:failures++
    }
}

function Assert-ExitCode([string]$name, [int]$expected, [scriptblock]$block) {
    Write-Output "TEST: $name"
    try {
        & $block
        $code = $LASTEXITCODE
        if ($code -ne $expected) {
            Write-Output "  FAIL: expected exit $expected, got $code"
            $script:failures++
            return
        }
        Write-Output "  PASS"
    } catch {
        Write-Output "  FAIL: $($_.Exception.Message)"
        $script:failures++
    }
}

$fixture = Join-Path $Shelf "scripts\tests\fixtures\minimal-docs-repo"
$trackedIgnoredFixture = Join-Path $Shelf "scripts\tests\fixtures\tracked-ignored-repo"
$deltaDryRunSlug = "delta-orchestrator-dry-run"
$fixtureSlug = "minimal-docs-repo"
$shelfDryRunSlug = "shelf-orchestrator-dry-run"
$blockedFullAuditSlug = "tracked-ignored-orchestrator-dry-run"
$remoteSlugDryRunSlug = "remote-slug-fixture"

function Initialize-TrackedIgnoredFixture {
    Remove-Item -LiteralPath (Join-Path $trackedIgnoredFixture ".git") -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $trackedIgnoredFixture "local-only.secret") -Force -ErrorAction SilentlyContinue

    $localOnlySecret = Join-Path $trackedIgnoredFixture "local-only.secret"
    Set-Content -LiteralPath $localOnlySecret -Value "fixture-secret=tracked-but-ignored" -NoNewline

    Push-Location $trackedIgnoredFixture
    try {
        git -c "safe.directory=$trackedIgnoredFixture" init | Out-Null
        git -c "safe.directory=$trackedIgnoredFixture" add README.md LICENSE SECURITY.md .gitignore
        if ($LASTEXITCODE -ne 0) { throw "failed to add tracked-ignored base files" }
        git -c "safe.directory=$trackedIgnoredFixture" add -f -- local-only.secret
        if ($LASTEXITCODE -ne 0) { throw "failed to add local-only.secret" }
        git -c "safe.directory=$trackedIgnoredFixture" -c user.email="fixture@test" -c user.name="fixture" commit -m "init tracked-ignored fixture" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "failed to commit tracked-ignored fixture" }
    } finally {
        Pop-Location
    }
}

function Test-SuiteEnabled([string]$Target) {
    return $Suite -eq "all" -or $Suite -eq $Target
}

function Initialize-MinimalDocsFixture {
    Remove-Item -LiteralPath (Join-Path $fixture ".git") -Recurse -Force -ErrorAction SilentlyContinue

    Push-Location $fixture
    try {
        git -c "safe.directory=$fixture" init | Out-Null
        git -c "safe.directory=$fixture" add README.md LICENSE SECURITY.md .gitignore
        if ($LASTEXITCODE -ne 0) { throw "failed to add minimal-docs fixture files" }
        git -c "safe.directory=$fixture" -c user.email="fixture@test" -c user.name="fixture" commit -m "init minimal docs fixture" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "failed to commit minimal-docs fixture" }
    } finally {
        Pop-Location
    }
}

function Remove-GeneratedTestArtifacts {
    $generatedPaths = @(
        (Join-Path $Shelf "audits\$deltaDryRunSlug"),
        (Join-Path $Shelf "audits\$fixtureSlug"),
        (Join-Path $Shelf "audits\$shelfDryRunSlug"),
        (Join-Path $Shelf "audits\$blockedFullAuditSlug"),
        (Join-Path $Shelf "audits\$remoteSlugDryRunSlug"),
        (Join-Path $fixture ".git"),
        (Join-Path $trackedIgnoredFixture ".git"),
        (Join-Path $trackedIgnoredFixture "local-only.secret"),
        (Join-Path $Shelf "scripts\tests\fixtures\quickstart-isolated-repo\out")
    )

    foreach ($generatedPath in $generatedPaths) {
        if (Test-Path -LiteralPath $generatedPath) {
            Remove-Item -LiteralPath $generatedPath -Recurse -Force
        }
    }
}

Remove-GeneratedTestArtifacts
Initialize-MinimalDocsFixture

if ($Suite -eq "all") {
Assert-ExitCode "validate-regulation-index" 0 {
    & (Join-Path $Shelf "scripts\validate-regulation-index.ps1") -ShelfPath $Shelf
}

Assert-ExitCode "check-tracked-files on shelf" 0 {
    & (Join-Path $Shelf "scripts\check-tracked-files.ps1") -RepoPath $Shelf
}

Assert-ExitCode "check-tracked-files on fixture" 0 {
    & (Join-Path $Shelf "scripts\check-tracked-files.ps1") -RepoPath $fixture
}

Assert-ExitCode "check-gitignore-consistency on shelf" 0 {
    & (Join-Path $Shelf "scripts\check-gitignore-consistency.ps1") -RepoPath $Shelf
}

Assert-ExitCode "check-gitignore-consistency on fixture" 0 {
    & (Join-Path $Shelf "scripts\check-gitignore-consistency.ps1") -RepoPath $fixture
}

Assert-ExitCode "check-gitignore-consistency blocked tracked-ignored fixture" 1 {
    Initialize-TrackedIgnoredFixture
    & (Join-Path $Shelf "scripts\check-gitignore-consistency.ps1") -RepoPath $trackedIgnoredFixture
}

Assert-Pass "collect-audit-evidence completes transcript and exits blocked after blocked gitignore" {
    Initialize-TrackedIgnoredFixture
    $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $trackedIgnoredFixture 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE" }
    if ($out -notmatch "=== Root Files ===") { throw "evidence transcript truncated before Root Files" }
    if ($out -match "result: BLOCKED \(execution environment .*gitleaks") {
        throw "gitleaks execution-environment artifact must be SKIPPED or scored from another transcript"
    }
}

Assert-Pass "collect-audit-evidence treats gitleaks access-denied artifact as skipped" {
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gitleaks-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    $fakeGitleaks = Join-Path $fakeDir "gitleaks.cmd"
    Set-Content -Path $fakeGitleaks -Value @(
        "@echo off",
        "echo Access is denied. 1>&2",
        "exit /b 2"
    )
    $previousPath = $env:PATH
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $fixture 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
        if ($out -notmatch "result: SKIPPED \(execution environment denied gitleaks execution; use direct gitleaks transcript for G-01 scoring\)") {
            throw "expected SKIPPED access-denied gitleaks artifact"
        }
    } finally {
        $env:PATH = $previousPath
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence redacts local absolute paths" {
    $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $Shelf 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
    foreach ($leak in @(
            $Shelf,
            $env:USERPROFILE,
            [System.IO.Path]::GetTempPath()
        )) {
        if ($leak -and $out.Contains($leak)) {
            throw "found local absolute path leak: $leak`n$out"
        }
    }
}

Assert-Pass "collect-audit-evidence handles non-ASCII tracked paths in large-file scan" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-unicode-fixture-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    $largePath = Join-Path $tempRepo "TëstLarge.bin"
    [System.IO.File]::WriteAllBytes($largePath, (New-Object byte[] 512100))
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore TëstLarge.bin
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init unicode fixture" | Out-Null
    Pop-Location
    try {
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -match "Illegal characters in path") {
            throw "large-file scan rejected quoted git path`n$out"
        }
        if ($out -notmatch [regex]::Escape("TëstLarge.bin 512100")) {
            throw "missing unicode large-file evidence`n$out"
        }
    } finally {
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence parses hosted JSON on Windows PowerShell 5.1 and distinguishes hosted evidence states" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-hosted-fixture-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init hosted fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/compat"" goto repo",
        "if /I ""%target%""==""repos/example/compat/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/compat/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/compat/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/compat/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/compat/actions/runs?per_page=3"" goto runs",
        "goto runs",
        ":repo",
        "echo {""description"":""fixture repo"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/compat" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                [regex]::Escape('"description":"fixture repo"'),
                [regex]::Escape('"health_percentage":100'),
                [regex]::Escape('"secret_scanning":{"status":"enabled"}'),
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"ABSENT").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/feature_request\.md")(?=.*"result":"ABSENT").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/config\.yml")(?=.*"result":"ABSENT").*\}',
                [regex]::Escape("result: NO_RUNS (workflow files exist but the GitHub Actions runs API returned 0 runs)")
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($out -match "ConvertFrom-Json : A parameter cannot be found that matches parameter name 'Depth'") {
            throw "Windows PowerShell 5.1 JSON compatibility regression`n$out"
        }
        if ($out -match "result: BLOCKED \(API_BLOCKED") {
            throw "hosted API should not be blocked in fake gh success path`n$out"
        }
        if ($out -match '"permissions":|"updated_at":|"total_count":') {
            throw "hosted collector output should stay compact across platforms`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks hosted issue templates as NOT_APPLICABLE when issues are disabled" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-issues-disabled-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-disabled-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init issues disabled fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/issues-disabled"" goto repo",
        "if /I ""%target%""==""repos/example/issues-disabled/community/profile"" goto community",
        "goto runs",
        ":repo",
        "echo {""description"":""issues disabled fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":false,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":80,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/issues-disabled" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($needle in @(
                '"has_issues":false',
                'result: NOT_APPLICABLE (issues disabled)',
                'result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)'
            )) {
            if ($out -notmatch [regex]::Escape($needle)) {
                throw "missing output: $needle`n$out"
            }
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence preserves PASS and ABSENT issue-template evidence when runs exist" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-partial-template-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-partial-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init partial template fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/partial/actions/runs/123/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/partial"" goto repo",
        "if /I ""%target%""==""repos/example/partial/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto bug",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/config.yml"" goto config",
        "goto runs",
        ":repo",
        "echo {""description"":""partial template fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":95,""files"":{""issue_template"":{}}}",
        "exit /b 0",
        ":bug",
        "echo {""path"":"".github/ISSUE_TEMPLATE/bug_report.md""}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":config",
        "echo {""path"":"".github/ISSUE_TEMPLATE/config.yml""}",
        "exit /b 0",
        ":runs",
        "echo {""workflow_runs"":[{""id"":123,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/1""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":4}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/partial" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"PASS")(?=.*"path":"\.github/ISSUE_TEMPLATE/bug_report\.md").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/feature_request\.md")(?=.*"result":"ABSENT")(?=.*"path":null).*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/config\.yml")(?=.*"result":"PASS")(?=.*"path":"\.github/ISSUE_TEMPLATE/config\.yml").*\}',
                '(?s)\{(?=.*"name":"CI")(?=.*"event":"push")(?=.*"status":"completed")(?=.*"conclusion":"success")(?=.*"run_attempt":1)(?=.*"run_started_at":"2026-06-20T10:00:00Z")(?=.*"updated_at":"2026-06-20T10:02:30Z")(?=.*"duration_seconds":150)(?=.*"jobs_total":4)(?=.*"evidence_scope":"default_branch")(?=.*"default_branch":"main")(?=.*"classification":"pass")(?=.*"r02_assessment":"pass")(?=.*"r02_reason":"latest_default_branch_run_green")(?=.*"head_branch":"main")(?=.*"html_url":"https://example.test/runs/1").*\}'
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($out -match "result: NO_RUNS|result: NOT_CONFIGURED") {
            throw "collector should emit concrete workflow run JSON when runs exist`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

}

if (Test-SuiteEnabled "ci-selection") {
Assert-Pass "collect-audit-evidence prefers the CI workflow over newer non-CI runs on the default branch" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-ci-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-ci-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init ci selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/ci-selection/actions/runs/900/jobs"" >nul && goto cijobs",
        "if /I ""%target%""==""repos/example/ci-selection"" goto repo",
        "if /I ""%target%""==""repos/example/ci-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/ci-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/ci-selection/actions/workflows/ci.yml/runs?branch=main"" goto ciworkflow",
        "if /I ""%target%""==""repos/example/ci-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""ci selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":ciworkflow",
        "echo {""workflow_runs"":[{""id"":900,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/900""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":901,""name"":""Dependabot Updates"",""event"":""dynamic"",""status"":""completed"",""conclusion"":""failure"",""path"":""dynamic/dependabot/dependabot-updates"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:03:05Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/901""},{""id"":900,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/900""}]}",
        "exit /b 0",
        ":cijobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/ci-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":2)(?=.*"classification":"pass")(?=.*"r02_assessment":"pass")(?=.*"html_url":"https://example\.test/runs/900").*\}') {
            throw "collector did not keep the CI workflow run as Latest CI`n$out"
        }
        if ($out -match 'https://example\.test/runs/901') {
            throw "collector should not surface the newer non-CI run in Latest CI output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence selects a non-ci-named primary workflow when it is the only local CI candidate" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-verify-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-verify-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\verify.yml") -Value @(
        "name: Verify",
        "on:",
        "  push:",
        "jobs:",
        "  verify:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo verify"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/verify.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init verify selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/verify-selection/actions/runs/905/jobs"" >nul && goto verifyjobs",
        "if /I ""%target%""==""repos/example/verify-selection"" goto repo",
        "if /I ""%target%""==""repos/example/verify-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/verify-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/verify-selection/actions/workflows/verify.yml/runs?branch=main"" goto verifyworkflow",
        "if /I ""%target%""==""repos/example/verify-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""verify selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":verifyworkflow",
        "echo {""workflow_runs"":[{""id"":905,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/905""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":906,""name"":""CodeQL"",""event"":""schedule"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/codeql.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:03:05Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/906""},{""id"":905,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/905""}]}",
        "exit /b 0",
        ":verifyjobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/verify-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"Verify")(?=.*"jobs_total":2)(?=.*"classification":"pass")(?=.*"selected_workflow_path":"\.github/workflows/verify\.yml")(?=.*"workflow_selection":"single_local_workflow").*\}') {
            throw "collector did not keep the selected verify workflow run as Latest CI`n$out"
        }
        if ($out -match 'https://example\.test/runs/906') {
            throw "collector should not surface the non-selected workflow run in Latest CI output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence prefers the heuristic primary workflow over non-ci analysis workflows" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-heuristic-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-heuristic-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\verify.yml") -Value @(
        "name: Verify",
        "on:",
        "  push:",
        "jobs:",
        "  verify:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo verify"
    )
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\codeql.yml") -Value @(
        "name: CodeQL",
        "on:",
        "  schedule:",
        "    - cron: '0 0 * * 0'"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/verify.yml .github/workflows/codeql.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init heuristic selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/heuristic-selection/actions/runs/915/jobs"" >nul && goto verifyjobs",
        "if /I ""%target%""==""repos/example/heuristic-selection"" goto repo",
        "if /I ""%target%""==""repos/example/heuristic-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/heuristic-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/heuristic-selection/actions/workflows/verify.yml/runs?branch=main"" goto verifyworkflow",
        "if /I ""%target%""==""repos/example/heuristic-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""heuristic selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":verifyworkflow",
        "echo {""workflow_runs"":[{""id"":915,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/915""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":916,""name"":""CodeQL"",""event"":""schedule"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/codeql.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:03:05Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/916""},{""id"":915,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/915""}]}",
        "exit /b 0",
        ":verifyjobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/heuristic-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"Verify")(?=.*"selected_workflow_path":"\.github/workflows/verify\.yml")(?=.*"workflow_selection":"heuristic_local_workflow").*\}') {
            throw "collector did not select the heuristic verify workflow`n$out"
        }
        if ($out -match 'https://example\.test/runs/916') {
            throw "collector should not surface the non-primary analysis workflow run in Latest CI output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence prefers run-tests over typecheck in heuristic selection" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-run-tests-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-run-tests-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\run-tests.yml") -Value @(
        "name: Tests",
        "on:",
        "  push:",
        "jobs:",
        "  tests:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo tests"
    )
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\typecheck.yml") -Value @(
        "name: Type Check",
        "on:",
        "  push:",
        "jobs:",
        "  typecheck:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo typecheck"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/run-tests.yml .github/workflows/typecheck.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init run-tests selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/run-tests-selection/actions/runs/935/jobs"" >nul && goto runtestsjobs",
        "echo %target% | findstr /C:""repos/example/run-tests-selection/actions/runs/936/jobs"" >nul && goto typecheckjobs",
        "if /I ""%target%""==""repos/example/run-tests-selection"" goto repo",
        "if /I ""%target%""==""repos/example/run-tests-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/run-tests-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/run-tests-selection/actions/workflows/run-tests.yml/runs?branch=main"" goto runtestsworkflow",
        "if /I ""%target%""==""repos/example/run-tests-selection/actions/workflows/typecheck.yml/runs?branch=main"" goto typecheckworkflow",
        "if /I ""%target%""==""repos/example/run-tests-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""run tests selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runtestsworkflow",
        "echo {""workflow_runs"":[{""id"":935,""name"":""Tests"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/run-tests.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/935""}]}",
        "exit /b 0",
        ":typecheckworkflow",
        "echo {""workflow_runs"":[{""id"":936,""name"":""Type Check"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/typecheck.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/936""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":936,""name"":""Type Check"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/typecheck.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/936""},{""id"":935,""name"":""Tests"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/run-tests.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/935""}]}",
        "exit /b 0",
        ":runtestsjobs",
        "echo {""total_count"":2}",
        "exit /b 0",
        ":typecheckjobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/run-tests-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"Tests")(?=.*"selected_workflow_path":"\.github/workflows/run-tests\.yml")(?=.*"workflow_selection":"heuristic_local_workflow").*\}') {
            throw "collector did not prefer run-tests workflow over typecheck`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence prefers go test workflow over govulncheck in heuristic selection" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-go-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-go-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\go.yml") -Value @(
        "name: Unit and Integration Tests",
        "on:",
        "  push:",
        "jobs:",
        "  test:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo test"
    )
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\govulncheck.yml") -Value @(
        "name: Go Vulnerability Check",
        "on:",
        "  push:",
        "jobs:",
        "  govulncheck:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - run: echo govulncheck"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/go.yml .github/workflows/govulncheck.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init go selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/go-selection/actions/runs/945/jobs"" >nul && goto gojobs",
        "echo %target% | findstr /C:""repos/example/go-selection/actions/runs/946/jobs"" >nul && goto vulnjobs",
        "if /I ""%target%""==""repos/example/go-selection"" goto repo",
        "if /I ""%target%""==""repos/example/go-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/go-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/go-selection/actions/workflows/go.yml/runs?branch=main"" goto goworkflow",
        "if /I ""%target%""==""repos/example/go-selection/actions/workflows/govulncheck.yml/runs?branch=main"" goto vulnworkflow",
        "if /I ""%target%""==""repos/example/go-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""go selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":goworkflow",
        "echo {""workflow_runs"":[{""id"":945,""name"":""Unit and Integration Tests"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/go.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/945""}]}",
        "exit /b 0",
        ":vulnworkflow",
        "echo {""workflow_runs"":[{""id"":946,""name"":""Go Vulnerability Check"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/govulncheck.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/946""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":946,""name"":""Go Vulnerability Check"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/govulncheck.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/946""},{""id"":945,""name"":""Unit and Integration Tests"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/go.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/945""}]}",
        "exit /b 0",
        ":gojobs",
        "echo {""total_count"":2}",
        "exit /b 0",
        ":vulnjobs",
        "echo {""total_count"":1}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/go-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"Unit and Integration Tests")(?=.*"selected_workflow_path":"\.github/workflows/go\.yml")(?=.*"workflow_selection":"heuristic_local_workflow").*\}') {
            throw "collector did not prefer go test workflow over govulncheck`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence honors audit manifest primary_ci_workflow override" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-manifest-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-manifest-selection-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo "audit.manifest.yml") -Value @(
        "version: 1",
        "primary_ci_workflow: .github/workflows/release-gate.yml",
        "workdir: in-place",
        "commands:",
        "  - id: noop",
        "    run_windows: echo ok",
        "    run_unix: echo ok",
        "    expect_exit: 0"
    )
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\release-gate.yml") -Value @(
        "name: Ship Window",
        "on:",
        "  workflow_dispatch:"
    )
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\codeql.yml") -Value @(
        "name: CodeQL",
        "on:",
        "  schedule:",
        "    - cron: '0 0 * * 0'"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore audit.manifest.yml .github/workflows/release-gate.yml .github/workflows/codeql.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init manifest selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/manifest-selection/actions/runs/925/jobs"" >nul && goto releasejobs",
        "if /I ""%target%""==""repos/example/manifest-selection"" goto repo",
        "if /I ""%target%""==""repos/example/manifest-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/manifest-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/manifest-selection/actions/workflows/release-gate.yml/runs?branch=main"" goto releaseworkflow",
        "if /I ""%target%""==""repos/example/manifest-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""manifest selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":releaseworkflow",
        "echo {""workflow_runs"":[{""id"":925,""name"":""Ship Window"",""event"":""workflow_dispatch"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/release-gate.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/925""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":926,""name"":""CodeQL"",""event"":""schedule"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/codeql.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:03:05Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/926""},{""id"":925,""name"":""Ship Window"",""event"":""workflow_dispatch"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/release-gate.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/925""}]}",
        "exit /b 0",
        ":releasejobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/manifest-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"Ship Window")(?=.*"selected_workflow_path":"\.github/workflows/release-gate\.yml")(?=.*"workflow_selection":"manifest_override").*\}') {
            throw "collector did not honor manifest workflow override`n$out"
        }
        if ($out -match 'https://example\.test/runs/926') {
            throw "collector should not surface the non-overridden workflow run in Latest CI output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence falls back to hosted workflow inventory when no local CI workflow is present" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-hosted-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-hosted-selection-" + [System.Guid]::NewGuid().ToString("N"))
    $workflowCallLog = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-hosted-selection-calls-" + [System.Guid]::NewGuid().ToString("N") + ".log")
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init hosted selection fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        ">>""$workflowCallLog"" echo %target%",
        "echo %target% | findstr /C:""repos/example/hosted-selection/actions/runs/935/jobs"" >nul && goto verifyjobs",
        "if /I ""%target%""==""repos/example/hosted-selection"" goto repo",
        "if /I ""%target%""==""repos/example/hosted-selection/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/hosted-selection/actions/workflows"" goto workflows",
        "if /I ""%target%""==""repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/hosted-selection/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/hosted-selection/actions/workflows/verify.yml/runs?branch=main"" goto verifyworkflow",
        "if /I ""%target%""==""repos/example/hosted-selection/actions/runs?branch=main"" goto allruns",
        "goto allruns",
        ":repo",
        "echo {""description"":""hosted selection fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":workflows",
        "echo {""total_count"":2,""workflows"":[{""name"":""CodeQL"",""path"":""/.github/workflows/codeql.yml"",""state"":""active""},{""name"":""Verify"",""path"":""/.github/workflows/verify.yml"",""state"":""active""}]}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":verifyworkflow",
        "echo {""workflow_runs"":[{""id"":935,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/935""}]}",
        "exit /b 0",
        ":allruns",
        "echo {""workflow_runs"":[{""id"":936,""name"":""CodeQL"",""event"":""schedule"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/codeql.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:03:00Z"",""updated_at"":""2026-06-20T10:03:05Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/936""},{""id"":935,""name"":""Verify"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""path"":""/.github/workflows/verify.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:30Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/935""}]}",
        "exit /b 0",
        ":verifyjobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/hosted-selection" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch [regex]::Escape("primary_ci_workflow: .github/workflows/verify.yml")) {
            throw "collector did not surface hosted primary_ci_workflow in GitHub Files output`n$out"
        }
        if ($out -notmatch [regex]::Escape("primary_ci_selection: hosted_workflow_inventory")) {
            throw "collector did not surface hosted primary_ci_selection in GitHub Files output`n$out"
        }
        if ($out -notmatch '(?s)\{(?=.*"name":"Verify")(?=.*"selected_workflow_path":"\.github/workflows/verify\.yml")(?=.*"workflow_selection":"hosted_workflow_inventory").*\}') {
            throw "collector did not honor hosted workflow inventory selection`n$out"
        }
        if ($out -match 'https://example\.test/runs/936') {
            throw "collector should not surface the non-selected hosted workflow run in Latest CI output`n$out"
        }
        $workflowApiCalls = @(
            Get-Content -LiteralPath $workflowCallLog -ErrorAction SilentlyContinue |
            Where-Object { $_ -eq "repos/example/hosted-selection/actions/workflows" }
        ).Count
        if ($workflowApiCalls -ne 1) {
            throw "collector should resolve hosted workflow inventory exactly once, saw $workflowApiCalls calls`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $workflowCallLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks branch-filter candidates for zero-job runs with filtered workflows" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-branch-filter-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-branch-filter-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value @(
        "name: ci",
        "on:",
        "  push:",
        "    branches:",
        "      - main"
    )
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init branch filter fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/branch-filter/actions/runs/321/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/branch-filter"" goto repo",
        "if /I ""%target%""==""repos/example/branch-filter/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/branch-filter/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""branch filter fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":321,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""startup_failure"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:00:03Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/321""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":0}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/branch-filter" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"path":"/\.github/workflows/ci\.yml")(?=.*"jobs_total":0)(?=.*"evidence_scope":"default_branch")(?=.*"default_branch":"main")(?=.*"classification":"branch_filter_candidate")(?=.*"r02_assessment":"review")(?=.*"r02_reason":"branch_filter_candidate_requires_confirmation")(?=.*"signals":\["no_jobs_recorded","startup_failure","startup_failure_candidate","near_zero_duration","branch_filter_candidate"\]).*\}') {
            throw "missing branch_filter_candidate output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks hard failures as blocked for R-02 on default branch" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-hard-failure-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-hard-failure-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init hard failure fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/hard-failure/actions/runs/654/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/hard-failure"" goto repo",
        "if /I ""%target%""==""repos/example/hard-failure/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/hard-failure/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""hard failure fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":654,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/654""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":3}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/hard-failure" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":3)(?=.*"classification":"hard_failure")(?=.*"r02_assessment":"blocked")(?=.*"r02_reason":"latest_default_branch_run_failed").*\}') {
            throw "missing hard-failure R-02 mapping`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks startup-failure candidates for manual review on default branch" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-startup-failure-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-startup-failure-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init startup failure fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/startup-failure/actions/runs/701/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/startup-failure"" goto repo",
        "if /I ""%target%""==""repos/example/startup-failure/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/startup-failure/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""startup failure fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":701,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""startup_failure"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:00:02Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/701""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":0}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/startup-failure" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":0)(?=.*"classification":"startup_failure_candidate")(?=.*"r02_assessment":"review")(?=.*"r02_reason":"startup_failure_candidate_requires_confirmation")(?=.*"signals":\["no_jobs_recorded","startup_failure","startup_failure_candidate","near_zero_duration"\]).*\}') {
            throw "missing startup_failure_candidate output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks in-progress default-branch runs for manual review" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-in-progress-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-in-progress-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init in-progress fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/in-progress/actions/runs/702/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/in-progress"" goto repo",
        "if /I ""%target%""==""repos/example/in-progress/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/in-progress/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""in progress fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":702,""name"":""CI"",""event"":""push"",""status"":""in_progress"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:01:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/702""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":1}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/in-progress" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":1)(?=.*"classification":"in_progress")(?=.*"r02_assessment":"review")(?=.*"r02_reason":"default_branch_run_in_progress").*\}') {
            throw "missing in_progress output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks non-blocking default-branch runs for manual review" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-non-blocking-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-non-blocking-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init non-blocking fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/non-blocking/actions/runs/703/jobs"" >nul && goto jobs",
        "if /I ""%target%""==""repos/example/non-blocking"" goto repo",
        "if /I ""%target%""==""repos/example/non-blocking/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/non-blocking/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""non blocking fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":703,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""skipped"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:02:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/703""}]}",
        "exit /b 0",
        ":jobs",
        "echo {""total_count"":2}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/non-blocking" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":2)(?=.*"classification":"non_blocking")(?=.*"r02_assessment":"review")(?=.*"r02_reason":"default_branch_run_non_green_non_blocking").*\}') {
            throw "missing non_blocking output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence marks jobs-api-blocked runs as unknown for manual review" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-unknown-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-unknown-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init unknown fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "echo %target% | findstr /C:""repos/example/unknown/actions/runs/704/jobs"" >nul && exit /b 1",
        "if /I ""%target%""==""repos/example/unknown"" goto repo",
        "if /I ""%target%""==""repos/example/unknown/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/unknown/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/unknown/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/unknown/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "goto runs",
        ":repo",
        "echo {""description"":""unknown fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""default_branch"":""main"",""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":90,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[{""id"":704,""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""failure"",""path"":""/.github/workflows/ci.yml"",""run_attempt"":1,""run_started_at"":""2026-06-20T10:00:00Z"",""updated_at"":""2026-06-20T10:04:00Z"",""head_branch"":""main"",""html_url"":""https://example.test/runs/704""}]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/unknown" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch '(?s)\{(?=.*"name":"CI")(?=.*"jobs_total":null)(?=.*"classification":"unknown")(?=.*"r02_assessment":"review")(?=.*"r02_reason":"insufficient_ci_evidence")(?=.*"signals":"jobs_api_blocked").*\}') {
            throw "missing unknown classification output`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

}

if ($Suite -eq "all") {
Assert-Pass "collect-audit-evidence preserves caller GH_CONFIG_DIR for public gh api access" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-gh-config-fixture-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-config-" + [System.Guid]::NewGuid().ToString("N"))
    $expectedGhConfigDir = "sentinel-gh-config-token"
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init gh config fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/gh-config"" goto repo",
        "if /I ""%target%""==""repos/example/gh-config/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/gh-config/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config/actions/runs?per_page=3"" goto runs",
        "goto runs",
        ":repo",
        "echo {""description"":""%GH_CONFIG_DIR%"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    $previousGhConfigDir = $env:GH_CONFIG_DIR
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $env:GH_CONFIG_DIR = $expectedGhConfigDir
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/gh-config" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                [regex]::Escape(('"description":"' + $expectedGhConfigDir + '"')),
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"ABSENT").*\}',
                [regex]::Escape("result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)")
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($env:GH_CONFIG_DIR -ne $expectedGhConfigDir) {
            throw "collector should preserve caller GH_CONFIG_DIR"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        if ($null -ne $previousGhConfigDir) {
            $env:GH_CONFIG_DIR = $previousGhConfigDir
        } else {
            Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence retries public gh api with isolated GH_CONFIG_DIR when default config is unreadable" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-gh-config-retry-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-config-retry-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init gh config retry fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "if not defined GH_CONFIG_DIR goto denied",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/gh-config-retry"" goto repo",
        "if /I ""%target%""==""repos/example/gh-config-retry/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/gh-config-retry/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config-retry/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config-retry/contents/.github/ISSUE_TEMPLATE/config.yml"" goto missing",
        "if /I ""%target%""==""repos/example/gh-config-retry/actions/runs?per_page=3"" goto runs",
        "goto runs",
        ":denied",
        "echo warning: failed to load config: open ^<GH_CONFIG_DIR^>/config.yml: Access is denied. 1>&2",
        "echo failed to create root command: failed to read configuration: open ^<GH_CONFIG_DIR^>/config.yml: Access is denied. 1>&2",
        "exit /b 1",
        ":repo",
        "echo {""description"":""retry-ok"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 4",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    $previousGhConfigDir = $env:GH_CONFIG_DIR
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/gh-config-retry" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                [regex]::Escape('"description":"retry-ok"'),
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"ABSENT").*\}',
                [regex]::Escape('result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)')
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($out -match 'API_BLOCKED') {
            throw "config-access-denied retry should not fall through to API_BLOCKED`n$out"
        }
        if ($null -ne $previousGhConfigDir -and $env:GH_CONFIG_DIR -ne $previousGhConfigDir) {
            throw "collector must restore caller GH_CONFIG_DIR after retry"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        if ($null -ne $previousGhConfigDir) {
            $env:GH_CONFIG_DIR = $previousGhConfigDir
        } else {
            Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence does not treat gh auth-required retry failures as ABSENT" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-gh-auth-required-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-auth-required-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init gh auth required fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "if not defined GH_CONFIG_DIR goto denied",
        ":auth",
        "echo To get started with GitHub CLI, please run:  gh auth login 1>&2",
        "echo Alternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token. 1>&2",
        "exit /b 4",
        ":denied",
        "echo warning: failed to load config: open ^<GH_CONFIG_DIR^>/config.yml: Access is denied. 1>&2",
        "echo failed to create root command: failed to read configuration: open ^<GH_CONFIG_DIR^>/config.yml: Access is denied. 1>&2",
        "exit /b 1"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    $previousGhConfigDir = $env:GH_CONFIG_DIR
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/gh-auth-required" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                [regex]::Escape('result: BLOCKED (API_BLOCKED: hosted metadata unavailable)'),
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"API_BLOCKED").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/feature_request\.md")(?=.*"result":"API_BLOCKED").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/config\.yml")(?=.*"result":"API_BLOCKED").*\}',
                [regex]::Escape('result: BLOCKED (API_BLOCKED: hosted issue-template lookup unavailable)'),
                [regex]::Escape('result: BLOCKED (API_BLOCKED: latest CI metadata unavailable)')
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($out -match '"result":"ABSENT","requested":".github/ISSUE_TEMPLATE/') {
            throw "gh auth-required retry must not be downgraded to ABSENT`n$out"
        }
        if ($null -ne $previousGhConfigDir -and $env:GH_CONFIG_DIR -ne $previousGhConfigDir) {
            throw "collector must restore caller GH_CONFIG_DIR after auth-required retry"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        if ($null -ne $previousGhConfigDir) {
            $env:GH_CONFIG_DIR = $previousGhConfigDir
        } else {
            Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence records API_BLOCKED when hosted issue templates cannot be fetched" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-issue-api-blocked-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-issue-blocked-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init issue api blocked fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/issue-api-blocked"" goto repo",
        "if /I ""%target%""==""repos/example/issue-api-blocked/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/issue-api-blocked/actions/runs?per_page=3"" goto runs",
        "exit /b 1",
        ":repo",
        "echo {""description"":""issue api blocked fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{""issue_template"":null}}",
        "exit /b 0",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/issue-api-blocked" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"API_BLOCKED").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/feature_request\.md")(?=.*"result":"API_BLOCKED").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/config\.yml")(?=.*"result":"API_BLOCKED").*\}',
                [regex]::Escape("result: BLOCKED (API_BLOCKED: hosted issue-template lookup unavailable)")
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence records API_BLOCKED when latest CI cannot be fetched" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-runs-api-blocked-" + [System.Guid]::NewGuid().ToString("N"))
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-runs-blocked-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $tempRepo ".github\workflows") -Force | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Set-Content -Path (Join-Path $tempRepo ".github\workflows\ci.yml") -Value "name: ci"
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore .github/workflows/ci.yml
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init runs api blocked fixture" | Out-Null
    Pop-Location

    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ""target=%~2""",
        "if /I ""%target%""==""repos/example/runs-api-blocked"" goto repo",
        "if /I ""%target%""==""repos/example/runs-api-blocked/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/bug_report.md"" exit /b 4",
        "if /I ""%target%""==""repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/feature_request.md"" exit /b 4",
        "if /I ""%target%""==""repos/example/runs-api-blocked/contents/.github/ISSUE_TEMPLATE/config.yml"" exit /b 4",
        "exit /b 1",
        ":repo",
        "echo {""description"":""runs api blocked fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{""issue_template"":null}}",
        "exit /b 0"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $tempRepo -HostedRepo "example/runs-api-blocked" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE`n$out" }
        if ($out -notmatch [regex]::Escape("result: BLOCKED (API_BLOCKED: latest CI metadata unavailable)")) {
            throw "missing API_BLOCKED latest CI line`n$out"
        }
        if ($out -match "result: NO_RUNS|result: NOT_CONFIGURED") {
            throw "latest CI should be blocked, not downgraded to NO_RUNS/NOT_CONFIGURED`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence records API_BLOCKED when hosted metadata cannot be fetched" {
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-blocked-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "exit /b 1"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $fixture -HostedRepo "example/blocked" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1) { throw "expected exit 1, got $LASTEXITCODE" }
        if ($out -notmatch [regex]::Escape("result: BLOCKED (API_BLOCKED: hosted metadata unavailable)")) {
            throw "expected API_BLOCKED hosted metadata line"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Pass "collect-audit-evidence treats gh 404 issue-template responses as absent" {
    $fakeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-fake-gh-404-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $fakeDir | Out-Null
    $fakeGh = Join-Path $fakeDir "gh.cmd"
    Set-Content -Path $fakeGh -Value @(
        "@echo off",
        "if /I not ""%~1""==""api"" exit /b 1",
        "set ARGS=%*",
        "echo %ARGS% | findstr /C:""repos/example/repo/community/profile"" >nul && goto community",
        "echo %ARGS% | findstr /C:""repos/example/repo/actions/runs?per_page=3"" >nul && goto runs",
        "echo %ARGS% | findstr /C:""repos/example/repo/contents/.github/ISSUE_TEMPLATE/bug_report.md"" >nul && goto missing",
        "echo %ARGS% | findstr /C:""repos/example/repo/contents/.github/ISSUE_TEMPLATE/feature_request.md"" >nul && goto missing",
        "echo %ARGS% | findstr /C:""repos/example/repo/contents/.github/ISSUE_TEMPLATE/config.yml"" >nul && goto missing",
        "echo %ARGS% | findstr /C:""repos/example/repo"" >nul && goto repo",
        "exit /b 1",
        ":repo",
        "echo {""description"":""fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true}",
        "exit /b 0",
        ":community",
        "echo {""health_percentage"":100,""files"":{}}",
        "exit /b 0",
        ":runs",
        "echo {""workflow_runs"":[]}",
        "exit /b 0",
        ":missing",
        "echo {""message"":""Not Found"",""status"":""404""}",
        "exit /b 1"
    )
    $previousPath = $env:PATH
    $previousDisableCurlFallback = $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK
    try {
        $env:PATH = "$fakeDir;$previousPath"
        $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = "1"
        $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $fixture -HostedRepo "example/repo" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        foreach ($pattern in @(
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/bug_report\.md")(?=.*"result":"ABSENT").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/feature_request\.md")(?=.*"result":"ABSENT").*\}',
                '(?s)\{(?=.*"requested":"\.github/ISSUE_TEMPLATE/config\.yml")(?=.*"result":"ABSENT").*\}',
                [regex]::Escape('result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)')
            )) {
            if ($out -notmatch $pattern) {
                throw "missing output pattern: $pattern`n$out"
            }
        }
        if ($out -match 'API_BLOCKED') {
            throw "gh 404 issue-template responses must not be reported as API_BLOCKED`n$out"
        }
    } finally {
        $env:PATH = $previousPath
        if ($null -ne $previousDisableCurlFallback) {
            $env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK = $previousDisableCurlFallback
        } else {
            Remove-Item Env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

}

if (Test-SuiteEnabled "orchestrator") {
$presentHead = (Invoke-TestGit -RepoPath $Shelf rev-parse HEAD)
# v1.1.4 -> present always includes audit.manifest.yml change (v1.1.5); stable across future commits
$manifestPriorHead = (Invoke-TestGit -RepoPath $Shelf rev-parse 'v1.1.4^{commit}')
Assert-ExitCode "run-delta-audit allowed (no changes)" 0 {
    & (Join-Path $Shelf "scripts\run-delta-audit.ps1") `
        -RepoPath $Shelf `
        -AuditSlug $deltaDryRunSlug `
        -PriorHead $presentHead `
        -SkipShelfValidation
}

Assert-Pass "delta audit record captures latest CI section and machine evidence" {
    $deltaPath = Join-Path $Shelf "audits\$deltaDryRunSlug\delta-audit-record.md"
    $deltaText = Get-Content -LiteralPath $deltaPath -Raw
    foreach ($pattern in @(
            [regex]::Escape('### Latest CI Assessment (`R-02`)'),
            [regex]::Escape('- selected workflow path: .github/workflows/ci.yml'),
            [regex]::Escape('- workflow selection: explicit_ci_filename'),
            [regex]::Escape('reviewer confirmation checklist when collector provisional assessment is `review`:'),
            [regex]::Escape("=== Repository ===")
        )) {
        if ($deltaText -notmatch $pattern) {
            throw "missing delta scaffold content: $pattern`n$deltaText"
        }
    }
}

Assert-ExitCode "run-delta-audit invalidates manifest change" 2 {
    & (Join-Path $Shelf "scripts\run-delta-audit.ps1") `
        -RepoPath $Shelf `
        -AuditSlug $deltaDryRunSlug `
        -PriorHead $manifestPriorHead `
        -SkipShelfValidation
}

Assert-ExitCode "run-audit-quickstart missing manifest exits 2" 2 {
    & (Join-Path $Shelf "scripts\run-audit-quickstart.ps1") -RepoPath $fixture
}

$quickstartFixture = Join-Path $Shelf "scripts\tests\fixtures\quickstart-manifest-repo"
Assert-ExitCode "run-audit-quickstart with manifest exits 0" 0 {
    & (Join-Path $Shelf "scripts\run-audit-quickstart.ps1") -RepoPath $quickstartFixture
}

Assert-Pass "run-audit-quickstart isolated env/assertions windows" {
    $isolatedFixture = Join-Path $Shelf "scripts\tests\fixtures\quickstart-isolated-repo"
    $leakedPath = Join-Path $isolatedFixture "out\env.txt"
    if (Test-Path $leakedPath) { Remove-Item -Recurse -Force (Join-Path $isolatedFixture "out") }

    $out = & (Join-Path $Shelf "scripts\run-audit-quickstart.ps1") -RepoPath $isolatedFixture 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
    foreach ($needle in @(
            "=== quickstart:write-env ===",
            "=== quickstart:legacy-run ===",
            "=== assertion:path_exists:out/env.txt ===",
            "assertions run: 1"
        )) {
        if ($out -notmatch [regex]::Escape($needle)) {
            throw "missing output: $needle"
        }
    }
    if (Test-Path $leakedPath) {
        throw "isolated workdir leaked artifact into fixture"
    }
}

Assert-ExitCode "run-audit-quickstart shelf manifest windows" 0 {
    & (Join-Path $Shelf "scripts\run-audit-quickstart.ps1") -RepoPath $Shelf
}

$requiredTemplates = @(
    "accepted-risk-record.md.template",
    "audit-report.md.template",
    "tier2-defer-record.md.template",
    "audit.manifest.yml.template",
    "delta-audit-record.md.template"
)

foreach ($tpl in $requiredTemplates) {
    Assert-Pass "template exists: $tpl" {
        if (-not (Test-Path (Join-Path $Shelf "templates\$tpl"))) {
            throw "missing $tpl"
        }
    }
}

$requiredPolicies = @(
    "regulation/execution/RE_AUDIT_POLICY.md",
    "regulation/execution/AUDIT_PHASE_POLICY.md",
    "regulation/execution/MULTI_REPO_ORCHESTRATION.md",
    "regulation/reference/TOOL_REVIEW_CADENCE.md"
)

foreach ($policy in $requiredPolicies) {
    Assert-Pass "policy exists: $policy" {
        if (-not (Test-Path (Join-Path $Shelf $policy))) {
            throw "missing $policy"
        }
    }
}

if (-not (Test-Path (Join-Path $fixture ".git"))) {
    Push-Location $fixture
    git -c "safe.directory=$fixture" init | Out-Null
    git -c "safe.directory=$fixture" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$fixture" -c user.email="fixture@test" -c user.name="fixture" commit -m "init minimal docs fixture" | Out-Null
    Pop-Location
}

$fixtureReport = Join-Path $Shelf "audits\$fixtureSlug\audit-report.md"
if (Test-Path $fixtureReport) { Remove-Item $fixtureReport -Force }

Assert-ExitCode "run-full-audit dry-run on fixture" 0 {
    & (Join-Path $Shelf "scripts\run-full-audit.ps1") `
        -RepoPath $fixture `
        -AuditSlug $fixtureSlug `
        -AuditMode public-prep `
        -AuditPhase pre-public
}

Assert-Pass "fixture audit-report scaffolded" {
    if (-not (Test-Path $fixtureReport)) {
        throw "missing $fixtureReport"
    }
}

Assert-Pass "full audit report captures latest CI section and machine evidence" {
    $reportText = Get-Content -LiteralPath $fixtureReport -Raw
    foreach ($pattern in @(
            [regex]::Escape('### Latest CI Assessment (`R-02`)'),
            [regex]::Escape('reviewer confirmation checklist when collector provisional assessment is `review`:'),
            [regex]::Escape("=== Repository ===")
        )) {
        if ($reportText -notmatch $pattern) {
            throw "missing audit report scaffold content: $pattern`n$reportText"
        }
    }
}

$blockedReport = Join-Path $Shelf "audits\$blockedFullAuditSlug\audit-report.md"
if (Test-Path $blockedReport) { Remove-Item $blockedReport -Force }

Assert-Pass "run-full-audit preserves blocked machine evidence but exits 0" {
    Initialize-TrackedIgnoredFixture
    $out = & (Join-Path $Shelf "scripts\run-full-audit.ps1") `
        -RepoPath $trackedIgnoredFixture `
        -AuditSlug $blockedFullAuditSlug `
        -AuditMode public-prep `
        -AuditPhase pre-public 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
    if ($out -notmatch [regex]::Escape("orchestrator: machine evidence captured; collector exit 1 reflects target findings or quickstart failures (review before scoring gates)")) {
        throw "missing blocked-evidence orchestrator note`n$out"
    }
    if (-not (Test-Path $blockedReport)) {
        throw "missing $blockedReport"
    }
}

Assert-Pass "run-full-audit prefers remote repository name for slug" {
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-remote-slug-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRepo | Out-Null
    Set-Content -Path (Join-Path $tempRepo "README.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "LICENSE") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo "SECURITY.md") -Value "fixture"
    Set-Content -Path (Join-Path $tempRepo ".gitignore") -Value ""
    Push-Location $tempRepo
    git -c "safe.directory=$tempRepo" init | Out-Null
    git -c "safe.directory=$tempRepo" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$tempRepo" -c user.email="fixture@test" -c user.name="fixture" commit -m "init remote slug fixture" | Out-Null
    git -c "safe.directory=$tempRepo" remote add origin https://github.com/example/remote-slug-fixture.git
    Pop-Location
    try {
        $out = & (Join-Path $Shelf "scripts\run-full-audit.ps1") `
            -RepoPath $tempRepo `
            -AuditMode public-prep `
            -AuditPhase pre-public `
            -SkipShelfValidation 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE`n$out" }
        if ($out -notmatch [regex]::Escape("Audit slug: remote-slug-fixture")) {
            throw "missing remote-derived slug in orchestrator output`n$out"
        }
        if (-not (Test-Path (Join-Path $Shelf "audits\$remoteSlugDryRunSlug\audit-report.md"))) {
            throw "missing audits\$remoteSlugDryRunSlug\audit-report.md"
        }
    } finally {
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Use a dedicated dry-run slug - never delete audits/github-optimization/ (real dogfood output).
$shelfDryRunReport = Join-Path $Shelf "audits\$shelfDryRunSlug\audit-report.md"
if (Test-Path $shelfDryRunReport) { Remove-Item $shelfDryRunReport -Force }

Assert-ExitCode "run-full-audit dry-run on shelf root" 0 {
    & (Join-Path $Shelf "scripts\run-full-audit.ps1") `
        -RepoPath $Shelf `
        -AuditSlug $shelfDryRunSlug `
        -AuditMode public-prep `
        -AuditPhase pre-public
}

Assert-Pass "shelf orchestrator dry-run report scaffolded" {
    if (-not (Test-Path $shelfDryRunReport)) {
        throw "missing $shelfDryRunReport"
    }
}

Assert-Pass "shelf audit report carries latest CI workflow summary" {
    $reportText = Get-Content -LiteralPath $shelfDryRunReport -Raw
    foreach ($pattern in @(
            [regex]::Escape('- selected workflow path: .github/workflows/ci.yml'),
            [regex]::Escape('- workflow selection: explicit_ci_filename')
        )) {
        if ($reportText -notmatch $pattern) {
            throw "missing report latest-ci summary: $pattern`n$reportText"
        }
    }
}

}

Remove-GeneratedTestArtifacts

Write-Output ""
if ($failures -eq 0) {
    Write-Output "regulation-tests: PASS"
    exit 0
}

Write-Output "regulation-tests: FAIL ($failures)"
exit 1
