# Audit Report

Status: Final

Output path: `common/github-optimization/audits/adop/audit-report.md`

## Target

- repository: maruwork/adop
- local path: `C:\Users\f_tan\project\adop`
- hosted URL: https://github.com/maruwork/adop
- audited at: 2026-06-17
- executor: agent:grok
- audit mode: `strict-product`
- audit phase: `post-public`
- HEAD: `f296a820b1633e0404f0cf5e7b11ae69a6223252`
- tag/describe: `v0.1.0-2-gf296a82`

## Read Log

- tracked file count: 43
- full read completed: yes
- G-21 result: pass

| Path | Class | Review | Notes |
|---|---|---|---|
| all 43 `git ls-files` entries | mixed | read | per-file notes in agent read log; no deferred rows |

## Machine Evidence

```text
=== Repository ===
Path: C:\Users\f_tan\project\adop
Hosted: maruwork/adop
HEAD: f296a820b1633e0404f0cf5e7b11ae69a6223252
describe: v0.1.0-2-gf296a82
Tracked files: 43
Large files >512KB: none

Root files: README LICENSE SECURITY CODE_OF_CONDUCT CHANGELOG CONTRIBUTING SUPPORT = all true
GitHub templates/workflows: all present

Gitleaks: no leaks found (30 commits)
Pytest local: 105 passed

Hosted metadata:
  description: set
  topics: adoption, governance, python, trial-management
  community profile: 100%
  secret_scanning: enabled, push_protection enabled
  dependabot_security_updates: disabled

Latest CI (gh run 27667103300): success
  "Add pip install support (pyproject.toml) and Windows/pip CI jobs"

Quickstart transcript (isolated temp dir):
  python adop_cli.py init -> ok
  quick-intake -> ok JSON status
  status -> lint-pipeline proposed
  lint -> ok (1 artifact)
```

## Facts

### Local

- Runnable CLI at `shared/python/adop_cli.py` with `pyproject.toml` entry points `adop` / `adop-sync`
- CI matrix: ubuntu + windows, Python 3.11/3.12, pip install job, lifecycle smoke on bash
- `adop.json` manifest lists 9 runtime files at v0.1.0
- HEAD is 2 commits ahead of tag `v0.1.0` (`973bf05`)

### Hosted GitHub

- Public repository, Community Profile 100%
- Secret scanning enabled with push protection
- Latest default-branch CI green (run `27667103300`)
- GitHub Release `v0.1.0` exists; no release for post-tag commits

### Execution

- README Option B quickstart path verified without shell alias
- pip install path documented and exercised in CI job `pip-install`

## Tier 1 — Public Prep Gate

| ID | Result | Evidence |
|---|---|---|
| G-01 | pass | gitleaks no leaks |
| G-02 | pass | 43 tracked files inventoried |
| G-03 | pass | no tracked AGENTS.md / CLAUDE.md |
| G-04 | pass | `.gitignore` excludes internal paths |
| G-05 | pass | `README.md` purpose stated |
| G-06 | pass | `LICENSE` |
| G-07 | pass | `SECURITY.md` |
| G-08 | pass | `CHANGELOG.md` |
| G-09 | pass | `CODE_OF_CONDUCT.md` |
| G-10 | pass | `CONTRIBUTING.md` |
| G-11 | pass | issue templates |
| G-12 | pass | PR template |
| G-13 | pass | hosted description set |
| G-14 | pass | topics set |
| G-15 | pass | community profile 100% |
| G-16 | pass | secret scanning enabled |
| G-17 | waived | dependabot security updates disabled; monthly Actions updates via `.github/dependabot.yml` |
| G-18 | waived | code scanning not enabled; Python CLI repo, secret scanning baseline sufficient |
| G-19 | pass | `CHANGELOG.md` + GitHub Release route |
| G-20 | pass | `audits/adop/publication-decision-record.md` |
| G-21 | pass | all tracked files read |
| G-22 | pass | no large tracked files |

Tier 1 result: PASS

## Tier 2 — Release Quality Gate

| ID | Result | Evidence |
|---|---|---|
| R-01 | pass | `.github/workflows/ci.yml` |
| R-02 | pass | run `27667103300` success |
| R-03 | pass | ubuntu + windows matrix |
| R-04 | n/a | code scanning not enabled |
| R-05 | pass | `adop_cli.py --version`, `adop.json` version |
| R-06 | pass | CHANGELOG v0.1.0 section matches release line |
| R-07 | blocked | HEAD `f296a82` != tag `v0.1.0` `973bf05`; 2 commits unreleased |
| R-08 | pass | pip + clone paths; CI pip-install job |
| R-09 | pass | quickstart transcript above |
| R-10 | pass | README Python 3.11/3.12 |
| R-11 | pass | Option B documents non-alias path |
| R-12 | pass | 105 pytest passed |
| R-13 | pass | quickstart + CI smoke |
| R-14 | pass | run id `27667103300` |

Tier 2 result: BLOCKED

## Tier 3 — Product Readiness Gate

| ID | Result | Evidence |
|---|---|---|
| P-01 | pass | pip install + clone documented |
| P-02 | pass | `python shared/python/adop_cli.py` works without alias |
| P-03 | pass | README fences render correctly |
| P-04 | blocked | Tier 2 BLOCKED (R-07) |
| P-05 | pass | docs/runtime agree at v0.1.0; unreleased commits are post-release fixes |
| P-06 | pass | `SUPPORT.md`, `CONTRIBUTING.md`, `SECURITY.md` |
| P-07 | blocked | maintenance claim vs unreleased HEAD commits |
| P-08 | pass | CI windows+ubuntu matches README Python claim |
| P-09 | pass | `SECURITY.md` reporting route |
| P-10 | pass | post-v0.1.0 work bounded in unreleased commits |

Tier 3 result: BLOCKED

## Evaluation

### Blockers

- R-07: default branch is 2 commits ahead of latest release tag `v0.1.0`
- P-04: Tier 2 not complete
- P-07: release/tag strategy not aligned with present HEAD

### Majors

- none beyond open Blockers

### Minors

- G-17/G-18 waived decisions should be revisited if dependency or code scanning policy changes

## Final Verdict

```text
Audit mode: strict-product
Tier 1 gate: PASS
Tier 2 gate: BLOCKED
Tier 3 gate: BLOCKED
Final label: RELEASE_BLOCKED
Open Blockers: R-07, P-04, P-07
Open Majors: 0
Facts confidence: high
```

## Waivers

| Gate ID | Reason | Owner |
|---|---|---|
| G-17 | Actions-only dependabot; no package lockfiles requiring version alerts | maintainer |
| G-18 | secret scanning baseline; CodeQL deferred | maintainer |

## Fix Tasks

1. Tag and release `v0.1.1` (or next semver) at HEAD `f296a82` with matching `CHANGELOG.md` section
2. Re-run audit after release to clear R-07 and P-07