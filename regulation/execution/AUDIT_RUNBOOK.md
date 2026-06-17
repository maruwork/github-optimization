# Audit Runbook

Status: Active

## Purpose

One route from start to finished audit report.

If you follow this runbook to completion, the audit is done except for fixes in the target repository.

## Start Here

1. Validate the regulation shelf with `scripts/validate-regulation-index.*` (or use `scripts/run-full-audit.*`, which runs this first)
2. Read `regulation/REGULATION_INDEX.md`
3. Read `regulation/execution/AGENT_EXECUTION_MODEL.md` and `regulation/execution/AUDIT_RULES.md`
4. Determine audit phase with `regulation/execution/AUDIT_PHASE_POLICY.md` (`pre-public` | `post-public`)
5. If a prior audit report exists, read `regulation/execution/RE_AUDIT_POLICY.md`
6. Determine repository slug (`adop`, `veil`, etc.) for output paths
7. Create `audits/<repository-slug>/` under this shelf if needed
8. Copy `templates/audit-report.md.template` to `audits/<repository-slug>/audit-report.md` unless orchestrator already scaffolded it
9. Fill the report as the agent completes each step below

References:

- `regulation/shelf/OUTPUT_PATHS.md`
- `regulation/shelf/SHELF_PATH.md`
- `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`
- `regulation/reference/AUDIT_MANIFEST_POLICY.md`
- `regulation/execution/MULTI_REPO_ORCHESTRATION.md`
- `regulation/reference/TOOL_REVIEW_CADENCE.md`
- `regulation/gates/GATE_REGISTRY.md`
- `regulation/reference/JUDGMENT_GUIDE.md`
- `regulation/reference/WAIVER_POLICY.md`

## Inputs

Record before Step 1:

- repository local path
- hosted URL (`owner/repo`)
- audit date
- executor (`agent:<name>` by default)
- audit mode: `public-prep` | `release` | `strict-product`
- audit phase: `pre-public` | `post-public`

| Mode | Required tiers |
|---|---|
| `public-prep` | Tier 1 only |
| `release` | Tier 1 + Tier 2 |
| `strict-product` | Tier 1 + Tier 2 + Tier 3 |

## Step 1 — Inventory (`G-02`)

```bash
git ls-files
git ls-files | wc -l
git rev-parse HEAD
git describe --tags --always
```

## Step 2 — Full file read (`G-21`)

Walk `checklists/repository-file-review-checklist.md`.

**Stop rule:** do not write code/content findings until `G-21` prerequisites are complete.

## Step 3 — Machine evidence (`G-01`, `G-22`, Tier 2 baseline)

Resolve shelf path per `regulation/shelf/SHELF_PATH.md`, then from repository root.

Preferred orchestrator:

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) { $env:GITHUB_OPTIMIZATION_ROOT } elseif (Test-Path "..\github-optimization") { (Resolve-Path "..\github-optimization").Path } else { "C:\Users\f_tan\project\github-optimization" }
& "$Shelf\scripts\run-full-audit.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo -AuditMode release -AuditPhase pre-public
```

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
"$SHELF/scripts/run-full-audit.sh" . owner/repo release pre-public
```

Evidence only:

```powershell
& "$Shelf\scripts\collect-audit-evidence.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo
```

```bash
"$SHELF/scripts/collect-audit-evidence.sh" . owner/repo
```

Paste output into the audit report Evidence section.

Quickstart (`R-08`, `R-09`):

- if `audit.manifest.yml` exists, evidence script runs `run-audit-quickstart`
- if not, derive commands from `README.md`, execute, record transcript
- after first successful runnable-tool audit, add `audit.manifest.yml`

## Step 4 — Tier 1 local checks (`G-01`…`G-12`, `G-22`)

Walk `regulation/reference/REPO_CONTENT_CLASSIFICATION.md` and `checklists/local-public-prep-checklist.md`.

## Step 5 — Tier 1 hosted checks (`G-13`…`G-19`)

Walk `regulation/reference/TOOL_VERIFICATION_MATRIX.md`, `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`, and `checklists/github-settings-checklist.md`.

## Step 6 — Publication responsibility (`G-20`)

Walk `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md` and `checklists/publication-decision-checklist.md`.

Write or verify `audits/<repository-slug>/publication-decision-record.md`.

## Step 7 — Tier 1 verdict

Score all Tier 1 rows in `regulation/gates/PUBLIC_PREP_GATE.md`.

If any row is `blocked`, final verdict cannot exceed `PUBLIC_PREP_BLOCKED`.

## Step 8 — Tier 2 release quality (`R-01`…`R-14`)

Required when audit mode is `release` or `strict-product`.

Walk `checklists/release-quality-checklist.md` and score `regulation/gates/RELEASE_QUALITY_GATE.md`.

If entire Tier 2 is deferred, write `audits/<repository-slug>/tier2-defer-record.md`.

Whole Tier 2 defer is invalid for `strict-product`.

## Step 9 — Tier 3 product readiness (`P-01`…`P-10`)

Required only when audit mode is `strict-product`.

Walk `checklists/product-readiness-checklist.md`, `regulation/reference/JUDGMENT_GUIDE.md`, and score `regulation/gates/PRODUCT_READINESS_GATE.md`.

## Step 10 — Final verdict

Apply `regulation/gates/FULL_AUDIT_VERDICT.md` and `regulation/reference/WAIVER_POLICY.md`.

Write facts, gate tables, evaluation, final label, and fix tasks.

## Finished Means

- [ ] `G-21` read log complete
- [ ] machine evidence attached
- [ ] Tier 1 table complete (`G-01`…`G-22`)
- [ ] Tier 2 table complete or `tier2-defer-record.md` exists
- [ ] Tier 3 table complete when mode is `strict-product`
- [ ] final label assigned
- [ ] every `blocked` row has a fix task

Completeness reference: `regulation/REGULATION_COMPLETENESS.md`

## What This Runbook Does Not Do

- fix the target repository
- publish the repository
- replace project-specific product roadmap decisions outside the gate tables