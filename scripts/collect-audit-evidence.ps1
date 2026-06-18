param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = ""
)

$resolvedRepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
$RepoPath = $resolvedRepoPath

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

function Convert-ToGitBashPath {
    param([string]$Path)

    $normalized = $Path -replace "\\", "/"
    if ($normalized -match "^([A-Za-z]):/(.*)$") {
        $drive = $matches[1].ToLowerInvariant()
        $rest = ($matches[2] -replace "/+", "/").TrimStart("/")
        return "/$drive/$rest"
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
    $resolvedGitleaks = Resolve-GitleaksCommand
    $isGitBash = $bashCommand.FullName -like "*\Git\*\bash.exe"
    if ($isGitBash) {
        $bashScriptPath = Convert-ToGitBashPath $resolvedCollector
        $bashRepoPath = Convert-ToGitBashPath $RepoPath
        $bashArgs = @("-lc", '"$0" "$@"', $bashScriptPath, $bashRepoPath)
        if ($HostedRepo) {
            $bashArgs += $HostedRepo
        }
        $previousGitleaks = $env:GITLEAKS_CMD
        try {
            if ($resolvedGitleaks) {
                $env:GITLEAKS_CMD = Convert-ToGitBashPath $resolvedGitleaks
            }
            $bashOutput = & $bashCommand.FullName @bashArgs 2>&1
        } finally {
            if ($null -ne $previousGitleaks) {
                $env:GITLEAKS_CMD = $previousGitleaks
            } else {
                Remove-Item Env:GITLEAKS_CMD -ErrorAction SilentlyContinue
            }
        }
    } else {
        $bashScriptPath = Convert-ToBashPath $resolvedCollector
        $bashRepoPath = Convert-ToBashPath $RepoPath
        $bashArgs = @($bashScriptPath, $bashRepoPath)
        if ($HostedRepo) {
            $bashArgs += $HostedRepo
        }
        $bashOutput = & $bashCommand.Source @bashArgs 2>&1
    }
    $bashExit = $LASTEXITCODE
    if ($bashExit -eq 0) {
        $bashOutput | ForEach-Object { Write-Output $_ }
        exit 0
    }
}

$ErrorActionPreference = "Continue"
Push-Location $RepoPath
$script:CollectorBlocked = $false

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
    & git -c "core.excludesFile=NUL" -c "safe.directory=$RepoPath" @GitArgs
}

function Initialize-GhConfig {
    $base = if ($env:TEMP) { $env:TEMP } else { "C:\tmp" }
    $ghConfigDir = Join-Path $base "github-optimization-gh"
    if (-not (Test-Path -LiteralPath $ghConfigDir)) {
        New-Item -ItemType Directory -Path $ghConfigDir -Force | Out-Null
    }
    return $ghConfigDir
}

function ConvertFrom-JsonCompat {
    param([string]$Json)

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey("Depth")) {
        return $Json | ConvertFrom-Json -Depth 50
    }
    return $Json | ConvertFrom-Json
}

function Invoke-PublicGitHubApi {
    param([string]$RelativePath)

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCommand -and $ghCommand.Source) {
        $previousConfigDir = $env:GH_CONFIG_DIR
        try {
            $env:GH_CONFIG_DIR = Initialize-GhConfig
            $raw = (& $ghCommand.Source api $RelativePath 2>$null) -join "`n"
            if ($LASTEXITCODE -eq 0 -and $raw) {
                return ConvertFrom-JsonCompat -Json $raw
            }
        } catch {
        } finally {
            if ($null -ne $previousConfigDir) {
                $env:GH_CONFIG_DIR = $previousConfigDir
            } else {
                Remove-Item Env:GH_CONFIG_DIR -ErrorAction SilentlyContinue
            }
        }
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

        $raw = (& $curlPath -fsSL "https://api.github.com/$RelativePath" 2>$null) -join "`n"
        if ($LASTEXITCODE -eq 0 -and $raw) {
            return ConvertFrom-JsonCompat -Json $raw
        }
    }

    try {
        return Invoke-RestMethod -Uri "https://api.github.com/$RelativePath" -Headers @{ "User-Agent" = "github-optimization-audit" }
    } catch {
        return $null
    }
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
    Write-Output "command: gitleaks detect --source . --no-banner"
    Write-Output "resolved: $gitleaksCmd"
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
    $null = Initialize-GhConfig
    Write-Section "Hosted Metadata"
    $repo = Invoke-PublicGitHubApi "repos/$HostedRepo"
    $community = Invoke-PublicGitHubApi "repos/$HostedRepo/community/profile"
    if ($repo -and $community) {
        Write-JsonCompact @{
            description = $repo.description
            topics      = $repo.topics
            homepage    = $repo.homepage
            visibility  = $repo.visibility
            has_issues  = $repo.has_issues
        }
        Write-JsonCompact @{
            health_percentage = $community.health_percentage
            files             = $community.files
        }
        Write-JsonCompact $repo.security_and_analysis
    } else {
        Write-CollectorBlocked "(hosted metadata unavailable)"
    }
    Write-Section "Hosted Issue Templates"
    foreach ($path in @(
            ".github/ISSUE_TEMPLATE/bug_report.md",
            ".github/ISSUE_TEMPLATE/feature_request.md",
            ".github/ISSUE_TEMPLATE/config.yml"
        )) {
        $content = Invoke-PublicGitHubApi "repos/$HostedRepo/contents/$path"
        if ($content) {
            Write-JsonCompact @{ path = $content.path }
        } else {
            $script:CollectorBlocked = $true
            Write-JsonCompact @{ path = $null; requested = $path; result = "BLOCKED" }
        }
    }
    Write-Section "Latest CI"
    $runs = Invoke-PublicGitHubApi "repos/$HostedRepo/actions/runs?per_page=3"
    if ($runs -and $runs.workflow_runs) {
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
    } else {
        Write-CollectorBlocked "(latest CI metadata unavailable)"
    }
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
if ($script:CollectorBlocked) {
    exit 1
}
exit 0
