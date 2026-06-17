# Agent Execution Model

Status: Active

## Purpose

Define how `github-optimization` is meant to be used in an agent-first workflow.

This shelf exists so an agent can complete an audit from evidence, not so a human repeats manual checklist labor.

## Default Executor

| Role | Default owner |
|---|---|
| inventory and full-file read | agent |
| command execution and evidence capture | agent |
| gate scoring | agent |
| audit report writing | agent |
| repository fixes | agent or project automation |
| publication approval | optional human or policy gate |

Treat "ask the user to run a command" as a failure mode when the execution environment can run commands.

## Evidence Over Instruction

Valid evidence types:

1. command transcript captured by the agent
2. output from `scripts/collect-audit-evidence.*`
3. output from `scripts/run-audit-quickstart.*`
4. hosted metadata from `gh api`
5. file:line references from full-file read

Invalid evidence:

- "the user should run ..."
- "this probably works"
- checklist ticks without output

## Quickstart Automation Contract

README quickstart is not a human chore. It is an agent-executed gate.

Automation order:

1. if `audit.manifest.yml` exists in the target repository, run `scripts/run-audit-quickstart.*`
2. if no manifest exists, the agent derives commands from `README.md`, executes them, and records the transcript
3. if the repository is meant to be repeatedly audited, add or update `audit.manifest.yml` from `templates/audit.manifest.yml.template`

This makes R-08 and R-09 machine-repeatable.

## Human Role Transition

Humans move toward:

- approving publication when policy requires it
- resolving policy conflicts the agent cannot settle
- accepting or rejecting the final verdict

Humans should not be the default executor for:

- secret scans
- pytest
- hosted settings lookup
- README quickstart replay
- gate table filling

## Completion Standard

An audit is agent-complete when:

- `AUDIT_RUNBOOK.md` finished
- evidence is attached
- final label is assigned
- remaining work is expressed as fix tasks, not as instructions to a human operator