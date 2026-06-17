# Multi-Repository Orchestration

Status: Active

## Purpose

Run regulation self-check across multiple repositories without mixing verdicts.

One repository always produces one audit report.

## Hard Rules

1. one `audits/<repository-slug>/audit-report.md` per repository
2. one final label per repository
3. no combined Blocker list across repositories
4. no shared waiver row across repositories

Read: `regulation/execution/AUDIT_RULES.md` section "One repository per report"

## Assignment Format

When an assigner names multiple repositories, use this structure:

```text
Shelf: <path to github-optimization>
Phase: pre-public | post-public
Mode: public-prep | release | strict-product
Repositories:
  - local: <path>
    hosted: owner/repo
    phase: <optional override>
    mode: <optional override>
  - local: <path>
    hosted: owner/repo
```

If phase or mode is omitted per repository, apply defaults from `regulation/execution/AUDIT_PHASE_POLICY.md` and `regulation/REGULATION_SELF_CHECK.md`.

## Execution Order

For each repository in list order:

1. resolve shelf path via `regulation/shelf/SHELF_PATH.md`
2. determine phase and audit mode
3. check for prior `audits/<repository-slug>/audit-report.md`
   - if present and assigner allows delta, follow `regulation/execution/RE_AUDIT_POLICY.md`
   - otherwise follow `regulation/execution/AUDIT_RUNBOOK.md` full path
4. write outputs under `audits/<repository-slug>/` in this shelf
5. record completion before starting the next repository

Parallel execution is allowed only when repositories are independent and the executor can keep evidence separated.

## Batch Evidence Shortcut

`scripts/run-full-audit.*` may be run per repository to collect machine evidence.

It does not replace per-repository `G-21` read review or gate scoring.

## Batch Summary (Optional)

When the assigner requests a portfolio summary, write a separate file outside any product repository, or in an assigned management surface.

The portfolio summary may list:

- repository name
- phase
- audit mode
- final label
- open Blocker count
- path to each `audit-report.md`

It must not replace per-repository audit reports.

## Failure Handling

If one repository audit is `BLOCKED`:

- continue other repositories only when the assigner explicitly allows partial batch completion
- never upgrade another repository's label because a sibling repository passed

## Runnable Tool Follow-Up

After the first successful audit in a batch, each runnable tool repository should receive its own `audit.manifest.yml` per `regulation/reference/AUDIT_MANIFEST_POLICY.md`.

Do not share one manifest across repositories.