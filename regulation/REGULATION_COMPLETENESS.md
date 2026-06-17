# Regulation Completeness

Status: Active

## Purpose

Record that previously identified gaps in this shelf are closed.

Use this file to confirm the regulation set is complete for agent self-check.

## Gap Closure Matrix

| Previous gap | Resolution | File |
|---|---|---|
| no single regulation index | required/excluded file list | `regulation/REGULATION_INDEX.md` |
| ambiguous read scope | excluded history and domain examples | `regulation/REGULATION_INDEX.md` |
| G-02 confused with full read | split inventory vs read | `G-21`, `regulation/reference/JUDGMENT_GUIDE.md` |
| large-file check not gated | added gate | `G-22`, `regulation/reference/EVIDENCE_COMMANDS.md` |
| output path undefined | shelf `audits/<slug>/` paths | `regulation/shelf/OUTPUT_PATHS.md`, `audits/README.md` |
| Tier 2 defer undefined | defer record template | `templates/tier2-defer-record.md.template` |
| hosted settings boundary unclear | verify/recommend/waive model | `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md` |
| audit.manifest policy weak | repeat-audit contract | `regulation/reference/AUDIT_MANIFEST_POLICY.md` |
| subjective gates drift | examples and pass rules | `regulation/reference/JUDGMENT_GUIDE.md` |
| waiver inconsistency | unified policy | `regulation/reference/WAIVER_POLICY.md` |
| judgment items scattered | 46-item registry | `regulation/gates/GATE_REGISTRY.md` |
| domain examples in generic shelf | removed; template only | `domain-option/README.md` |
| README purpose unclear | explicit folder role | `README.md` |
| hardcoded script path | resolution order | `regulation/shelf/SHELF_PATH.md` |
| APPLICATION_GUIDE duplication | deprecated pointer | `APPLICATION_GUIDE.md` |
| no accepted-risk template | R-02 supporting record | `templates/accepted-risk-record.md.template` |
| no re-audit policy | repeat and delta rules | `regulation/execution/RE_AUDIT_POLICY.md` |
| pre-public vs post-public unclear | phase policy | `regulation/execution/AUDIT_PHASE_POLICY.md` |
| multi-repo batch undefined | one-repo-per-report orchestration | `regulation/execution/MULTI_REPO_ORCHESTRATION.md` |
| shelf index not self-validated | index validator scripts | `scripts/validate-regulation-index.*` |
| no end-to-end orchestrator | scaffold + evidence runner | `scripts/run-full-audit.*` |
| regulation scripts untested | regression test runner | `scripts/tests/run-regulation-tests.*` |
| tool review cadence informal | scheduled review policy | `regulation/reference/TOOL_REVIEW_CADENCE.md` |
| shelf portability undefined | standalone distribution policy | `regulation/shelf/SHELF_DISTRIBUTION.md` |
| shelf version untracked | version and changelog files | `regulation/shelf/SHELF_VERSION.md`, `regulation/shelf/SHELF_CHANGELOG.md` |
| orchestrator not dry-run tested | fixture + shelf dry-run tests | `scripts/tests/fixtures/minimal-docs-repo/` |
| shelf root policy files missing | LICENSE SECURITY CHANGELOG CONTRIBUTING | root policy files |
| shelf CI missing | regulation-tests workflow | `.github/workflows/regulation-tests.yml` |
| shelf meta-audit missing | self-audit report | `audits/github-optimization/audit-report.md` (local, gitignored) |
| gitleaks stderr noise on PowerShell | normalized native stderr lines | `collect-audit-evidence.ps1` |

## Completeness Checklist

- [x] entry instruction exists
- [x] regulation index exists
- [x] 46 gate IDs exist
- [x] audit runbook exists
- [x] audit rules exist
- [x] agent execution model exists
- [x] output paths exist
- [x] waiver policy exists
- [x] judgment guide exists
- [x] all checklists map to gate IDs
- [x] audit report template covers all G/R/P gates
- [x] evidence scripts cover G-01 G-22 baseline and hosted metadata
- [x] no project-specific live records remain in this shelf
- [x] accepted-risk output template exists
- [x] re-audit and audit-phase policies exist
- [x] multi-repository orchestration policy exists
- [x] shelf index validator exists
- [x] full-audit orchestrator exists
- [x] regulation script regression tests exist
- [x] tool review cadence policy exists
- [x] shelf distribution and version files exist
- [x] run-full-audit dry-run tests exist
- [x] shelf root publication policy files exist
- [x] shelf CI workflow exists
- [x] shelf self-audit report exists
- [x] gitleaks evidence script is PowerShell-clean

## Remaining Non-Goals

This shelf still does not:

- fix target repositories automatically
- operate GitHub web UI
- replace project-specific product roadmaps

Those are outside regulation completeness.