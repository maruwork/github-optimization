$ErrorActionPreference = "Stop"

$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) {
    $env:GITHUB_OPTIMIZATION_ROOT
} else {
    (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

$failures = 0

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

Assert-ExitCode "validate-regulation-index" 0 {
    & (Join-Path $Shelf "scripts\validate-regulation-index.ps1") -ShelfPath $Shelf
}

$fixture = Join-Path $Shelf "scripts\tests\fixtures\minimal-docs-repo"

Assert-ExitCode "run-audit-quickstart missing manifest exits 2" 2 {
    & (Join-Path $Shelf "scripts\run-audit-quickstart.ps1") -RepoPath $fixture
}

$requiredTemplates = @(
    "accepted-risk-record.md.template",
    "audit-report.md.template",
    "tier2-defer-record.md.template",
    "audit.manifest.yml.template"
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
    git init | Out-Null
    git add README.md LICENSE SECURITY.md .gitignore
    git -c user.email="fixture@test" -c user.name="fixture" commit -m "init minimal docs fixture" | Out-Null
    Pop-Location
}

$fixtureSlug = "minimal-docs-repo"
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

$shelfSlug = "github-optimization"
$shelfReport = Join-Path $Shelf "audits\$shelfSlug\audit-report.md"
if (Test-Path $shelfReport) { Remove-Item $shelfReport -Force }

Assert-ExitCode "run-full-audit dry-run on shelf root" 0 {
    & (Join-Path $Shelf "scripts\run-full-audit.ps1") `
        -RepoPath $Shelf `
        -AuditSlug $shelfSlug `
        -AuditMode public-prep `
        -AuditPhase pre-public
}

Assert-Pass "shelf audit-report scaffolded" {
    if (-not (Test-Path $shelfReport)) {
        throw "missing $shelfReport"
    }
}

Write-Output ""
if ($failures -eq 0) {
    Write-Output "regulation-tests: PASS"
    exit 0
}

Write-Output "regulation-tests: FAIL ($failures)"
exit 1