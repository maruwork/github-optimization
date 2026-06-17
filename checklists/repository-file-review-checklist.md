# Repository File Review Checklist

Status: Active

Tier: audit prerequisite

Gate: `G-21`

## Purpose

Enforce the read-before-assert rule from `AUDIT_RULES.md`.

## Minimum

- [ ] `git ls-files` captured in the audit report (`G-02`)
- [ ] tracked file count recorded
- [ ] every tracked file marked `read`, `classified-without-read`, or `deferred-with-reason`
- [ ] no evaluation section written before this checklist is complete
- [ ] `G-21` scored only after this checklist is complete

## Per-File Log

Use this table in `docs/governance/audit-report.md`:

| Path | Class | Review | Notes |
|---|---|---|---|
| `README.md` | user-facing | read | |
| `.github/workflows/ci.yml` | github-standard | read | |

### Review values

| Value | Meaning |
|---|---|
| `read` | full file read |
| `classified-without-read` | only allowed for explicit exceptions in `AUDIT_RULES.md` |
| `deferred-with-reason` | temporarily not read; reason and owner recorded |

## Classification Reference

Use `REPO_CONTENT_CLASSIFICATION.md` classes:

- user-facing
- github-standard
- developer-only
- internal-management

## Stop Rule

If any file remains unreviewed and not explicitly deferred, the audit is invalid and `G-21` must be `blocked`.