# Regulation Index

Status: Active

## Purpose

Authoritative list of **generic regulation** files for self-check.

The responsible AI reads the Required set below. Everything in Excluded is not regulation.

Completeness proof: `regulation/REGULATION_COMPLETENESS.md`

## Required — Generic Regulation

### Entry

- `README.md`
- `regulation/README.md`
- `regulation/REGULATION_SELF_CHECK.md`
- `regulation/REGULATION_INDEX.md`
- `regulation/REGULATION_COMPLETENESS.md`
- `regulation/gates/GATE_REGISTRY.md`
- `regulation/shelf/OUTPUT_PATHS.md`
- `regulation/shelf/SHELF_PATH.md`
- `regulation/shelf/SHELF_DISTRIBUTION.md`
- `regulation/shelf/SHELF_VERSION.md`
- `regulation/shelf/SHELF_CHANGELOG.md`

### Execution model

- `regulation/execution/AGENT_EXECUTION_MODEL.md`
- `regulation/execution/AUDIT_RULES.md`
- `regulation/execution/AUDIT_RUNBOOK.md`
- `regulation/execution/SCOPE_AND_TIERS.md`
- `regulation/execution/AUDIT_PHASE_POLICY.md`
- `regulation/execution/RE_AUDIT_POLICY.md`
- `regulation/execution/MULTI_REPO_ORCHESTRATION.md`

### Classification, tools, boundaries, and judgment

- `regulation/reference/REPO_CONTENT_CLASSIFICATION.md`
- `regulation/reference/TRACKED_FILE_SCREENING.md`
- `regulation/reference/GITIGNORE_CONSISTENCY.md`
- `regulation/reference/TOOL_VERIFICATION_MATRIX.md`
- `regulation/reference/TOOL_REVIEW_CADENCE.md`
- `regulation/reference/EVIDENCE_COMMANDS.md`
- `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`
- `regulation/reference/AUDIT_MANIFEST_POLICY.md`
- `regulation/reference/JUDGMENT_GUIDE.md`
- `regulation/reference/WAIVER_POLICY.md`

### Gates and verdict

- `regulation/gates/PUBLIC_PREP_GATE.md`
- `regulation/gates/RELEASE_QUALITY_GATE.md`
- `regulation/gates/PRODUCT_READINESS_GATE.md`
- `regulation/gates/FULL_AUDIT_VERDICT.md`

### Responsibility

- `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md`

### Audit results (per audited repository)

- `audits/README.md`
- `regulation/shelf/OUTPUT_PATHS.md` (defines `audits/<repository-slug>/` layout)

### Shelf self-proof (this repository only)

- `docs/governance/shelf-self-audit-report.md`
- `docs/governance/publication-decision-record.md`

### Checklists

- `checklists/README.md`
- `checklists/repository-file-review-checklist.md`
- `checklists/local-public-prep-checklist.md`
- `checklists/github-settings-checklist.md`
- `checklists/publication-decision-checklist.md`
- `checklists/release-quality-checklist.md`
- `checklists/product-readiness-checklist.md`

### Output templates

- `templates/audit-report.md.template`
- `templates/publication-decision-record.md.template`
- `templates/tier2-defer-record.md.template`
- `templates/accepted-risk-record.md.template`
- `templates/audit.manifest.yml.template`
- `templates/delta-audit-record.md.template`

### Automation scripts

- `scripts/check-tracked-files.ps1`
- `scripts/check-tracked-files.sh`
- `scripts/check-gitignore-consistency.ps1`
- `scripts/check-gitignore-consistency.sh`
- `scripts/run-delta-audit.ps1`
- `scripts/run-delta-audit.sh`
- `scripts/collect-audit-evidence.ps1`
- `scripts/collect-audit-evidence.sh`
- `scripts/run-audit-quickstart.ps1`
- `scripts/run-audit-quickstart.sh`
- `scripts/validate-regulation-index.ps1`
- `scripts/validate-regulation-index.sh`
- `scripts/run-full-audit.ps1`
- `scripts/run-full-audit.sh`
- `scripts/tests/README.md`
- `scripts/tests/run-regulation-tests.ps1`
- `scripts/tests/run-regulation-tests.sh`

### Repair starters

- `templates/README.md`
- all `templates/*.template` referenced by `templates/README.md`

## Excluded — Not Generic Regulation

| Path | Reason |
|---|---|
| `domain-option/**` | copy templates only; no project examples |
| `roadmap/**` | shelf build history |
| `design/**` | shelf build history |
| `tasks/**` | shelf build history |
| `APPLICATION_GUIDE.md` | deprecated pointer |
| `GITHUB_OPTIMIZATION_PRODUCTIZATION_SUMMARY.md` | meta record |
| `GITHUB_OPTIMIZATION_TOOL_VERIFICATION_SUMMARY.md` | meta record |

## Hard Rules

1. regulation text stays generic; scored audit artifacts live under `audits/<repository-slug>/`
2. never write audit reports into public product repositories
3. all 46 gate IDs in `regulation/gates/GATE_REGISTRY.md` must be scored or marked `n/a` with reason
4. `audit.manifest.yml` may remain in a product repository root for quickstart automation only