# GitHub Optimization Templates

Status: Active

## Purpose

Reusable file starters and output skeletons for regulation self-check.
The `README.md.template` is also a writing guide for explaining user value before publication.
It is designed to help authors answer the core first-visit questions: what, why, how to start, where to get help, and who maintains the project.

## Root Templates

| Template | Target |
|---|---|
| `README.md.template` | repository root `README.md` |
| `LICENSE.template` | repository root `LICENSE` |
| `SECURITY.md.template` | repository root `SECURITY.md` |
| `CODE_OF_CONDUCT.md.template` | repository root `CODE_OF_CONDUCT.md` |
| `CHANGELOG.md.template` | repository root `CHANGELOG.md` |
| `CONTRIBUTING.md.template` | repository root `CONTRIBUTING.md` |
| `SUPPORT.md.template` | repository root `SUPPORT.md` (optional) |
| `gitignore.public-prep.template` | merge into repository `.gitignore` |

## `.github/` Templates

| Template | Target |
|---|---|
| `ISSUE_TEMPLATE_bug_report.md.template` | `.github/ISSUE_TEMPLATE/bug_report.md` |
| `ISSUE_TEMPLATE_feature_request.md.template` | `.github/ISSUE_TEMPLATE/feature_request.md` |
| `ISSUE_TEMPLATE_config.yml.template` | `.github/ISSUE_TEMPLATE/config.yml` |
| `PULL_REQUEST_TEMPLATE.md.template` | `.github/PULL_REQUEST_TEMPLATE.md` |
| `dependabot.yml.template` | `.github/dependabot.yml` |

## Governance Output Templates

| Template | Default target |
|---|---|
| `audit-report.md.template` | `audits/<repository-slug>/audit-report.md` |
| `publication-decision-record.md.template` | `audits/<repository-slug>/publication-decision-record.md` |
| `tier2-defer-record.md.template` | `audits/<repository-slug>/tier2-defer-record.md` |
| `accepted-risk-record.md.template` | `audits/<repository-slug>/accepted-risk-record.md` |
| `audit.manifest.yml.template` | repository root `audit.manifest.yml` |

Read: `regulation/shelf/OUTPUT_PATHS.md`

## Installation Rule

Do not copy repair starters into a project until that project defines where root files and `.github/` files are allowed to live.

Governance outputs belong under `audits/<repository-slug>/` in this shelf. Do not write audit reports into public product repositories.
