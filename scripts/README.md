# Audit Evidence Scripts

Status: Active

## Purpose

Collect machine-readable publication-readiness audit evidence in one pass.

Output is designed to paste into `templates/audit-report.md.template`.
They gather repeatable audit evidence across docs, quickstart, CI, metadata, and basic hygiene checks.

## Scripts

| Script | Platform |
|---|---|
| `run-full-audit.ps1` | Windows PowerShell - shelf validate + scaffold + evidence |
| `run-full-audit.sh` | Linux/macOS bash - shelf validate + scaffold + evidence |
| `validate-regulation-index.ps1` | Windows PowerShell - shelf self-check |
| `validate-regulation-index.sh` | Linux/macOS bash - shelf self-check |
| `check-tracked-files.ps1` | Windows PowerShell - unnecessary tracked-file scan |
| `check-tracked-files.sh` | Linux/macOS bash - unnecessary tracked-file scan |
| `check-gitignore-consistency.ps1` | Windows PowerShell - `.gitignore` vs index consistency |
| `check-gitignore-consistency.sh` | Linux/macOS bash - `.gitignore` vs index consistency |
| `run-delta-audit.ps1` | Windows PowerShell - delta re-audit orchestrator |
| `run-delta-audit.sh` | Linux/macOS bash - delta re-audit orchestrator |
| `collect-audit-evidence.ps1` | Windows PowerShell native collector |
| `collect-audit-evidence.sh` | Linux/macOS bash |
| `run-audit-quickstart.ps1` | Windows PowerShell |
| `run-audit-quickstart.sh` | Linux/macOS bash |
| `tests/run-regulation-tests.ps1` | Windows PowerShell - shelf regression tests |
| `tests/run-regulation-tests.sh` | Linux/macOS bash - shelf regression tests |

## Exit Code Contract

`collect-audit-evidence.*` exits `0` only when the collector produced no `result: BLOCKED` rows and no quickstart failure.
It may still print `result: SKIPPED` for non-scoring execution-environment artifacts such as Windows Git Bash or managed-sandbox WinGet `gitleaks.exe` issues.
Any real `result: BLOCKED` row makes the collector exit non-zero after it finishes printing the transcript.

`run-full-audit.*` and `run-delta-audit.*` are scaffold/evidence orchestrators, not final verdict engines.
An orchestrator exit `0` means the scaffold and machine-evidence phase completed; the agent still must complete full-file read coverage, transcript mapping, gate scoring, waivers, and final verdict assignment.

## Usage

```powershell
.\run-full-audit.ps1 -RepoPath C:\path\to\repo -HostedRepo owner/repo -AuditMode release -AuditPhase pre-public
```

```powershell
.\validate-regulation-index.ps1 -ShelfPath C:\path\to\github-optimization
```

```powershell
.\check-tracked-files.ps1 -RepoPath C:\path\to\repo
```

```powershell
.\collect-audit-evidence.ps1 -RepoPath C:\path\to\repo -HostedRepo owner/repo
```

```bash
./collect-audit-evidence.sh /path/to/repo owner/repo
```

Use `collect-audit-evidence.ps1` as the authoritative Windows evidence path.
Use `collect-audit-evidence.sh` for Linux/macOS bash evidence.
Windows Git Bash may report `Gitleaks` as `SKIPPED`; score `G-01` from the Windows PowerShell collector or a direct `gitleaks detect --source . --no-banner` transcript.
If a managed sandbox denies a WinGet `gitleaks.exe` path, keep that raw `SKIPPED` output and score from the successful direct transcript.

## What They Collect

- `git ls-files` count
- tracked-file screening for developer-only, internal-management, cache, and misplaced audit paths
- gitignore consistency (`git ls-files -ci --exclude-standard`)
- HEAD and describe
- root/github file presence
- latest CI run summary when `gh` is available
- hosted metadata and Community Profile when `gh` is available
- security feature state when `gh` is available
- Gitleaks result when `gitleaks` is available; Windows Git Bash may emit `SKIPPED` and defer `G-01` scoring to PowerShell or a direct transcript
- large tracked files over 512KB (`G-22`)
- pytest result when `pytest` is available (`R-12` baseline)
- hosted issue-template contents when issues are enabled and GitHub Community Profile omits the template entry

## Quickstart Contract

Repeated audits should add `audit.manifest.yml` to the target repository using `templates/audit.manifest.yml.template`.

Without a manifest, the agent still executes README-derived commands and records the transcript.

Supported quickstart manifest helpers:

- shared `env` variables for all commands
- legacy `run` fallback when OS-specific fields are omitted
- `assertions[].path_exists` post-checks for created artifacts

## Regression Tests

Run after shelf edits:

```powershell
.\tests\run-regulation-tests.ps1
```

Read: `regulation/reference/TOOL_REVIEW_CADENCE.md`

## Limitation

Scripts do not replace full-file read review or gate scoring.
They replace human-operated evidence gathering and shelf self-validation.

`collect-audit-evidence.*` can leave a gate in a visibly blocked state when a required tool is unavailable on the authoritative route.
When that happens, it exits non-zero after preserving the full transcript.
Windows Git Bash is not the authoritative route for `G-01`; it records `SKIPPED` for Windows-only Gitleaks path issues.

`run-full-audit.*` captures the raw machine evidence bundle into the scaffolded report.
The agent still must complete read coverage, per-claim transcript rows, and gate scoring before closing the audit.
