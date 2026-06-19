param(
    [string]$ShelfPath = ""
)

$ErrorActionPreference = "Stop"

if (-not $ShelfPath) {
    if ($env:GITHUB_OPTIMIZATION_ROOT) {
        $ShelfPath = $env:GITHUB_OPTIMIZATION_ROOT
    } else {
        $ShelfPath = Split-Path $PSScriptRoot -Parent
    }
}

$shelfLabel = Split-Path $ShelfPath -Leaf

$indexPath = Join-Path $ShelfPath "regulation/REGULATION_INDEX.md"
if (-not (Test-Path $indexPath)) {
    Write-Error "regulation/REGULATION_INDEX.md not found at $ShelfPath"
}

$lines = Get-Content $indexPath
$inRequired = $false
$required = New-Object System.Collections.Generic.List[string]

foreach ($line in $lines) {
    if ($line -match '^## Required') { $inRequired = $true; continue }
    if ($line -match '^## Excluded') { break }
    if (-not $inRequired) { continue }
    if ($line -match '^- `([^`]+)`') {
        $path = $Matches[1]
        if ($path -notmatch '\*\*|all ') {
            $required.Add($path) | Out-Null
        }
    }
}

$templateDir = Join-Path $ShelfPath "templates"
Get-ChildItem -Path $templateDir -Filter "*.template" -File | ForEach-Object {
    $required.Add(("templates/" + $_.Name)) | Out-Null
}

$failures = @()
foreach ($rel in $required | Select-Object -Unique) {
    $full = Join-Path $ShelfPath $rel
    if (-not (Test-Path -LiteralPath $full)) {
        $failures += "missing required file: $rel"
    }
}

$gatePath = Join-Path $ShelfPath "regulation/gates/GATE_REGISTRY.md"
if (Test-Path $gatePath) {
    $gateText = Get-Content $gatePath -Raw
    foreach ($prefix in @("G", "R", "P")) {
        $max = if ($prefix -eq "G") { 22 } elseif ($prefix -eq "R") { 14 } else { 10 }
        for ($i = 1; $i -le $max; $i++) {
            $id = "{0}-{1:D2}" -f $prefix, $i
            if ($gateText -notmatch [regex]::Escape("| $id ")) {
                $failures += "GATE_REGISTRY missing row: $id"
            }
        }
    }
} else {
    $failures += "missing regulation/gates/GATE_REGISTRY.md"
}

Write-Output "=== Regulation Index Validation ==="
Write-Output "Shelf: $shelfLabel"
Write-Output "Required paths checked: $(($required | Select-Object -Unique).Count)"

if ($failures.Count -eq 0) {
    Write-Output "result: PASS"
    exit 0
}

foreach ($f in $failures) { Write-Output "FAIL: $f" }
Write-Output "result: FAIL ($($failures.Count) issues)"
exit 1
