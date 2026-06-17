# Execution Packet Template

Status: Template

## Purpose

Record one repository's GitHub-side execution results without turning project-specific facts into generic rules.

Copy this file to `audits/<repository-slug>/github-execution-packet.md` in this shelf.

Read: `../regulation/shelf/OUTPUT_PATHS.md`

## Repository

- local path:
- hosted URL:
- reviewed at:

## Tier 1 Result

- `regulation/gates/PUBLIC_PREP_GATE.md` result: PASS | BLOCKED
- blocked items:
- waivers:

## Hosted State

| Item | State | Notes |
|---|---|---|
| visibility | | |
| About description | | |
| Topics | | |
| homepage | | |
| Community Profile | | |
| secret scanning | | |
| secret scanning push protection | | |
| Dependabot | | |
| code scanning | | |
| latest default-branch CI | | |

## Files Present

- README.md:
- LICENSE:
- SECURITY.md:
- CODE_OF_CONDUCT.md:
- CHANGELOG.md:
- CONTRIBUTING.md:
- issue template:
- pull request template:

## Tier 2 Result

- release-quality checklist: completed / deferred
- CI evidence:
- version/release alignment:
- quickstart evidence:

## Remaining Work

### Decision-fixed

-

### Follow-up

-

## Rule Learned

If this packet reveals a rule that should apply to every repository, move that rule to the parent `github-optimization/` shelf and keep only repository-specific facts here.