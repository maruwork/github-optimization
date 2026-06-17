# Shelf Changelog

All notable changes to the generic regulation shelf.

## 1.1.2 — 2026-06-17

### Removed from GitHub

- shelf build history: `design/`, `roadmap/`, `tasks/`
- deprecated meta files: `APPLICATION_GUIDE.md`, `GITHUB_OPTIMIZATION_*_SUMMARY.md`
- product audit results from remote tracking (`audits/<slug>/` now gitignored)

### Changed

- shelf moved to `C:\Users\f_tan\project\github-optimization` (project root)
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

- complete 46-gate regulation set and `REGULATION_INDEX.md`
- agent execution model, audit runbook, and output path contract
- policy files: `RE_AUDIT_POLICY.md`, `AUDIT_PHASE_POLICY.md`, `MULTI_REPO_ORCHESTRATION.md`, `TOOL_REVIEW_CADENCE.md`
- governance templates including `accepted-risk-record.md.template`
- scripts: `validate-regulation-index.*`, `run-full-audit.*`, `collect-audit-evidence.*`, `run-audit-quickstart.*`
- regression tests: `scripts/tests/run-regulation-tests.*`
- distribution docs: `SHELF_DISTRIBUTION.md`, `SHELF_VERSION.md`
- dry-run fixture: `scripts/tests/fixtures/minimal-docs-repo/`

### Changed

- `README.md` rewritten for agent-first self-check purpose
- `domain-option/` reduced to copy templates only

### Removed

- live project-specific execution records from generic shelf