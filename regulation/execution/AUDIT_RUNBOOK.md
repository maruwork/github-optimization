# Audit Runbook

Status: Active

## Purpose

One route from start to finished audit report.

If you follow this runbook to completion, the audit is done except for fixes in the target repository.

## Start Here

1. Validate the regulation shelf with `scripts/validate-regulation-index.*` or use `scripts/run-full-audit.*`, which runs this first.
2. Read `regulation/REGULATION_INDEX.md`.
3. Read `regulation/execution/AGENT_EXECUTION_MODEL.md` and `regulation/execution/AUDIT_RULES.md`.
4. Determine audit phase with `regulation/execution/AUDIT_PHASE_POLICY.md` (`pre-public` | `post-public`).
5. If a prior audit report exists, read `regulation/execution/RE_AUDIT_POLICY.md`.
6. Determine repository slug (`adop`, `veil`, etc.) for output paths.
7. Create `audits/<repository-slug>/` under this shelf if needed.
8. Copy `templates/audit-report.md.template` to `audits/<repository-slug>/audit-report.md` unless orchestrator already scaffolded it.
9. Fill the report as the agent completes each step below.

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

- repository slug or display name
- hosted URL (`owner/repo`)
- audit date
- executor (`agent:<name>` by default)
- audit mode: `public-prep` | `release` | `strict-product`
- audit phase: `pre-public` | `post-public`

Do not copy machine-local absolute paths into tracked or shareable artifacts.

| Mode | Required tiers |
|---|---|
| `public-prep` | Tier 1 only |
| `release` | Tier 1 + Tier 2 |
| `strict-product` | Tier 1 + Tier 2 + Tier 3 |

## Step 1 - Inventory (`G-02`)

```bash
git ls-files
git ls-files | wc -l
git rev-parse HEAD
git describe --tags --always
```

## Step 2 - Full file read (`G-21`)

Walk `checklists/repository-file-review-checklist.md`.

Stop rule: do not write code or content findings until `G-21` prerequisites are complete.

Before final scoring, the report must contain:

- `## Read Log`
- `### Read Exceptions`
- `### Read Coverage`

If any path was not fully read, record it explicitly in `### Read Exceptions`.

## Step 3 - Machine evidence (`G-01`, `G-22`, Tier 2 baseline)

Resolve shelf path per `regulation/shelf/SHELF_PATH.md`, then run from repository root.

Preferred orchestrator:

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) { $env:GITHUB_OPTIMIZATION_ROOT } elseif (Test-Path "..\github-optimization") { (Resolve-Path "..\github-optimization").Path } else { throw "Set GITHUB_OPTIMIZATION_ROOT or clone github-optimization next to the target repo" }
& "$Shelf\scripts\run-full-audit.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo -AuditMode release -AuditPhase pre-public
```

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
"$SHELF/scripts/run-full-audit.sh" . owner/repo release pre-public
```

The orchestrator is not the final scorer.
Exit `0` from `run-full-audit.*` means shelf validation, report scaffold, and machine-evidence collection completed.
The audit is still unfinished until the agent completes read coverage, transcript mapping, gate scoring, waivers, and final label assignment.

Evidence only:

```powershell
& "$Shelf\scripts\collect-audit-evidence.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo
```

```bash
"$SHELF/scripts/collect-audit-evidence.sh" . owner/repo
```

Store the raw collector output in `## Machine Evidence Bundle`.
`collect-audit-evidence.*` exits non-zero when it prints any real `result: BLOCKED` row, but it still attempts to print the full transcript first.
`result: SKIPPED` is reserved for non-scoring execution-environment artifacts and does not by itself make the collector fail.

Then fill:

- `## Evidence Index`
- `## Local Command Transcripts`
- `## Hosted Transcripts`
- `## Quickstart Transcript`

Do not replace these sections with prose summary alone.
Each scored runtime, quickstart, and hosted claim must point to an explicit transcript row.

If the raw collector blocks because the current execution environment cannot execute a tool or cannot read the caller's hosted CLI state:

- preserve that raw bundle exactly as collected
- rerun the affected check through another agent-executable route when available
- score the gate from the successful transcript row, not from the raw blocked bundle alone
- add a short note that the blocked raw result was an execution-environment artifact rather than a repository defect

For Windows collector evidence, prefer a normal Windows PowerShell host terminal as the authoritative route.
If a managed sandbox reports a WinGet `gitleaks.exe` path as a directory but the host terminal transcript passes, keep both records and score from the host-terminal transcript.

If `gitleaks` is unavailable, do not score `G-01` `pass`.
Record the missing-tool state and treat Tier 1 as blocked until a baseline secret-scan transcript exists.

Quickstart (`R-08`, `R-09`):

- if `audit.manifest.yml` exists, evidence script runs `run-audit-quickstart`
- if not, derive commands from `README.md`, execute, record transcript
- after first successful runnable-tool audit, add `audit.manifest.yml`

## Step 4 - Tier 1 local checks (`G-01` to `G-12`, `G-22`)

Walk `regulation/reference/REPO_CONTENT_CLASSIFICATION.md` and `checklists/local-public-prep-checklist.md`.

