# Regulation Shelf Tests

Status: Active

## Purpose

Regression and dry-run tests for the generic regulation shelf itself.

These tests do not audit product repositories.

## Run

```powershell
.\run-regulation-tests.ps1
```

```bash
./run-regulation-tests.sh
```

## Fixture

`fixtures/minimal-docs-repo/` is a tiny git repository used by the `run-full-audit` dry-run test.

Dry-run outputs may appear under `fixtures/minimal-docs-repo/docs/governance/`. They are gitignored and safe to delete.

## Shelf Self Dry-Run

The regression suite also runs `run-full-audit` against the shelf root to verify orchestration on a real tracked tree.

Any `docs/governance/` created at the shelf root is gitignored and must not be committed.