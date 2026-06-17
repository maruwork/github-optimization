# Publication Decision Record

Status: Active

## Repository

- name: github-optimization
- role: generic regulation shelf
- reviewed at: 2026-06-17
- decision owner: shelf maintainer

## Publication Intent

Publish this shelf as a reusable governance repository so responsible AIs can clone or reference it outside the original workspace.

Publication does not turn this shelf into a product runtime.

## Decision

| Item | Decision |
|---|---|
| visibility | private first; public after hosted settings review |
| audience | maintainers and responsible AIs |
| contribution | limited; regulation changes only |
| remote | `https://github.com/maruwork/github-optimization` |

## Preconditions

- [x] regulation index self-validation passes
- [x] regression tests pass locally (including dogfood fixes on HEAD `86ae86e`)
- [x] CI workflow exists
- [x] `LICENSE`, `SECURITY.md`, `CHANGELOG.md` exist
- [x] remote created and initial push completed
- [x] hosted About description and Topics set
- [x] community profile reviewed (71%; waivers recorded)
- [x] release dogfood audit completed (`audits/github-optimization/audit-report.md`)
- [ ] `v1.1.4` tag at HEAD to clear R-07
- [ ] dogfood commits pushed to remote

## Execution Notes

Release dogfood audit (`release` mode) found and fixed three shelf bugs (CHANGELOG drift, quickstart recursion, audit-report clobber).  
Tier 2 remains blocked on R-07 until `v1.1.4` tag after push.

Detailed waivers: `audits/github-optimization/publication-decision-record.md`