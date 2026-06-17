# GitHub Optimization Checklists

Status: Active

## Purpose

Walk the responsible AI through regulation self-check without mixing tiers or surfaces.

## Checklist Map

| File | Tier | Role |
|---|---|---|
| `repository-file-review-checklist.md` | prerequisite | full `git ls-files` read log (`G-21`) |
| `local-public-prep-checklist.md` | 1 | local repository checks (`G-01`…`G-12`, `G-22`) |
| `github-settings-checklist.md` | 1 | hosted GitHub settings (`G-13`…`G-19`) |
| `publication-decision-checklist.md` | 1 | responsibility gate (`G-20`) |
| `release-quality-checklist.md` | 2 | CI, version, quickstart (`R-01`…`R-14`) |
| `product-readiness-checklist.md` | 3 | strict product verdict (`P-01`…`P-10`) |

## Gate Registry

All judgment item IDs: `GATE_REGISTRY.md`

## Audit Route

Use `../AUDIT_RUNBOOK.md`, not ad hoc checklist reading.

## Gate Completion

| Tier | Complete when |
|---|---|
| 1 | `PUBLIC_PREP_GATE.md` has no `blocked` rows |
| 2 | `RELEASE_QUALITY_GATE.md` has no applicable `blocked` rows, or formal defer record exists |
| 3 | `PRODUCT_READINESS_GATE.md` has no `blocked` rows |