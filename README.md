# GitHub Optimization

[![CI](https://github.com/maruwork/github-optimization/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/maruwork/github-optimization/actions/workflows/ci.yml)
[![CodeQL](https://github.com/maruwork/github-optimization/actions/workflows/codeql.yml/badge.svg?branch=master)](https://github.com/maruwork/github-optimization/actions/workflows/codeql.yml)
[![Latest Release](https://img.shields.io/github/v/release/maruwork/github-optimization)](https://github.com/maruwork/github-optimization/releases)

Status: Active

Shelf version: `1.2.16` (`regulation/shelf/SHELF_VERSION.md`)

## What This Repository Is

Use this repository to turn GitHub publication uncertainty into a repeatable, evidence-backed audit with clear fix targets and reusable records.

It is an AI-run **GitHub publication optimization shelf**. The responsible AI reads this shelf, executes evidence against a target repository, gathers evidence for all 46 gates, and writes audit artifacts under `audits/<repository-slug>/` on disk.

In one line:

- turn "Can we publish this repo on GitHub?" into an audit report, a fix list, and a reusable decision trail

When you run it, you get:

- a structured audit report under `audits/<slug>/audit-report.md`
- clear fix targets instead of vague publication anxiety
- reusable evidence and judgment records for re-audits

## Who This Is For

- people preparing a repository for GitHub publication and wanting one repeatable audit route
- people re-running a prior publication audit without rebuilding the checklist from scratch
- an AI executor that needs explicit rules, evidence paths, and output records instead of ad hoc judgment

## 60-Second Quickstart

If you want to use this repository right now, start here.

Prerequisites:

- Git
- GitHub CLI (`gh`) if you want hosted GitHub evidence in the report
- PowerShell on Windows, or bash on Linux/macOS

Before you run the command:

- replace `owner/repo` with the GitHub repository you are auditing
- run the command from the target repository root
- expect the generated audit records to land under `github-optimization/audits/<slug>/`

1. Put `github-optimization` next to the target repository, or set `GITHUB_OPTIMIZATION_ROOT` to this shelf path.
2. Run the full-audit orchestrator against the target repository.
3. Open the generated report under `audits/<slug>/`.
4. Finish the final judgment using the cited transcripts and gate tables.

Windows PowerShell:

```powershell
$Shelf = if ($env:GITHUB_OPTIMIZATION_ROOT) { $env:GITHUB_OPTIMIZATION_ROOT } elseif (Test-Path "..\github-optimization") { (Resolve-Path "..\github-optimization").Path } else { throw "Set GITHUB_OPTIMIZATION_ROOT or clone github-optimization next to the target repo" }
& "$Shelf\scripts\run-full-audit.ps1" -RepoPath (Get-Location) -HostedRepo owner/repo -AuditMode release -AuditPhase pre-public
```

Linux/macOS bash:

```bash
SHELF="${GITHUB_OPTIMIZATION_ROOT:-../github-optimization}"
"$SHELF/scripts/run-full-audit.sh" . owner/repo release pre-public
```

Result location:

- `audits/<repository-slug>/audit-report.md`

Important:

- `run-full-audit.*` is the fastest way to start the audit
- `run-full-audit.*` is not the final scorer
- the audit is only complete when the required records and judgments are closed under `regulation/reference/AUDIT_COMPLETION_DEFINITION.md`

## Most Common Use

For most users, the practical flow is:

1. run `scripts/run-full-audit.*`
2. inspect `audits/<slug>/audit-report.md`
3. fill read coverage, transcript mapping, gate scoring, waivers if needed, and final label
4. treat remaining repository defects as fix work, not as unfinished audit work

## What Problem It Solves

Users usually get stuck on the same questions before publishing:

- Is this repository clean enough to put on GitHub?
- Did we forget public-facing files, settings, or quickstart proof?
- Are there tracked files, ignored files, or internal leftovers that should not go up?
- Can we check all of that without redoing the same manual review every time?

This shelf answers those questions by turning them into one repeatable audit flow.

## What It Can Reliably Do

If you use this shelf correctly, this is what you should expect it to do well:

- collect publication evidence from the target repository and hosted GitHub state
- organize that evidence against the 46 gates and the selected audit tier
- separate straightforward `pass` / `blocked` cases from `review` cases that still need explicit judgment
- verify setup, install, and quickstart claims with execution transcripts instead of trusting README prose alone
- scaffold and populate audit records under `audits/<slug>/` so the judgment trail is reusable
- support repeat audits and delta audits without redefining the gate model each time

## What It Does Not Do

If you need any of the behaviors below, use other tools or explicit human review instead of expecting this shelf to do them:

- replace audit judgment with a universal auto-grading bot
- silently fix, rewrite, or clean up the target repository as an auto-fixer
- act as a general-purpose DevSecOps platform outside GitHub publication readiness
- declare a repository publishable or unpublishable from a single CI result alone
- treat `run-full-audit.*` as the final scorer; the audit is incomplete until the required audit records and judgments are closed

## Definition of Complete

Completion is a real stopping condition, not a vague feeling that the review has probably gone far enough.

In this shelf, `complete` means **equilibrium**:

- no required audit work remains open for the chosen audit mode
- the final label is defensible from the report and cited transcripts
- remaining work, if any, belongs to fixing the target repository rather than continuing the audit itself

A completed audit can still end in `blocked`.
Coverage matters, but completion is not defined as the point where coverage simply stops growing.

Canonical definition: `regulation/reference/AUDIT_COMPLETION_DEFINITION.md`

## What It Does

It turns eight publication concerns into AI-executed evidence collection plus explicit gate judgment:

1. reduce pre-publication uncertainty
2. find missing public files and GitHub settings
3. detect internal files, AI control files, caches, secret-risk files, and misplaced audit artifacts
4. check whether README, help, and maintainer information answer a new user's first questions
5. verify install, setup, and quickstart with execution transcripts
6. record GitHub-side decisions for CI, Dependabot, CodeQL, secret scanning, and related automation
7. store audit results in `github-optimization/audits/<slug>/`, outside the product repository
8. support repeat audits and delta audits with the same criteria

## Three-Layer Model

| Layer | Purpose | Primary files |
|---|---|---|
| User value | the eight publication concerns this shelf removes | `README.md`, `regulation/reference/GO_ROLE_CRITERIA.md` |
| Audit judgment | convert those concerns into pass/blocked decisions | `regulation/gates/*.md`, `regulation/execution/SCOPE_AND_TIERS.md`, `regulation/gates/FULL_AUDIT_VERDICT.md` |
| Execution and records | gather evidence and store reusable audit artifacts | `scripts/`, `templates/`, `audits/<slug>/` |

Flow:

```text
user publication concerns
  -> GO role criteria and 46 gates
  -> scripts collect evidence and replay quickstarts
  -> templates shape the report
  -> audits/<slug>/ stores the result
  -> final verdict labels the repository state
```

## GO Roles

GO roles are the internal criteria behind the eight user-value axes:

- ready for GitHub publication
- only user-needed material is exposed
- unnecessary files and leftovers are caught before release
- the repository communicates its usefulness effectively
- setup and quickstart actually work
- publication evidence is repeatable
- audit outputs stay outside the product repository
- repeat audits are supported
- manual publication review work is reduced

| Role | Action |
|---|---|
| Responsible AI | read regulation, run scripts, gather evidence, and write gate judgments into audit artifacts |
| Human | optional publication approval; not default command execution |

## Toolset At A Glance

- `regulation/` defines the audit rules, gate set, and runbook
- `scripts/` runs the actual optimization checks: evidence collection, quickstart replay, full audit orchestration, and delta re-audit
- `templates/` provides audit report and supporting record templates
- `checklists/` maps human-readable review flow to the gate model
- `audits/<slug>/` stores the finished outputs for each target repository

## What This Repository Is Not

| Not for | Reason |
|---|---|
| universal auto-grading or fully automatic publication approval | this shelf gathers evidence and structures judgment, but final audit scoring still follows the runbook and gate tables |
| silent auto-fixing of target repositories | the shelf is for audit execution and records, not unreviewed repository mutation |
| general-purpose DevSecOps management | scope is GitHub publication readiness under this regulation, not broad platform governance |
| single-signal publishability decisions | `R-02` and other gates require scoped evidence, transcript citation, and rule-based judgment rather than one CI result |
| audit reports in product repos | scored artifacts belong in `audits/<slug>/` here |
| live project examples (`VEIL_*`, `ADOP_*`, etc.) | generic shelf only; see `domain-option/` templates |
| copying this folder into public product repos | unless the product documents shared governance |
| filled records under `docs/governance/` | pointer only; canonical path is `audits/<slug>/` |

## Regulation Start Here

1. `regulation/REGULATION_SELF_CHECK.md` - assignment to the responsible AI
2. `regulation/REGULATION_INDEX.md` - required regulation files
3. `regulation/execution/AUDIT_RUNBOOK.md` - execution order
4. `regulation/gates/GATE_REGISTRY.md` - all 46 judgment items
5. `templates/audit-report.md.template` - output skeleton

One-line assignment:

```text
Read $GITHUB_OPTIMIZATION_ROOT (or ../github-optimization relative to the target repo), decide whether the target repository is publication-ready under this regulation, execute evidence, and complete the audit report.
```

## Execution Pipeline

Run in this order unless `RE_AUDIT_POLICY.md` limits scope to a delta.

| Step | Script | Purpose |
|---|---|---|
| 1 | `scripts/run-full-audit.*` | shelf validate + scaffold + evidence (orchestrator, not final scorer) |
| 2 | `scripts/validate-regulation-index.*` | required-file index check (shelf self-proof) |
| 3 | `scripts/collect-audit-evidence.*` | machine evidence bundle |
| 4 | `scripts/check-tracked-files.*` | unnecessary tracked-file screening (`G-03`, `G-21`) |
| 5 | `scripts/check-gitignore-consistency.*` | tracked vs `.gitignore` consistency (`G-04`) |
| 6 | `scripts/run-audit-quickstart.*` | `audit.manifest.yml` quickstart (`R-08`, `R-09`) |
| 7 | `scripts/run-delta-audit.*` | delta re-audit when prior report exists |

Script reference and usage examples: `scripts/README.md`

`run-full-audit.*` and `run-delta-audit.*` do not mechanically complete the final audit verdict.
They create or update audit artifacts, collect machine evidence, and then list the remaining agent judgment steps.
The audit is complete only after the required audit records and judgments are closed under the completion definition.
They now prefer the hosted repository name for `audits/<slug>/` resolution, which avoids worktree-directory slugs when a remote is configured.
Latest CI evidence now prefers a selected primary CI workflow on the default branch. Selection order is: manifest override, explicit `ci.yml` / `ci.yaml`, heuristic local workflow candidate, hosted workflow inventory candidate, then overall runs fallback. When a heuristic local candidate has no default-branch runs but a hosted inventory candidate does, the collector upgrades to the hosted candidate. The collector also emits `selected_workflow_path` and `workflow_selection` so candidate branch-filter / startup-failure runs stay distinguishable from hard failures during gate review.

Regression tests after shelf edits:

```powershell
.\scripts\tests\run-regulation-tests.ps1
.\scripts\tests\run-regulation-tests-ci.ps1
.\scripts\tests\run-regulation-tests-orchestrator.ps1
```

```bash
./scripts/tests/run-regulation-tests.sh
```

```bash
./scripts/tests/run-regulation-tests-ci.sh
./scripts/tests/run-regulation-tests-orchestrator.sh
```

Use `run-regulation-tests.sh` for full bash coverage.
Use `run-regulation-tests-ci.sh` when iterating on `R-02` workflow selection / classification logic.

When `R-02` heuristics change, run the public GitHub corpus as an external-validity check:

```powershell
.\scripts\run-public-corpus.ps1
```

```bash
./scripts/run-public-corpus.sh
```

This corpus uses `scripts/corpus/public-r02-corpus.json` and is expected to require network access.

## Audit Modes And Tiers

| Tier | Gate file | Count | When required |
|---|---|---|---|
| 1 | `regulation/gates/PUBLIC_PREP_GATE.md` | 22 | always |
| 2 | `regulation/gates/RELEASE_QUALITY_GATE.md` | 14 | `release`, `strict-product` |
| 3 | `regulation/gates/PRODUCT_READINESS_GATE.md` | 10 | `strict-product` only |

| Audit mode | Tiers evaluated |
|---|---|
| `public-prep` | Tier 1 |
| `release` | Tier 1 + 2 |
| `strict-product` | Tier 1 + 2 + 3 |

Read: `regulation/execution/SCOPE_AND_TIERS.md`

Final label: `regulation/gates/FULL_AUDIT_VERDICT.md`

## Repository Layout

```text
README.md, LICENSE, SECURITY.md, CHANGELOG.md, etc.   # entry and shelf metadata
audit.manifest.yml                                    # shelf self-check quickstart only
regulation/                                           # all regulation text
checklists/  templates/  scripts/
docs/governance/README.md                             # pointer; no filled records
audits/                                               # local audit results (gitignored)
.github/workflows/ci.yml                              # shelf CI
.github/workflows/codeql.yml                          # code scanning (G-18)
domain-option/                                        # copy templates only (excluded from regulation)
```

## Output Locations

The responsible AI writes audit artifacts under `audits/<slug>/` in this shelf. Do not write completed audit reports into public product repositories.

| Artifact | Path |
|---|---|
| audit report | `audits/<slug>/audit-report.md` |
| delta audit record | `audits/<slug>/delta-audit-record.md` |
| publication decision record | `audits/<slug>/publication-decision-record.md` |
| Tier 2 defer record | `audits/<slug>/tier2-defer-record.md` |
| accepted risk record | `audits/<slug>/accepted-risk-record.md` |
| GitHub execution packet | `audits/<slug>/github-execution-packet.md` |
| audit quickstart manifest | `<product-repo-root>/audit.manifest.yml` (product repos only) |
| governance pointer | `docs/governance/README.md` (this shelf; not a filled record) |

Read: `regulation/shelf/OUTPUT_PATHS.md`, `audits/README.md`

## Quickstart Contract (`R-08`, `R-09`)

| Target | Quickstart source |
|---|---|
| Product repository | `audit.manifest.yml` at product root (`templates/audit.manifest.yml.template`) |
| No manifest | agent derives commands from product `README.md` and records transcript |
| This shelf (self-check) | root `audit.manifest.yml` runs validate-index, tracked-file screening, gitignore consistency |

Manifest fields: `run_windows` / `run_unix` per `regulation/reference/AUDIT_MANIFEST_POLICY.md`

## Audit Shape

The shelf evaluates four broad areas together:

- repository entry quality and publication files
- repeatable quickstart and release evidence
- hosted GitHub metadata and automation state
- basic security and hygiene evidence

## Regulation Scope

Required files: `regulation/REGULATION_INDEX.md`

Excluded from self-check unless explicitly assigned:

- `domain-option/**`
- `roadmap/**`, `design/**`, `tasks/**`
- project-specific execution records

## Reference Map

| Topic | File |
|---|---|
| Agent execution model | `regulation/execution/AGENT_EXECUTION_MODEL.md` |
| Validity rules | `regulation/execution/AUDIT_RULES.md` |
| Audit phase | `regulation/execution/AUDIT_PHASE_POLICY.md` |
| Re-audit / delta | `regulation/execution/RE_AUDIT_POLICY.md` |
| Multi-repo batch | `regulation/execution/MULTI_REPO_ORCHESTRATION.md` |
| Repo classification | `regulation/reference/REPO_CONTENT_CLASSIFICATION.md` |
| Tracked-file screening | `regulation/reference/TRACKED_FILE_SCREENING.md` |
| Gitignore consistency | `regulation/reference/GITIGNORE_CONSISTENCY.md` |
| Tool decisions | `regulation/reference/TOOL_VERIFICATION_MATRIX.md` |
| Tool review cadence | `regulation/reference/TOOL_REVIEW_CADENCE.md` |
| Evidence commands | `regulation/reference/EVIDENCE_COMMANDS.md` |
| Hosted settings | `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md` |
| Quickstart policy | `regulation/reference/AUDIT_MANIFEST_POLICY.md` |
| Waivers | `regulation/reference/WAIVER_POLICY.md` |
| Subjective gates | `regulation/reference/JUDGMENT_GUIDE.md` |
| Publication responsibility | `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md` |
| Shelf path | `regulation/shelf/SHELF_PATH.md` |
| Distribution | `regulation/shelf/SHELF_DISTRIBUTION.md` |
| Completeness proof | `regulation/REGULATION_COMPLETENESS.md` |
| Repair starters | `templates/*.template`, `checklists/*.md` |

## Completion Standard

Self-check is complete when:

- every file in `regulation/REGULATION_INDEX.md` Required set was used
- every `git ls-files` entry in the target repo was read or explicitly excepted (`G-21`)
- all 46 gate tables (`G` / `R` / `P`) are filled or marked `n/a` with reason
- machine evidence is attached
- waivers follow `regulation/reference/WAIVER_POLICY.md`
- subjective gates follow `regulation/reference/JUDGMENT_GUIDE.md`
- final label is assigned via `FULL_AUDIT_VERDICT.md`
- open Blockers are listed as fix tasks

## GitHub Remote Scope

The public remote keeps **regulation files only**:

- gates, policies, checklists, templates, scripts, CI
- not audit results (`audits/**` is gitignored except `audits/README.md`)
- not shelf build history (`design/`, `roadmap/`, `tasks/`)

Shelf self-check: `scripts/validate-regulation-index.*`, `scripts/tests/run-regulation-tests.*`

Distribution and versioning: `regulation/shelf/SHELF_DISTRIBUTION.md`, `regulation/shelf/SHELF_CHANGELOG.md`
