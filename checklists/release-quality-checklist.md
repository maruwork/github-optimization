# Release Quality Checklist

Status: Active

Tier: 2

Gate mapping: `../regulation/gates/GATE_REGISTRY.md`
Defer record: `../templates/tier2-defer-record.md.template`

## Purpose

Add release discipline for repositories that ship runnable code, CLIs, installers, or versioned artifacts.

Skip only when Tier 2 is formally deferred in `audits/<repository-slug>/tier2-defer-record.md`.

## CI And Automation

- [ ] default-branch CI exists (`R-01`)
- [ ] latest default-branch CI result is green (`R-02`)
- [ ] CI covers the primary supported platform(s) for the product claim (`R-03`)
- [ ] hosted code scanning alerts are reviewed when code scanning is enabled (`R-04`)

For `R-02`, use the collector `Latest CI` row.
If `r02_assessment=review`, confirm branch scope, selected workflow path, and trigger filters before scoring `blocked`.

## Version And Release Alignment

- [ ] runtime version source is explicit (`R-05`)
- [ ] changelog latest section matches the intended release line (`R-06`)
- [ ] latest tag/release points at the intended commit when releases are used (`R-07`)
- [ ] unreleased HEAD commits are intentional, not accidental drift

## Documentation And First-Run Path

- [ ] README install/setup steps match the actual entry path (`R-08`)
- [ ] README quickstart succeeds end-to-end (`R-09`)
- [ ] README opening explains the user-facing value before internal implementation detail
- [ ] README status and support/help route are explicit when they matter
- [ ] About description and Topics still match the actual product purpose after release changes
- [ ] required runtime versions are stated when they matter (`R-10`)
- [ ] known platform caveats are documented when CI or local evidence found them (`R-11`)
- [ ] `audit.manifest.yml` exists when the repository expects repeat audits

## Evidence

- [ ] test command and result recorded by agent (`R-12`)
- [ ] quickstart evidence recorded by agent (`R-13`)
- [ ] hosted CI evidence link or run id recorded (`R-14`)

Read: `../regulation/reference/AUDIT_MANIFEST_POLICY.md`, `../regulation/reference/JUDGMENT_GUIDE.md`, `../regulation/reference/EVIDENCE_COMMANDS.md`

## Defer Rule

If this checklist is deferred, write `audits/<repository-slug>/tier2-defer-record.md`.

Whole Tier 2 defer is invalid for `strict-product` audit mode.
