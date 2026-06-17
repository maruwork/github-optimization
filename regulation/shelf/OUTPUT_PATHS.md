# Output Paths

Status: Active

## Purpose

Fix where self-check outputs live so audits do not drift.

The responsible AI writes audit artifacts into **`github-optimization/audits/<repository-slug>/`**.

Do **not** write audit reports into public product repositories.

## Default Paths

Replace `<slug>` with the audited repository slug (`adop`, `veil`, etc.):

| Artifact | Path |
|---|---|
| audit report | `audits/<slug>/audit-report.md` |
| delta audit record | `audits/<slug>/delta-audit-record.md` |
| publication decision record | `audits/<slug>/publication-decision-record.md` |
| Tier 2 defer record | `audits/<slug>/tier2-defer-record.md` |
| accepted risk record | `audits/<slug>/accepted-risk-record.md` |
| GitHub execution packet | `audits/<slug>/github-execution-packet.md` |
| audit quickstart manifest | `<product-repo-root>/audit.manifest.yml` only |

## Why Not Inside Product Repositories

Audited repositories such as `maruwork/adop` and `maruwork/veil` are public on GitHub.

Audit reports contain internal gate results, blockers, and waivers.  
Those files must not be committed to public product surfaces.

## Creation Rule

If `audits/<slug>/` does not exist, the responsible AI creates it under this shelf.

## Git Tracking Policy

| File | Tracking |
|---|---|
| `audits/<slug>/audit-report.md` | local workspace only (gitignored) |
| `audits/<slug>/publication-decision-record.md` | local workspace only (gitignored) |
| `audit.manifest.yml` in product repo | optional; automation contract only |

GitHub remote keeps **regulation files only**. Audit results stay on disk under `audits/` but are not pushed.

Read: `audits/README.md`