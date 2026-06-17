param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = "",
    [string]$AuditSlug = "",
    [ValidateSet("public-prep", "release", "strict-product")]
    [string]$AuditMode = "release",
    [ValidateSet("pre-public", "post-public")]
    [string]$AuditPhase = "pre-public",
    [switch]$SkipShelfValidation,
    [switch]$ForceScaffold
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $RepoPath)) {
    Write-Error "Repository path not found: $RepoPath"
}

if ($env:GITHUB_OPTIMIZATION_ROOT) {
    $Shelf = $env:GITHUB_OPTIMIZATION_ROOT
} elseif (Test-Path (Join-Path $RepoPath "..\github-optimization")) {
    $Shelf = (Resolve-Path (Join-Path $RepoPath "..\github-optimization")).Path
} else {
    $Shelf = Split-Path $PSScriptRoot -Parent
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path

if ($AuditSlug) {
    $slug = $AuditSlug.ToLower()
} else {
    $slug = (Split-Path $RepoPath -Leaf).ToLower()
}

$auditDir = Join-Path $Shelf "audits\$slug"
$reportPath = Join-Path $auditDir "audit-report.md"
$reportRel = "audits/$slug/audit-report.md"

Write-Output "=== Full Audit Orchestrator ==="
Write-Output "Shelf: $Shelf"
Write-Output "Repository: $RepoPath"
Write-Output "Audit slug: $slug"
Write-Output "Hosted: $HostedRepo"
Write-Output "Audit mode: $AuditMode"
Write-Output "Audit phase: $AuditPhase"

if (-not $SkipShelfValidation) {
    Write-Output ""
    & (Join-Path $Shelf "scripts\validate-regulation-index.ps1") -ShelfPath $Shelf
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Shelf validation failed. Fix the regulation shelf before auditing target repositories."
    }
}

if (-not (Test-Path $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir | Out-Null
    Write-Output "Created: audits/$slug/"
}

$templatePath = Join-Path $Shelf "templates\audit-report.md.template"
if ((-not (Test-Path $reportPath)) -or $ForceScaffold) {
    Copy-Item -Path $templatePath -Destination $reportPath -Force
    Write-Output "Scaffolded: $reportRel"
} else {
    Write-Output "Existing report kept: $reportRel"
}

$evidenceScript = Join-Path $Shelf "scripts\collect-audit-evidence.ps1"
Write-Output ""
Write-Output "=== Machine Evidence ==="
& $evidenceScript -RepoPath $RepoPath -HostedRepo $HostedRepo
$evidenceExit = $LASTEXITCODE

Write-Output ""
Write-Output "=== Agent Steps Remaining ==="
Write-Output "1. Read REGULATION_INDEX.md and complete G-21 full file read in target repository"
Write-Output "2. Paste machine evidence into $reportRel"
Write-Output "3. Score Tier 1 gates G-01..G-22 (PUBLIC_PREP_GATE.md)"
if ($AuditMode -in @("release", "strict-product")) {
    Write-Output "4. Score Tier 2 gates R-01..R-14 (RELEASE_QUALITY_GATE.md)"
}
if ($AuditMode -eq "strict-product") {
    Write-Output "5. Score Tier 3 gates P-01..P-10 (PRODUCT_READINESS_GATE.md)"
}
Write-Output "6. Apply AUDIT_PHASE_POLICY.md for phase=$AuditPhase"
Write-Output "7. Write audits/$slug/publication-decision-record.md when phase=pre-public (G-20)"
Write-Output "8. If R-02 blocked with accepted risk, write audits/$slug/accepted-risk-record.md"
Write-Output "9. Assign final label via FULL_AUDIT_VERDICT.md"
Write-Output ""
Write-Output "Read: AUDIT_RUNBOOK.md, RE_AUDIT_POLICY.md, OUTPUT_PATHS.md"

if ($evidenceExit -ne 0) {
    Write-Output ""
    Write-Output "orchestrator: evidence script exited $evidenceExit (review output before scoring gates)"
    exit $evidenceExit
}

Write-Output ""
Write-Output "orchestrator: scaffold and evidence complete; agent judgment steps remain"
exit 0