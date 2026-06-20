param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = ""
)

$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$RepoPath = $resolvedRepoPath
$RepoLabel = Split-Path $RepoPath -Leaf
$ShelfPath = Split-Path $PSScriptRoot -Parent

function Convert-ToBashPath {
    param([string]$Path)

    $normalized = $Path -replace "\\", "/"
    if ($normalized -match "^([A-Za-z]):/(.*)$") {
        $drive = $matches[1].ToLowerInvariant()
        $rest = ($matches[2] -replace "/+", "/").TrimStart("/")
        return "/mnt/$drive/$rest"
    }

    return $normalized -replace "/+", "/"
}

function Resolve-GitleaksCommand {
    foreach ($commandName in @("gitleaks", "gitleaks.exe")) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source -and (Test-Path -LiteralPath $command.Source)) {
            return $command.Source
        }
    }

    $whereOutput = & where.exe gitleaks 2>$null
    if ($LASTEXITCODE -eq 0) {
        foreach ($path in $whereOutput) {
            if ($path -and (Test-Path -LiteralPath $path)) {
                return $path
            }
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe\gitleaks.exe"),
        (Join-Path $env:USERPROFILE "AppData\Local\Microsoft\WinGet\Packages\Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe\gitleaks.exe"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\gitleaks.exe"),
        (Join-Path $env:USERPROFILE "AppData\Local\Microsoft\WinGet\Links\gitleaks.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }

    $candidate = $candidates | Select-Object -First 1
    if (-not $candidate) {
        return $null
    }

    $item = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
    return $candidate
}

$gitBashCandidates = @(
    "C:\Program Files\Git\bin\bash.exe",
    "C:\Program Files\Git\usr\bin\bash.exe"
) | Where-Object { Test-Path -LiteralPath $_ }

$bashCommand = if ($gitBashCandidates.Count -gt 0) {
    Get-Item -LiteralPath $gitBashCandidates[0]
} else {
    Get-Command bash -ErrorAction SilentlyContinue
}

$bashCollector = Join-Path $PSScriptRoot "collect-audit-evidence.sh"
$isGitBashCollector = $bashCommand -and $bashCommand.FullName -like "*\Git\*\bash.exe"
if ($bashCommand -and -not $isGitBashCollector -and (Test-Path -LiteralPath $bashCollector)) {
    $resolvedCollector = (Resolve-Path -LiteralPath $bashCollector).Path
    $bashScriptPath = Convert-ToBashPath $resolvedCollector
    $bashRepoPath = Convert-ToBashPath $RepoPath
    $bashArgs = @($bashScriptPath, $bashRepoPath)
    if ($HostedRepo) {
        $bashArgs += $HostedRepo
    }
    $bashOutput = & $bashCommand.Source @bashArgs 2>&1
    $bashExit = $LASTEXITCODE
    if ($bashExit -eq 0) {
        $bashOutput | ForEach-Object { Write-Output $_ }
        exit 0
    }
}

$ErrorActionPreference = "Continue"
Push-Location $RepoPath
$script:CollectorBlocked = $false
$script:PrimaryCiWorkflow = $null

function Write-CollectorBlocked {
    param([string]$Reason)
    $script:CollectorBlocked = $true
    Write-Output "result: BLOCKED $Reason"
}

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )
    & git -c "core.excludesFile=NUL" -c "core.quotepath=false" -c "safe.directory=$RepoPath" @GitArgs
}

function ConvertFrom-JsonCompat {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey("Depth")) {
        return $Json | ConvertFrom-Json -Depth 50
    }
    return $Json | ConvertFrom-Json
}

function New-GitHubApiResult {
    param(
        [bool]$Success,
        [string]$State,
        [object]$Value = $null,
        [int]$HttpStatus = 0
    )

    [pscustomobject]@{
        Success    = $Success
        State      = $State
        Value      = $Value
        HttpStatus = $HttpStatus
    }
}

function Get-GitHubApiErrorStatus {
    param([string]$Json)

    if (-not $Json) {
        return 0
    }

    try {
        $parsed = ConvertFrom-JsonCompat -Json $Json
    } catch {
        return 0
    }

    if (-not $parsed) {
        return 0
    }

    $statusValue = $parsed.PSObject.Properties["status"]
    if (-not $statusValue) {
        return 0
    }

    $statusCode = 0
    [void][int]::TryParse([string]$statusValue.Value, [ref]$statusCode)
    return $statusCode
}

function Test-GhConfigAccessDenied {
    param([string]$Text)

    if (-not $Text) {
        return $false
    }

    return ($Text -match "failed to load config") -or
    ($Text -match "failed to read configuration") -or
    ($Text -match "config\.yml: Access is denied")
}

