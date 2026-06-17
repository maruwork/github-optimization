# Product Readiness Gate

Status: Active

Tier: 3

## Purpose

Provide a strict product verdict without mixing it into Tier 1 public-prep.

Required only for audit mode `strict-product`.

Registry: `regulation/gates/GATE_REGISTRY.md`
Judgment examples: `regulation/reference/JUDGMENT_GUIDE.md`
Waiver rules: `regulation/reference/WAIVER_POLICY.md`

## Gate Rule

| Result | Meaning |
|---|---|
| `pass` | requirement met with evidence |
| `waived` | accepted product limitation; reason recorded |
| `blocked` | strict product verdict must fail |

**Strict product rule:** any `blocked` row means the repository is not market-ready at strict level.

## Gate Table

| ID | Requirement | Evidence |
|---|---|---|
| P-01 | distribution path is explicit | pip/installer/clone-only documented |
| P-02 | first-run path works without hidden local aliases | command transcript |
| P-03 | README critical setup/quickstart sections render and read correctly | rendered review note |
| P-04 | no Tier 2 Blocker remains open | Tier 2 gate result |
| P-05 | no unresolved Major docs/runtime mismatch | file:line references |
| P-06 | support and maintenance ownership explicit | SUPPORT/CONTRIBUTING/decision record |
| P-07 | release/tag strategy matches maintenance claim | release + SECURITY policy note |
| P-08 | claimed platform support matches CI or documented caveat | CI matrix + README |
| P-09 | security-sensitive flows have explicit reporting route | `SECURITY.md` |
| P-10 | known deferred work is bounded and recorded | changelog/report note |

## Summary Block

```text
P-01 pass | P-02 pass | P-03 pass | P-04 pass | P-05 pass
P-06 pass | P-07 pass | P-08 blocked | P-09 pass | P-10 pass

Strict product gate result: PASS | BLOCKED
```