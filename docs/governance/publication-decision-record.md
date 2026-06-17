# Publication Decision Record

Status: Active

## Repository

- name: github-optimization
- role: generic regulation shelf
- reviewed at: 2026-06-17
- decision owner: shelf maintainer

## Publication Intent

Publish this shelf as a reusable governance repository so responsible AIs can clone or reference it outside the original workspace.

## Decision

| Item | Decision |
|---|---|
| visibility | private first; public when maintainer approves |
| audience | maintainers and responsible AIs |
| contribution | limited; regulation changes only |
| remote | `https://github.com/maruwork/github-optimization` |

## Preconditions (local release readiness)

- [x] regulation index self-validation passes
- [x] regression tests pass locally
- [x] CI workflow exists
- [x] `LICENSE`, `SECURITY.md`, `CHANGELOG.md` exist
- [x] remote created
- [x] hosted About description and Topics set
- [x] release dogfood audit: `RELEASE_READY` at tag `v1.1.4`
- [x] dogfood bugs fixed (CHANGELOG, recursion, report clobber, path portability)
- [ ] push `v1.1.4` to remote (deferred by maintainer)
- [ ] public visibility (deferred by maintainer)

## Execution Notes

Local shelf is release-ready at `v1.1.4`. Push and public promotion remain maintainer decisions.

Detailed waivers: `audits/github-optimization/publication-decision-record.md`