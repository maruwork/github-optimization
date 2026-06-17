# Gitignore Consistency

Status: Active

## Purpose

Detect mismatch between `.gitignore` rules and what Git still tracks.

Supports `G-04` and complements `scripts/check-tracked-files.*`.

## Script

```powershell
& "$Shelf/scripts/check-gitignore-consistency.ps1" -RepoPath <target-repo>
```

```bash
"$Shelf/scripts/check-gitignore-consistency.sh" <target-repo>
```

`collect-audit-evidence.*` runs this automatically.

## Checks

| Check | Severity | Meaning |
|---|---|---|
| tracked-but-ignored | blocked | path is in the index but matches `.gitignore` (`git ls-files -ci --exclude-standard`) |
| missing-recommended-rule | review | `templates/gitignore.public-prep.template` pattern absent from `.gitignore` |
| no-gitignore | review | repository has no `.gitignore` at root |

## Fix Guidance

Tracked-but-ignored rows usually need:

```bash
git rm --cached <path>
```

Then confirm the path stays ignored locally.

## Gate Mapping

| Gate | Role |
|---|---|
| G-04 | proves ignore boundaries are enforced in the index |
| G-03 | complements developer-only screening |

Read: `regulation/reference/TRACKED_FILE_SCREENING.md`