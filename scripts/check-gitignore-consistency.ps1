param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath
)

$ErrorActionPreference = "Stop"
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
Push-Location $RepoPath

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$GitArgs
    )
    & git -c "core.excludesFile=NUL" -c "safe.directory=$RepoPath" @GitArgs
}

$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Path,
        [string]$Category,
        [string]$Severity,
        [string]$Reason
    )
    $script:findings.Add([pscustomobject]@{
            Path     = $Path
            Category = $Category
            Severity = $Severity
            Reason   = $Reason
        }) | Out-Null
}

$recommended = @(
    "__pycache__/",
    "*.pyc",
    ".pytest_cache/",
    ".env",
    "AGENTS.md",
    "CLAUDE.md",
    ".claudeignore"
)

$gitignorePath = Join-Path $RepoPath ".gitignore"
$gitignoreText = ""
if (Test-Path $gitignorePath) {
    $gitignoreText = Get-Content $gitignorePath -Raw
} else {
    Add-Finding ".gitignore" "missing-file" "review" "No root .gitignore file"
}

foreach ($pattern in $recommended) {
    $escaped = [regex]::Escape($pattern)
    if ($gitignoreText -and ($gitignoreText -notmatch $escaped)) {
        Add-Finding $pattern "missing-recommended-rule" "review" "Recommended public-prep ignore rule not present in .gitignore"
    }
}

$ignoredTracked = @(Invoke-Git ls-files -ci --exclude-standard 2>$null)
foreach ($rel in $ignoredTracked) {
    if (-not $rel) { continue }
    $rule = (Invoke-Git check-ignore -v $rel 2>$null | Select-Object -First 1)
    if (-not $rule) { $rule = "unknown" }
    Add-Finding $rel "tracked-but-ignored" "blocked" "Tracked file matches ignore rule: $rule"
}

Write-Output "=== Gitignore Consistency ==="
Write-Output "Repository: $RepoPath"
Write-Output "Tracked files: $((Invoke-Git ls-files | Measure-Object).Count)"

$blocked = @($findings | Where-Object { $_.Severity -eq "blocked" })
$review = @($findings | Where-Object { $_.Severity -eq "review" })

if ($findings.Count -eq 0) {
    Write-Output "Findings: none"
    Write-Output "result: PASS"
    Pop-Location
    exit 0
}

Write-Output "Findings: $($findings.Count) (blocked: $($blocked.Count), review: $($review.Count))"
foreach ($item in $findings) {
    Write-Output "[$($item.Severity)/$($item.Category)] $($item.Path) - $($item.Reason)"
}

if ($blocked.Count -gt 0) {
    Write-Output "result: BLOCKED"
    Pop-Location
    exit 1
}

Write-Output "result: PASS_WITH_REVIEW"
Pop-Location
exit 0
