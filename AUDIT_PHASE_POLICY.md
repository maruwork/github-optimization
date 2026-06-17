# Audit Phase Policy

Status: Active

## Purpose

Separate **pre-public** and **post-public** self-check expectations without changing the 46 gate IDs.

Phase affects default audit mode, waiver strictness, and required supporting records.

Gate IDs remain defined in `GATE_REGISTRY.md`.

## Phases

| Phase | Definition |
|---|---|
| `pre-public` | repository is private, unpublished, or publication decision is not yet executed |
| `post-public` | repository is publicly visible on GitHub or publication execution has started |

Record the phase at the top of `audits/<repository-slug>/audit-report.md`.

## Default Audit Mode By Phase

| Phase | Repository type | Default mode |
|---|---|---|
| `pre-public` | docs-only | `public-prep` |
| `pre-public` | runnable tool | `release` |
| `post-public` | docs-only | `public-prep` |
| `post-public` | runnable tool | `release` |
| either | strict market judgment requested | `strict-product` |

Assigner may override mode explicitly.

## Pre-Public Requirements

Pre-public audits must produce:

- `audits/<repository-slug>/audit-report.md`
- `audits/<repository-slug>/publication-decision-record.md` before publication execution (`G-20`)

Pre-public waivers:

- `G-18` code scanning may be `waived` with owner and revisit trigger
- hosted settings may be `verify` or `recommend-fix` per `HOSTED_SETTINGS_BOUNDARY.md`

Pre-public audits may defer entire Tier 2 only when:

- repository is docs-only, or
- `audits/<repository-slug>/tier2-defer-record.md` exists and audit mode is not `strict-product`

## Post-Public Requirements

Post-public audits must produce:

- `audits/<repository-slug>/audit-report.md`
- refreshed machine evidence for `R-02`, `R-09`, and hosted gates `G-13`…`G-19`

Post-public waivers:

- fewer waivers are acceptable; public visibility increases accountability
- `G-18` waiver must include revisit date not later than next release
- `R-02` cannot be waived in `release` or `strict-product` modes

Post-public audits should follow `RE_AUDIT_POLICY.md` when a prior report exists.

## Phase Transitions

When a repository moves from `pre-public` to `post-public`:

1. run a new audit before or immediately after publication execution
2. do not carry forward pre-public `waived` rows without revalidation
3. verify `G-20` publication decision record reflects executed state

Record the transition in the audit report Facts section.

## Relationship To Tiers

| Tier | Pre-public | Post-public |
|---|---|---|
| Tier 1 | always required | always required |
| Tier 2 | required for runnable tools unless deferred | required for runnable tools |
| Tier 3 | only when mode is `strict-product` | only when mode is `strict-product` |

Phase does not remove Tier 1 gates.

## Orchestration

For multiple repositories, read `MULTI_REPO_ORCHESTRATION.md`.