# Tracked File Screening

Status: Active

## Purpose

Machine-assist check for **tracked files that users would download but should not be published**.

This supports `G-03`, `G-04`, `G-21`, and `G-22`. It does not replace full-file read review.

Classification reference: `regulation/reference/REPO_CONTENT_CLASSIFICATION.md`

## Script

```powershell
& "$Shelf/scripts/check-tracked-files.ps1" -RepoPath <target-repo>
```

```bash
"$Shelf/scripts/check-tracked-files.sh" <target-repo>
```

`collect-audit-evidence.*` runs this automatically and includes the transcript.

## Severity

| Severity | Meaning |
|---|---|
| `blocked` | should not be tracked; clear `G-03` / `G-04` / `G-22` risk |
| `review` | may be valid for some repositories; requires `G-21` judgment |

## Blocked Patterns (default product repository)

| Category | Examples |
|---|---|
| developer-only | `AGENTS.md`, `CLAUDE.md`, `.claudeignore` |
| cache-artifact | `__pycache__/`, `*.pyc`, `.pytest_cache/` |
| secret-risk | `.env` at repository root |
| internal-management | `design/`, `roadmap/`, `tasks/` |
| audit-in-product | tracked `audits/<slug>/` outputs inside a product repo |
| governance-in-product | `docs/governance/*audit*` inside a product repo |

## Review Patterns

| Category | Examples |
|---|---|
| internal-management-candidate | `common/`, `workspace/`, `archive/`, `index/` |
| root-clutter | more than 12 tracked entries directly under repository root |

## Shelf Exception

When the target repository is this regulation shelf (`regulation/REGULATION_INDEX.md` exists at root), these paths are allowed:

- `docs/governance/README.md` (pointer only)
- `audits/README.md`

Filled audit artifacts must not be tracked; they belong in `audits/<slug>/` on disk only.

## Gate Mapping

| Gate | Screening role |
|---|---|
| G-03 | flags developer-only tracked files |
| G-04 | flags internal-management paths |
| G-21 | narrows manual read list to `review` rows + unclassified files |
| G-22 | complements large-file scan in `collect-audit-evidence.*` |

## Result Rule

- `blocked` count `0` -> screening `PASS`
- any `blocked` row -> screening `BLOCKED` (exit code 1)
- `review` rows alone -> screening `PASS_WITH_REVIEW`
