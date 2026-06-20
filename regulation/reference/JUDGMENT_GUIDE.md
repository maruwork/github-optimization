# Judgment Guide

Status: Active

## Purpose

Reduce subjective drift for gates that are not simple file-existence checks.

Use with `regulation/gates/GATE_REGISTRY.md`. Facts still require evidence.

## G-02 vs G-21

| Gate | Question | Pass when |
|---|---|---|
| G-02 | was inventory captured? | `git ls-files` count and list reference exist |
| G-21 | was every file read? | read log table complete with no unreviewed rows |

Listing files is not the same as reading them.

## G-18 Code Scanning

| Result | When |
|---|---|
| `pass` | enabled and reviewed, or disabled with policy reason in matrix |
| `waived` | intentionally deferred with owner and revisit trigger |
| `blocked` | eligible repo with no decision recorded |

## R-02 CI Green

| Result | When |
|---|---|
| `pass` | latest default-branch CI evidence is scoped to `default_branch` and collector `r02_assessment` is `pass` |
| `waived` | not applicable - CI failure cannot be waived in `release` or `strict-product` |
| `blocked` | collector `r02_assessment` is `blocked` and no accepted-risk record exists |

Accepted-risk record must name owner, reason, and fix deadline.

Collector `r02_assessment=review` is not itself a gate result.
It means the raw latest-CI status is insufficient to score `blocked` yet.
Before scoring, confirm the run scope and failure type from the same transcript row:

- `evidence_scope=default_branch` or explicit manual confirmation that the run is the relevant default-branch release signal
- `selected_workflow_path` plus `workflow_selection` explains why this workflow was treated as the primary CI signal
- `workflow_selection=hosted_workflow_inventory` requires a cited hosted workflow inventory row that names the selected workflow path
- `workflow_selection=all_runs_fallback` requires a note explaining why no narrower workflow selection was available
- `classification=branch_filter_candidate` means do not score `blocked` from status alone; confirm trigger filters and whether the run is a real default-branch CI failure
- `classification=startup_failure_candidate` means confirm whether the failure is a real job failure or a zero-job / orchestration artifact before scoring
- `classification=in_progress`, `non_blocking`, or `unknown` means `R-02` still needs explicit reviewer judgment and cannot be scored `pass` from the raw collector row alone

Recommended scoring flow:

1. If `r02_assessment=pass`, score `R-02` `pass` from the cited hosted transcript.
2. If `r02_assessment=blocked`, score `R-02` `blocked` unless an accepted-risk record explicitly covers the failing run.
3. If `r02_assessment=review`, do not score `blocked` yet. Confirm branch scope, workflow trigger filters, job count, and run URL first, then score `pass` or `blocked` with a note.

Classification guardrails:

1. `branch_filter_candidate`: keep `review` unless the note explicitly states that branch filters do not explain the run and the run still represents the intended release signal.
2. `startup_failure_candidate`: keep `review` unless the note explicitly states that real jobs should have started and the failure is not a zero-job orchestration artifact.
3. `all_runs_fallback`: do not score `pass` or `blocked` without a note explaining why fallback evidence is still representative.
4. `hosted_workflow_inventory`: acceptable when the hosted workflow inventory transcript names the selected workflow and local selection was absent or insufficient.

Minimum note content for a final `R-02` reviewer override:

1. state whether the evaluated run is default-branch evidence or a recent-runs fallback
2. state the selected workflow path and selection reason (`manifest_override`, `explicit_ci_filename`, `single_local_workflow`, `heuristic_local_workflow`, `hosted_workflow_inventory`, or `all_runs_fallback`)
3. state whether workflow trigger filters explain the observed run
4. state the cited job count and duration
5. cite the run URL or ID used for the decision

Write `audits/<repository-slug>/accepted-risk-record.md` from `templates/accepted-risk-record.md.template` and cite it in the audit report Evaluation section.

## R-09 Quickstart

| Result | When |
|---|---|
| `pass` | execution transcript shows end-to-end success |
| `blocked` | README command fails, or shorthand hides real entry path |

Common Major finding: README uses `tool` alias but only `python path/to/cli.py` works.

## P-05 Docs / Runtime Mismatch

Score `blocked` when any of these are true:

- README documents output format that CLI does not produce
- README omits required flag that validation enforces
- version in docs/changelog/runtime disagree without explicit unreleased note
- design doc states required behavior that code path does not implement and no waiver exists

Score `pass` when mismatches are absent or every mismatch has an explicit waiver.

Evidence format: `file:line` for both sides.

## P-08 Platform Support

| Result | When |
|---|---|
| `pass` | CI matrix matches README claim, or README documents unsupported platforms |
| `blocked` | README implies Windows support but Windows CI is red and no caveat exists |

## P-03 README Render

| Result | When |
|---|---|
| `pass` | Setup and Quickstart fences and headings render correctly |
| `blocked` | prose merged into code fence, broken list, or missing newline after closing fence |

Evidence: `README.md:line` excerpt.
