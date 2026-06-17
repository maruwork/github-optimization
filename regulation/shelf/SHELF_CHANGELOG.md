# Shelf Changelog

All notable changes to the generic regulation shelf.

## 1.1.11 — 2026-06-17

### Fixed

- tracked-ignored-repo fixture shipped in repo (CI path missing on v1.1.10)

## 1.1.10 — 2026-06-17

### Fixed

- bash gitignore consistency severity field order; blocked exit parity with PowerShell
- bash evidence collector no longer aborts on screening/gitignore non-zero
- delta-audit bash: no python dependency; empty diff list output
- quickstart isolated copy includes dotfiles on Windows

## 1.1.9 — 2026-06-17

### Fixed

- bash quickstart multiline manifest parse (`awk` RS + NUL records); fixes Ubuntu regulation-tests `commands run: 0`

## 1.1.8 — 2026-06-17

### Fixed

- governance path split eliminated (`docs/governance/` filled records removed)
- cross-OS quickstart manifest + evidence propagation parity
- shelf `.gitignore` AI-control patterns; tracked-file screening for governance paths

## 1.1.7 — 2026-06-17

### Fixed

- publication-decision-record output path drift across regulation files
- bash quickstart manifest id parse; collect-audit-evidence quickstart exit propagation
- AUDIT_RULES Tier 1 gate range G-21/G-22

## 1.1.6 — 2026-06-17

### Added

- gitignore consistency checker (`git ls-files -ci --exclude-standard`)
- delta re-audit orchestrator and `delta-audit-record.md.template`

### Changed

- evidence bundle includes gitignore consistency screening

### Fixed

- delta orchestrator: Windows name-status parse, Open Blockers count parse

## 1.1.5 — 2026-06-17

### Added

- `scripts/check-tracked-files.*` for unnecessary tracked-file detection
- `regulation/reference/TRACKED_FILE_SCREENING.md`

### Changed

- evidence bundle and shelf quickstart include screening output

## 1.1.4 — 2026-06-17

### Added

- `audit.manifest.yml` for shelf quickstart automation

### Fixed

- dogfood audit: `CHANGELOG.md` synced through 1.1.3
- dogfood audit: quickstart test infinite recursion when shelf has `audit.manifest.yml`
- dogfood audit: `regulation-tests` no longer deletes `audits/github-optimization/`
- `run-full-audit.*` refuses to overwrite `Status: Final` audit reports
- shelf dry-run test uses `shelf-orchestrator-dry-run` slug only
- removed hardcoded user workspace paths from README and regulation entry files

### Changed

- `docs/governance/` self-audit summary updated to release dogfood verdict

## 1.1.3 — 2026-06-17

### Changed

- moved all regulation markdown from repository root into `regulation/` subdirectories
- root now shows README + standard repo files only

## 1.1.2 — 2026-06-17

### Removed from GitHub

- shelf build history: `design/`, `roadmap/`, `tasks/`
- deprecated meta files: `APPLICATION_GUIDE.md`, `GITHUB_OPTIMIZATION_*_SUMMARY.md`
- product audit results from remote tracking (`audits/<slug>/` now gitignored)

### Changed

- shelf moved to project root (`github-optimization/`)
- GitHub remote scope: regulation files only

## 1.1.1 — 2026-06-17

### Added

- `audits/` layout and `audits/README.md` for per-repository audit results
- tracked ADOP and VEIL audit reports under `audits/adop/` and `audits/veil/`

### Changed

- output contract: audit reports belong in `audits/<repository-slug>/`, not public product repos
- `run-full-audit.*` scaffolds shelf `audits/<slug>/` with optional `-AuditSlug`
- regulation tests, templates, policies, and checklists updated to new paths

## 1.1.0 — 2026-06-17

### Added

- root policy files: `LICENSE`, `SECURITY.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- CI workflow `.github/workflows/regulation-tests.yml` and Dependabot config
- tracked shelf self-audit artifacts under `docs/governance/`
- gitleaks stderr handling fix in `collect-audit-evidence.ps1`

### Changed

- `.gitignore` allows tracked self-audit governance files only

## 1.0.0 — 2026-06-17

### Added

- complete 46-gate regulation set and `regulation/REGULATION_INDEX.md`
- agent execution model, audit runbook, and output path contract
- policy files: `regulation/execution/RE_AUDIT_POLICY.md`, `regulation/execution/AUDIT_PHASE_POLICY.md`, `regulation/execution/MULTI_REPO_ORCHESTRATION.md`, `regulation/reference/TOOL_REVIEW_CADENCE.md`
- governance templates including `accepted-risk-record.md.template`
- scripts: `validate-regulation-index.*`, `run-full-audit.*`, `collect-audit-evidence.*`, `run-audit-quickstart.*`
- regression tests: `scripts/tests/run-regulation-tests.*`
- distribution docs: `regulation/shelf/SHELF_DISTRIBUTION.md`, `regulation/shelf/SHELF_VERSION.md`
- dry-run fixture: `scripts/tests/fixtures/minimal-docs-repo/`

### Changed

- `README.md` rewritten for agent-first self-check purpose
- `domain-option/` reduced to copy templates only

### Removed

- live project-specific execution records from generic shelf