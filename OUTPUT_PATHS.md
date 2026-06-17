# Output Paths

Status: Active

## Purpose

Fix where self-check outputs live so audits do not drift by repository.

The responsible AI writes outputs into the **target repository**, never into `common/github-optimization`.

## Default Paths

Use these unless the target project shelf defines a different management surface:

| Artifact | Default path in target repo |
|---|---|
| audit report | `docs/governance/audit-report.md` |
| publication decision record | `docs/governance/publication-decision-record.md` |
| Tier 2 defer record | `docs/governance/tier2-defer-record.md` |
| accepted risk record | `docs/governance/accepted-risk-record.md` |
| GitHub execution packet | `docs/governance/github-execution-packet.md` |
| audit quickstart manifest | `audit.manifest.yml` (repository root) |

## Creation Rule

If `docs/governance/` does not exist, the responsible AI creates it in the target repository.

Do not commit governance docs to `common/`.

## Git Tracking Policy

| File | Typical tracking |
|---|---|
| `audit-report.md` | usually untracked or tracked per project policy |
| `publication-decision-record.md` | usually untracked or tracked per project policy |
| `accepted-risk-record.md` | tracked when R-02 failure is temporarily accepted |
| `audit.manifest.yml` | tracked when the repository expects repeat audits |
| `github-execution-packet.md` | usually untracked |

Follow the target project's governance policy when it exists.