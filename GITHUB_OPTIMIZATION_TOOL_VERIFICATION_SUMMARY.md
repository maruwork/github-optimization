# GitHub Optimization Tool Verification Summary

Status: Complete

Recorded: 2026-06-17

## Purpose

Durable record for GOTV-T5. Use with `TOOL_VERIFICATION_MATRIX.md`.

## Verification Scope

Verified items are limited to named external tools and named GitHub-native features listed in the matrix.

Unnamed tool categories were removed from recommendations and replaced with outcome-based guidance.

## External Tool Results

| Item | Class | Rationale |
|---|---|---|
| `Gitleaks` | `use` | still usable as baseline local secret scan; maintainers describe it as feature complete with security-patch releases |
| `git-secrets` | `conditional` | useful for hook enforcement but requires per-repository hook adoption |
| `TruffleHog` | `conditional` | broader and heavier than baseline scan |
| `git-sizer` | `conditional` | only when size/history risk is plausible |
| `git filter-repo` | `conditional` | only when history rewrite is actually required |
| `git gc --prune=now` | `conditional` | cleanup after maintenance or rewrite |

## GitHub-Native Results

| Item | Class | Rationale |
|---|---|---|
| `Topics` | `use` | baseline discoverability metadata |
| `Community Profile` | `use` | baseline public-health checklist |
| `Dependabot version updates` | `use` | when dependency manifests or actions updates matter |
| `Dependabot alerts` | `use` | baseline hosted vulnerability visibility when available |
| `Secret scanning` | `use` | baseline hosted secret visibility when available |
| `Code scanning` | `conditional` | choose default setup first when repository language support exists |

## Review Cadence

Re-check the matrix when any of the following happens:

1. a recommended tool changes maintenance status materially
2. GitHub changes the settings surface for a listed native feature
3. a repository waiver pattern repeats and should become a generic rule

Default scheduled review: at least once per quarter unless an earlier trigger occurs.

## Replacement Guidance

Do not recommend unnamed:

- code structure analysis tools
- repository integration tools

Recommend the resulting artifacts instead:

- `README.md`
- `docs/`
- `llms.txt` or equivalent operator guidance when needed

## Next Maintainer Actions

1. update `Verified on:` in `TOOL_VERIFICATION_MATRIX.md` after each review
2. move repeated conditional decisions into `SCOPE_AND_TIERS.md` only when they apply to every repository
3. keep `EVIDENCE_COMMANDS.md` aligned with actual review practice