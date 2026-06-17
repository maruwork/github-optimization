# Shelf Path

Status: Active

## Purpose

Resolve where `github-optimization` lives so scripts work without hardcoded user paths.

## Default In This Workspace

```text
C:\Users\f_tan\project\github-optimization
```

## Resolution Order

The responsible AI uses the first path that exists:

1. environment variable `GITHUB_OPTIMIZATION_ROOT`
2. `../github-optimization` relative to target repository root
3. standalone clone path documented in `regulation/shelf/SHELF_DISTRIBUTION.md`
4. `C:\Users\f_tan\project\github-optimization`

Standalone clone users should set `GITHUB_OPTIMIZATION_ROOT` explicitly.

## Script Invocation

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) { $env:GITHUB_OPTIMIZATION_ROOT } elseif (Test-Path "..\github-optimization") { Resolve-Path "..\github-optimization" } else { "C:\Users\f_tan\project\github-optimization" }
& "$Shelf\scripts\collect-audit-evidence.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo
```

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
"$SHELF/scripts/collect-audit-evidence.sh" . owner/repo
```