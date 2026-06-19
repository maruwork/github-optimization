# Changelog

All notable changes to this regulation shelf are documented here.

The detailed shelf changelog lives in `regulation/shelf/SHELF_CHANGELOG.md`.

## [1.2.11] - 2026-06-19

### Fixed

- GitHub-hosted hardening is now aligned with the shelf's own public-release expectations, including secret scanning, push protection, Dependabot security updates, and protected `master` status checks.
- The PowerShell collector no longer carries an unreachable Git Bash branch-selection path, and the Git Bash collector now projects hosted JSON via stdin-backed temporary input instead of environment-variable payload transfer.
- Verdict, distribution, workflow, and verification docs now reflect the current release state without stale examples or ambiguous decision-table wording.

## [1.2.10] - 2026-06-19

### Fixed

- Branch version metadata now reflects the current `master` state instead of advertising the previous `v1.2.9` release after additional commits landed.
- The Git Bash collector now projects hosted metadata and latest CI evidence down to the same compact schema used by the PowerShell collector, removing duplicate raw repo payload churn from dogfood transcripts.

## [1.2.9] - 2026-06-19

### Fixed

- Windows PowerShell regression assertions for hosted issue-template evidence are now order-insensitive across `ABSENT`, `PASS`, and `API_BLOCKED` cases.
- Fixed-message assertions in the Windows collector regression suite now escape literal gate text correctly, so CI matches local verification.

## [1.2.8] - 2026-06-19

### Fixed

- Windows regression coverage no longer depends on JSON property order when hosted issue-template evidence is emitted.
- The hosted issue-template self-check now stays green on GitHub Actions Windows runners after release-tag timing and PowerShell serializer differences.

## [1.2.7] - 2026-06-19

### Fixed

- `gh` public-API retries no longer misclassify auth-required failures as `ABSENT`; the collectors keep them as `API_BLOCKED` unless a real 404 payload is present.
- PowerShell and Git Bash regression suites now cover the auth-required retry path and fixture initialization needed to keep shelf self-check deterministic after reruns.
- Audit orchestrator and collector docs now align with the current hosted-evidence and exit-semantics behavior.

## [1.2.6] - 2026-06-18

### Fixed

- Bash and PowerShell collector regressions now verify that access-denied Gitleaks execution-environment artifacts are reported as `SKIPPED`, not scoring `BLOCKED`.

## [1.2.5] - 2026-06-18

### Fixed

- Quickstart fixture environment names no longer use token-like wording, reducing secret-risk false positives during all-file audits.

## [1.2.4] - 2026-06-18

### Fixed

- PowerShell collector now resolves `gitleaks` from `PATH`, including CI-installed `go install` binaries, before declaring the tool unavailable.

## [1.2.3] - 2026-06-18

### Fixed

- CI Gitleaks installation now uses the current Go module path `github.com/zricethezav/gitleaks/v8`.

## [1.2.2] - 2026-06-18

### Fixed

- CI now installs `gitleaks` before running regulation tests so the stricter collector exit-code contract is tested on the authoritative baseline route.

## [1.2.1] - 2026-06-18

### Changed

- `collect-audit-evidence.*` now exits non-zero when it emits a real `result: BLOCKED` row while still preserving the full transcript.
- README, runbook, and scripts documentation now state that `run-full-audit.*` and `run-delta-audit.*` are scaffold/evidence orchestrators, not final verdict engines.

### Fixed

- Bash collector now treats Windows Git Bash / WinGet `gitleaks.exe` access-denied artifacts as `SKIPPED`, matching the PowerShell route and evidence rules.
- Regression tests now fail if blocked collector evidence exits successfully.

## [1.2.0] - 2026-06-18

### Added

- GO role criteria and coverage references for the public value model
- quickstart fixture coverage for manifest env, legacy run, and path assertions
- `.gitattributes` LF normalization for shell scripts

### Changed

- README now frames the shelf around eight publication-readiness concerns
- evidence rules distinguish raw machine evidence from final gate scoring transcripts
- Windows collector guidance now treats normal Windows PowerShell host-terminal evidence as authoritative for managed-sandbox path artifacts

### Fixed

- audit evidence wording no longer treats a managed sandbox WinGet path artifact as a repository defect after host-terminal proof exists
- tracked documentation text is ASCII-normalized to avoid terminal mojibake

## [1.1.14] - 2026-06-17

### Added

- `CODE_OF_CONDUCT.md`, `SUPPORT.md`
- `.github/ISSUE_TEMPLATE/*`, `.github/PULL_REQUEST_TEMPLATE.md`
- `.github/workflows/ci.yml` (canonical shelf CI; replaces `regulation-tests.yml`)
- `.github/workflows/codeql.yml` (G-18 code scanning)

### Changed

- `collect-audit-evidence.*` checks `ci.yml` and `codeql.yml`
- `SECURITY.md` supported versions include `1.1.x`

## [1.1.13] - 2026-06-17

### Changed

- `README.md` rewritten to match `OUTPUT_PATHS.md`, `REGULATION_INDEX.md`, and full script pipeline (v1.1.6 to 1.1.12 scope)

## [1.1.12] - 2026-06-17

### Fixed

- tracked-ignored-repo fixture stored as normal files (not gitlink); secret file generated at test runtime

## [1.1.11] - 2026-06-17

### Fixed

- tracked-ignored regression fixture committed (`local-only.secret`; avoids root `AGENTS.md` gitignore)

## [1.1.10] - 2026-06-17

