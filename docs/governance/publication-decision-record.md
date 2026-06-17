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
| remote | `maruwork/github-optimization` when created |

## Preconditions

- [x] regulation index self-validation passes
- [x] regression tests pass locally
- [x] CI workflow exists
- [x] `LICENSE`, `SECURITY.md`, `CHANGELOG.md` exist
- [ ] hosted About/Topics/Community Profile reviewed after remote creation
- [ ] secret scanning and Dependabot decisions recorded after remote creation

## Execution Notes

Hosted settings gates `G-13`…`G-18` remain `waived` until the remote repository exists and is reviewed.