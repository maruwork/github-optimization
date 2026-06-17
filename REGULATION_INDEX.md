# Regulation Index

Status: Active

## Purpose

Authoritative list of **generic regulation** files for self-check.

The responsible AI reads the Required set below. Everything in Excluded is not regulation.

Completeness proof: `REGULATION_COMPLETENESS.md`

## Required — Generic Regulation

### Entry

- `README.md`
- `REGULATION_SELF_CHECK.md`
- `REGULATION_INDEX.md`
- `REGULATION_COMPLETENESS.md`
- `GATE_REGISTRY.md`
- `OUTPUT_PATHS.md`
- `SHELF_PATH.md`
- `SHELF_DISTRIBUTION.md`
- `SHELF_VERSION.md`
- `SHELF_CHANGELOG.md`

### Execution model

- `AGENT_EXECUTION_MODEL.md`
- `AUDIT_RULES.md`
- `AUDIT_RUNBOOK.md`
- `SCOPE_AND_TIERS.md`
- `AUDIT_PHASE_POLICY.md`
- `RE_AUDIT_POLICY.md`
- `MULTI_REPO_ORCHESTRATION.md`

### Classification, tools, boundaries, and judgment

- `REPO_CONTENT_CLASSIFICATION.md`
- `TOOL_VERIFICATION_MATRIX.md`
- `TOOL_REVIEW_CADENCE.md`
- `EVIDENCE_COMMANDS.md`
- `HOSTED_SETTINGS_BOUNDARY.md`
- `AUDIT_MANIFEST_POLICY.md`
- `JUDGMENT_GUIDE.md`
- `WAIVER_POLICY.md`

### Gates and verdict

- `PUBLIC_PREP_GATE.md`
- `RELEASE_QUALITY_GATE.md`
- `PRODUCT_READINESS_GATE.md`
- `FULL_AUDIT_VERDICT.md`

### Responsibility

- `PUBLICATION_RESPONSIBILITY_MODEL.md`

### Audit results (per audited repository)

- `audits/README.md`
- `OUTPUT_PATHS.md` (defines `audits/<repository-slug>/` layout)

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

### Automation scripts

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
3. all 46 gate IDs in `GATE_REGISTRY.md` must be scored or marked `n/a` with reason
4. `audit.manifest.yml` may remain in a product repository root for quickstart automation only