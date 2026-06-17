# Shelf Changelog

All notable changes to the generic regulation shelf.

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