function Test-GhAuthRequired {
    param([string]$Text)

    if (-not $Text) {
        return $false
    }

    return ($Text -match "gh auth login") -or
    ($Text -match "GH_TOKEN") -or
    ($Text -match "authentication required")
}

function Invoke-GhApiCommand {
    param(
        [string]$CommandPath,
        [string]$RelativePath,
        [string]$ConfigDir = $null
    )

    $stderrFile = [System.IO.Path]::GetTempFileName()
    $hadGhConfigDir = Test-Path Env:GH_CONFIG_DIR
    $previousGhConfigDir = $env:GH_CONFIG_DIR
    try {
        if ($PSBoundParameters.ContainsKey("ConfigDir")) {
            if ($ConfigDir) {
                $env:GH_CONFIG_DIR = $ConfigDir
            } else {
                Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
            }
        }

        $raw = (& $CommandPath api $RelativePath 2>$stderrFile) -join "`n"
        $stderr = if (Test-Path -LiteralPath $stderrFile) {
            Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue
        } else {
            ""
        }

        [pscustomobject]@{
            Raw      = $raw
            Stderr   = $stderr
            ExitCode = $LASTEXITCODE
        }
    } finally {
        if ($hadGhConfigDir) {
            $env:GH_CONFIG_DIR = $previousGhConfigDir
        } else {
            Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-PublicGitHubApi {
    param([string]$RelativePath)

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCommand -and $ghCommand.Source) {
        try {
            $ghAttempt = Invoke-GhApiCommand -CommandPath $ghCommand.Source -RelativePath $RelativePath
            if (($ghAttempt.ExitCode -ne 0) -and (-not (Test-Path Env:GH_CONFIG_DIR)) -and (Test-GhConfigAccessDenied -Text $ghAttempt.Stderr)) {
                $isolatedGhConfig = Join-Path ([System.IO.Path]::GetTempPath()) ("github-optimization-gh-" + [System.Guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Path $isolatedGhConfig | Out-Null
                try {
                    $ghAttempt = Invoke-GhApiCommand -CommandPath $ghCommand.Source -RelativePath $RelativePath -ConfigDir $isolatedGhConfig
                } finally {
                    Remove-Item -LiteralPath $isolatedGhConfig -Recurse -Force -ErrorAction SilentlyContinue
                }
            }

            $raw = $ghAttempt.Raw
            if ($ghAttempt.ExitCode -eq 0 -and $raw) {
                return New-GitHubApiResult -Success $true -State "OK" -Value (ConvertFrom-JsonCompat -Json $raw) -HttpStatus 200
            }
            $ghStatus = Get-GitHubApiErrorStatus -Json $raw
            if ($ghStatus -eq 404) {
                return New-GitHubApiResult -Success $false -State "ABSENT" -HttpStatus 404
            }
            if (Test-GhAuthRequired -Text $ghAttempt.Stderr) {
                if ($env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -eq "1") {
                    return New-GitHubApiResult -Success $false -State "API_BLOCKED"
                }
            }
            if ($env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -eq "1") {
                return New-GitHubApiResult -Success $false -State "API_BLOCKED"
            }
        } catch {
            if ($env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -eq "1") {
                return New-GitHubApiResult -Success $false -State "API_BLOCKED"
            }
        }
    }

    if ($env:GITHUB_OPTIMIZATION_DISABLE_CURL_FALLBACK -eq "1") {
        return New-GitHubApiResult -Success $false -State "API_BLOCKED"
    }

    $curlCandidates = @()
    $curlCommand = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCommand -and $curlCommand.Source) {
        $curlCandidates += $curlCommand.Source
    }
    $curlCandidates += "C:\Windows\System32\curl.exe"

    foreach ($curlPath in ($curlCandidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $curlPath)) {
            continue
        }

        $bodyFile = [System.IO.Path]::GetTempFileName()
        try {
            $statusText = (& $curlPath -sS -L -H "User-Agent: github-optimization-audit" -o $bodyFile -w "%{http_code}" "https://api.github.com/$RelativePath" 2>$null) -join ""
            $httpStatus = 0
            [void][int]::TryParse($statusText, [ref]$httpStatus)
            $raw = if (Test-Path -LiteralPath $bodyFile) { Get-Content -LiteralPath $bodyFile -Raw -ErrorAction SilentlyContinue } else { "" }
            if ($httpStatus -ge 200 -and $httpStatus -lt 300 -and $raw) {
                return New-GitHubApiResult -Success $true -State "OK" -Value (ConvertFrom-JsonCompat -Json $raw) -HttpStatus $httpStatus
            }
            if ($httpStatus -eq 404) {
                return New-GitHubApiResult -Success $false -State "ABSENT" -HttpStatus $httpStatus
            }
        } finally {
            Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        $response = Invoke-WebRequest -Uri "https://api.github.com/$RelativePath" -Headers @{ "User-Agent" = "github-optimization-audit" } -UseBasicParsing
        if ($response.Content) {
            return New-GitHubApiResult -Success $true -State "OK" -Value (ConvertFrom-JsonCompat -Json $response.Content) -HttpStatus ([int]$response.StatusCode)
        }
    } catch {
        $statusCode = 0
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 404) {
            return New-GitHubApiResult -Success $false -State "ABSENT" -HttpStatus 404
        }
    }
    return New-GitHubApiResult -Success $false -State "API_BLOCKED"
}

function Write-JsonCompact {
    param([object]$Value)
    $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

function Write-Section($title) {
    Write-Output ""
    Write-Output "=== $title ==="
}

function Get-RedactedPath {
    param([string]$Text)
    if (-not $Text) { return $Text }

    $result = $Text
    if ($RepoPath) {
        $result = $result -replace [regex]::Escape($RepoPath.TrimEnd('\')), '<REPO_PATH>'
    }
    if ($ShelfPath) {
        $result = $result -replace [regex]::Escape($ShelfPath.TrimEnd('\')), '<SHELF_PATH>'
    }
    if ($env:USERPROFILE) {
        $result = $result -replace [regex]::Escape($env:USERPROFILE.TrimEnd('\')), '<HOME>'
    }
    if ($HOME) {
        $result = $result -replace [regex]::Escape($HOME.TrimEnd('\')), '<HOME>'
    }
    $tempPath = [System.IO.Path]::GetTempPath()
    if ($tempPath) {
        $result = $result -replace [regex]::Escape($tempPath.TrimEnd('\')), '<TMP>'
    }
    return $result
}

function Get-WorkflowRunDurationSeconds {
    param([object]$Run)

    $startText = if ($Run.run_started_at) { [string]$Run.run_started_at } elseif ($Run.created_at) { [string]$Run.created_at } else { "" }
    $endText = if ($Run.updated_at) { [string]$Run.updated_at } elseif ($Run.completed_at) { [string]$Run.completed_at } else { "" }
    if (-not $startText -or -not $endText) {
        return $null
    }

    try {
        $start = [datetimeoffset]::Parse($startText)
        $end = [datetimeoffset]::Parse($endText)
        return [int][math]::Max([math]::Round(($end - $start).TotalSeconds), 0)
    } catch {
        return $null
    }
}

function Get-WorkflowRunLocalPath {
    param([object]$Run)

    $pathText = [string]$Run.path
    if (-not $pathText) {
        return ""
    }

    $normalized = (($pathText -split '@', 2)[0].Trim()).TrimStart('/', '\')
    if (-not $normalized) {
        return ""
    }

    return $normalized -replace '/', '\'
}

function Get-WorkflowSelectionScore {
    param(
        [string]$RelativePath,
        [string]$WorkflowText
    )

    $normalizedPath = (($RelativePath -replace "\\", "/").TrimStart("/")).ToLowerInvariant()
    if (-not $normalizedPath) {
        return [int]::MinValue
    }

    $score = 0
    switch -Regex ($normalizedPath) {
        '^\.github/workflows/ci\.ya?ml$' { return 1000 }
        '/ci\.ya?ml$' { $score += 900; break }
        '/(tests?|build|verify|checks?|validate|pipeline)\.ya?ml$' { $score += 700; break }
    }

    if ($normalizedPath -match '(?i)(^|/)(codeql|dependabot|scorecards|pages)\.ya?ml$') {
        $score -= 800
    }

    if ($WorkflowText) {
        $nameMatch = [regex]::Match($WorkflowText, '(?im)^\s*name\s*:\s*["'']?(?<name>[^"'']+?)["'']?\s*$')
        if ($nameMatch.Success) {
            $workflowName = $nameMatch.Groups["name"].Value.Trim()
            if ($workflowName -match '(?i)\bci\b') {
                $score += 500
            } elseif ($workflowName -match '(?i)\b(test|build|verify|check|validate)\b') {
                $score += 350
            }

            if ($workflowName -match '(?i)\b(codeql|dependabot|scorecards|pages)\b') {
                $score -= 600
            }
        }

        if ($WorkflowText -match '(?im)^\s*(push|pull_request)\s*:') {
            $score += 100
        }
    }

    return $score
}

function Get-ManifestScalarValue {
    param(
        [string]$ManifestPath,
        [string]$Key
    )

    if (-not $ManifestPath -or -not $Key -or -not (Test-Path -LiteralPath $ManifestPath)) {
        return ""
    }

    $match = Select-String -LiteralPath $ManifestPath -Pattern ("^(?m){0}:\s*(.+)$" -f [regex]::Escape($Key)) | Select-Object -First 1
    if (-not $match) {
        return ""
    }

    $value = $match.Matches[0].Groups[1].Value.Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        return $value.Substring(1, $value.Length - 2)
    }

    return $value
}

function Get-PrimaryCiWorkflowCandidate {
    param([string]$RepoRoot)

    $workflowDir = Join-Path $RepoRoot ".github\workflows"
    if (-not (Test-Path -LiteralPath $workflowDir)) {
        return $null
    }

    $manifestPath = Join-Path $RepoRoot "audit.manifest.yml"
    $manifestOverride = Get-ManifestScalarValue -ManifestPath $manifestPath -Key "primary_ci_workflow"
    if ($manifestOverride) {
        $normalizedOverride = (($manifestOverride -replace "/", "\").TrimStart("\"))
        $overridePath = Join-Path $RepoRoot $normalizedOverride
        if (Test-Path -LiteralPath $overridePath) {
            return [pscustomobject]@{
                RelativePath = $normalizedOverride
                ApiPath      = ($normalizedOverride -replace "\\", "/")
                Reason       = "manifest_override"
            }
        }
    }

    $workflowFiles = @(Get-ChildItem -LiteralPath $workflowDir -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension -in @(".yml", ".yaml")
    } | Sort-Object FullName)
    if ($workflowFiles.Count -eq 0) {
        return $null
    }

    $descriptors = @(
        foreach ($file in $workflowFiles) {
            $relativeFs = ".github\workflows\" + $file.Name
            $workflowText = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
            [pscustomobject]@{
                RelativePath = $relativeFs
                ApiPath      = ($relativeFs -replace "\\", "/")
                Score        = Get-WorkflowSelectionScore -RelativePath $relativeFs -WorkflowText $workflowText
            }
        }
    )

    $exactCi = @($descriptors | Where-Object { $_.ApiPath -match '^\.github/workflows/ci\.ya?ml$' } | Select-Object -First 1)
    if ($exactCi.Count -gt 0) {
        return [pscustomobject]@{
            RelativePath = $exactCi[0].RelativePath
            ApiPath      = $exactCi[0].ApiPath
            Reason       = "explicit_ci_filename"
        }
    }

    $ranked = @($descriptors | Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = "ApiPath"; Descending = $false })
    if (($ranked.Count -gt 0) -and ($ranked[0].Score -gt 0)) {
        return [pscustomobject]@{
            RelativePath = $ranked[0].RelativePath
            ApiPath      = $ranked[0].ApiPath
            Reason       = if ($descriptors.Count -eq 1) { "single_local_workflow" } else { "heuristic_local_workflow" }
        }
    }

    return $null
}

function Get-HostedWorkflowSelectionScore {
    param(
        [string]$RelativePath,
        [string]$WorkflowName,
        [string]$State
    )

    $normalizedPath = (($RelativePath -replace "\\", "/").TrimStart("/")).ToLowerInvariant()
    if (-not $normalizedPath) {
        return [int]::MinValue
    }

    $score = 0
    switch -Regex ($normalizedPath) {
        '^\.github/workflows/ci\.ya?ml$' { $score += 1000; break }
        '/ci\.ya?ml$' { $score += 900; break }
        '/(tests?|build|verify|checks?|validate|pipeline)\.ya?ml$' { $score += 700; break }
    }

    if ($normalizedPath -match '(?i)(^|/)(codeql|dependabot|scorecards|pages)\.ya?ml$') {
        $score -= 800
    }

    if ($WorkflowName) {
        if ($WorkflowName -match '(?i)\bci\b') {
            $score += 500
        } elseif ($WorkflowName -match '(?i)\b(test|build|verify|check|validate|pipeline)\b') {
            $score += 350
        }

        if ($WorkflowName -match '(?i)\b(codeql|dependabot|scorecards|pages)\b') {
            $score -= 600
        }
    }

    if ($State -eq "active") {
        $score += 25
    }

    return $score
}

function Get-HostedPrimaryCiWorkflowCandidate {
    param([string]$HostedRepo)

    if (-not $HostedRepo) {
        return $null
    }

    $workflows = Invoke-PublicGitHubApi "repos/$HostedRepo/actions/workflows"
    if (-not $workflows.Success) {
        return $null
    }

    $descriptors = @(
        foreach ($workflow in @($workflows.Value.workflows)) {
            $path = [string]$workflow.path
            if (-not $path) {
                continue
            }

            $normalizedPath = (($path -split '@', 2)[0].Trim()).TrimStart('/', '\')
            if (-not $normalizedPath) {
                continue
            }

            [pscustomobject]@{
                RelativePath = ($normalizedPath -replace '/', '\')
                ApiPath      = ($normalizedPath -replace '\\', '/')
                Score        = Get-HostedWorkflowSelectionScore -RelativePath $normalizedPath -WorkflowName ([string]$workflow.name) -State ([string]$workflow.state)
            }
        }
    )

    if ($descriptors.Count -eq 0) {
        return $null
    }

    $ranked = @($descriptors | Sort-Object @{ Expression = "Score"; Descending = $true }, @{ Expression = "ApiPath"; Descending = $false })
    if ($ranked[0].Score -gt 0) {
        return [pscustomobject]@{
            RelativePath = $ranked[0].RelativePath
            ApiPath      = $ranked[0].ApiPath
            Reason       = "hosted_workflow_inventory"
        }
    }

    return $null
}

function Test-WorkflowRunHasBranchFilters {
    param(
        [string]$RepoRoot,
        [object]$Run
    )

    $relativePath = Get-WorkflowRunLocalPath -Run $Run
    if (-not $relativePath) {
        return $false
    }

    $workflowPath = Join-Path $RepoRoot $relativePath
    if (-not (Test-Path -LiteralPath $workflowPath)) {
        return $false
    }

    $workflowText = Get-Content -LiteralPath $workflowPath -Raw -ErrorAction SilentlyContinue
    if (-not $workflowText) {
        return $false
    }

    return ($workflowText -match '(?m)^\s*branches(?:-ignore)?\s*:')
}

function Get-WorkflowRunJobsState {
    param(
        [string]$HostedRepo,
        [object]$Run
    )

    $runId = [string]$Run.id
    if (-not $HostedRepo -or -not $runId) {
        return [pscustomobject]@{
            JobsTotal = $null
            Signal    = $null
        }
    }

    $jobs = Invoke-PublicGitHubApi "repos/$HostedRepo/actions/runs/$runId/jobs?per_page=1"
    if ($jobs.Success) {
        $jobsTotal = $null
        $totalCountProperty = $jobs.Value.PSObject.Properties["total_count"]
        if ($totalCountProperty) {
            $parsed = 0
            if ([int]::TryParse([string]$totalCountProperty.Value, [ref]$parsed)) {
                $jobsTotal = $parsed
            }
        }
        return [pscustomobject]@{
            JobsTotal = $jobsTotal
            Signal    = $null
        }
    }

    return [pscustomobject]@{
        JobsTotal = $null
        Signal    = "jobs_api_blocked"
    }
}

function Get-WorkflowRunSignals {
    param(
        [object]$Run,
        [object]$JobsState,
        [Nullable[int]]$DurationSeconds,
        [bool]$HasBranchFilters
    )

    $signals = New-Object System.Collections.Generic.List[string]

    if ($null -ne $JobsState.JobsTotal -and $JobsState.JobsTotal -eq 0) {
        $signals.Add("no_jobs_recorded") | Out-Null
    }

    if ([string]$Run.conclusion -eq "startup_failure") {
        $signals.Add("startup_failure") | Out-Null
    }

    if (
        ([string]$Run.conclusion -in @("failure", "startup_failure", "cancelled")) -and
        ($null -ne $JobsState.JobsTotal) -and
        ($JobsState.JobsTotal -eq 0)
    ) {
        $signals.Add("startup_failure_candidate") | Out-Null
    }

    if (
        ($null -ne $DurationSeconds) -and
        ($DurationSeconds -le 10) -and
        ($null -ne $JobsState.JobsTotal) -and
        ($JobsState.JobsTotal -eq 0)
    ) {
        $signals.Add("near_zero_duration") | Out-Null
    }

    if (
        $HasBranchFilters -and
        ($null -ne $JobsState.JobsTotal) -and
        ($JobsState.JobsTotal -eq 0)
    ) {
        $signals.Add("branch_filter_candidate") | Out-Null
    }

    if ($JobsState.Signal) {
        $signals.Add([string]$JobsState.Signal) | Out-Null
    }

    $uniqueSignals = @($signals | Select-Object -Unique)
    if ($uniqueSignals.Count -eq 0) {
        return $null
    }

    return $uniqueSignals
}

function Get-WorkflowRunClassification {
    param(
        [object]$Run,
        [object]$JobsState,
        [string[]]$Signals
    )

    $status = [string]$Run.status
    $conclusion = [string]$Run.conclusion
    $signalSet = @($Signals)

    if ($JobsState.Signal -eq "jobs_api_blocked") {
        return "unknown"
    }

    if (($signalSet -contains "branch_filter_candidate")) {
        return "branch_filter_candidate"
    }

    if (($signalSet -contains "startup_failure_candidate")) {
        return "startup_failure_candidate"
    }

    if ($status -and $status -ne "completed" -and -not $conclusion) {
        return "in_progress"
    }

    if ($conclusion -eq "success") {
        return "pass"
    }

    if ($conclusion -in @("neutral", "skipped")) {
        return "non_blocking"
    }

    if ($conclusion) {
        return "hard_failure"
    }

    return "unknown"
}

function Get-WorkflowRunR02State {
    param(
        [string]$Classification,
        [string]$EvidenceScope
    )

    if ($EvidenceScope -ne "default_branch") {
        return [pscustomobject]@{
            Assessment = "review"
            Reason     = "default_branch_scope_missing"
        }
    }

    switch ($Classification) {
        "pass" {
            return [pscustomobject]@{
                Assessment = "pass"
                Reason     = "latest_default_branch_run_green"
            }
        }
        "hard_failure" {
            return [pscustomobject]@{
                Assessment = "blocked"
                Reason     = "latest_default_branch_run_failed"
            }
        }
        "branch_filter_candidate" {
            return [pscustomobject]@{
                Assessment = "review"
                Reason     = "branch_filter_candidate_requires_confirmation"
            }
        }
        "startup_failure_candidate" {
            return [pscustomobject]@{
                Assessment = "review"
                Reason     = "startup_failure_candidate_requires_confirmation"
            }
        }
        "in_progress" {
            return [pscustomobject]@{
                Assessment = "review"
                Reason     = "default_branch_run_in_progress"
            }
        }
        "non_blocking" {
            return [pscustomobject]@{
                Assessment = "review"
                Reason     = "default_branch_run_non_green_non_blocking"
            }
        }
        default {
            return [pscustomobject]@{
                Assessment = "review"
                Reason     = "insufficient_ci_evidence"
            }
        }
    }
}

Write-Section "Repository"
Write-Output "Repository: $RepoLabel"
if ($HostedRepo) { Write-Output "Hosted: $HostedRepo" }

Write-Section "Git"
Invoke-Git rev-parse HEAD
Invoke-Git describe --tags --always 2>$null

$files = Invoke-Git ls-files
$count = ($files | Measure-Object).Count
Write-Output "Tracked files: $count"

$screenScript = Join-Path $PSScriptRoot "check-tracked-files.ps1"
if (Test-Path $screenScript) {
    & $screenScript -RepoPath $RepoPath
    if ($LASTEXITCODE -ne 0) {
        $script:CollectorBlocked = $true
    }
}

$gitignoreScript = Join-Path $PSScriptRoot "check-gitignore-consistency.ps1"
if (Test-Path $gitignoreScript) {
    & $gitignoreScript -RepoPath $RepoPath
    if ($LASTEXITCODE -ne 0) {
        $script:CollectorBlocked = $true
    }
}

Write-Section "Large Tracked Files (>512KB)"
$large = @()
foreach ($f in $files) {
    if ($f -and (Test-Path -LiteralPath $f)) {
        $s = (Get-Item -LiteralPath $f).Length
        if ($s -gt 512000) { $large += "$f $s" }
    }
}
if ($large.Count -eq 0) { Write-Output "none" } else { $large }

Write-Section "Root Files"
@("README.md","LICENSE","SECURITY.md","CODE_OF_CONDUCT.md","CHANGELOG.md","CONTRIBUTING.md","SUPPORT.md") | ForEach-Object {
    Write-Output "$_`: $(Test-Path $_)"
}

$script:PrimaryCiWorkflow = Get-PrimaryCiWorkflowCandidate -RepoRoot $RepoPath
if ((-not $script:PrimaryCiWorkflow) -and $HostedRepo) {
    $script:PrimaryCiWorkflow = Get-HostedPrimaryCiWorkflowCandidate -HostedRepo $HostedRepo
}

Write-Section "GitHub Files"
@(
    ".github/ISSUE_TEMPLATE/bug_report.md",
    ".github/ISSUE_TEMPLATE/feature_request.md",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".github/PULL_REQUEST_TEMPLATE.md",
    ".github/dependabot.yml",
    ".github/workflows/ci.yml",
    ".github/workflows/codeql.yml"
) | ForEach-Object {
    Write-Output "$_`: $(Test-Path $_)"
}
Write-Output ("primary_ci_workflow: " + $(if ($script:PrimaryCiWorkflow) { $script:PrimaryCiWorkflow.ApiPath } else { "none" }))
Write-Output ("primary_ci_selection: " + $(if ($script:PrimaryCiWorkflow) { $script:PrimaryCiWorkflow.Reason } else { "all_runs_fallback" }))

Write-Section "Gitleaks"
$gitleaksCmd = Resolve-GitleaksCommand
if ($gitleaksCmd) {
    Write-Output "command: gitleaks detect --source . --no-banner"
    Write-Output ("resolved: " + (Get-RedactedPath $gitleaksCmd))
    $gitleaksLines = @()
    & cmd.exe /d /c $gitleaksCmd detect --source . --no-banner 2>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $gitleaksLines += $_.ToString()
        } else {
            $gitleaksLines += [string]$_
        }
    }
    $gitleaksExit = $LASTEXITCODE
    $gitleaksLines | Select-Object -Last 3 | ForEach-Object { Write-Output $_ }
    Write-Output "exit code: $gitleaksExit"
    if ($gitleaksLines -match "NativeCommandFailed|ApplicationFailedException|ResourceUnavailable") {
        Write-CollectorBlocked "(gitleaks execution failed)"
    } elseif ($gitleaksExit -eq 0) {
        Write-Output "result: PASS"
    } elseif ($gitleaksLines -match "Is a directory") {
        Write-CollectorBlocked "(execution environment exposed the resolved gitleaks path as a directory)"
    } elseif ($gitleaksLines -match "Access is denied") {
        Write-Output "result: SKIPPED (execution environment denied gitleaks execution; use direct gitleaks transcript for G-01 scoring)"
    } elseif ($gitleaksLines -match "not recognized") {
        Write-CollectorBlocked "(G-01 cannot pass without a baseline gitleaks transcript)"
    } elseif ($gitleaksExit -eq 1) {
        Write-CollectorBlocked "(gitleaks findings)"
    } else {
        Write-CollectorBlocked "(gitleaks execution failed)"
    }
} else {
    Write-Output "gitleaks: unavailable"
    Write-CollectorBlocked "(G-01 cannot pass without a baseline gitleaks transcript)"
}

if ((Test-Path "pytest.ini") -or (Test-Path "tests")) {
    Write-Section "Pytest"
    python -m pytest -q 2>&1 | Select-Object -Last 5
}

if ($HostedRepo) {
    Write-Section "Hosted Metadata"
    $repo = Invoke-PublicGitHubApi "repos/$HostedRepo"
    $community = Invoke-PublicGitHubApi "repos/$HostedRepo/community/profile"
    $security = Invoke-PublicGitHubApi "repos/$HostedRepo"
    if ($repo.Success -and $community.Success -and $security.Success) {
        Write-JsonCompact @{
            description = $repo.Value.description
            topics      = $repo.Value.topics
            homepage    = $repo.Value.homepage
            visibility  = $repo.Value.visibility
            has_issues  = $repo.Value.has_issues
            default_branch = $repo.Value.default_branch
        }
        Write-JsonCompact @{
            health_percentage = $community.Value.health_percentage
            files             = $community.Value.files
        }
        Write-JsonCompact $security.Value.security_and_analysis
    } else {
        Write-CollectorBlocked "(API_BLOCKED: hosted metadata unavailable)"
    }
    Write-Section "Hosted Issue Templates"
    if ($repo.Success -and -not $repo.Value.has_issues) {
        Write-Output "result: NOT_APPLICABLE (issues disabled)"
    } else {
        $issueApiBlocked = $false
        foreach ($path in @(
                ".github/ISSUE_TEMPLATE/bug_report.md",
                ".github/ISSUE_TEMPLATE/feature_request.md",
                ".github/ISSUE_TEMPLATE/config.yml"
            )) {
            $content = Invoke-PublicGitHubApi "repos/$HostedRepo/contents/$path"
            if ($content.Success) {
                Write-JsonCompact @{ path = $content.Value.path; requested = $path; result = "PASS" }
            } elseif ($content.State -eq "ABSENT") {
                Write-JsonCompact @{ path = $null; requested = $path; result = "ABSENT" }
            } else {
                $issueApiBlocked = $true
                Write-JsonCompact @{ path = $null; requested = $path; result = "API_BLOCKED" }
            }
        }
        if ($issueApiBlocked) {
            Write-CollectorBlocked "(API_BLOCKED: hosted issue-template lookup unavailable)"
        } else {
        }
    }
    Write-Section "Latest CI"
    $defaultBranch = if ($repo.Success) { [string]$repo.Value.default_branch } else { "" }
    $encodedDefaultBranch = if ($defaultBranch) { [uri]::EscapeDataString($defaultBranch) } else { "" }
    $selectedWorkflow = $script:PrimaryCiWorkflow
    $selectedWorkflowId = if ($selectedWorkflow) { [System.IO.Path]::GetFileName($selectedWorkflow.ApiPath) } else { "" }
    $runsPath = if ($selectedWorkflow) {
        if ($encodedDefaultBranch) {
            "repos/$HostedRepo/actions/workflows/$selectedWorkflowId/runs?branch=$encodedDefaultBranch"
        } else {
            "repos/$HostedRepo/actions/workflows/$selectedWorkflowId/runs?per_page=3"
        }
    } elseif ($encodedDefaultBranch) {
        "repos/$HostedRepo/actions/runs?branch=$encodedDefaultBranch"
    } else {
        "repos/$HostedRepo/actions/runs?per_page=3"
    }
    $evidenceScope = if ($defaultBranch) { "default_branch" } else { "recent_runs" }
    $runs = Invoke-PublicGitHubApi $runsPath
    if ((-not $runs.Success) -and $selectedWorkflow) {
        $fallbackRunsPath = if ($encodedDefaultBranch) {
            "repos/$HostedRepo/actions/runs?branch=$encodedDefaultBranch"
        } else {
            "repos/$HostedRepo/actions/runs?per_page=3"
        }
        $runs = Invoke-PublicGitHubApi $fallbackRunsPath
    }
    $workflowFilesPresent = (Get-ChildItem -LiteralPath (Join-Path $RepoPath ".github\workflows") -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    if ($runs.Success) {
        $workflowRuns = @($runs.Value.workflow_runs)
        if ($selectedWorkflow) {
            $ciWorkflowRelativePath = $selectedWorkflow.RelativePath
            $workflowRuns = @(
                $workflowRuns | Where-Object {
                    (Get-WorkflowRunLocalPath -Run $_) -ieq $ciWorkflowRelativePath
                }
            )
        }
        if ($workflowRuns.Count -gt 0) {
            $projectedRuns = @($workflowRuns | Select-Object -First 3 | ForEach-Object {
                $jobsState = Get-WorkflowRunJobsState -HostedRepo $HostedRepo -Run $_
                $durationSeconds = Get-WorkflowRunDurationSeconds -Run $_
                $hasBranchFilters = Test-WorkflowRunHasBranchFilters -RepoRoot $RepoPath -Run $_
                $signals = Get-WorkflowRunSignals -Run $_ -JobsState $jobsState -DurationSeconds $durationSeconds -HasBranchFilters:$hasBranchFilters
                $classification = Get-WorkflowRunClassification -Run $_ -JobsState $jobsState -Signals $signals
                $r02State = Get-WorkflowRunR02State -Classification $classification -EvidenceScope $evidenceScope
                [pscustomobject]@{
                    name             = $_.name
                    event            = $_.event
                    status           = $_.status
                    conclusion       = $_.conclusion
                    path             = $_.path
                    run_attempt      = $_.run_attempt
                    run_started_at   = $_.run_started_at
                    updated_at       = $_.updated_at
                    duration_seconds = $durationSeconds
                    jobs_total       = $jobsState.JobsTotal
                    evidence_scope   = $evidenceScope
                    default_branch   = if ($defaultBranch) { $defaultBranch } else { $null }
                    classification   = $classification
                    r02_assessment   = $r02State.Assessment
                    r02_reason       = $r02State.Reason
                    signals          = $signals
                    head_branch      = $_.head_branch
                    html_url         = $_.html_url
                    selected_workflow_path = if ($selectedWorkflow) { $selectedWorkflow.ApiPath } else { $null }
                    workflow_selection = if ($selectedWorkflow) { $selectedWorkflow.Reason } else { "all_runs_fallback" }
                }
            })
            Write-JsonCompact $projectedRuns
        } elseif ($workflowFilesPresent) {
            Write-Output "result: NO_RUNS (workflow files exist but the GitHub Actions runs API returned 0 runs)"
        } else {
            Write-Output "result: NOT_CONFIGURED (no local GitHub Actions workflow files detected and the runs API returned 0 runs)"
        }
    } else {
        Write-CollectorBlocked "(API_BLOCKED: latest CI metadata unavailable)"
    }
}

$manifestPath = Join-Path $RepoPath "audit.manifest.yml"
$quickstartScript = Join-Path $PSScriptRoot "run-audit-quickstart.ps1"
if ((Test-Path $manifestPath) -and (Test-Path $quickstartScript)) {
    Write-Section "Quickstart"
    $quickstartOutput = & $quickstartScript -RepoPath $RepoPath 2>&1
    $quickstartOutput | ForEach-Object { Write-Output (Get-RedactedPath ([string]$_)) }
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        exit $LASTEXITCODE
    }
}

Pop-Location
if ($script:CollectorBlocked) {
    exit 1
}
exit 0
