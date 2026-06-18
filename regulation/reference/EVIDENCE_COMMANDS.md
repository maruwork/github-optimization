# Evidence Commands

Status: Active

## Purpose

Provide agent-executable commands for Tier 1 and Tier 2 evidence gathering.

The agent runs these commands and stores the transcript in the audit report.

Adapt paths and repository names to the target project.

## Required Audit Record

Every completed audit report stores:

- repository path and reviewed commit or ref
- audit date and responsible agent
- tracked-file inventory reference
- read log reference
- command transcripts with working directory and result
- hosted metadata transcript for scored GitHub settings
- quickstart source: `audit.manifest.yml` or README-derived transcript
- final gate table and verdict

Do not treat chat history as the canonical record.

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

If `audit.manifest.yml` is missing, the agent still executes README-derived commands.
The audit report must then store:

- exact command lines
- working directory
- required environment values
- any path assertions used to judge success

If the repository is expected to be re-audited and is runnable, the agent should then add a manifest for the next run unless an explicit waiver is recorded.

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

If `gitleaks` is unavailable on the authoritative route, `G-01` cannot be scored `pass`.
Record the missing-tool state explicitly and treat the gate as `blocked` until a baseline transcript exists.
On Windows Git Bash, a WinGet path issue is recorded as `SKIPPED`; score `G-01` from `collect-audit-evidence.ps1` or a direct `gitleaks detect --source . --no-banner` transcript.

If the tool is installed but the current execution environment exposes its path incorrectly, denies execution, or hides hosted CLI state, keep that raw output and verify through another agent-executable route before scoring the repository itself `blocked`.

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
gh api repos/<owner>/<repo> --jq '{description, topics: .topics, homepage, visibility, has_issues}'
gh api repos/<owner>/<repo>/community/profile --jq '{health_percentage, files}'
gh api repos/<owner>/<repo> --jq '.security_and_analysis'
```

Issue template evidence when GitHub Community Profile does not surface the template entry reliably:

```bash
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/bug_report.md --jq '{path}'
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/feature_request.md --jq '{path}'
gh api repos/<owner>/<repo>/contents/.github/ISSUE_TEMPLATE/config.yml --jq '{path}'
```

## Publication Decision Record

Copy `templates/publication-decision-record.md.template` to:

```text
audits/<repository-slug>/publication-decision-record.md
```

Read: `regulation/shelf/OUTPUT_PATHS.md`

Do **not** store the filled record in a public product repository or in `docs/governance/` on the product side.

## Evidence Storage Rule

Store command transcripts in `audits/<repository-slug>/audit-report.md` on this shelf.

Canonical report shape:

- `## Read Log`
- `### Read Exceptions`
- `### Read Coverage`
- `## Evidence Index`
- `## Local Command Transcripts`
- `## Hosted Transcripts`
- `## Quickstart Transcript`
- `## Machine Evidence Bundle`

Raw machine evidence is not the scoring authority by itself when the same audit proves an execution-environment artifact.
In that case, keep the raw bundle and add a successful transcript row for the route actually used to score the claim.

For Windows evidence, the preferred authoritative route is the normal Windows PowerShell host terminal.
If a managed sandbox reports a WinGet tool path differently from that host terminal, record the sandbox output as raw `SKIPPED` or environment-artifact evidence and score from the successful host-terminal or equivalent transcript.

Each executed check records:

- command or script path used
- working directory
- environment overrides if used
- date and reviewer
- exit code or pass/fail result
- short output excerpt or hosted evidence reference

Each hosted-settings claim records:

- API command used, or
- cited hosted page/report path captured during the audit

Recommended transcript subsection format:

```markdown
### Transcript N

- check:
- command:
- working directory:
- env overrides:
- exit code / result:

```text
<raw excerpt>
```
```

Do not mark a scored claim `pass` from memory or chat summary alone.
