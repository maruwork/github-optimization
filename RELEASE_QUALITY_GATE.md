# Release Quality Gate

Status: Active

Tier: 2

## Purpose

Provide one pass-or-block surface for release discipline after Tier 1 public-prep.

Required for audit modes `release` and `strict-product`.

Registry: `GATE_REGISTRY.md`
Judgment examples: `JUDGMENT_GUIDE.md`
Waiver rules: `WAIVER_POLICY.md`
Defer record: `templates/tier2-defer-record.md.template`

## Gate Rule

| Result | Meaning |
|---|---|
| `pass` | requirement met with evidence |
| `waived` | intentionally not required for this repository; reason recorded |
| `blocked` | requirement not met and not waived |
| `n/a` | repository is docs-only or non-runnable and item does not apply |

**Release gate rule:** any applicable `blocked` row means release-quality is not complete.

Formal deferral of the whole Tier 2 is allowed only in the audit report with owner and expiry.

## Gate Table

| ID | Requirement | Evidence |
|---|---|---|
| R-01 | default-branch CI workflow exists | `.github/workflows/*` path |
| R-02 | latest default-branch CI is green | `gh run list` / run id |
| R-03 | CI covers primary claimed platform(s) | workflow runner matrix note |
| R-04 | code scanning alerts reviewed when code scanning is enabled | alert count + disposition |
| R-05 | runtime version source is explicit | version file/command path |
| R-06 | changelog latest section matches intended release line | `CHANGELOG.md` excerpt |
| R-07 | latest tag/release matches intended commit when releases are used | `git rev-parse` comparison |
| R-08 | README install/setup path is real | agent execution transcript |
| R-09 | README quickstart succeeds end-to-end | `run-audit-quickstart` output or README-derived agent transcript |
| R-10 | required runtime versions are stated when they matter | README excerpt |
| R-11 | known platform caveats are documented when evidence found them | README/docs excerpt |
| R-12 | test command and result recorded | pytest or equivalent output |
| R-13 | smoke or quickstart evidence recorded | command output |
| R-14 | hosted CI evidence link or run id recorded | `gh run view` id |

## Summary Block

```text
R-01 pass | R-02 pass | R-03 pass | R-04 n/a
R-05 pass | R-06 pass | R-07 waived | R-08 pass
R-09 pass | R-10 pass | R-11 pass
R-12 pass | R-13 pass | R-14 pass

Release gate result: PASS | BLOCKED | DEFERRED
```