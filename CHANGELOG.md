# Changelog

All notable changes to this regulation shelf are documented here.

The detailed shelf changelog lives in `regulation/shelf/SHELF_CHANGELOG.md`.

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