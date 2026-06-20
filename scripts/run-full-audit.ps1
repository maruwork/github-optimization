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

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )
    & git -C $RepoPath -c "core.excludesFile=NUL" -c "safe.directory=$RepoPath" @GitArgs
}

function Get-RepoNameFromRemoteUrl {
    param([string]$RemoteUrl)

    if (-not $RemoteUrl) {
        return ""
    }

    $normalized = ($RemoteUrl.Trim().TrimEnd('/') -replace '\\', '/') -replace '\.git$', ''
    $normalized = $normalized -replace ':', '/'
    $segments = @($normalized -split '/')
    if ($segments.Count -eq 0) {
        return ""
    }

    return [string]$segments[-1]
}

function Resolve-AuditSlug {
    param(
        [string]$ExplicitSlug,
        [string]$ResolvedRepoPath
    )

    if ($ExplicitSlug) {
        return $ExplicitSlug.ToLowerInvariant()
    }

    $remoteCandidates = New-Object System.Collections.Generic.List[string]
    $remoteCandidates.Add("origin") | Out-Null
    foreach ($remoteName in @(Invoke-Git remote 2>$null)) {
        if ($remoteName) {
            $remoteCandidates.Add([string]$remoteName) | Out-Null
        }
    }

    foreach ($remoteName in $remoteCandidates | Select-Object -Unique) {
        $remoteUrl = [string]((Invoke-Git remote get-url $remoteName 2>$null | Select-Object -First 1))
        $remoteRepo = Get-RepoNameFromRemoteUrl -RemoteUrl $remoteUrl
        if ($remoteRepo) {
            return $remoteRepo.ToLowerInvariant()
        }
    }

    $topLevel = [string]((Invoke-Git rev-parse --show-toplevel 2>$null | Select-Object -First 1))
    if ($topLevel) {
        return (Split-Path $topLevel.Trim() -Leaf).ToLowerInvariant()
    }

    return (Split-Path $ResolvedRepoPath -Leaf).ToLowerInvariant()
}

if ($AuditSlug) {
    $slug = Resolve-AuditSlug -ExplicitSlug $AuditSlug -ResolvedRepoPath $RepoPath
} else {
    $slug = Resolve-AuditSlug -ExplicitSlug "" -ResolvedRepoPath $RepoPath
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

function ConvertFrom-JsonCompat {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey("Depth")) {
        return $Json | ConvertFrom-Json -Depth 50
    }
    return $Json | ConvertFrom-Json
}

function Set-ReportLatestCiSummary {
    param(
        [string]$Path,
        [string]$EvidenceText
    )

    $summary = [ordered]@{
        "evidence scope"              = ""
        "default branch"              = ""
        "selected workflow path"      = ""
        "workflow selection"          = ""
        "latest evaluated run URL or ID" = ""
        "collector classification"    = ""
        "collector provisional assessment" = ""
        "collector reason"            = ""
    }

    $primaryCiWorkflow = ""
    $primaryCiSelection = ""
    $latestCiRow = $null

    foreach ($line in ($EvidenceText -split "`r?`n")) {
        if ($line -match '^primary_ci_workflow:\s*(.+)$') {
            $primaryCiWorkflow = $Matches[1].Trim()
            continue
        }
        if ($line -match '^primary_ci_selection:\s*(.+)$') {
            $primaryCiSelection = $Matches[1].Trim()
            continue
        }
        $trimmed = $line.Trim()
        if (-not $trimmed.StartsWith("{") -and -not $trimmed.StartsWith("[")) {
            continue
        }
        try {
            $parsed = ConvertFrom-JsonCompat -Json $trimmed
        } catch {
            continue
        }
        if ($parsed -is [System.Array] -and $parsed.Count -gt 0 -and $parsed[0].PSObject.Properties["r02_assessment"]) {
            $latestCiRow = $parsed[0]
            break
        }
        if ($parsed.PSObject.Properties["r02_assessment"]) {
            $latestCiRow = $parsed
            break
        }
    }

    if ($latestCiRow) {
        $summary["evidence scope"] = [string]$latestCiRow.evidence_scope
        $summary["default branch"] = [string]$latestCiRow.default_branch
        $summary["selected workflow path"] = [string]$latestCiRow.selected_workflow_path
        $summary["workflow selection"] = [string]$latestCiRow.workflow_selection
        $summary["latest evaluated run URL or ID"] = if ($latestCiRow.html_url) { [string]$latestCiRow.html_url } else { [string]$latestCiRow.id }
        $summary["collector classification"] = [string]$latestCiRow.classification
        $summary["collector provisional assessment"] = [string]$latestCiRow.r02_assessment
        $summary["collector reason"] = [string]$latestCiRow.r02_reason
    } else {
        if ($primaryCiWorkflow -and $primaryCiWorkflow -ne "none") {
            $summary["selected workflow path"] = $primaryCiWorkflow
        }
        if ($primaryCiSelection) {
            $summary["workflow selection"] = $primaryCiSelection
        }
    }

    $hasAnySummary = $false
    foreach ($value in $summary.Values) {
        if ($value) {
            $hasAnySummary = $true
            break
        }
    }
    if (-not $hasAnySummary) {
        return
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    foreach ($key in $summary.Keys) {
        $replacement = "- {0}: {1}" -f $key, $summary[$key]
        $pattern = "(?m)^- " + [regex]::Escape($key) + ":[`t ]*.*$"
        $raw = [regex]::Replace($raw, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $replacement })
    }
    Set-Content -LiteralPath $Path -Value $raw -NoNewline
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
    Set-ReportLatestCiSummary -Path $reportPath -EvidenceText $evidenceText
}

Write-Output ""
Write-Output "=== Agent Steps Remaining ==="
Write-Output "1. Read regulation/REGULATION_INDEX.md and complete G-21 full file read in target repository"
Write-Output "2. Complete Read Exceptions and Read Coverage in $reportRel"
Write-Output "3. Fill Evidence Index, Local Command Transcripts, Hosted Transcripts, Quickstart Transcript, and Latest CI Assessment (R-02) in $reportRel"
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
