# Evidence Commands

Status: Active

## Purpose

Provide agent-executable commands for Tier 1 and Tier 2 evidence gathering.

The agent runs these commands and stores the transcript in the audit report.

Adapt paths and repository names to the target project.

## Agent Bundle

Preferred single pass:

```powershell
& ".../github-optimization/scripts/collect-audit-evidence.ps1" `
  -RepoPath <repo> -HostedRepo <owner/repo>
```

```bash
.../github-optimization/scripts/collect-audit-evidence.sh <repo> <owner/repo>
```

Quickstart only:

```powershell
& ".../github-optimization/scripts/run-audit-quickstart.ps1" -RepoPath <repo>
```

If `audit.manifest.yml` is missing, the agent still executes README-derived commands and should then add a manifest for the next run.

Shelf path resolution: `regulation/shelf/SHELF_PATH.md`

## Tracked File Inventory

```bash
git ls-files
git ls-files | wc -l
```

Screen for files that should not be downloaded:

```powershell
& "$Shelf/scripts/check-tracked-files.ps1" -RepoPath <repo>
```

```bash
"$Shelf/scripts/check-tracked-files.sh" <repo>
```

Review every path against `regulation/reference/REPO_CONTENT_CLASSIFICATION.md`.  
Screening rules: `regulation/reference/TRACKED_FILE_SCREENING.md`.

## Secret Scan

Baseline:

```bash
gitleaks detect --source . --verbose
```

Optional deeper scan:

```bash
trufflehog filesystem . --results-only
```

## Large File Scan

Gate: `G-22`

```bash
git ls-files -z | xargs -0 ls -la | awk '$5 > 512000 {print}'
```

```powershell
git ls-files | ForEach-Object { if (Test-Path $_) { $s=(Get-Item $_).Length; if ($s -gt 512000) { "$_ $s" } } }
```

## Local Policy Files

```bash
test -f README.md && test -f LICENSE && test -f SECURITY.md && test -f CHANGELOG.md
test -f .github/ISSUE_TEMPLATE/bug_report.md
test -f .github/PULL_REQUEST_TEMPLATE.md
```

## Tests And CI Evidence

```bash
python -m pytest tests/ -q
```

```bash
gh run list --limit 5
gh run view <run-id> --json conclusion,jobs
```

Record the default-branch result, not only a local machine result.

## Version And Release Alignment

```bash
git describe --tags --always
git rev-parse HEAD
git rev-parse <tag>
```

```bash
gh release list --limit 5
gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name,.target_commitish'
```

## Hosted GitHub Metadata

```bash
gh api repos/<owner>/<repo> --jq '{description, topics: .topics, homepage, visibility}'
gh api repos/<owner>/<repo>/community/profile --jq '{health_percentage, files}'
gh api repos/<owner>/<repo> --jq '.security_and_analysis'
```

## Publication Decision Record

Copy `templates/publication-decision-record.md.template` to:

```text
audits/<repository-slug>/publication-decision-record.md
```

Read: `regulation/shelf/OUTPUT_PATHS.md`

Do **not** store the filled record in a public product repository or in `docs/governance/` on the product side.

## Evidence Storage Rule

Store command transcripts in `audits/<repository-slug>/audit-report.md` on this shelf:

- command used
- date and reviewer
- pass/fail result
- short excerpt or link to hosted evidence

Do not rely on chat history as the canonical record.