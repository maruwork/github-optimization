# Tool Review Cadence

Status: Active

## Purpose

Keep `regulation/reference/TOOL_VERIFICATION_MATRIX.md` current without manual ad hoc drift.

This file defines review timing and the automated self-check that guards the regulation shelf.

## Review Schedule

| Event | Action |
|---|---|
| shelf file added or removed | update `regulation/REGULATION_INDEX.md` and run index validator |
| external tool major version change | review matrix row and evidence commands |
| calendar quarterly review | re-read `regulation/reference/TOOL_VERIFICATION_MATRIX.md` and `regulation/reference/EVIDENCE_COMMANDS.md` |
| GitHub feature policy change | review hosted feature rows in matrix |

Record the latest review date in `regulation/reference/TOOL_VERIFICATION_MATRIX.md` header.

## Automated Self-Check

Before relying on the shelf for a target-repository audit, run:

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) { $env:GITHUB_OPTIMIZATION_ROOT } elseif (Test-Path "..\github-optimization") { (Resolve-Path "..\github-optimization").Path } else { throw "Set GITHUB_OPTIMIZATION_ROOT" }
& "$Shelf\scripts\validate-regulation-index.ps1" -ShelfPath $Shelf
```

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
"$SHELF/scripts/validate-regulation-index.sh" "$SHELF"
```

`scripts/run-full-audit.*` runs this validator by default before evidence collection.

## Validator Scope

`validate-regulation-index.*` checks:

- every Required path in `regulation/REGULATION_INDEX.md` exists
- every `templates/*.template` exists
- `regulation/gates/GATE_REGISTRY.md` contains expected gate ID ranges
- regulation scripts listed in `regulation/REGULATION_INDEX.md` exist

It does not validate target repositories.

## Regression Tests

Run after shelf edits:

```powershell
# From shelf root
./scripts/tests/run-regulation-tests.ps1
```

```bash
# From shelf root
./scripts/tests/run-regulation-tests.sh
```

## Escalation

If validator or regression tests fail:

1. fix the shelf before auditing target repositories
2. record the failure in `regulation/shelf/SHELF_CHANGELOG.md` if the fix changes tool recommendations
3. update `Verified on:` date in `regulation/reference/TOOL_VERIFICATION_MATRIX.md` when matrix content changes