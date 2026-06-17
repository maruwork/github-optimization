# GitHub Optimization

Status: Active

Shelf version: `1.1.13` (`regulation/shelf/SHELF_VERSION.md`)

## What This Repository Is

Generic **regulation shelf** for public-repository self-check.

The responsible AI reads this shelf, executes evidence against a target repository, scores 46 gates, and writes results under `audits/<repository-slug>/` on disk. This is not a human-operated checklist.

| Role | Action |
|---|---|
| Responsible AI | read regulation, run scripts, score gates, write audit artifacts |
| Human | optional publication approval; not default command execution |

## What This Repository Is Not

| Not for | Reason |
|---|---|
| audit reports in product repos | scored artifacts belong in `audits/<slug>/` here |
| live project examples (`VEIL_*`, `ADOP_*`, …) | generic shelf only; see `domain-option/` templates |
| copying this folder into public product repos | unless the product documents shared governance |
| filled records under `docs/governance/` | pointer only; canonical path is `audits/<slug>/` |

## Start Here

1. `regulation/REGULATION_SELF_CHECK.md` — assignment to the responsible AI
2. `regulation/REGULATION_INDEX.md` — required regulation files
3. `regulation/execution/AUDIT_RUNBOOK.md` — execution order
4. `regulation/gates/GATE_REGISTRY.md` — all 46 judgment items
5. `templates/audit-report.md.template` — output skeleton

One-line assignment:

```text
Read $GITHUB_OPTIMIZATION_ROOT (or ../github-optimization relative to the target repo), self-assess whether the target repository complies with this regulation, execute evidence, and complete the audit report.
```

## Execution Pipeline

Run in this order unless `RE_AUDIT_POLICY.md` limits scope to a delta.

| Step | Script | Purpose |
|---|---|---|
| 1 | `scripts/run-full-audit.*` | shelf validate + scaffold + evidence (orchestrator) |
| 2 | `scripts/validate-regulation-index.*` | required-file index check (shelf self-proof) |
| 3 | `scripts/collect-audit-evidence.*` | machine evidence bundle |
| 4 | `scripts/check-tracked-files.*` | unnecessary tracked-file screening (`G-03`, `G-21`) |
| 5 | `scripts/check-gitignore-consistency.*` | tracked vs `.gitignore` consistency (`G-04`) |
| 6 | `scripts/run-audit-quickstart.*` | `audit.manifest.yml` quickstart (`R-08`, `R-09`) |
| 7 | `scripts/run-delta-audit.*` | delta re-audit when prior report exists |

Script reference and usage examples: `scripts/README.md`

Regression tests after shelf edits:

```powershell
.\scripts\tests\run-regulation-tests.ps1
```

```bash
./scripts/tests/run-regulation-tests.sh
```

## Audit Modes And Tiers

| Tier | Gate file | Count | When required |
|---|---|---|---|
| 1 | `regulation/gates/PUBLIC_PREP_GATE.md` | 22 | always |
| 2 | `regulation/gates/RELEASE_QUALITY_GATE.md` | 14 | `release`, `strict-product` |
| 3 | `regulation/gates/PRODUCT_READINESS_GATE.md` | 10 | `strict-product` only |

| Audit mode | Tiers evaluated |
|---|---|
| `public-prep` | Tier 1 |
| `release` | Tier 1 + 2 |
| `strict-product` | Tier 1 + 2 + 3 |

Read: `regulation/execution/SCOPE_AND_TIERS.md`

Final label: `regulation/gates/FULL_AUDIT_VERDICT.md`

## Repository Layout

```text
README.md, LICENSE, SECURITY.md, CHANGELOG.md, …   # entry and shelf metadata
audit.manifest.yml                                 # shelf self-check quickstart only
regulation/                                        # all regulation text
checklists/  templates/  scripts/
docs/governance/README.md                          # pointer; no filled records
audits/                                            # local audit results (gitignored)
.github/workflows/regulation-tests.yml           # shelf CI
domain-option/                                     # copy templates only (excluded from regulation)
```

## Output Locations

The responsible AI writes audit artifacts under `audits/<slug>/` in this shelf. Do not write scored audit reports into public product repositories.

