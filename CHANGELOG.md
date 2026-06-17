# Changelog

All notable changes to this regulation shelf are documented here.

The detailed shelf changelog lives in `regulation/shelf/SHELF_CHANGELOG.md`.

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

- `scripts/check-gitignore-consistency.*` — tracked vs `.gitignore` index checks (`G-04`)
- `scripts/run-delta-audit.*` — delta re-audit orchestrator per `RE_AUDIT_POLICY.md`
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