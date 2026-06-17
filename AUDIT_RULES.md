# Audit Rules

Status: Active

## Purpose

Make audits finish from evidence, not inference.

These rules apply whenever this shelf is used to audit a repository before or after public release.

Default executor: **agent**. Read `AGENT_EXECUTION_MODEL.md`.

## Mandatory Rules

### 1. Read before assert

Do not start content audit until every `git ls-files` entry is read or intentionally classified without reading.

Walk: `checklists/repository-file-review-checklist.md`

Allowed without full read:

- generated vendor blobs explicitly marked review-deferred in the worksheet
- binary assets reviewed by size/hash/classification only, with reason recorded

Everything else requires full read.

### 2. Separate fact and evaluation

| Label | Meaning |
|---|---|
| Fact | directly observed in files, command output, or hosted settings |
| Evaluation | judgment derived from facts |

Never present evaluation as fact.

Subjective gates must follow `JUDGMENT_GUIDE.md`.

### 3. Execute before recommend

The agent runs evidence commands before claiming pass/fail.

Primary routes:

- `scripts/collect-audit-evidence.*`
- `scripts/run-audit-quickstart.*`
- `EVIDENCE_COMMANDS.md`

Forbidden default behavior:

- telling the user to run a command the agent can run
- scoring R-08 or R-09 without an execution transcript

### 4. One repository per report

Audit each repository separately.

Do not mix findings from multiple repositories in one verdict block.

### 5. Record waivers explicitly

Read: `WAIVER_POLICY.md`

`waived` is valid only when the waiver policy is satisfied.

### 6. Use gate IDs

Mark findings against:

- Tier 1: `G-01` … `G-20` in `PUBLIC_PREP_GATE.md`
- Tier 2: `R-01` … `R-14` in `RELEASE_QUALITY_GATE.md`
- Tier 3: `P-01` … `P-10` in `PRODUCT_READINESS_GATE.md`

## Invalid Audit

An audit is invalid when any of the following is true:

- content assertions were made before `git ls-files` full read completed
- Tier 1 gate was scored without hosted-settings evidence
- runnable-tool audit skipped Tier 2 without explicit deferral
- strict product verdict was issued without Tier 3 review
- verdict mixed multiple repositories
- README quickstart was scored without agent execution evidence
- `G-21` was scored `pass` without a completed read log

If invalid, restart from `AUDIT_RUNBOOK.md` Step 1.

## Output Rule

Self-check outputs belong under `audits/<repository-slug>/` in this shelf per `OUTPUT_PATHS.md`. Do not write audit reports into public product repositories.

## Severity Labels

Use these only in the evaluation section:

| Severity | Meaning |
|---|---|
| Blocker | public release or market release must stop |
| Major | does not block public prep alone, but blocks strict product verdict |
| Minor | should fix, but does not change gate result alone |
| Info | observation only |