# GitHub Optimization Scope And Tiers

Status: Active

## Purpose

Define what this common tool owns, what it recommends, and what belongs to project-specific product judgment.

Use this file to avoid mixing GitHub public-prep checks with full product-release audits.

## Tier 1 - Minimum Public-Prep Baseline

**Owned by this tool. Required before public release.**

| Surface | What to check |
|---|---|
| Local | secret scan, tracked-file review, `.gitignore` boundary, root policy files |
| Repository files | `README.md`, `LICENSE`, `SECURITY.md`, `CHANGELOG.md`, community files when contribution is expected |
| `.github/` | issue template, pull request template when contribution is expected |
| Hosted GitHub | About, Topics, Community Profile, secret scanning decision, Dependabot decision, code scanning decision |
| Responsibility | publication decision record exists |

Read:

- `checklists/local-public-prep-checklist.md`
- `checklists/github-settings-checklist.md`
- `checklists/publication-decision-checklist.md`
- `regulation/gates/PUBLIC_PREP_GATE.md`

## Tier 2 - Release Quality

**Recommended for repositories that ship runnable tools, not required for every public repository.**

| Surface | What to check |
|---|---|
| CI | default branch CI is green |
| Version | tag/release aligns with runtime version when releases are used |
| Docs | README quickstart matches actual install/run path |
| Evidence | test and smoke commands are recorded |

Read:

- `checklists/release-quality-checklist.md`

## Tier 3 - Product Readiness

**Required only for audit mode `strict-product`.**

This tier is part of the generic regulation shelf, but it is not required for every public repository.

| Surface | What to check |
|---|---|
| Distribution | install path explicit and honest |
| First run | quickstart works without hidden aliases |
| Claims | platform support, support ownership, bounded deferrals |

Read:

- `checklists/product-readiness-checklist.md`
- `regulation/gates/PRODUCT_READINESS_GATE.md`

Tier 3 does not replace Tier 1. It adds a strict market-ready verdict on top.

## Waiver Rule

A Tier 1 item may be waived only when all of the following are true:

1. the reason is explicit
2. the replacement route is explicit
3. the waiver is recorded in `audits/<repository-slug>/publication-decision-record.md` or `audits/<repository-slug>/accepted-risk-record.md`

Silent omission is not a waiver.

## Relationship To `domain-option/`

- Tier 1 and Tier 2 rules belong in the parent shelf
- `domain-option/` contains copy templates only, not project examples or live execution records
- project-specific packets belong in the target repository
- if a domain packet discovers a rule that should apply to every repository, move it to Tier 1 or Tier 2 here
