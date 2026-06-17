# Public Prep Gate

Status: Active

## Purpose

Provide one pass-or-block decision surface for Tier 1 public preparation.

Use this after the checklists are walked and evidence is collected.

Registry: `regulation/gates/GATE_REGISTRY.md`

## How To Score Each Row

| Result | Meaning |
|---|---|
| `pass` | requirement met with evidence |
| `waived` | requirement intentionally not met; waiver recorded |
| `blocked` | requirement not met and not waived |

**Gate rule:** any `blocked` row means public-prep is not complete.

## Tier 1 Gate Table

| ID | Requirement | Primary checklist | Evidence |
|---|---|---|---|
| G-01 | `Gitleaks` baseline secret scan completed | local-public-prep | scan command + result |
| G-02 | tracked file inventory captured with `git ls-files` | local-public-prep, classification | file count + list reference; not a substitute for `G-21` |
| G-03 | developer-only AI files are not tracked | local-public-prep, classification | `git ls-files` proof |
| G-04 | internal-management paths are ignored | local-public-prep | `.gitignore` excerpt |
| G-05 | `README.md` exists and states purpose | local-public-prep | file path |
| G-06 | `LICENSE` exists | local-public-prep | file path |
| G-07 | `SECURITY.md` exists | local-public-prep | file path |
| G-08 | `CHANGELOG.md` exists or release history route is explicit | local-public-prep, github-settings | file path or waiver |
| G-09 | `CODE_OF_CONDUCT.md` exists when public contribution is expected | local-public-prep | file path or waiver |
| G-10 | `CONTRIBUTING.md` exists when outside contribution is expected | local-public-prep, github-settings | file path or waiver |
| G-11 | issue template exists when issues are enabled | github-settings | file path or waiver |
| G-12 | pull request template exists when public contribution is expected | github-settings | file path or waiver |
| G-13 | About description is set | github-settings | hosted metadata note |
| G-14 | Topics are set | github-settings | hosted metadata note |
| G-15 | Community Profile reviewed | github-settings | health percentage or review note |
| G-16 | secret scanning decision is explicit | github-settings, tool matrix | enabled/disabled + reason |
| G-17 | Dependabot decision is explicit | github-settings, tool matrix | enabled/disabled + reason |
| G-18 | code scanning decision is explicit | github-settings, tool matrix | enabled/disabled/waived + reason |
| G-19 | release/changelog route is explicit | github-settings | `CHANGELOG.md` or release note |
| G-20 | publication decision record exists | publication-decision | filled record path |
| G-21 | every tracked file fully read or explicitly excepted | repository-file-review | read log table |
| G-22 | no unnecessary large generated files remain tracked | local-public-prep | size scan note |

## Recommended Gate Summary Block

```text
Repository:
Reviewed at:
Executor:

G-01 pass | G-02 pass | G-03 pass | G-04 pass
G-05 pass | G-06 pass | G-07 pass | G-08 pass
G-09 pass | G-10 pass | G-11 pass | G-12 pass
G-13 pass | G-14 pass | G-15 pass
G-16 pass | G-17 pass | G-18 waived(code scanning deferred — reason: ...)
G-19 pass | G-20 pass
G-21 pass | G-22 pass

Gate result: PASS | BLOCKED
```

Store the filled summary at `audits/<repository-slug>/audit-report.md` per `regulation/shelf/OUTPUT_PATHS.md`.

Read: `regulation/shelf/OUTPUT_PATHS.md`

## Tier 2 Extension

Tier 2 does not change the Tier 1 gate rule.

Use `checklists/release-quality-checklist.md` separately when the repository ships runnable code and needs release discipline beyond GitHub public-prep.