## Step 5 - Tier 1 hosted checks (`G-13` to `G-19`)

Walk `regulation/reference/TOOL_VERIFICATION_MATRIX.md`, `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`, and `checklists/github-settings-checklist.md`.

When GitHub Community Profile omits issue-template evidence, verify `G-11` from hosted repository contents and issue-enablement state.

## Step 6 - Publication responsibility (`G-20`)

Walk `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md` and `checklists/publication-decision-checklist.md`.

Write or verify `audits/<repository-slug>/publication-decision-record.md`.

## Step 7 - Tier 1 verdict

Score all Tier 1 rows in `regulation/gates/PUBLIC_PREP_GATE.md`.

If any row is `blocked`, final verdict cannot exceed `PUBLIC_PREP_BLOCKED`.

## Step 8 - Tier 2 release quality (`R-01` to `R-14`)

Required when audit mode is `release` or `strict-product`.

Walk `checklists/release-quality-checklist.md` and score `regulation/gates/RELEASE_QUALITY_GATE.md`.

For `R-02`, start from the collector `Latest CI` row rather than the raw `conclusion` alone.
Use these fields together:

- `evidence_scope`
- `default_branch`
- `classification`
- `r02_assessment`
- `r02_reason`
- `selected_workflow_path`
- `workflow_selection`

Scoring rule:

- if `r02_assessment=pass`, score `R-02` `pass` after citing the hosted transcript row
- if `r02_assessment=blocked`, score `R-02` `blocked` unless an accepted-risk record explicitly covers the failing run
- if `r02_assessment=review`, do not score `blocked` from the raw row alone; confirm branch scope, trigger filters, job count, and run URL first, then score `pass` or `blocked` with a note

Reviewer checklist for `r02_assessment=review`:

- confirm the evaluated run is the intended default-branch release signal, or write why a recent-runs fallback still supports the gate call
- record the selected workflow path and whether it came from `manifest_override`, `explicit_ci_filename`, `single_local_workflow`, `heuristic_local_workflow`, `hosted_workflow_inventory`, or `all_runs_fallback`
- if `workflow_selection=manifest_override`, cite the matching `audit.manifest.yml` line in the report
- if `workflow_selection=hosted_workflow_inventory`, cite the hosted workflow inventory transcript row that selected the workflow and note that local workflow selection was absent or insufficient
- if `workflow_selection=all_runs_fallback`, write why no narrower workflow selection was available before treating the run as the release signal
- record whether workflow branch filters explain a zero-job run before treating `startup_failure` as a real CI failure
- record job count and duration from the same row so `0 jobs` / `<=10s` orchestration artifacts stay distinguishable from test failures
- cite the run URL or run ID used for the final judgment
- if `classification=branch_filter_candidate` or `startup_failure_candidate`, default to `review` until the above checks are written in the report

Decision guardrails:

- do not score `blocked` from `classification=branch_filter_candidate` unless the report explicitly states that workflow trigger filters do not explain the zero-job run and the cited run is still the intended default-branch release signal
- do not score `blocked` from `classification=startup_failure_candidate` unless the report explicitly states that the run should have started real jobs and the failure is not a zero-job orchestration artifact
- do not score `pass` from `workflow_selection=all_runs_fallback` unless the report explicitly states why the fallback run is still representative of the repository's release signal
- `workflow_selection=hosted_workflow_inventory` is acceptable evidence only when the hosted transcript names the selected workflow path or filename

If entire Tier 2 is deferred, write `audits/<repository-slug>/tier2-defer-record.md`.

Whole Tier 2 defer is invalid for `strict-product`.

## Step 9 - Tier 3 product readiness (`P-01` to `P-10`)

Required only when audit mode is `strict-product`.

Walk `checklists/product-readiness-checklist.md`, `regulation/reference/JUDGMENT_GUIDE.md`, and score `regulation/gates/PRODUCT_READINESS_GATE.md`.

## Step 10 - Final verdict

Apply `regulation/gates/FULL_AUDIT_VERDICT.md` and `regulation/reference/WAIVER_POLICY.md`.

Write facts, gate tables, evaluation, final label, and fix tasks.

## Finished Means

- [ ] `G-21` read log complete
- [ ] read exceptions explicitly recorded or `none`
- [ ] read coverage recorded
- [ ] evidence index complete for every scored runtime, quickstart, and hosted claim
- [ ] machine evidence bundle attached
- [ ] local command transcripts stored with command, workdir, env, exit, excerpt
- [ ] hosted transcripts stored with command, workdir, env, exit, excerpt
- [ ] quickstart transcript stored with source, command, workdir, env, exit, excerpt
- [ ] Tier 1 table complete (`G-01` to `G-22`)
- [ ] Tier 2 table complete or `tier2-defer-record.md` exists
- [ ] Tier 3 table complete when mode is `strict-product`
- [ ] final label assigned
- [ ] every `blocked` row has a fix task

Completeness reference: `regulation/REGULATION_COMPLETENESS.md`

## What This Runbook Does Not Do

- fix the target repository
- publish the repository
- replace project-specific product roadmap decisions outside the gate tables
