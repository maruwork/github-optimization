# Regulation Self-Check

Status: Active

## Instruction To The Responsible AI

You are the responsible AI for the target repository.

1. Read the Required set in `regulation/REGULATION_INDEX.md`. Confirm completeness with `regulation/REGULATION_COMPLETENESS.md`. Do not read `domain-option/`, `roadmap/`, `design/`, or `tasks/` unless explicitly assigned.
2. Read the target repository completely (`git ls-files` every tracked file).
3. Follow `regulation/execution/AUDIT_RUNBOOK.md`.
4. Execute evidence yourself. Do not ask a human to run commands you can run.
5. Decide whether the target repository complies with this regulation.
6. Write the result to `audits/<repository-slug>/audit-report.md` using `templates/audit-report.md.template`.
7. Write supporting records to paths in `regulation/shelf/OUTPUT_PATHS.md`. Do not write audit reports into public product repositories.

## One-Line Assignment

```text
Read $GITHUB_OPTIMIZATION_ROOT (or ../github-optimization relative to the target repo), self-assess whether the target repository complies with this regulation, execute evidence, and complete the audit report.
```

## What "Self-Check" Means

| Required | Not required by default |
|---|---|
| read the regulation shelf | human manual checklist labor |
| read every tracked file in the target repo | user-run command instructions |
| run available evidence commands | oral explanation of the shelf |
| score gate tables | mixing multiple repositories in one verdict |
| separate fact and evaluation | claiming pass without evidence |

## Audit Mode Selection

If the assigner does not specify mode, default to `release` for runnable tools and `public-prep` for docs-only repositories.

| Mode | Use when |
|---|---|
| `public-prep` | GitHub public surface only |
| `release` | runnable tool or CLI |
| `strict-product` | market-ready strict judgment requested |

## Output Contract

The self-check is complete only when all of the following exist:

- filled `audits/<repository-slug>/audit-report.md` in this shelf
- Tier 1 gate table scored (`G-01` to `G-22`)
- Tier 2 gate table scored or formally deferred with `audits/<repository-slug>/tier2-defer-record.md`
- Tier 3 gate table scored when mode is `strict-product`
- final label from `regulation/gates/FULL_AUDIT_VERDICT.md`
- fix task list for every `blocked` row

Paths: `regulation/shelf/OUTPUT_PATHS.md`
Judgment items: `regulation/gates/GATE_REGISTRY.md` (46 total)

## Audit Phase

Record `pre-public` or `post-public` in the audit report.

Read: `regulation/execution/AUDIT_PHASE_POLICY.md`

If a prior audit report exists, read `regulation/execution/RE_AUDIT_POLICY.md`.

For multiple repositories in one assignment, read `regulation/execution/MULTI_REPO_ORCHESTRATION.md`.

## Optional Accelerators

Use only when they help repeatability:

- `scripts/run-full-audit.*` - preferred entry for scaffold + evidence
- `scripts/validate-regulation-index.*` - shelf self-check before auditing targets
- `scripts/collect-audit-evidence.*`
- `audit.manifest.yml` in the target repository
- `scripts/run-audit-quickstart.*`
- `scripts/tests/run-regulation-tests.*` - after shelf edits

These are helpers. They do not replace reading the regulation shelf.
