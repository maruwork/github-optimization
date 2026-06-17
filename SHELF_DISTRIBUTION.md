# Shelf Distribution

Status: Active

## Purpose

Define how this regulation shelf is versioned, cloned, and resolved outside the original workspace.

## Standalone Repository

This shelf may live as its own git repository.

| Field | Value |
|---|---|
| repository role | generic regulation shelf only |
| not a product repo | do not ship runtime code from here |
| version file | `SHELF_VERSION.md` |

## Clone And Resolve

After clone, set the shelf root explicitly:

```powershell
$env:GITHUB_OPTIMIZATION_ROOT = "C:\path\to\github-optimization"
```

```bash
export GITHUB_OPTIMIZATION_ROOT=/path/to/github-optimization
```

Resolution order remains in `SHELF_PATH.md`.

## Target Repository Layout

Typical workspace:

```text
workspace/
  common/github-optimization/   # or cloned shelf path
  my-product/                   # audit target
```

The responsible AI audits `my-product`, not the shelf.

## Outputs Never Live In The Shelf

Audit outputs belong only in the target repository:

- `docs/governance/audit-report.md`
- `docs/governance/publication-decision-record.md`
- other paths in `OUTPUT_PATHS.md`

The shelf `.gitignore` excludes `docs/governance/` to prevent accidental dry-run commits.

## Dry-Run Contract

Use dry-run only to verify orchestration:

```powershell
& "$env:GITHUB_OPTIMIZATION_ROOT\scripts\run-full-audit.ps1" `
  -RepoPath "$env:GITHUB_OPTIMIZATION_ROOT\scripts\tests\fixtures\minimal-docs-repo" `
  -AuditMode public-prep -AuditPhase pre-public
```

Regression tests run this automatically via `scripts/tests/run-regulation-tests.*`.

## Release Discipline

When shelf regulation changes:

1. update `SHELF_CHANGELOG.md`
2. bump `SHELF_VERSION.md`
3. run `scripts/tests/run-regulation-tests.*`
4. run `scripts/validate-regulation-index.*`
5. tag the shelf repository if version control is in use