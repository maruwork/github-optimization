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

function Get-ManifestValue([string]$Value) {
    $trimmed = $Value.Trim()
    if (
        ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or
        ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))
    ) {
        return $trimmed.Substring(1, $trimmed.Length - 2)
    }
    return $trimmed
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

$lines = Get-Content $ManifestPath
$raw = $lines -join "`n"
Write-Output "=== Quickstart Manifest ==="
Write-Output "Manifest: $ManifestPath"

$workdir = "in-place"
if ($raw -match '(?m)^workdir:\s*(.+)$') { $workdir = Get-ManifestValue $Matches[1] }

$envVars = @{}
$inEnv = $false
foreach ($line in $lines) {
    if ($line -match '^\S') {
        $inEnv = $line -match '^env:\s*$'
        continue
    }
    if (-not $inEnv) { continue }
    if ($line -match '^\s{2}([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.+)\s*$') {
        $envVars[$Matches[1]] = Get-ManifestValue $Matches[2]
    }
}

$pathAssertions = New-Object System.Collections.Generic.List[string]
$inAssertions = $false
foreach ($line in $lines) {
    if ($line -match '^\S') {
        $inAssertions = $line -match '^assertions:\s*$'
        continue
    }
    if (-not $inAssertions) { continue }
    if ($line -match '^\s{4}path_exists:\s*(.+)\s*$') {
        $pathAssertions.Add((Get-ManifestValue $Matches[1])) | Out-Null
    }
}

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
$assertionsRun = 0

$priorEnv = @{}
foreach ($name in $envVars.Keys) {
    $existing = [Environment]::GetEnvironmentVariable($name, "Process")
    if ($null -ne $existing) {
        $priorEnv[$name] = $existing
    }
    [Environment]::SetEnvironmentVariable($name, $envVars[$name], "Process")
}

try {
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
            cmd.exe /d /c $cmd 2>&1 | ForEach-Object { Write-Output $_ }
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
} finally {
    foreach ($name in $envVars.Keys) {
        if ($priorEnv.ContainsKey($name)) {
            [Environment]::SetEnvironmentVariable($name, $priorEnv[$name], "Process")
        } else {
            [Environment]::SetEnvironmentVariable($name, $null, "Process")
        }
    }
}

foreach ($path in $pathAssertions) {
    Write-Output ""
    Write-Output "=== assertion:path_exists:$path ==="
    $assertionsRun++
    if (Test-Path -LiteralPath (Join-Path $runRoot $path)) {
        Write-Output "result: PASS"
    } else {
        Write-Output "result: FAIL (missing path)"
        $failures++
    }
}

if ($tempRoot) {
    Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
}

Write-Output ""
Write-Output "=== Quickstart Summary ==="
Write-Output "commands run: $ran"
Write-Output "assertions run: $assertionsRun"
Write-Output "failures: $failures"

if ($ran -eq 0) {
    exit 2
}
if ($failures -gt 0) {
    exit 1
}
exit 0
