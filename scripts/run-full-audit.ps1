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

if ($slug -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $slug.Contains("..")) {
    [Console]::Error.WriteLine("Invalid audit slug: $slug")
    exit 2
}

$auditDir = Join-Path $Shelf "audits\$slug"
$reportPath = Join-Path $auditDir "audit-report.md"
$reportRel = "audits/$slug/audit-report.md"
$shelfLabel = Split-Path $Shelf -Leaf
$repoLabel = Split-Path $RepoPath -Leaf

function Set-ReportMachineEvidence {
    param(
        [string]$Path,
        [string]$EvidenceText
    )

    $raw = Get-Content -LiteralPath $Path -Raw
    $replacement = "<!-- GO_MACHINE_EVIDENCE_START -->`r`n" + '```text' + "`r`n$EvidenceText`r`n" + '```' + "`r`n<!-- GO_MACHINE_EVIDENCE_END -->"
    $updated = [regex]::Replace(
        $raw,
        '(?s)<!-- GO_MACHINE_EVIDENCE_START -->.*?<!-- GO_MACHINE_EVIDENCE_END -->',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement }
    )
    Set-Content -LiteralPath $Path -Value $updated -NoNewline
}

Write-Output "=== Full Audit Orchestrator ==="
Write-Output "Shelf: $shelfLabel"
Write-Output "Repository: $repoLabel"
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
$reportExists = Test-Path $reportPath
$reportIsFinal = $false
if ($reportExists) {
    $reportIsFinal = (Get-Content $reportPath -Raw) -match '(?m)^Status:\s*Final\s*$'
}

if ($ForceScaffold -and $reportIsFinal) {
    Write-Error "Refusing to overwrite Final audit report: $reportRel (back up first or edit in place)"
}

if ((-not $reportExists) -or $ForceScaffold) {
    Copy-Item -Path $templatePath -Destination $reportPath -Force
    Write-Output "Scaffolded: $reportRel"
} else {
    Write-Output "Existing report kept: $reportRel"
}

$evidenceScript = Join-Path $Shelf "scripts\collect-audit-evidence.ps1"
Write-Output ""
Write-Output "=== Machine Evidence ==="
$evidenceOutput = & $evidenceScript -RepoPath $RepoPath -HostedRepo $HostedRepo 2>&1
$evidenceOutput | ForEach-Object { Write-Output $_ }
$evidenceExit = $LASTEXITCODE
$evidenceText = ($evidenceOutput | ForEach-Object { [string]$_ }) -join "`r`n"
if (Test-Path -LiteralPath $reportPath) {
    Set-ReportMachineEvidence -Path $reportPath -EvidenceText $evidenceText
}

Write-Output ""
Write-Output "=== Agent Steps Remaining ==="
Write-Output "1. Read regulation/REGULATION_INDEX.md and complete G-21 full file read in target repository"
Write-Output "2. Complete Read Exceptions and Read Coverage in $reportRel"
Write-Output "3. Fill Evidence Index, Local Command Transcripts, Hosted Transcripts, and Quickstart Transcript in $reportRel"
Write-Output "4. Score Tier 1 gates G-01..G-22 (regulation/gates/PUBLIC_PREP_GATE.md)"
if ($AuditMode -in @("release", "strict-product")) {
    Write-Output "5. Score Tier 2 gates R-01..R-14 (regulation/gates/RELEASE_QUALITY_GATE.md)"
}
if ($AuditMode -eq "strict-product") {
    Write-Output "6. Score Tier 3 gates P-01..P-10 (regulation/gates/PRODUCT_READINESS_GATE.md)"
}
Write-Output "7. Apply regulation/execution/AUDIT_PHASE_POLICY.md for phase=$AuditPhase"
Write-Output "8. Write audits/$slug/publication-decision-record.md when phase=pre-public (G-20)"
Write-Output "9. If R-02 blocked with accepted risk, write audits/$slug/accepted-risk-record.md"
Write-Output "10. Assign final label via regulation/gates/FULL_AUDIT_VERDICT.md"
Write-Output ""
Write-Output "Read: regulation/execution/AUDIT_RUNBOOK.md, regulation/execution/RE_AUDIT_POLICY.md, regulation/shelf/OUTPUT_PATHS.md"

if ($evidenceExit -ne 0) {
    Write-Output ""
    Write-Output "orchestrator: machine evidence captured; collector exit $evidenceExit reflects target findings or quickstart failures (review before scoring gates)"
}

Write-Output ""
Write-Output "orchestrator: scaffold and evidence complete; agent judgment steps remain"
exit 0
