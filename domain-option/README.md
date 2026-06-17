# Domain Option

Status: Active

## Purpose

`domain-option/` holds **copy templates only** for project-local records.

It does not hold live project examples, execution results, or domain-specific regulation.

## Rules

- nothing in this folder is generic regulation
- the responsible AI must not read this folder during self-check unless explicitly assigned
- project-specific packets belong in the target repository
- if guidance applies to every project, move it to the parent `github-optimization/` shelf

## Contents

| File | Use |
|---|---|
| `EXECUTION_PACKET.template.md` | copy into target project when recording GitHub-side execution results |

## Do Not Store Here

- `VEIL_*`, `ADOP_*`, or any named project packet
- filled audit reports
- filled publication decision records
- hosted-state snapshots that go stale

Filled audit reports and publication decision records belong in `audits/<repository-slug>/` on this shelf (`regulation/shelf/OUTPUT_PATHS.md`). GitHub execution packets may be copied into the target repository when explicitly assigned.