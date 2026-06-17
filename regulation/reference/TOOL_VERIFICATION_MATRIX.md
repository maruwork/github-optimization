# GitHub Optimization Tool Verification Matrix

Status: Active

Verified on: 2026-06-17

Review cadence: `regulation/reference/TOOL_REVIEW_CADENCE.md`

## External Tools

| item | class | recommendation |
|---|---|---|
| `Gitleaks` | `use` | baseline local secret scan |
| `git-secrets` | `conditional` | commit-hook enforcement when a repository explicitly wants local hook defense |
| `TruffleHog` | `conditional` | deeper secret validation and broader source scanning when baseline secret scan is not enough |
| `git-sizer` | `conditional` | repository-size analysis for history-heavy or asset-heavy repositories |
| `git filter-repo` | `conditional` | history rewrite only when secrets or unwanted large assets must be purged from history |
| `git gc --prune=now` | `conditional` | local cleanup after history repair or repository maintenance |

## GitHub-Native Features

| item | class | recommendation |
|---|---|---|
| `Topics` | `use` | baseline discoverability metadata |
| `Community Profile` | `use` | baseline public-health checklist |
| `Dependabot version updates` | `use` | baseline dependency-update automation when manifests exist |
| `Dependabot alerts` | `use` | baseline dependency-vulnerability visibility |
| `Secret scanning` | `use` | baseline hosted secret visibility |
| `Code scanning` | `conditional` | use default setup first when the repository is eligible and has supported languages |

## Not A Shared Named Tool Recommendation

These were named in the original note but are too vague to remain as explicit tool recommendations in the shared shelf unless a concrete product is named:

- `code structure analysis tool`
- `repository integration tool`

Keep the outcomes instead:

- `llms.txt`
- `ai-instructions.md`
- explicit root-entry guidance

## Notes

- `Gitleaks` is still usable, but its maintainers state that it is feature complete and future releases are for security patches only.
- `TruffleHog` is active and broader than a baseline local secret scan, but it is heavier and should not replace the simpler baseline by default.
- `git-secrets` still works, but it depends on per-repository hook installation, so it is not the easiest baseline for every repository.