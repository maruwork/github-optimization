# Re-Audit Policy

Status: Active

## Purpose

Define when and how to repeat regulation self-check on a repository that was audited before.

Use with `regulation/reference/AUDIT_MANIFEST_POLICY.md` and `regulation/shelf/OUTPUT_PATHS.md`.

## Triggers

Run a full re-audit when any of the following is true:

| Trigger | Required mode |
|---|---|
| first public visibility execution | `public-prep` minimum |
| new release tag or GitHub Release | `release` for runnable tools |
| default-branch CI changed from green to red | `release` minimum |
| blocker fix claimed complete | same mode as prior audit |
| assigner requests strict market judgment | `strict-product` |
| prior audit is older than 90 days on a public runnable tool | `release` minimum |

Run a delta re-audit only when all of the following are true:

1. a prior `audits/<repository-slug>/audit-report.md` exists with `HEAD` recorded
2. assigner explicitly allows delta mode
3. changes are limited to docs, config, or a bounded file set named in the assignment

Otherwise default to full re-audit.

## Full Re-Audit

Follow `regulation/execution/AUDIT_RUNBOOK.md` without shortcut.

Required outputs:

- new `audits/<repository-slug>/audit-report.md` replaces or supersedes the prior report
- all 46 gate rows rescored for the active audit mode
- `G-21` read log covers every present `git ls-files` entry

Record in the new report:

- prior audit date
- prior `HEAD`
- present `HEAD`
- reason for re-audit

## Delta Re-Audit

Delta mode reduces read scope; it does not reduce gate accountability.

### Required steps

1. Read prior `audits/<repository-slug>/audit-report.md`
2. Capture present inventory (`G-02`)
3. Compute changed tracked files:

```bash
git diff --name-only <prior-HEAD> HEAD
git ls-files --others --exclude-standard
```

4. Full read (`G-21`) only:

- every changed or newly tracked file
- every file referenced by changed gates in the prior report
- every file in the dependency cone of changed runtime or workflow paths

Preferred orchestrator:

```powershell
& "$Shelf/scripts/run-delta-audit.ps1" -RepoPath <repo> -HostedRepo owner/repo -AuditSlug <slug> -AuditMode release
```

```bash
"$Shelf/scripts/run-delta-audit.sh" <repo> owner/repo release <slug>
```

The orchestrator writes `audits/<slug>/delta-audit-record.md` and runs machine evidence.

5. Re-run machine evidence (`scripts/collect-audit-evidence.*`) when not using `run-delta-audit.*`
6. Re-score every gate row affected by the change set
7. Copy forward unchanged gate rows only when evidence still applies and assigner allows carry-forward

### Carry-forward rule

A gate row may be copied from the prior report only when:

- the row was `pass` or formally `waived`
- no changed file can affect that gate
- machine evidence for that gate is unchanged or refreshed in the new report

If unsure, rescore the gate.

### Delta invalidation

Delta mode is invalid and must upgrade to full re-audit when:

- `git ls-files` count changed by more than 20% without explicit assignment allowance
- license, security policy, CI workflow, or release path changed
- prior audit had any open Blocker
- `audit.manifest.yml` commands changed

## Manifest Maintenance

After a successful re-audit of a runnable tool:

1. update `audit.manifest.yml` if quickstart commands changed
2. record manifest path and command IDs in the audit report

## Gate Mapping

| Gate | Re-audit note |
|---|---|
| G-02 | always refresh inventory |
| G-21 | full read or delta read per rules above |
| R-02 | always refresh hosted CI evidence |
| R-09 | always rerun quickstart or README-derived transcript |
| P-05 | rescore when docs or runtime paths changed |

## Output Rule

Re-audit outputs stay under `audits/<repository-slug>/` in this shelf per `regulation/shelf/OUTPUT_PATHS.md`.

Do not write re-audit results into public product repositories.