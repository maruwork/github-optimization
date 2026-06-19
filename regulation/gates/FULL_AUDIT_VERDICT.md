# Full Audit Verdict

Status: Active

## Purpose

Convert Tier 1, Tier 2, and Tier 3 gate results into one final label.

Use after `regulation/execution/AUDIT_RUNBOOK.md` Steps 7 to 10.

Gate count: 46 (`regulation/gates/GATE_REGISTRY.md`)
Waiver rules: `regulation/reference/WAIVER_POLICY.md`

## Gate Inputs

| Tier | Source | Required for |
|---|---|---|
| 1 | `regulation/gates/PUBLIC_PREP_GATE.md` | all modes |
| 2 | `regulation/gates/RELEASE_QUALITY_GATE.md` | `release`, `strict-product` |
| 3 | `regulation/gates/PRODUCT_READINESS_GATE.md` | `strict-product` only |

## Verdict Labels

| Label | Meaning |
|---|---|
| `PUBLIC_PREP_BLOCKED` | Tier 1 has any `blocked` row |
| `PUBLIC_PREP_PASS` | Tier 1 complete; Tier 2 not evaluated or whole Tier 2 deferred |
| `RELEASE_READY` | Tier 1 pass and Tier 2 pass |
| `RELEASE_BLOCKED` | Tier 1 pass but Tier 2 has applicable `blocked` row |
| `STRICT_PRODUCT_PASS` | Tier 1 pass, Tier 2 pass, Tier 3 pass |
| `STRICT_PRODUCT_BLOCKED` | Tier 1 and Tier 2 pass, but Tier 3 has `blocked` row |

## Decision Table

| Tier 1 | Tier 2 | Tier 3 | Final label |
|---|---|---|---|
| blocked | any | any | `PUBLIC_PREP_BLOCKED` |
| pass | blocked | not evaluated | `RELEASE_BLOCKED` |
| pass | deferred (whole tier) | not evaluated | `PUBLIC_PREP_PASS` |
| pass | pass | not evaluated | `RELEASE_READY` |
| pass | pass | blocked | `STRICT_PRODUCT_BLOCKED` |
| pass | pass | pass | `STRICT_PRODUCT_PASS` |

Notes:

- whole Tier 2 `DEFERRED` keeps final label at `PUBLIC_PREP_PASS`
- `RELEASE_READY` requires Tier 2 `PASS`, not deferred
- mixed Tier 2 states should be resolved to one tier verdict before using this table

## Evaluation Wording

Use plain-language evaluation after gate labels:

| Final label | Typical evaluation |
|---|---|
| `PUBLIC_PREP_BLOCKED` | not ready for public release |
| `PUBLIC_PREP_PASS` | public GitHub surface is substantially ready; release discipline not fully verified |
| `RELEASE_BLOCKED` | public surface acceptable, but release evidence incomplete |
| `RELEASE_READY` | suitable for public release of a runnable tool with current release evidence |
| `STRICT_PRODUCT_BLOCKED` | public and release acceptable, but strict market-ready standard not met |
| `STRICT_PRODUCT_PASS` | strict market-ready standard met at audit time |

## Required Final Section

Every finished audit report must end with:

```text
Audit mode:
Tier 1 gate:
Tier 2 gate:
Tier 3 gate:
Final label:
Open Blockers:
Open Majors:
Facts confidence: high | medium | low
```

`Facts confidence: low` is mandatory when full-file read or execution evidence is incomplete.
