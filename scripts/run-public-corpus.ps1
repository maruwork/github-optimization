param(
    [string]$CorpusPath = "",
    [string]$WorkRoot = "",
    [string[]]$EntryId = @(),
    [switch]$KeepRepos
)

$ErrorActionPreference = "Stop"

$Shelf = Split-Path $PSScriptRoot -Parent
if (-not $CorpusPath) {
    $CorpusPath = Join-Path $PSScriptRoot "corpus\public-r02-corpus.json"
}

if (-not (Test-Path -LiteralPath $CorpusPath)) {
    Write-Error "Corpus file not found: $CorpusPath"
}

function ConvertFrom-JsonCompat {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey("Depth")) {
        return $Json | ConvertFrom-Json -Depth 50
    }
    return $Json | ConvertFrom-Json
}

function Get-LatestCiSummaryFromEvidence {
    param([string]$EvidenceText)

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
        if (-not $trimmed) {
            continue
        }
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

    [pscustomobject]@{
        primary_ci_workflow        = $primaryCiWorkflow
        primary_ci_selection       = $primaryCiSelection
        selected_workflow_path     = if ($latestCiRow -and $latestCiRow.selected_workflow_path) { [string]$latestCiRow.selected_workflow_path } elseif ($primaryCiWorkflow -and $primaryCiWorkflow -ne "none") { $primaryCiWorkflow } else { "" }
        workflow_selection         = if ($latestCiRow -and $latestCiRow.workflow_selection) { [string]$latestCiRow.workflow_selection } elseif ($primaryCiSelection) { $primaryCiSelection } else { "" }
        classification             = if ($latestCiRow) { [string]$latestCiRow.classification } else { "" }
        r02_assessment             = if ($latestCiRow) { [string]$latestCiRow.r02_assessment } else { "" }
        r02_reason                 = if ($latestCiRow) { [string]$latestCiRow.r02_reason } else { "" }
        evidence_scope             = if ($latestCiRow) { [string]$latestCiRow.evidence_scope } else { "" }
        default_branch             = if ($latestCiRow) { [string]$latestCiRow.default_branch } else { "" }
        html_url                   = if ($latestCiRow) { [string]$latestCiRow.html_url } else { "" }
    }
}

function Invoke-CorpusGit {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        @(& git @GitArgs 2>&1 | ForEach-Object { [string]$_ })
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

$corpus = ConvertFrom-JsonCompat -Json (Get-Content -LiteralPath $CorpusPath -Raw)
$entries = @($corpus.entries)
if ($EntryId.Count -gt 0) {
    $selectedIds = @($EntryId | ForEach-Object { $_.ToLowerInvariant() })
    $entries = @($entries | Where-Object { $selectedIds -contains ([string]$_.id).ToLowerInvariant() })
}

if ($entries.Count -eq 0) {
    Write-Error "No corpus entries selected."
}

$createdWorkRoot = $false
if (-not $WorkRoot) {
    $WorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-public-corpus-" + [System.Guid]::NewGuid().ToString("N"))
    $createdWorkRoot = $true
}
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null

$collectorPath = Join-Path $PSScriptRoot "collect-audit-evidence.ps1"
$results = New-Object System.Collections.Generic.List[object]
$failures = 0

Write-Output "=== Public GitHub Corpus ==="
Write-Output "Corpus: $CorpusPath"
Write-Output "Work root: $WorkRoot"
Write-Output "Entries: $($entries.Count)"

foreach ($entry in $entries) {
    $id = [string]$entry.id
    $repo = [string]$entry.repo
    $cloneUrl = "https://github.com/$repo.git"
    $clonePath = Join-Path $WorkRoot $id

    if (Test-Path -LiteralPath $clonePath) {
        Remove-Item -LiteralPath $clonePath -Recurse -Force
    }

    Write-Output ""
    Write-Output "TEST: $id ($repo)"
    $cloneOutput = Invoke-CorpusGit clone --depth 1 $cloneUrl $clonePath 2>&1
    $cloneExit = $LASTEXITCODE
    if ($cloneExit -ne 0) {
        $failures++
        Write-Output "  FAIL: clone failed"
        $cloneOutput | ForEach-Object { Write-Output "  $_" }
        $results.Add([pscustomobject]@{
            id              = $id
            repo            = $repo
            result          = "FAIL"
            failure_reason  = "clone_failed"
            clone_exit_code = $cloneExit
        }) | Out-Null
        continue
    }

    $evidenceOutput = & $collectorPath -RepoPath $clonePath -HostedRepo $repo 2>&1
    $collectorExit = $LASTEXITCODE
    $evidenceText = ($evidenceOutput | ForEach-Object { [string]$_ }) -join "`r`n"
    $summary = Get-LatestCiSummaryFromEvidence -EvidenceText $evidenceText

    $mismatches = New-Object System.Collections.Generic.List[string]
    if (-not $summary.workflow_selection) {
        $mismatches.Add("missing workflow_selection") | Out-Null
    }
    if (-not $summary.selected_workflow_path) {
        $mismatches.Add("missing selected_workflow_path") | Out-Null
    }
    if ($entry.PSObject.Properties["expected_workflow_selection"] -and $entry.expected_workflow_selection) {
        if ([string]$entry.expected_workflow_selection -ne $summary.workflow_selection) {
            $mismatches.Add("workflow_selection expected '$($entry.expected_workflow_selection)' got '$($summary.workflow_selection)'") | Out-Null
        }
    }
    if ($entry.PSObject.Properties["expected_selected_workflow_path"] -and $entry.expected_selected_workflow_path) {
        if ([string]$entry.expected_selected_workflow_path -ne $summary.selected_workflow_path) {
            $mismatches.Add("selected_workflow_path expected '$($entry.expected_selected_workflow_path)' got '$($summary.selected_workflow_path)'") | Out-Null
        }
    }

    $result = if ($mismatches.Count -eq 0) { "PASS" } else { "FAIL" }
    if ($result -eq "FAIL") {
        $failures++
    }

    Write-Output "  collector exit: $collectorExit"
    Write-Output "  workflow selection: $($summary.workflow_selection)"
    Write-Output "  selected workflow: $($summary.selected_workflow_path)"
    if ($summary.classification) {
        Write-Output "  classification: $($summary.classification)"
    }
    if ($summary.r02_assessment) {
        Write-Output "  r02 assessment: $($summary.r02_assessment)"
    }
    if ($mismatches.Count -gt 0) {
        foreach ($mismatch in $mismatches) {
            Write-Output "  mismatch: $mismatch"
        }
    } else {
        Write-Output "  PASS"
    }

    $results.Add([pscustomobject]@{
        id                     = $id
        repo                   = $repo
        result                 = $result
        collector_exit_code    = $collectorExit
        workflow_selection     = $summary.workflow_selection
        selected_workflow_path = $summary.selected_workflow_path
        classification         = $summary.classification
        r02_assessment         = $summary.r02_assessment
        r02_reason             = $summary.r02_reason
        evidence_scope         = $summary.evidence_scope
        default_branch         = $summary.default_branch
        html_url               = $summary.html_url
        notes                  = [string]$entry.notes
        mismatches             = @($mismatches)
    }) | Out-Null
}

Write-Output ""
Write-Output "=== Corpus Summary ==="
$results | ConvertTo-Json -Depth 10 -Compress | Write-Output

if (-not $KeepRepos) {
    if ($createdWorkRoot -and (Test-Path -LiteralPath $WorkRoot)) {
        Remove-Item -LiteralPath $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures -gt 0) {
    exit 1
}
exit 0
