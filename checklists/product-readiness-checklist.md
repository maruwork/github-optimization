# Product Readiness Checklist

Status: Active

Tier: 3

Required only for audit mode `strict-product`.

Gate mapping: `../regulation/gates/GATE_REGISTRY.md`
Judgment guide: `../regulation/reference/JUDGMENT_GUIDE.md`

## Distribution And First Run

- [ ] install/distribution path is explicit (`P-01`)
- [ ] first-run path works without hidden local aliases (`P-02`)
- [ ] README critical setup/quickstart sections are readable and not broken (`P-03`)

## Release And Support Discipline

- [ ] no open Tier 2 Blocker remains (`P-04`)
- [ ] support and maintenance ownership are explicit (`P-06`)
- [ ] release/tag strategy matches maintenance claim (`P-07`)

## Product Claims

- [ ] claimed platform support matches CI or documented caveat (`P-08`)
- [ ] major docs/runtime mismatches are absent or explicitly waived (`P-05`)
- [ ] security reporting route exists for security-sensitive tools (`P-09`)

## Bounded Deferrals

- [ ] known deferred work is listed with owner and scope (`P-10`)
- [ ] deferred work does not include open Blockers

## Gate

Score `regulation/gates/PRODUCT_READINESS_GATE.md` after this checklist.

Evaluation wording: `regulation/gates/FULL_AUDIT_VERDICT.md`