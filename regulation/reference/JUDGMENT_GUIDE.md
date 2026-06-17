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
| `pass` | latest default-branch run is success |
| `waived` | not applicable — CI failure cannot be waived in `release` or `strict-product` |
| `blocked` | latest run failed and no accepted-risk record exists |

Accepted-risk record must name owner, reason, and fix deadline.

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