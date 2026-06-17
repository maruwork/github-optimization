param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = "",
    [string]$AuditSlug = "",
    [string]$PriorHead = "",
    [ValidateSet("public-prep", "release", "strict-product")]
    [string]$AuditMode = "release",
    [switch]$AllowLargeDelta,
    [switch]$SkipShelfValidation
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
$deltaPath = Join-Path $auditDir "delta-audit-record.md"
$deltaRel = "audits/$slug/delta-audit-record.md"
$reportRel = "audits/$slug/audit-report.md"

function Get-PriorHeadFromReport([string]$text) {
    if ($text -match '(?m)^-\s*HEAD:\s*`?([0-9a-f]{7,40})`?') { return $Matches[1] }
    if ($text -match '(?m)^HEAD:\s*`?([0-9a-f]{7,40})`?') { return $Matches[1] }
    if ($text -match 'HEAD:\s*at tag[^`]*`([0-9a-f]{7,40})`') { return $Matches[1] }
    return ""
}

Write-Output "=== Delta Audit Orchestrator ==="
Write-Output "Shelf: $Shelf"
Write-Output "Repository: $RepoPath"
Write-Output "Audit slug: $slug"
Write-Output "Audit mode: $AuditMode"

if (-not $SkipShelfValidation) {
    Write-Output ""
    & (Join-Path $Shelf "scripts\validate-regulation-index.ps1") -ShelfPath $Shelf
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Shelf validation failed."
    }
}

if (-not $PriorHead) {
    if (-not (Test-Path $reportPath)) {
        Write-Error "Prior audit report not found at $reportRel. Supply -PriorHead or run full audit first."
    }
    $PriorHead = Get-PriorHeadFromReport (Get-Content $reportPath -Raw)
    if (-not $PriorHead) {
        Write-Error "Could not parse prior HEAD from $reportRel. Supply -PriorHead explicitly."
    }
}

Push-Location $RepoPath
try {
    $presentHead = (git rev-parse HEAD).Trim()
    $priorFull = (git rev-parse $PriorHead 2>$null).Trim()
    if (-not $priorFull) {
        Write-Error "Prior HEAD not found in repository: $PriorHead"
    }

    $priorCount = [int](git ls-tree -r --name-only $priorFull | Measure-Object).Count
    $presentCount = [int](git ls-files | Measure-Object).Count
    $changed = @(git diff --name-only $priorFull $presentHead)
    $untracked = @(git ls-files --others --exclude-standard)

    $deltaPercent = if ($priorCount -gt 0) {
        [math]::Round((100.0 * [math]::Abs($presentCount - $priorCount) / $priorCount), 1)
    } else { 100.0 }

    $invalidations = New-Object System.Collections.Generic.List[string]
    if ($deltaPercent -gt 20 -and -not $AllowLargeDelta) {
        $invalidations.Add("inventory delta ${deltaPercent}% exceeds 20%") | Out-Null
    }

    $sensitivePatterns = @(
        '^LICENSE$',
        '^SECURITY\.md$',
        '^audit\.manifest\.yml$',
        '^\.github/workflows/'
    )
    foreach ($path in $changed) {
        foreach ($pat in $sensitivePatterns) {
            if ($path -match $pat) {
                $invalidations.Add("sensitive path changed: $path") | Out-Null
                break
            }
        }
    }

    if (Test-Path $reportPath) {
        $priorReport = Get-Content $reportPath -Raw
        if ($priorReport -match '(?m)^Open Blockers:\s*(\d+)') {
            if ([int]$Matches[1] -gt 0) {
                $invalidations.Add("prior audit reports open Blockers") | Out-Null
            }
        }
    }

    $deltaMode = if ($invalidations.Count -gt 0) { "upgrade-to-full" } else { "allowed" }

    if (-not (Test-Path $auditDir)) {
        New-Item -ItemType Directory -Path $auditDir | Out-Null
    }

    $templatePath = Join-Path $Shelf "templates\delta-audit-record.md.template"
    Copy-Item -Path $templatePath -Destination $deltaPath -Force

    Write-Output ""
    Write-Output "=== Delta Summary ==="
    Write-Output "Prior HEAD: $priorFull"
    Write-Output "Present HEAD: $presentHead"
    Write-Output "Prior tracked count: $priorCount"
    Write-Output "Present tracked count: $presentCount"
    Write-Output "Inventory delta: $deltaPercent%"
    Write-Output "Changed tracked paths: $($changed.Count)"
    foreach ($p in $changed) { Write-Output "  M $p" }
    if ($untracked.Count -gt 0) {
        Write-Output "New untracked (non-ignored): $($untracked.Count)"
        foreach ($p in $untracked | Select-Object -First 20) { Write-Output "  ? $p" }
    }
    Write-Output "Delta mode: $deltaMode"
    if ($invalidations.Count -gt 0) {
        Write-Output "Invalidation reasons:"
        foreach ($r in $invalidations) { Write-Output "  - $r" }
    }

    Write-Output ""
    Write-Output "Scaffolded: $deltaRel"

    $evidenceScript = Join-Path $Shelf "scripts\collect-audit-evidence.ps1"
    Write-Output ""
    Write-Output "=== Machine Evidence ==="
    & $evidenceScript -RepoPath $RepoPath -HostedRepo $HostedRepo

    Write-Output ""
    Write-Output "=== Agent Steps Remaining ==="
    if ($deltaMode -eq "upgrade-to-full") {
        Write-Output "1. Delta invalid - run scripts/run-full-audit.* for full re-audit"
    } else {
        Write-Output "1. Read regulation/execution/RE_AUDIT_POLICY.md delta rules"
        Write-Output "2. G-21 full read only changed paths + dependency cone listed above"
        Write-Output "3. Rescore gates affected by the change set; carry forward others only when allowed"
        Write-Output "4. Update $reportRel and fill $deltaRel"
    }
    Write-Output "5. Refresh R-02, R-09 when audit mode is release or strict-product"

    if ($deltaMode -eq "upgrade-to-full") {
        exit 2
    }
    exit 0
} finally {
    Pop-Location
}