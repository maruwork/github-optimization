# Audit Results

Status: Active

## Purpose

Store regulation self-check outputs per audited repository.

Audit results live here because audited repositories may be **public on GitHub**.  
Do not place audit reports inside public product repositories.

## Layout

```text
audits/
  <repository-slug>/
    audit-report.md
    publication-decision-record.md
    tier2-defer-record.md          (when used)
    accepted-risk-record.md        (when used)
    github-execution-packet.md     (optional summary)
```

Examples:

- `audits/adop/audit-report.md`
- `audits/veil/audit-report.md`

## Rules

1. one directory per audited repository slug
2. never write audit reports into public product repositories
3. `audit.manifest.yml` may remain in a product repository root for quickstart automation only
4. regulation files stay in the parent shelf; only execution results live under `audits/`
5. audit result files are **gitignored** - they stay local and are not pushed to GitHub

Read: `regulation/shelf/OUTPUT_PATHS.md`
