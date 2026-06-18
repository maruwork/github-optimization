# Audit Rules

Status: Active

## Purpose

Make audits finish from evidence, not inference.

These rules apply whenever this shelf is used to audit a repository before or after public release.

Default executor: **agent**. Read `regulation/execution/AGENT_EXECUTION_MODEL.md`.

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

Subjective gates must follow `regulation/reference/JUDGMENT_GUIDE.md`.

### 3. Execute before recommend

The agent runs evidence commands before claiming pass/fail.

Primary routes:

- `scripts/collect-audit-evidence.*`
- `scripts/run-audit-quickstart.*`
- `regulation/reference/EVIDENCE_COMMANDS.md`

Forbidden default behavior:

- telling the user to run a command the agent can run
- scoring R-08 or R-09 without an execution transcript

### 4. Record the minimum evidence bundle

Every audit report must contain:

- repository identity and reviewed commit or ref
- tracked-file inventory reference
- completed read log or explicit exception table
- executed command transcript for each scored runtime or quickstart claim
- hosted metadata transcript for each scored GitHub-settings claim
- final gate table and verdict block

If one of these is missing, the audit is incomplete.

Environment-artifact rule:

- keep the raw collector output even when the current execution environment blocks a tool path or hosted CLI config
- `collect-audit-evidence.*` must exit non-zero when it prints any real `result: BLOCKED` row, after preserving the full transcript
- `result: SKIPPED` is allowed only for non-scoring execution-environment artifacts and must not be used to hide repository defects
- do not score the repository `blocked` from that raw bundle alone when the same check is verified through another agent-executable route in the same audit
- when this happens, store both:
  - the raw bundle excerpt
  - the successful transcript row used for scoring, plus a short note that the blocked raw result was an execution-environment artifact
- for Windows collector evidence, the authoritative route is a normal Windows PowerShell host terminal unless the audit explicitly names another validated Windows route
- if a managed sandbox exposes a WinGet tool path differently than the host terminal, record it as `SKIPPED` or environment-artifact evidence and treat it as non-scoring only after a host-terminal or equivalent transcript proves the same check

### 5. Define the rerun contract

For runnable repositories, the audit must leave one direct rerun path:

- `audit.manifest.yml`, or
- a README-derived transcript that records exact commands, working directory, and required environment values

If the repository is expected to be re-audited and is not docs-only, the agent should add or update `audit.manifest.yml` before closing the audit unless an explicit waiver is recorded.

### 6. One repository per report

Audit each repository separately.

Do not mix findings from multiple repositories in one verdict block.

### 7. Record waivers explicitly

Read: `regulation/reference/WAIVER_POLICY.md`

`waived` is valid only when the waiver policy is satisfied.

### 8. Use gate IDs

Mark findings against:

- Tier 1: `G-01` to `G-22` in `regulation/gates/PUBLIC_PREP_GATE.md`
- Tier 2: `R-01` to `R-14` in `regulation/gates/RELEASE_QUALITY_GATE.md`
- Tier 3: `P-01` to `P-10` in `regulation/gates/PRODUCT_READINESS_GATE.md`

## Invalid Audit

An audit is invalid when any of the following is true:

- content assertions were made before `git ls-files` full read completed
- Tier 1 gate was scored without hosted-settings evidence
- runnable-tool audit skipped Tier 2 without explicit deferral
- strict product verdict was issued without Tier 3 review
- verdict mixed multiple repositories
- README quickstart was scored without agent execution evidence
- `G-21` was scored `pass` without a completed read log
- a scored runtime, setup, or quickstart claim has no command transcript
- a scored hosted-settings claim has no stored `gh api`, `gh run`, or equivalent cited hosted transcript
- the minimum evidence bundle is missing
- a repeated runnable-repository audit closed without `audit.manifest.yml`, README-derived rerun transcript, or recorded waiver
- the report tells a human to execute a routine command that the agent environment could have executed itself
- a repository was scored `blocked` only from a raw collector failure that the same audit already proved was an execution-environment artifact

If invalid, restart from `regulation/execution/AUDIT_RUNBOOK.md` Step 1.

## Output Rule

Self-check outputs belong under `audits/<repository-slug>/` in this shelf per `regulation/shelf/OUTPUT_PATHS.md`. Do not write audit reports into public product repositories.

## Severity Labels

Use these only in the evaluation section:

| Severity | Meaning |
|---|---|
| Blocker | public release or market release must stop |
| Major | does not block public prep alone, but blocks strict product verdict |
| Minor | should fix, but does not change gate result alone |
| Info | observation only |
