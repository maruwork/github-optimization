# Waiver Policy

Status: Active

## Purpose

One waiver rule for every gate in `GATE_REGISTRY.md`.

## Valid Waiver

A gate may be scored `waived` only when all four are true:

1. gate ID is named (`G-18`, `R-07`, etc.)
2. reason is explicit
3. owner or reviewer is named
4. waiver is recorded in:
   - `docs/governance/audit-report.md` Waivers table, and
   - `docs/governance/publication-decision-record.md` when Tier 1 is involved

## Invalid Waiver

| Pattern | Why invalid |
|---|---|
| silent omission | no recorded decision |
| "not needed yet" without owner | no accountability |
| waiver without replacement route | user cannot tell what to do instead |
| Tier 2 `blocked` called `waived` | Blockers must be fixed or audit stops |

## Common Waiver Patterns

| Gate | Valid waiver example |
|---|---|
| G-09 | docs-only repo with no contribution expected; owner: project-side |
| G-10 | maintainers-only repo; issues accepted but no outside PR flow |
| G-11 | issues disabled by policy; GitHub issues off |
| G-18 | code scanning deferred until first stable release; revisit on next audit |
| G-20 | pre-public dry-run audit; decision record due before publish execution |
| R-07 | no release tags until `v0.1.0`; HEAD ahead is intentional |
| P-08 | Windows unsupported in v0.1; README states Ubuntu/macOS only |

## Tier 2 Whole Defer

Deferring all of Tier 2 requires `docs/governance/tier2-defer-record.md` from `templates/tier2-defer-record.md.template`.

Whole Tier 2 defer is invalid for `strict-product` audit mode.