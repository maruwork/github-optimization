# GitHub Optimization

Status: Active

## このフォルダの目的

`common/github-optimization` は、**公開前リポジトリを担当 AI が自己判定するための共通レギュレーション棚**です。

人間がチェックリストを手で回すための資料ではありません。  
担当 AI にこのフォルダを渡し、対象リポジトリが規定に適合しているかを**証拠付きで判定させる**ためにあります。

## What This Folder Is For

This folder is the **generic regulation shelf** for public-repository self-check.

| Use | Description |
|---|---|
| Primary consumer | responsible AI for the target repository |
| Primary action | regulation self-check with executed evidence |
| Primary output | `audits/<repository-slug>/audit-report.md` in this shelf |
| Judgment surface | 46 gate items across Tier 1 / 2 / 3 |

## What This Folder Is Not

| Not for | Reason |
|---|---|
| public audit reports in product repos | audit results belong in `audits/<slug>/` here |
| live examples such as `VEIL_*` or `ADOP_*` | generic shelf only |
| human-operated checklist labor | agent executes evidence |
| copying this folder into public product repos | unless the product documents shared governance |

## One-Line Assignment

```text
C:\Users\f_tan\project\common\github-optimization を読み、対象リポジトリがこのレギュレーションに適合しているか自己判定せよ。証拠を実行し、audit-report を完成させよ。
```

Read first: `REGULATION_SELF_CHECK.md`

## Responsible AI Route

1. `REGULATION_INDEX.md` — required regulation files only
2. `AUDIT_RUNBOOK.md` — execution order
3. `AUDIT_RULES.md` — validity rules
4. `GATE_REGISTRY.md` — all 46 judgment items
5. `templates/audit-report.md.template` — output skeleton

Orchestrator: `scripts/run-full-audit.*` (shelf validate + scaffold + evidence)

Optional accelerators: `scripts/`, `audit.manifest.yml` in target repo

Human role: optional publication approval, not default command execution.

## Three Tiers

| Tier | Name | When required |
|---|---|---|
| 1 | Public-prep baseline | always |
| 2 | Release quality | `release` and `strict-product` audit modes |
| 3 | Product readiness | `strict-product` audit mode only |

| Audit mode | Tiers evaluated |
|---|---|
| `public-prep` | Tier 1 |
| `release` | Tier 1 + 2 |
| `strict-product` | Tier 1 + 2 + 3 |

Read: `SCOPE_AND_TIERS.md`

## Judgment Items

| Tier | Gate file | Count |
|---|---|---|
| 1 | `PUBLIC_PREP_GATE.md` | 22 |
| 2 | `RELEASE_QUALITY_GATE.md` | 14 |
| 3 | `PRODUCT_READINESS_GATE.md` | 10 |

Master list: `GATE_REGISTRY.md`

Final label: `FULL_AUDIT_VERDICT.md`

## Output Locations

The responsible AI writes into the target repository:

| Artifact | Default path |
|---|---|
| audit report | `audits/<slug>/audit-report.md` |
| publication decision record | `audits/<slug>/publication-decision-record.md` |
| Tier 2 defer record | `audits/<slug>/tier2-defer-record.md` |
| accepted risk record | `audits/<slug>/accepted-risk-record.md` |
| audit manifest | product repo root `audit.manifest.yml` only |

Read: `OUTPUT_PATHS.md`

## Regulation Scope

Required files: `REGULATION_INDEX.md`

Excluded from self-check:

- `domain-option/**` except when explicitly assigned
- `roadmap/**`, `design/**`, `tasks/**`
- project-specific execution records

`domain-option/` contains copy templates only. No live project examples belong here.

## Supporting Surfaces

| Area | Files |
|---|---|
| Classification | `REPO_CONTENT_CLASSIFICATION.md` |
| Tool decisions | `TOOL_VERIFICATION_MATRIX.md` |
| Hosted settings | `HOSTED_SETTINGS_BOUNDARY.md` |
| Quickstart automation | `AUDIT_MANIFEST_POLICY.md` |
| Waiver rules | `WAIVER_POLICY.md` |
| Subjective gate examples | `JUDGMENT_GUIDE.md` |
| Audit phase | `AUDIT_PHASE_POLICY.md` |
| Re-audit / delta audit | `RE_AUDIT_POLICY.md` |
| Multi-repository batch | `MULTI_REPO_ORCHESTRATION.md` |
| Shelf path resolution | `SHELF_PATH.md` |
| Tool review cadence | `TOOL_REVIEW_CADENCE.md` |
| Completeness proof | `REGULATION_COMPLETENESS.md` |
| Evidence commands | `EVIDENCE_COMMANDS.md` |
| Responsibility | `PUBLICATION_RESPONSIBILITY_MODEL.md` |
| Repair starters | `templates/*.template` |
| Checklists | `checklists/*.md` |

## Completion Standard

Self-check is complete when:

- all required regulation files in `REGULATION_INDEX.md` were used
- every `git ls-files` entry in the target repo was read or explicitly excepted (`G-21`)
- all 46 gate tables G / R / P are filled or marked `n/a` with reason
- evidence is attached
- waivers follow `WAIVER_POLICY.md`
- subjective gates follow `JUDGMENT_GUIDE.md`
- final label is assigned
- open Blockers are listed as fix tasks

Gap closure record: `REGULATION_COMPLETENESS.md`

## Shelf History

`roadmap/`, `design/`, `tasks/`, and `GITHUB_OPTIMIZATION_*_SUMMARY.md` record how this shelf was built.  
They are not part of the regulation itself.

Review cadence for tool recommendations: `TOOL_REVIEW_CADENCE.md`, `GITHUB_OPTIMIZATION_TOOL_VERIFICATION_SUMMARY.md`

Shelf self-check: `scripts/validate-regulation-index.*`, `scripts/tests/run-regulation-tests.*`

Distribution: `SHELF_DISTRIBUTION.md`, version `SHELF_VERSION.md`