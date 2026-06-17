# GitHub Optimization Productization Summary

Status: Complete

Recorded: 2026-06-17

## Shelf Role

`common/github-optimization` is the generic regulation shelf for agent-operated public-repository self-check.

It is complete when a responsible AI can:

1. read `REGULATION_INDEX.md`
2. follow `AUDIT_RUNBOOK.md`
3. score all 46 gate items
4. write outputs to target `docs/governance/`
5. finish without human command execution

## Final Structure

| Layer | Files |
|---|---|
| Entry | `README.md`, `REGULATION_SELF_CHECK.md`, `REGULATION_INDEX.md` |
| Judgment | `GATE_REGISTRY.md`, `PUBLIC_PREP_GATE.md`, `RELEASE_QUALITY_GATE.md`, `PRODUCT_READINESS_GATE.md`, `FULL_AUDIT_VERDICT.md` |
| Execution | `AGENT_EXECUTION_MODEL.md`, `AUDIT_RULES.md`, `AUDIT_RUNBOOK.md` |
| Boundaries | `OUTPUT_PATHS.md`, `HOSTED_SETTINGS_BOUNDARY.md`, `AUDIT_MANIFEST_POLICY.md`, `REPO_CONTENT_CLASSIFICATION.md` |
| Checklists | `checklists/*.md` |
| Templates | `templates/*.template` |
| Scripts | `scripts/collect-audit-evidence.*`, `scripts/run-audit-quickstart.*` |
| Excluded | `domain-option/**` live examples, `roadmap/**`, `design/**`, `tasks/**` |

## 2026-06-17 Gap Closure Pass

- added `WAIVER_POLICY.md`
- added `JUDGMENT_GUIDE.md`
- added `SHELF_PATH.md`
- added `REGULATION_COMPLETENESS.md`
- mapped every checklist item to gate IDs
- extended evidence scripts for `G-22`
- separated `AUDIT_RUNBOOK` steps for `G-02`, `G-21`, and machine evidence
- linked Tier 2 defer to `tier2-defer-record.md.template`

## 2026-06-17 Completion Pass

- removed project-specific `VEIL_GITHUB_EXECUTION_PACKET.md` from common shelf
- added `REGULATION_INDEX.md` and `GATE_REGISTRY.md`
- added `G-21` full-file read and `G-22` large-file gates
- added `OUTPUT_PATHS.md`, `HOSTED_SETTINGS_BOUNDARY.md`, `AUDIT_MANIFEST_POLICY.md`
- added `tier2-defer-record.md.template`
- rewrote `README.md` with explicit folder purpose
- deprecated `APPLICATION_GUIDE.md` as reference-only

## Maintenance Rule

When regulation changes:

1. update gate files and `GATE_REGISTRY.md`
2. update `REGULATION_INDEX.md` if file membership changes
3. do not store project-specific results in this shelf