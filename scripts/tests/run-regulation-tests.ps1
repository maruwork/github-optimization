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
        "if /I ""%target%""==""repos/example/partial"" goto repo",
        "if /I ""%target%""==""repos/example/partial/community/profile"" goto community",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/bug_report.md"" goto bug",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/feature_request.md"" goto missing",
        "if /I ""%target%""==""repos/example/partial/contents/.github/ISSUE_TEMPLATE/config.yml"" goto config",
        "goto runs",
        ":repo",
        "echo {""description"":""partial template fixture"",""topics"":[],""homepage"":"""",""visibility"":""public"",""has_issues"":true,""security_and_analysis"":{""secret_scanning"":{""status"":""enabled""}}}",
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
        "echo {""workflow_runs"":[{""name"":""CI"",""event"":""push"",""status"":""completed"",""conclusion"":""success"",""head_branch"":""main"",""html_url"":""https://example.test/runs/1""}]}",
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
                [regex]::Escape('"name":"CI","event":"push","status":"completed","conclusion":"success","head_branch":"main","html_url":"https://example.test/runs/1"')
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

Remove-GeneratedTestArtifacts

Write-Output ""
if ($failures -eq 0) {
    Write-Output "regulation-tests: PASS"
    exit 0
}

Write-Output "regulation-tests: FAIL ($failures)"
exit 1
