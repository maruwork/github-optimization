param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$HostedRepo = ""
)

$ErrorActionPreference = "Continue"
Push-Location $RepoPath

function Write-Section($title) {
    Write-Output ""
    Write-Output "=== $title ==="
}

Write-Section "Repository"
Write-Output "Path: $RepoPath"
if ($HostedRepo) { Write-Output "Hosted: $HostedRepo" }

Write-Section "Git"
git rev-parse HEAD
git describe --tags --always 2>$null

$files = git ls-files
$count = ($files | Measure-Object).Count
Write-Output "Tracked files: $count"

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
    ".github/workflows/ci.yml"
) | ForEach-Object {
    Write-Output "$_`: $(Test-Path $_)"
}

if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
    Write-Section "Gitleaks"
    $gitleaksOutput = gitleaks detect --source . --no-banner 2>&1
    $gitleaksOutput | Select-Object -Last 3 | ForEach-Object { Write-Output $_ }
} else {
    Write-Section "Gitleaks"
    Write-Output "gitleaks: not installed"
}

if ((Test-Path "pytest.ini") -or (Test-Path "tests")) {
    Write-Section "Pytest"
    python -m pytest -q 2>&1 | Select-Object -Last 5
}

if ($HostedRepo -and (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Section "Hosted Metadata"
    gh api "repos/$HostedRepo" --jq '{description, topics: .topics, homepage, visibility}' 2>&1
    gh api "repos/$HostedRepo/community/profile" --jq '{health_percentage}' 2>&1
    gh api "repos/$HostedRepo" --jq '.security_and_analysis' 2>&1
    Write-Section "Latest CI"
    gh run list -R $HostedRepo --limit 3 2>&1
}

$quickstartScript = Join-Path $PSScriptRoot "run-audit-quickstart.ps1"
if (Test-Path $quickstartScript) {
    Write-Section "Quickstart"
    $quickstartOutput = & $quickstartScript -RepoPath $RepoPath 2>&1
    $quickstartOutput | ForEach-Object { Write-Output $_ }
    if ($LASTEXITCODE -eq 1) {
        Pop-Location
        exit 1
    }
}

Pop-Location
exit 0