| Artifact | Path |
|---|---|
| audit report | `audits/<slug>/audit-report.md` |
| delta audit record | `audits/<slug>/delta-audit-record.md` |
| publication decision record | `audits/<slug>/publication-decision-record.md` |
| Tier 2 defer record | `audits/<slug>/tier2-defer-record.md` |
| accepted risk record | `audits/<slug>/accepted-risk-record.md` |
| GitHub execution packet | `audits/<slug>/github-execution-packet.md` |
| audit quickstart manifest | `<product-repo-root>/audit.manifest.yml` (product repos only) |
| governance pointer | `docs/governance/README.md` (this shelf; not a filled record) |

Read: `regulation/shelf/OUTPUT_PATHS.md`, `audits/README.md`

## Quickstart Contract (`R-08`, `R-09`)

| Target | Quickstart source |
|---|---|
| Product repository | `audit.manifest.yml` at product root (`templates/audit.manifest.yml.template`) |
| No manifest | agent derives commands from product `README.md` and records transcript |
| This shelf (self-check) | root `audit.manifest.yml` runs validate-index, tracked-file screening, gitignore consistency |

Manifest fields: `run_windows` / `run_unix` per `regulation/reference/AUDIT_MANIFEST_POLICY.md`

## Regulation Scope

Required files: `regulation/REGULATION_INDEX.md`

Excluded from self-check unless explicitly assigned:

- `domain-option/**`
- `roadmap/**`, `design/**`, `tasks/**`
- project-specific execution records

## Reference Map

| Topic | File |
|---|---|
| Agent execution model | `regulation/execution/AGENT_EXECUTION_MODEL.md` |
| Validity rules | `regulation/execution/AUDIT_RULES.md` |
| Audit phase | `regulation/execution/AUDIT_PHASE_POLICY.md` |
| Re-audit / delta | `regulation/execution/RE_AUDIT_POLICY.md` |
| Multi-repo batch | `regulation/execution/MULTI_REPO_ORCHESTRATION.md` |
| Repo classification | `regulation/reference/REPO_CONTENT_CLASSIFICATION.md` |
| Tracked-file screening | `regulation/reference/TRACKED_FILE_SCREENING.md` |
| Gitignore consistency | `regulation/reference/GITIGNORE_CONSISTENCY.md` |
| Tool decisions | `regulation/reference/TOOL_VERIFICATION_MATRIX.md` |
| Tool review cadence | `regulation/reference/TOOL_REVIEW_CADENCE.md` |
| Evidence commands | `regulation/reference/EVIDENCE_COMMANDS.md` |
| Hosted settings | `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md` |
| Quickstart policy | `regulation/reference/AUDIT_MANIFEST_POLICY.md` |
| Waivers | `regulation/reference/WAIVER_POLICY.md` |
| Subjective gates | `regulation/reference/JUDGMENT_GUIDE.md` |
| Publication responsibility | `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md` |
| Shelf path | `regulation/shelf/SHELF_PATH.md` |
| Distribution | `regulation/shelf/SHELF_DISTRIBUTION.md` |
| Completeness proof | `regulation/REGULATION_COMPLETENESS.md` |
| Repair starters | `templates/*.template`, `checklists/*.md` |

## Completion Standard

Self-check is complete when:

- every file in `regulation/REGULATION_INDEX.md` Required set was used
- every `git ls-files` entry in the target repo was read or explicitly excepted (`G-21`)
- all 46 gate tables (`G` / `R` / `P`) are filled or marked `n/a` with reason
- machine evidence is attached
- waivers follow `regulation/reference/WAIVER_POLICY.md`
- subjective gates follow `regulation/reference/JUDGMENT_GUIDE.md`
- final label is assigned via `FULL_AUDIT_VERDICT.md`
- open Blockers are listed as fix tasks

## GitHub Remote Scope

The public remote keeps **regulation files only**:

- gates, policies, checklists, templates, scripts, CI
- not audit results (`audits/**` is gitignored except `audits/README.md`)
- not shelf build history (`design/`, `roadmap/`, `tasks/`)

Shelf self-check: `scripts/validate-regulation-index.*`, `scripts/tests/run-regulation-tests.*`

Distribution and versioning: `regulation/shelf/SHELF_DISTRIBUTION.md`, `regulation/shelf/SHELF_CHANGELOG.md`