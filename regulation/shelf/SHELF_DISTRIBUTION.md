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
| version file | `regulation/shelf/SHELF_VERSION.md` |

## Clone And Resolve

After clone, set the shelf root explicitly:

```powershell
$env:GITHUB_OPTIMIZATION_ROOT = "C:\path\to\github-optimization"
```

```bash
export GITHUB_OPTIMIZATION_ROOT=/path/to/github-optimization
```

Resolution order remains in `regulation/shelf/SHELF_PATH.md`.

## Target Repository Layout

Typical workspace:

```text
workspace/
  github-optimization/          # or cloned shelf path
  my-product/                   # audit target
```

The responsible AI audits `my-product`, not the shelf.

## Audit Outputs Live Under `audits/`

Audit outputs belong under `audits/<repository-slug>/` in this shelf:

- `audits/<repository-slug>/audit-report.md`
- `audits/<repository-slug>/publication-decision-record.md`
- other paths in `regulation/shelf/OUTPUT_PATHS.md`

Do not write audit reports into public product repositories.

The shelf `.gitignore` excludes filled records under `audits/` and all of `docs/governance/` except `docs/governance/README.md` (pointer). Canonical audit outputs live under `audits/<slug>/` on disk only.

## Dry-Run Contract

Use dry-run only to verify orchestration:

```powershell
& "$env:GITHUB_OPTIMIZATION_ROOT\scripts\run-full-audit.ps1" `
  -RepoPath "$env:GITHUB_OPTIMIZATION_ROOT\scripts\tests\fixtures\minimal-docs-repo" `
  -AuditSlug minimal-docs-repo `
  -AuditMode public-prep -AuditPhase pre-public
```

Regression tests run this automatically via `scripts/tests/run-regulation-tests.*`.

## Remote Bootstrap

Create and push the shelf repository:

```powershell
cd C:\path\to\github-optimization
gh repo create github-optimization --private --source=. --remote=origin --push
git tag -a v1.1.0 -m "Generic regulation shelf v1.1.0"
git push origin v1.1.0
```

After the remote exists, re-run hosted gates `G-13`…`G-18` in `post-public` phase per `regulation/execution/AUDIT_PHASE_POLICY.md`.

## Release Discipline

When shelf regulation changes:

1. update `regulation/shelf/SHELF_CHANGELOG.md`
2. bump `regulation/shelf/SHELF_VERSION.md`
3. run `scripts/tests/run-regulation-tests.*`
4. run `scripts/validate-regulation-index.*`
5. tag the shelf repository if version control is in use
6. push branch and tags to `origin`