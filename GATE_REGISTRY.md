# Gate Registry

Status: Active

## Purpose

Single registry of every judgment item used in regulation self-check.

## Tier 1 — Public Prep (`PUBLIC_PREP_GATE.md`)

| ID | Requirement |
|---|---|
| G-01 | Gitleaks baseline secret scan completed |
| G-02 | tracked file inventory captured |
| G-03 | developer-only AI files are not tracked |
| G-04 | internal-management paths are ignored |
| G-05 | `README.md` exists and states purpose |
| G-06 | `LICENSE` exists |
| G-07 | `SECURITY.md` exists |
| G-08 | `CHANGELOG.md` exists or release route is explicit |
| G-09 | `CODE_OF_CONDUCT.md` when public contribution expected |
| G-10 | `CONTRIBUTING.md` when outside contribution expected |
| G-11 | issue template when issues enabled |
| G-12 | pull request template when public contribution expected |
| G-13 | About description is set |
| G-14 | Topics are set |
| G-15 | Community Profile reviewed |
| G-16 | secret scanning decision explicit |
| G-17 | Dependabot decision explicit |
| G-18 | code scanning decision explicit |
| G-19 | release/changelog route explicit |
| G-20 | publication decision record exists |
| G-21 | every tracked file fully read or explicitly excepted |
| G-22 | no unnecessary large generated files remain tracked |

## Tier 2 — Release Quality (`RELEASE_QUALITY_GATE.md`)

| ID | Requirement |
|---|---|
| R-01 | default-branch CI workflow exists |
| R-02 | latest default-branch CI is green or explicitly accepted |
| R-03 | CI covers primary claimed platform(s) |
| R-04 | code scanning alerts reviewed when enabled |
| R-05 | runtime version source is explicit |
| R-06 | changelog latest section matches intended release line |
| R-07 | latest tag/release matches intended commit when releases used |
| R-08 | README install/setup path is real |
| R-09 | README quickstart succeeds end-to-end |
| R-10 | required runtime versions stated when they matter |
| R-11 | known platform caveats documented when evidence found them |
| R-12 | test command and result recorded |
| R-13 | smoke or quickstart evidence recorded |
| R-14 | hosted CI evidence link or run id recorded |

## Tier 3 — Product Readiness (`PRODUCT_READINESS_GATE.md`)

| ID | Requirement |
|---|---|
| P-01 | distribution path is explicit |
| P-02 | first-run path works without hidden local aliases |
| P-03 | README critical setup/quickstart sections render correctly |
| P-04 | no Tier 2 Blocker remains open |
| P-05 | no unresolved Major docs/runtime mismatch |
| P-06 | support and maintenance ownership explicit |
| P-07 | release/tag strategy matches maintenance claim |
| P-08 | claimed platform support matches CI or documented caveat |
| P-09 | security-sensitive flows have explicit reporting route |
| P-10 | known deferred work is bounded and recorded |

## Total

- Tier 1: 22 items
- Tier 2: 14 items
- Tier 3: 10 items
- **Total: 46 judgment items**