### Fixed

- `check-gitignore-consistency.sh` stores finding fields as `severity|category|path|reason` (blocked findings now exit 1 on bash)
- `collect-audit-evidence.sh` collects full transcript under `set -e` (screening/gitignore/gitleaks/pytest/gh no longer abort early)
- `run-delta-audit.sh` uses `awk` instead of `python`; empty changed-path list no longer prints spurious `M` line
- `run-audit-quickstart.ps1` isolated workdir copies dotfiles (`.gitignore`, `.github/`, etc.)

### Added

- regulation tests for tracked-but-ignored fixture and evidence transcript continuity

## [1.1.9] - 2026-06-17

### Fixed

- `run-audit-quickstart.sh` reads multiline YAML command blocks via NUL-delimited records (Ubuntu CI no longer reports `commands run: 0`)

## [1.1.8] - 2026-06-17

### Fixed

- removed tracked `docs/governance/*` filled records; canonical path is `audits/<slug>/` only (`docs/governance/README.md` pointer)
- `audit.manifest.yml` uses `run_windows` / `run_unix` for cross-OS quickstart (Ubuntu CI R-08/R-09)
- `collect-audit-evidence.*` runs quickstart only when manifest exists; any non-zero exit fails evidence
- `check-tracked-files.*` blocks filled `docs/governance/` paths on shelf and product repos
- `.gitignore` adds recommended `AGENTS.md` / `CLAUDE.md` / `.claudeignore` patterns
- bash script em-dash output normalized to ASCII `-`

### Changed

- `templates/audit.manifest.yml.template` and `AUDIT_MANIFEST_POLICY.md` document OS-specific command fields
- `checklists/README.md` Tier 1 local checklist includes `G-21`

## [1.1.7] - 2026-06-17

### Fixed

- publication-decision-record path unified to `audits/<slug>/` in `EVIDENCE_COMMANDS.md`, `PUBLICATION_RESPONSIBILITY_MODEL.md`, `SCOPE_AND_TIERS.md`
- `run-audit-quickstart.sh` parses `- id:` / indented `run:` blocks correctly (bash quickstart no longer exits 2 with valid manifest)
- `collect-audit-evidence.sh` propagates quickstart failure (aligned with PowerShell)
- `AUDIT_RULES.md` Tier 1 range corrected to `G-01..G-22`

### Added

- regulation test fixture for bash quickstart manifest parsing

## [1.1.6] - 2026-06-17

### Added

- `scripts/check-gitignore-consistency.*` - tracked vs `.gitignore` index checks (`G-04`)
- `scripts/run-delta-audit.*` - delta re-audit orchestrator per `RE_AUDIT_POLICY.md`
- `regulation/reference/GITIGNORE_CONSISTENCY.md`
- `templates/delta-audit-record.md.template`

### Changed

- `collect-audit-evidence.*` includes gitignore consistency output
- `OUTPUT_PATHS.md` documents `delta-audit-record.md`

### Fixed

- `run-delta-audit.*` sensitive-path detection uses `--name-only` (Windows `Mpath` format)
- `run-delta-audit.*` `Open Blockers: 0` no longer false-positive invalidates delta

## [1.1.5] - 2026-06-17

### Added

- `scripts/check-tracked-files.*` to screen unnecessary tracked files (`G-03`, `G-04`, `G-21`)
- `regulation/reference/TRACKED_FILE_SCREENING.md`

### Changed

- `collect-audit-evidence.*` includes tracked-file screening output
- `audit.manifest.yml` runs screening on shelf quickstart

## [1.1.4] - 2026-06-17

### Added

- `audit.manifest.yml` for shelf quickstart automation

### Fixed

- dogfood audit findings: CHANGELOG drift, quickstart recursion, audit-report clobber
- `run-full-audit.*` refuses to overwrite `Status: Final` audit reports
- `run-regulation-tests.*` shelf dry-run uses `shelf-orchestrator-dry-run` slug only
- removed hardcoded user workspace paths from README and regulation entry files

### Changed

- `docs/governance/` self-audit summary updated to release dogfood verdict

## [1.1.3] - 2026-06-17

### Changed

- moved all regulation markdown from repository root into `regulation/` subdirectories
- root now shows README + standard repo files only

## [1.1.2] - 2026-06-17

### Removed from GitHub

- shelf build history: `design/`, `roadmap/`, `tasks/`
- deprecated meta files: `APPLICATION_GUIDE.md`, `GITHUB_OPTIMIZATION_*_SUMMARY.md`
- product audit results from remote tracking (`audits/<slug>/` now gitignored)

### Changed

- shelf moved to project root (`github-optimization/`)
- GitHub remote scope: regulation files only

## [1.1.1] - 2026-06-17

### Added

- `audits/` layout and `audits/README.md` for per-repository audit results

### Changed

- output contract: audit reports belong in `audits/<repository-slug>/`, not public product repos
- `run-full-audit.*` scaffolds shelf `audits/<slug>/` with optional `-AuditSlug`
- regulation tests, templates, policies, and checklists updated to new paths

## [1.1.0] - 2026-06-17

### Added

- root policy files, CI workflow, Dependabot, and shelf self-audit artifacts
- PowerShell gitleaks stderr normalization

## [1.0.0] - 2026-06-17

### Added

- complete generic regulation shelf for agent self-check
- 46 gate model, runbook, templates, and evidence scripts
- shelf self-validation, dry-run tests, distribution docs, and git tag `v1.0.0`
