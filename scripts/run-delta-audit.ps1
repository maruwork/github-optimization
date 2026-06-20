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

$slug = Resolve-AuditSlug -ExplicitSlug $AuditSlug -ResolvedRepoPath $RepoPath

if ($slug -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $slug.Contains("..")) {
    [Console]::Error.WriteLine("Invalid audit slug: $slug")
    exit 2
}

$auditDir = Join-Path $Shelf "audits\$slug"
$reportPath = Join-Path $auditDir "audit-report.md"
$deltaPath = Join-Path $auditDir "delta-audit-record.md"
$deltaRel = "audits/$slug/delta-audit-record.md"
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

function Get-PriorHeadFromReport([string]$text) {
    if ($text -match '(?m)^-\s*HEAD:\s*`?([0-9a-f]{7,40})`?') { return $Matches[1] }
    if ($text -match '(?m)^HEAD:\s*`?([0-9a-f]{7,40})`?') { return $Matches[1] }
    if ($text -match 'HEAD:\s*at tag[^`]*`([0-9a-f]{7,40})`') { return $Matches[1] }
    return ""
}

Write-Output "=== Delta Audit Orchestrator ==="
Write-Output "Shelf: $shelfLabel"
Write-Output "Repository: $repoLabel"
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
    $presentHead = (Invoke-Git rev-parse HEAD).Trim()
    $priorFull = (Invoke-Git rev-parse $PriorHead 2>$null).Trim()
    if (-not $priorFull) {
        Write-Error "Prior HEAD not found in repository: $PriorHead"
    }

    $priorCount = [int](Invoke-Git ls-tree -r --name-only $priorFull | Measure-Object).Count
    $presentCount = [int](Invoke-Git ls-files | Measure-Object).Count
    $changed = @(Invoke-Git diff --name-only $priorFull $presentHead)
    $untracked = @(Invoke-Git ls-files --others --exclude-standard)

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
    $evidenceOutput = & $evidenceScript -RepoPath $RepoPath -HostedRepo $HostedRepo 2>&1
    $evidenceExit = $LASTEXITCODE
    $evidenceOutput | ForEach-Object { Write-Output $_ }
    $evidenceText = ($evidenceOutput | ForEach-Object { [string]$_ }) -join "`r`n"
    if (Test-Path -LiteralPath $deltaPath) {
        Set-ReportMachineEvidence -Path $deltaPath -EvidenceText $evidenceText
        Set-ReportLatestCiSummary -Path $deltaPath -EvidenceText $evidenceText
    }

    Write-Output ""
    Write-Output "=== Agent Steps Remaining ==="
    if ($deltaMode -eq "upgrade-to-full") {
        Write-Output "1. Delta invalid - run scripts/run-full-audit.* for full re-audit"
    } else {
        Write-Output "1. Read regulation/execution/RE_AUDIT_POLICY.md delta rules"
        Write-Output "2. G-21 full read only changed paths + dependency cone listed above"
        Write-Output "3. Rescore gates affected by the change set; carry forward others only when allowed"
        Write-Output "4. Update $reportRel and fill $deltaRel, including Latest CI Assessment (R-02)"
    }
    Write-Output "5. Refresh R-02, R-09 when audit mode is release or strict-product"
    if ($evidenceExit -ne 0) {
        Write-Output ""
        Write-Output "orchestrator: machine evidence captured; collector exit $evidenceExit reflects target findings or quickstart failures (review before scoring gates)"
    }

    if ($deltaMode -eq "upgrade-to-full") {
        exit 2
    }
    exit 0
} finally {
    Pop-Location
}
