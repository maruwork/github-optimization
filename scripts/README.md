# Audit Evidence Scripts

Status: Active

## Purpose

Collect machine-readable audit evidence in one pass.

Output is designed to paste into `templates/audit-report.md.template`.

## Scripts

| Script | Platform |
|---|---|
| `run-full-audit.ps1` | Windows PowerShell — shelf validate + scaffold + evidence |
| `run-full-audit.sh` | Linux/macOS bash — shelf validate + scaffold + evidence |
| `validate-regulation-index.ps1` | Windows PowerShell — shelf self-check |
| `validate-regulation-index.sh` | Linux/macOS bash — shelf self-check |
| `check-tracked-files.ps1` | Windows PowerShell — unnecessary tracked-file scan |
| `check-tracked-files.sh` | Linux/macOS bash — unnecessary tracked-file scan |
| `check-gitignore-consistency.ps1` | Windows PowerShell — `.gitignore` vs index consistency |
| `check-gitignore-consistency.sh` | Linux/macOS bash — `.gitignore` vs index consistency |
| `run-delta-audit.ps1` | Windows PowerShell — delta re-audit orchestrator |
| `run-delta-audit.sh` | Linux/macOS bash — delta re-audit orchestrator |
| `collect-audit-evidence.ps1` | Windows PowerShell |
| `collect-audit-evidence.sh` | Linux/macOS bash |
| `run-audit-quickstart.ps1` | Windows PowerShell |
| `run-audit-quickstart.sh` | Linux/macOS bash |
| `tests/run-regulation-tests.ps1` | Windows PowerShell — shelf regression tests |
| `tests/run-regulation-tests.sh` | Linux/macOS bash — shelf regression tests |

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

## What They Collect

- `git ls-files` count
- tracked-file screening for developer-only, internal-management, cache, and misplaced audit paths
- gitignore consistency (`git ls-files -ci --exclude-standard`)
- HEAD and describe
- root/github file presence
- latest CI run summary when `gh` is available
- hosted metadata and Community Profile when `gh` is available
- security feature state when `gh` is available
- Gitleaks result when `gitleaks` is installed (`G-01`)
- large tracked files over 512KB (`G-22`)
- pytest result when `pytest` is available (`R-12` baseline)

## Quickstart Contract

Repeated audits should add `audit.manifest.yml` to the target repository using `templates/audit.manifest.yml.template`.

Without a manifest, the agent still executes README-derived commands and records the transcript.

## Regression Tests

Run after shelf edits:

```powershell
.\tests\run-regulation-tests.ps1
```

Read: `regulation/reference/TOOL_REVIEW_CADENCE.md`

## Limitation

Scripts do not replace full-file read review or gate scoring.
They replace human-operated evidence gathering and shelf self-validation.