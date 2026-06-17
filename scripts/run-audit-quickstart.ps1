param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $ManifestPath) {
    $ManifestPath = Join-Path $RepoPath "audit.manifest.yml"
}

if (-not (Test-Path $ManifestPath)) {
    Write-Output "audit.manifest.yml: missing"
    Write-Output "quickstart automation: skipped - agent must derive commands from README.md and execute them"
    exit 2
}

function Get-QuickstartCommand([string]$Block) {
    if ($Block -match '(?m)^\s*run_windows:\s*(.+)$') {
        return $Matches[1].Trim()
    }
    if ($Block -match '(?m)^\s*run:\s*(.+)$') {
        return $Matches[1].Trim()
    }
    return ""
}

$raw = Get-Content $ManifestPath -Raw
Write-Output "=== Quickstart Manifest ==="
Write-Output "Manifest: $ManifestPath"

$workdir = "in-place"
if ($raw -match '(?m)^workdir:\s*(\S+)') { $workdir = $Matches[1] }

$runRoot = $RepoPath
$tempRoot = $null
if ($workdir -eq "isolated") {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("audit-quickstart-" + [guid]::NewGuid().ToString("n"))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    Get-ChildItem -LiteralPath $RepoPath -Force |
        Where-Object { $_.Name -notin '.', '..' } |
        ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $tempRoot $_.Name) -Recurse -Force
        }
    $runRoot = $tempRoot
    Write-Output "Isolated workdir: $runRoot"
} else {
    Write-Output "In-place workdir: $runRoot"
}

$commandBlocks = [regex]::Split($raw, '(?m)^\s*-\s+id:\s*')
$failures = 0
$ran = 0

foreach ($block in $commandBlocks) {
    if ($block -notmatch '^\s*([^\r\n]+)') { continue }
    $id = $Matches[1].Trim()
    $cmd = Get-QuickstartCommand $block
    if (-not $cmd -or $cmd -match '^<.*>$') { continue }

    $expectExit = 0
    if ($block -match '(?m)^\s*expect_exit:\s*(\d+)') { $expectExit = [int]$Matches[1] }

    Write-Output ""
    Write-Output "=== quickstart:$id ==="
    Write-Output "run: $cmd"

    Push-Location $runRoot
    try {
        cmd.exe /c $cmd 2>&1 | ForEach-Object { Write-Output $_ }
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    $ran++
    if ($code -ne $expectExit) {
        Write-Output "result: FAIL (exit $code, expected $expectExit)"
        $failures++
    } else {
        Write-Output "result: PASS"
    }
}

if ($tempRoot) {
    Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output "=== Quickstart Summary ==="
Write-Output "commands run: $ran"
Write-Output "failures: $failures"

if ($ran -eq 0) {
    exit 2
}
if ($failures -gt 0) {
    exit 1
}
exit 0