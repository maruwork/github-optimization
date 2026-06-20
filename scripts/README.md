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
| `run-public-corpus.ps1` | Windows PowerShell - public GitHub external-validation corpus runner |
| `run-public-corpus.sh` | Linux/macOS bash - public GitHub external-validation corpus runner |
| `run-audit-quickstart.ps1` | Windows PowerShell |
| `run-audit-quickstart.sh` | Linux/macOS bash |
| `tests/run-regulation-tests.ps1` | Windows PowerShell - shelf regression tests (`-Suite all|ci-selection|orchestrator`) |
| `tests/run-regulation-tests-ci.ps1` | Windows PowerShell - focused latest-CI workflow selection / classification regression tests |
| `tests/run-regulation-tests-orchestrator.ps1` | Windows PowerShell - delta/full-audit / quickstart orchestrator regression tests |
| `tests/run-regulation-tests.sh` | Linux/macOS bash - full shelf regression tests (`--suite all|ci-selection|orchestrator`) |
| `tests/run-regulation-tests-ci.sh` | Linux/macOS bash - focused latest-CI workflow selection / classification regression tests |
| `tests/run-regulation-tests-orchestrator.sh` | Linux/macOS bash - delta/full-audit / quickstart orchestrator regression tests |

## Exit Code Contract

`collect-audit-evidence.*` exits `0` only when the collector produced no `result: BLOCKED` rows and no quickstart failure.
It may still print `result: SKIPPED` for non-scoring execution-environment artifacts such as Windows Git Bash or managed-sandbox WinGet `gitleaks.exe` issues.
When `gh` cannot read the default GitHub CLI config during public hosted evidence collection, the collector retries with an isolated temporary `GH_CONFIG_DIR` and then restores the caller environment.
Any real `result: BLOCKED` row makes the collector exit non-zero after it finishes printing the transcript.

`run-full-audit.*` and `run-delta-audit.*` are scaffold/evidence orchestrators, not final verdict engines.
An orchestrator exit `0` means the scaffold and machine-evidence phase completed, even when the captured collector transcript contains `result: BLOCKED` rows for the target repository.
Those target findings stay in the report as raw machine evidence; the agent still must complete full-file read coverage, transcript mapping, gate scoring, waivers, and final verdict assignment.
`run-delta-audit.*` still exits `2` when delta invalidation upgrades the run to a required full re-audit.

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

```powershell
.\run-public-corpus.ps1
```

```bash
./run-public-corpus.sh
```

Use `collect-audit-evidence.ps1` as the authoritative Windows evidence path.
Use `collect-audit-evidence.sh` for Linux/macOS bash evidence.
Windows Git Bash may report `Gitleaks` as `SKIPPED`; score `G-01` from the Windows PowerShell collector or a direct `gitleaks detect --source . --no-banner` transcript.
If a managed sandbox denies a WinGet `gitleaks.exe` path, keep that raw `SKIPPED` output and score from the successful direct transcript.
If hosted metadata still reports `API_BLOCKED` inside a managed sandbox, rerun the same command in a normal Windows PowerShell host terminal before scoring hosted GitHub evidence.

## What They Collect

- `git ls-files` count
- tracked-file screening for developer-only, internal-management, cache, and misplaced audit paths
- gitignore consistency (`git ls-files -ci --exclude-standard`)
- HEAD and describe
- root/github file presence
- latest CI workflow summary when `gh` is available, preferring the selected primary CI workflow on the default branch (manifest override, `ci.yml` / `ci.yaml`, heuristic local candidate, hosted workflow inventory candidate, then overall-runs fallback), upgrading to hosted inventory when a heuristic local candidate has no default-branch runs, and including timing, job count, coarse classification, `R-02` provisional assessment, `selected_workflow_path`, `workflow_selection`, and candidate signals when available
- hosted metadata and Community Profile when `gh` is available
- security feature state when `gh` is available
- Gitleaks result when `gitleaks` is available; Windows Git Bash may emit `SKIPPED` and defer `G-01` scoring to PowerShell or a direct transcript
- public GitHub API evidence via `gh api` with temporary-config retry when the default GitHub CLI config path is unreadable
- large tracked files over 512KB (`G-22`)
- pytest result when `pytest` is available (`R-12` baseline)
- hosted issue-template contents when issues are enabled and GitHub Community Profile omits the template entry
- external-validation corpus replay against selected public GitHub repositories via `scripts/corpus/public-r02-corpus.json`

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
.\tests\run-regulation-tests-ci.ps1
.\tests\run-regulation-tests-orchestrator.ps1
```

```bash
./tests/run-regulation-tests-ci.sh
./tests/run-regulation-tests-orchestrator.sh
```

Read: `regulation/reference/TOOL_REVIEW_CADENCE.md`

## Public Corpus

Use `run-public-corpus.*` when `R-02` workflow-selection heuristics or classification rules change.
It shallow-clones the public repositories listed in `scripts/corpus/public-r02-corpus.json`, runs the native collector, and checks whether `workflow_selection` plus `selected_workflow_path` match the curated expectation set when a narrower workflow can be selected. `all_runs_fallback` is allowed to leave `selected_workflow_path` empty because the point of that classification is that no narrower workflow selection was available.

This corpus is intentionally narrower than the no-network regression suite:

- it validates behavior against live public GitHub repository data
- it is expected to require network access
- it focuses on external validity of `R-02`, not on full audit pass/fail status of those repositories

For volatile latest-run states, keep observational dogfooding snapshots in `scripts/corpus/public-r02-observed-live-cases.json` instead of promoting them directly into the gating corpus.
This is the right place for live `branch_filter_candidate`, `in_progress`, or temporary hard-failure examples whose exact classification may change as upstream repositories publish new runs.

## Limitation

Scripts do not replace full-file read review or gate scoring.
They replace human-operated evidence gathering and shelf self-validation.
When a repository remote is configured, the orchestrators prefer the hosted repository name for `audits/<slug>/` output instead of the current worktree directory name.

`collect-audit-evidence.*` can leave a gate in a visibly blocked state when a required tool is unavailable on the authoritative route.
When that happens, it exits non-zero after preserving the full transcript.
Windows Git Bash is not the authoritative route for `G-01`; it records `SKIPPED` for Windows-only Gitleaks path issues.
For `R-02`, treat collector `r02_assessment=review` as a follow-up requirement, not as an automatic Blocker.

`run-full-audit.*` captures the raw machine evidence bundle into the scaffolded report.
The agent still must complete read coverage, per-claim transcript rows, and gate scoring before closing the audit.
