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

## Standard Agent Path

The normal audit path is:

1. capture repository identity, tracked-file inventory, and full-read log
2. run local evidence commands and save transcripts
3. execute README setup and quickstart from manifest or README-derived commands
4. capture hosted GitHub metadata when gates depend on hosted settings
5. write the gate table, verdict, and publication decision record

This is the default expectation, not an ideal case.

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

## Failure Modes

The audit method failed if the report:

- asks a human to execute a routine command the agent environment could run
- leaves README setup or quickstart as an unexecuted suggestion
- scores a runtime or hosted claim without stored evidence
- depends on chat history instead of shelf-stored audit artifacts

## Completion Standard

An audit is agent-complete when:

- `regulation/execution/AUDIT_RUNBOOK.md` finished
- evidence is attached
- final label is assigned
- no routine operator command remains unresolved
- remaining work is expressed as fix tasks, approvals, policy choices, or external-state changes
