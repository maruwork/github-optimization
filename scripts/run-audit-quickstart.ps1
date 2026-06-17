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
    Write-Output "quickstart automation: skipped — agent must derive commands from README.md and execute them"
    exit 2
}

function Read-SimpleYamlMap([string[]]$lines) {
    $map = @{}
    foreach ($line in $lines) {
        if ($line -match '^\s*([A-Za-z0-9_\-]+):\s*(.*)$') {
            $map[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $map
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
    Copy-Item -Path (Join-Path $RepoPath "*") -Destination $tempRoot -Recurse -Force
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
    if (-not ($block -match '(?m)^\s*run:\s*(.+)$')) { continue }
    $cmd = $Matches[1].Trim()
    if ($cmd -match '^<.*>$') { continue }

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