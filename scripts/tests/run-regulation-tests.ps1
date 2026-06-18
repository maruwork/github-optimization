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

function Remove-GeneratedTestArtifacts {
    $generatedPaths = @(
        (Join-Path $Shelf "audits\$deltaDryRunSlug"),
        (Join-Path $Shelf "audits\$fixtureSlug"),
        (Join-Path $Shelf "audits\$shelfDryRunSlug"),
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

if (-not (Test-Path (Join-Path $trackedIgnoredFixture ".git"))) {
    Push-Location $trackedIgnoredFixture
    Set-Content -Path "local-only.secret" -Value "fixture-secret=tracked-but-ignored" -NoNewline
    git -c "safe.directory=$trackedIgnoredFixture" init | Out-Null
    git -c "safe.directory=$trackedIgnoredFixture" add README.md LICENSE SECURITY.md .gitignore
    git -c "safe.directory=$trackedIgnoredFixture" add -f local-only.secret
    git -c "safe.directory=$trackedIgnoredFixture" -c user.email="fixture@test" -c user.name="fixture" commit -m "init tracked-ignored fixture" | Out-Null
    Pop-Location
}

Assert-ExitCode "check-gitignore-consistency blocked tracked-ignored fixture" 1 {
    & (Join-Path $Shelf "scripts\check-gitignore-consistency.ps1") -RepoPath $trackedIgnoredFixture
}

Assert-Pass "collect-audit-evidence completes after blocked gitignore" {
    $out = & (Join-Path $Shelf "scripts\collect-audit-evidence.ps1") -RepoPath $trackedIgnoredFixture 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "expected exit 0, got $LASTEXITCODE" }
    if ($out -notmatch "=== Root Files ===") { throw "evidence transcript truncated before Root Files" }
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
