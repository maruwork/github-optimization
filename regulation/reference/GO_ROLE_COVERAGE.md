# GO Role Coverage

Status: Active

## Purpose

Audit whether the current `G/R/P` gate set actually covers the roles listed in `README.md` and formalized in `GO_ROLE_CRITERIA.md`.

This file answers three questions for each role:

- is the current gate set sufficient?
- is checklist or wording reinforcement still needed?
- would a new gate be justified?

## Coverage Status

| GO role | Current coverage | Judgment | Next action |
|---|---|---|---|
| ready for GitHub publication | direct gate coverage through Tier 1/2/3 verdict surfaces and `G-20` publication record | sufficient | no new gate |
| only user-needed material is exposed | covered by tracked-file inventory, tracked-file screening, gitignore consistency, full read, and large-file scan | sufficient after exception narrowing in `GO_ROLE_CRITERIA.md` | no new gate |
| unnecessary files and leftovers are caught before release | covered by `G-01`, `G-03`, `G-04`, `G-22` plus evidence scripts | sufficient | no new gate |
| the repository communicates its usefulness effectively | covered by `G-05`, `G-13`, `G-14`, `P-06`, `R-08`, `R-10`, `R-11`, `P-03` after wording and checklist reinforcement | sufficient | no new gate |
| setup and quickstart actually work | covered directly by `R-08` through `R-13`, with `P-02`, `P-03`, `P-08` for strict-product claims | sufficient | no new gate |
| publication evidence is repeatable | covered indirectly by audit validity rules, evidence commands, hosted boundary, `R-08`, `R-09`, `R-14`, `G-02`, `G-21`; enforced through explicit evidence-bundle and transcript rules rather than a single gate | sufficient as audit-validity rule | no product gate; keep as audit validity rule |
| audit outputs stay outside the product repository | covered by output-path policy and tracked-file screening rules that block misplaced audit outputs | sufficient | no new gate |
| repeat audits are supported | covered as shelf capability via manifest policy, delta audit rules, templates, regression tests, and explicit rerun-contract requirements | sufficient as shelf capability | no product gate |
| manual publication review work is reduced | covered as shelf capability via agent execution model, runbook, scripts, and explicit no-routine-human-execution rules | sufficient as shelf capability | no product gate |

## Detailed Notes

### Roles with sufficient direct gate coverage

- ready for GitHub publication
- only user-needed material is exposed
- unnecessary files and leftovers are caught before release
- setup and quickstart actually work
- audit outputs stay outside the product repository

These roles already map cleanly to pass/block conditions in the current gate model.

### Roles that needed wording or checklist reinforcement

#### the repository communicates its usefulness effectively

Existing gates already contained the right surfaces, but they were underspecified.

Reinforced coverage now depends on:

- `G-05` for README value and start-path communication
- `G-13` for About description clarity
- `G-14` for purpose-led Topics
- `P-06` for support and maintenance ownership
- `R-08`, `R-10`, `R-11`, `P-03` for truthful and readable entry guidance

This role now has sufficient coverage because the gap was precision, not absence.
It still does **not** justify a new gate.

### Roles that are better treated as audit-validity or shelf-capability rules

#### publication evidence is repeatable

This is primarily a property of the audit method, not only of the target repository.

GO treats it as satisfied when:

- commands and transcripts are recorded
- hosted facts are backed by hosted evidence
- quickstart is rerunnable from manifest or transcript
- inventory and read log are stored in the audit report
- repository identity and verdict are stored in the same report

This is better enforced by:

- `regulation/execution/AUDIT_RULES.md`
- `regulation/reference/EVIDENCE_COMMANDS.md`
- `regulation/reference/AUDIT_MANIFEST_POLICY.md`

than by adding a new product-facing gate row.

#### repeat audits are supported

This is a shelf capability.
It depends on:

- manifest policy
- delta audit policy
- templates
- regression tests
- explicit rerun contract in the audit record

It should stay out of the product verdict surface unless GO later decides that every runnable repository must prove repeat-audit readiness as part of release quality.

#### manual publication review work is reduced

This is also a shelf capability.
The measurable condition is whether the responsible AI can execute the standard audit path without asking a human to run routine commands.

That belongs in:

- `regulation/execution/AGENT_EXECUTION_MODEL.md`
- `regulation/execution/AUDIT_RUNBOOK.md`
- `regulation/execution/AUDIT_RULES.md`

not in a product-facing gate row.

## Current Decision

At the current maturity level:

- no new `G/R/P` gate is required
- communication-related gates and checklists needed precision work, which has been applied
- repeatability and reduced manual work should remain enforcement rules of the shelf itself

Revisit this file only if:

- a role cannot be judged from existing gates and validity rules
- a repeated audit dispute shows a missing verdict surface
- a future external study shows a missing public optimization dimension that belongs in the common baseline
