# Hosted Settings Boundary

Status: Active

## Purpose

Define what the responsible AI does about GitHub-hosted settings during self-check.

## Three Actions

| Action | When | Record as |
|---|---|---|
| `verify` | setting is visible through `gh api` or GitHub UI evidence | fact in audit report |
| `recommend-fix` | setting is wrong but change requires web UI or org policy | Major or Blocker + recommendation |
| `waive` | setting is intentionally disabled or deferred | waiver row with reason |

## Default Rule

The responsible AI **verifies** hosted settings. It does not assume it can change them.

Forbidden default:

- scoring `pass` without hosted evidence
- leaving Dependabot / secret scanning / code scanning implicit

## Evidence Sources

```bash
gh api repos/<owner>/<repo> --jq '{description, topics: .topics, homepage, visibility}'
gh api repos/<owner>/<repo>/community/profile --jq '{health_percentage, files}'
gh api repos/<owner>/<repo> --jq '.security_and_analysis'
gh run list -R <owner>/<repo> --limit 5
```

## Gate Mapping

| Gate | Hosted action |
|---|---|
| G-13 | verify About description |
| G-14 | verify Topics |
| G-15 | verify Community Profile |
| G-16 | verify secret scanning decision |
| G-17 | verify Dependabot decision |
| G-18 | verify code scanning decision |
| R-02 | verify default-branch CI |
| R-04 | verify code scanning alerts when enabled |