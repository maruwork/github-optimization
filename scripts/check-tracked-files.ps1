param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [switch]$ShowAll
)

$ErrorActionPreference = "Stop"
$RepoPath = (Resolve-Path -LiteralPath $RepoPath).Path
Push-Location $RepoPath

function Test-IsShelfRepo {
    Test-Path -LiteralPath (Join-Path $RepoPath "regulation/REGULATION_INDEX.md")
}

function Test-ShelfAllow {
    param([string]$RelPath)
    $allowed = @(
        "audits/README.md",
        "docs/governance/README.md"
    )
    return $allowed -contains ($RelPath -replace '\\', '/')
}

$isShelf = Test-IsShelfRepo
$files = @(git ls-files)
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Path,
        [string]$Category,
        [string]$Severity,
        [string]$Reason
    )
    if ($isShelf -and (Test-ShelfAllow $Path)) { return }
    $script:findings.Add([pscustomobject]@{
            Path     = $Path
            Category = $Category
            Severity = $Severity
            Reason   = $Reason
        }) | Out-Null
}

foreach ($rel in $files) {
    $norm = $rel -replace '\\', '/'

    if ($norm -match '^(AGENTS|CLAUDE)\.md$') {
        Add-Finding $norm "developer-only" "blocked" "AI control file must not be tracked"
        continue
    }
    if ($norm -match '\.claudeignore$') {
        Add-Finding $norm "developer-only" "blocked" "AI ignore file must not be tracked"
        continue
    }
    if ($norm -match '__pycache__/') {
        Add-Finding $norm "cache-artifact" "blocked" "Python cache directory must not be tracked"
        continue
    }
    if ($norm -match '\.pyc$') {
        Add-Finding $norm "cache-artifact" "blocked" "Compiled Python artifact must not be tracked"
        continue
    }
    if ($norm -match '(^|/)\.pytest_cache/') {
        Add-Finding $norm "cache-artifact" "blocked" "Pytest cache must not be tracked"
        continue
    }
    if ($norm -eq '.env') {
        Add-Finding $norm "secret-risk" "blocked" "Environment file must not be tracked"
        continue
    }
    if ($norm -match '^(design|roadmap|tasks)/') {
        Add-Finding $norm "internal-management" "blocked" "Shelf build history must not be tracked"
        continue
    }
    if (-not $isShelf -and $norm -match '^audits/') {
        Add-Finding $norm "audit-in-product" "blocked" "Audit outputs belong in github-optimization/audits/<slug>/"
        continue
    }
    if ($norm -match '^docs/governance/' -and $norm -ne 'docs/governance/README.md') {
        $category = if ($isShelf) { "governance-in-shelf" } else { "governance-in-product" }
        Add-Finding $norm $category "blocked" "Filled governance records belong in audits/<slug>/ on the regulation shelf"
        continue
    }
    if ($norm -match '^(common|index|archive|workspace)/') {
        Add-Finding $norm "internal-management-candidate" "review" "Typical internal-management path; confirm user-facing intent"
        continue
    }
}

$rootEntries = $files | Where-Object { $_ -notmatch '/' -and $_ -notmatch '\\' }
if ($rootEntries.Count -gt 12) {
    Add-Finding "(root)" "root-clutter" "review" "Root has $($rootEntries.Count) tracked entries; confirm each is user-facing or GitHub-standard"
}

Write-Output "=== Tracked File Screening ==="
Write-Output "Repository: $RepoPath"
Write-Output "Mode: $(if ($isShelf) { 'regulation-shelf' } else { 'product' })"
Write-Output "Tracked files: $($files.Count)"

$blocked = @($findings | Where-Object { $_.Severity -eq 'blocked' })
$review = @($findings | Where-Object { $_.Severity -eq 'review' })

if ($findings.Count -eq 0) {
    Write-Output "Suspicious tracked files: none"
    Write-Output "result: PASS"
    Pop-Location
    exit 0
}

Write-Output "Suspicious tracked files: $($findings.Count) (blocked: $($blocked.Count), review: $($review.Count))"
foreach ($item in $findings) {
    Write-Output "[$($item.Severity)/$($item.Category)] $($item.Path) - $($item.Reason)"
}

if ($ShowAll) {
    Write-Output ""
    Write-Output "All tracked files:"
    $files | ForEach-Object { Write-Output "  $_" }
}

if ($blocked.Count -gt 0) {
    Write-Output "result: BLOCKED"
    Pop-Location
    exit 1
}

Write-Output "result: PASS_WITH_REVIEW"
Pop-Location
exit 0