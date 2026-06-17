# Shelf Path

Status: Active

## Purpose

Resolve where `github-optimization` lives so scripts work without hardcoded user paths.

## Resolution Order

The responsible AI uses the first path that exists:

1. environment variable `GITHUB_OPTIMIZATION_ROOT`
2. `../github-optimization` relative to target repository root
3. parent directory of `scripts/` when invoked from this shelf (scripts infer shelf root automatically)
4. standalone clone path documented in `regulation/shelf/SHELF_DISTRIBUTION.md`

If none apply, set `GITHUB_OPTIMIZATION_ROOT` before running evidence scripts.

## Script Invocation

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) {
    $env:GITHUB_OPTIMIZATION_ROOT
} elseif (Test-Path "..\github-optimization") {
    (Resolve-Path "..\github-optimization").Path
} else {
    throw "Set GITHUB_OPTIMIZATION_ROOT or place github-optimization next to the target repo"
}
& "$Shelf\scripts\collect-audit-evidence.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo
```

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
if [[ ! -d "$SHELF" ]]; then
  echo "Set GITHUB_OPTIMIZATION_ROOT or place github-optimization next to the target repo" >&2
  exit 1
fi
"$SHELF/scripts/collect-audit-evidence.sh" . owner/repo
```