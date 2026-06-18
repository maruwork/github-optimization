param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = ""
)

$ErrorActionPreference = "Continue"
Push-Location $RepoPath

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )
    & git -c "core.excludesFile=NUL" -c "safe.directory=$RepoPath" @GitArgs
}

function Resolve-GitleaksCommand {
    $cmd = Get-Command gitleaks -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $item = Get-Item -LiteralPath $cmd.Source -ErrorAction SilentlyContinue
        if ($item -and $item.Target) {
            return @($item.Target)[0]
        }
        return $cmd.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\\WinGet\\Links\\gitleaks.exe"),
        (Join-Path $env:USERPROFILE "AppData\\Local\\Microsoft\\WinGet\\Links\\gitleaks.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }

    $candidate = $candidates | Select-Object -First 1
    if (-not $candidate) {
        return $null
    }

    $item = Get-Item -LiteralPath $candidate -ErrorAction SilentlyContinue
    if ($item -and $item.Target) {
        return @($item.Target)[0]
    }

    return $candidate
}

function Initialize-GhConfig {
    return
}

function Invoke-PublicGitHubApi {
    param([string]$RelativePath)

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

        $raw = (& $curlPath -fsSL "https://api.github.com/$RelativePath" 2>$null) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $raw) {
            return $raw | ConvertFrom-Json -Depth 50
        }
    }

    Invoke-RestMethod -Uri "https://api.github.com/$RelativePath" -Headers @{ "User-Agent" = "github-optimization-audit" }
}

function Write-JsonCompact {
    param([object]$Value)
    $Value | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

function Write-Section($title) {
    Write-Output ""
    Write-Output "=== $title ==="
}

Write-Section "Repository"
Write-Output "Path: $RepoPath"
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
}

$gitignoreScript = Join-Path $PSScriptRoot "check-gitignore-consistency.ps1"
if (Test-Path $gitignoreScript) {
    & $gitignoreScript -RepoPath $RepoPath
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

Write-Section "Gitleaks"
$gitleaksCmd = Resolve-GitleaksCommand
if ($gitleaksCmd) {
    $gitleaksLines = @()
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Stop"
        & $gitleaksCmd detect --source . --no-banner 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $gitleaksLines += $_.ToString()
            } else {
                $gitleaksLines += [string]$_
            }
        }
        $gitleaksExit = $LASTEXITCODE
    } catch {
        $gitleaksLines += $_.Exception.Message
        $gitleaksExit = 126
    } finally {
        $ErrorActionPreference = $savedPreference
    }
    $gitleaksLines | Select-Object -Last 3 | ForEach-Object { Write-Output $_ }
    Write-Output "exit code: $gitleaksExit"
    if ($gitleaksExit -eq 0) {
        Write-Output "result: PASS"
    } elseif ($gitleaksExit -eq 1) {
        Write-Output "result: BLOCKED (gitleaks findings)"
    } else {
        Write-Output "result: BLOCKED (gitleaks execution failed)"
    }
} else {
    Write-Output "gitleaks: unavailable"
    Write-Output "result: BLOCKED (G-01 cannot pass without a baseline gitleaks transcript)"
}

if ((Test-Path "pytest.ini") -or (Test-Path "tests")) {
    Write-Section "Pytest"
    python -m pytest -q 2>&1 | Select-Object -Last 5
}

if ($HostedRepo) {
    Initialize-GhConfig
    Write-Section "Hosted Metadata"
    $repo = Invoke-PublicGitHubApi "repos/$HostedRepo"
    Write-JsonCompact @{
        description = $repo.description
        topics      = $repo.topics
        homepage    = $repo.homepage
        visibility  = $repo.visibility
        has_issues  = $repo.has_issues
    }
    $community = Invoke-PublicGitHubApi "repos/$HostedRepo/community/profile"
    Write-JsonCompact @{
        health_percentage = $community.health_percentage
        files             = $community.files
    }
    Write-JsonCompact $repo.security_and_analysis
    Write-Section "Hosted Issue Templates"
    foreach ($path in @(
            ".github/ISSUE_TEMPLATE/bug_report.md",
            ".github/ISSUE_TEMPLATE/feature_request.md",
            ".github/ISSUE_TEMPLATE/config.yml"
        )) {
        $content = Invoke-PublicGitHubApi "repos/$HostedRepo/contents/$path"
        Write-JsonCompact @{ path = $content.path }
    }
    Write-Section "Latest CI"
    $runs = Invoke-PublicGitHubApi "repos/$HostedRepo/actions/runs?per_page=3"
    $projectedRuns = @($runs.workflow_runs | Select-Object -First 3 | ForEach-Object {
            [pscustomobject]@{
                name        = $_.name
                event       = $_.event
                status      = $_.status
                conclusion  = $_.conclusion
                head_branch = $_.head_branch
                html_url    = $_.html_url
            }
        })
    Write-JsonCompact $projectedRuns
}

$manifestPath = Join-Path $RepoPath "audit.manifest.yml"
$quickstartScript = Join-Path $PSScriptRoot "run-audit-quickstart.ps1"
if ((Test-Path $manifestPath) -and (Test-Path $quickstartScript)) {
    Write-Section "Quickstart"
    $quickstartOutput = & $quickstartScript -RepoPath $RepoPath 2>&1
    $quickstartOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -ne 0) {
        Pop-Location
        exit $LASTEXITCODE
    }
}

Pop-Location
exit 0
