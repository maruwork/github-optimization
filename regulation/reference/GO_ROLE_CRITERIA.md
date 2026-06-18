# GO Role Criteria

Status: Active

## Purpose

Define the internal pass criteria behind the short `GO Roles` list in `README.md`.

The README states the user-facing role.
This file states how the shelf should judge that the role was actually fulfilled.

Use this file with:

- `regulation/gates/GATE_REGISTRY.md`
- `regulation/reference/JUDGMENT_GUIDE.md`
- `checklists/*.md`
- `scripts/*.ps1`, `scripts/*.sh`

## Source Model

Each role below is based on one of two source types:

- external support: GitHub Docs, Open Source Guides, or research support the criterion directly
- GO-local policy: the criterion is an architectural rule of this shelf and is enforced locally

When external sources do not define a single exact rule, GO uses the narrowest criterion that is still consistent with the sources and keeps the remainder as local policy.

## Role Table

| GO role | Internal pass criteria | Primary GO files | Gate/check mapping | Source anchors |
|---|---|---|---|---|
| ready for GitHub publication | all required Tier 1 rows are scored; no applicable Tier 1 `blocked` row remains; `publication-decision-record.md` exists; Tier 2 and Tier 3 also have no applicable `blocked` row when the audit mode requires them | `regulation/gates/PUBLIC_PREP_GATE.md`, `regulation/gates/RELEASE_QUALITY_GATE.md`, `regulation/gates/PRODUCT_READINESS_GATE.md`, `templates/publication-decision-record.md.template` | `G-01..G-22`, `R-*`, `P-*`, `G-20` | GH-CONTRIB, GH-RELEASES, GO-LOCAL |
| only user-needed material is exposed | every tracked path is classified as user-facing, runtime-required, legal/community-required, or release asset; any tracked path kept by exception has a recorded public-facing reason in the audit report or read log; no internal-management path or misplaced scored audit output remains tracked | `regulation/reference/REPO_CONTENT_CLASSIFICATION.md`, `regulation/reference/TRACKED_FILE_SCREENING.md`, `checklists/repository-file-review-checklist.md`, `regulation/reference/GITIGNORE_CONSISTENCY.md` | `G-02`, `G-03`, `G-04`, `G-21`, `G-22` | GH-README, GH-ARCHIVES, GO-LOCAL |
| unnecessary files and leftovers are caught before release | tracked-file screening has no `blocked` finding; gitignore consistency has no `blocked` finding; large-file scan has no unnecessary tracked generated file; secret scan result is recorded; any remaining review-only finding is carried into the audit report | `scripts/check-tracked-files.*`, `scripts/check-gitignore-consistency.*`, `scripts/collect-audit-evidence.*`, `regulation/reference/TRACKED_FILE_SCREENING.md` | `G-01`, `G-03`, `G-04`, `G-22`, local-public-prep checklist | GH-SENSITIVE, GH-README, GO-LOCAL |
| the repository communicates its usefulness effectively | README contains evidence for all five GitHub entry questions: what the project does, why it is useful, how to get started, where to get help, and who maintains/contributes; About description is non-empty and purpose-led; Topics are present and map to intended purpose, subject area, community, or language; when the repository is intended for external sharing outside GitHub UI, social preview is set or explicitly waived with reason | `templates/README.md.template`, `checklists/github-settings-checklist.md`, `regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`, `regulation/reference/JUDGMENT_GUIDE.md` | `G-05`, `G-13`, `G-14`, `G-15`, `R-08`, `R-10`, `R-11`, `P-03` | GH-README, GH-TOPICS, GH-SOCIAL, GH-CONTRIB, OSG-START, RS-README-CATS, RS-README-POP, RS-DESCRIPTION |
| setup and quickstart actually work | setup/install path in README is executed from the agent transcript and succeeds; quickstart succeeds end-to-end from manifest or README-derived commands; required runtime versions are stated when they matter; known platform caveats found during evidence are documented; test or smoke result is recorded when applicable | `regulation/reference/AUDIT_MANIFEST_POLICY.md`, `regulation/reference/JUDGMENT_GUIDE.md`, `scripts/run-audit-quickstart.*`, `scripts/collect-audit-evidence.*` | `R-08` through `R-13` | GH-README, GH-RELEASES, OSG-START, RS-INSTALL |
| publication evidence is repeatable | audit report stores repository identity, tracked-file inventory reference, file-read log, command transcripts, hosted metadata output, and final verdict; every executed check records the command or script path used plus working directory; quickstart is rerunnable from `audit.manifest.yml` or a README-derived transcript that records commands, working directory, and required environment values; hosted settings facts are backed by stored `gh api`, `gh run`, or equivalent cited hosted transcript | `regulation/reference/EVIDENCE_COMMANDS.md`, `regulation/execution/AUDIT_RUNBOOK.md`, `scripts/collect-audit-evidence.*`, `scripts/run-full-audit.*`, `audit.manifest.yml` | `G-02`, `G-15..G-18`, `G-21`, `R-02`, `R-08`, `R-09`, `R-14` | GH-README, GH-CONTRIB, GO-LOCAL, RS-INSTALL |
| audit outputs stay outside the product repository | scored audit report and supporting decision records exist only under `audits/<slug>/` on this shelf; product repository contains no scored audit report, decision record, or filled governance record; `audit.manifest.yml` may remain in the product repository root only as a quickstart contract | `regulation/shelf/OUTPUT_PATHS.md`, `audits/README.md`, `regulation/reference/PUBLICATION_RESPONSIBILITY_MODEL.md` | `G-20`, `G-21`, tracked-file screening, output-path rules | GO-LOCAL |
| repeat audits are supported | rerun path is defined before the next audit starts through templates, manifest contract, or README-derived transcript that records commands, working directory, and required environment values; prior audit can be delta-checked using `RE_AUDIT_POLICY.md`; shelf regression tests cover the rerun contract; if a repository is runnable and expected to be re-audited, `audit.manifest.yml` exists before audit close unless the repository is docs-only or an explicit waiver is recorded | `regulation/execution/RE_AUDIT_POLICY.md`, `regulation/reference/AUDIT_MANIFEST_POLICY.md`, `templates/*.template`, `scripts/run-delta-audit.*`, `scripts/tests/run-regulation-tests.*` | `R-08`, `R-09`, delta audit rules, tests | GH-README, GO-LOCAL, RS-INSTALL |
| manual publication review work is reduced | the standard audit path can be completed by the responsible AI using shelf scripts, documented commands, and hosted evidence without asking a human to execute routine commands; the final report contains no unresolved routine operator step; any required human step is limited to approval, policy choice, or external-state change outside the agent environment | `regulation/execution/AGENT_EXECUTION_MODEL.md`, `regulation/execution/AUDIT_RUNBOOK.md`, `scripts/run-full-audit.*`, `scripts/collect-audit-evidence.*` | agent execution model, runbook, quickstart rules | GO-LOCAL |

## Source Anchor Legend

| Anchor | Meaning |
|---|---|
| `GH-README` | GitHub Docs: About the repository README file |
| `GH-CONTRIB` | GitHub Docs: Setting up your project for healthy contributions / community profile guidance |
| `GH-TOPICS` | GitHub Docs: Classifying your repository with topics |
| `GH-SOCIAL` | GitHub Docs: Customizing your repository's social media preview |
| `GH-RELEASES` | GitHub Docs: About releases |
| `GH-ARCHIVES` | GitHub Docs: Downloading source code archives |
| `GH-SENSITIVE` | GitHub Docs: Removing sensitive data from a repository |
| `GH-CITATION` | GitHub Docs: About CITATION files |
| `OSG-START` | Open Source Guides: Starting an Open Source Project |
| `RS-README-CATS` | Prana et al. 2018: README `what/how` common, `purpose/status` often missing |
| `RS-README-POP` | Venigalla et al. 2022: organized README structure, links, contribution guidance correlate with popularity |
| `RS-DESCRIPTION` | Hellman et al. 2021: LSP description template is clearer and more informative |
| `RS-INSTALL` | Gao et al. 2023/2025: installation docs improve when pre-install, install, post-install, help, and presentation are explicit |
| `GO-LOCAL` | shelf-specific architectural rule, not claimed as a GitHub platform requirement |

## External Source Register

Checked: `2026-06-18`

| Anchor | Source | URL | Supports roles |
|---|---|---|---|
| `GH-README` | GitHub Docs: About the repository README file | `https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-readmes` | communicates usefulness effectively; setup and quickstart actually work; publication evidence is repeatable |
| `GH-CONTRIB` | GitHub Docs: Setting up your project for healthy contributions | `https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions` | ready for GitHub publication; communicates usefulness effectively; publication evidence is repeatable |
| `GH-TOPICS` | GitHub Docs: Classifying your repository with topics | `https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/classifying-your-repository-with-topics` | communicates usefulness effectively |
| `GH-SOCIAL` | GitHub Docs: Customizing your repository's social media preview | `https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview` | communicates usefulness effectively |
| `GH-RELEASES` | GitHub Docs: About releases | `https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases` | ready for GitHub publication; setup and quickstart actually work |
| `GH-SENSITIVE` | GitHub Docs: Secret scanning | `https://docs.github.com/en/code-security/concepts/secret-security/secret-scanning` | unnecessary files and leftovers are caught before release |
| `OSG-START` | Open Source Guides: Starting an Open Source Project | `https://opensource.guide/starting-a-project/` | communicates usefulness effectively; setup and quickstart actually work |
| `RS-README-CATS` | Prana et al. 2018: Categorizing the Content of GitHub README Files | `https://arxiv.org/abs/1802.06997` | communicates usefulness effectively |
| `RS-README-POP` | Venigalla et al. 2022: An Empirical Study On Correlation between Readme Content and Project Popularity | `https://arxiv.org/abs/2206.10772` | communicates usefulness effectively |
| `RS-DESCRIPTION` | Hellman et al. 2021: Generating GitHub Repository Descriptions | `https://arxiv.org/abs/2110.13283` | communicates usefulness effectively |
| `RS-INSTALL` | Gao et al. 2023: Adapting Installation Instructions in Rapidly Evolving Software Ecosystems | `https://arxiv.org/abs/2312.03250` | setup and quickstart actually work; publication evidence is repeatable |

## External Support Notes

### README and entry communication

GitHub Docs treats the README as the first project entry and recommends it answer:

- what the project does
- why it is useful
- how to get started
- where to get help
- who maintains and contributes

GitHub Docs also says the README should contain only the information needed to get started using and contributing, with longer documentation moved elsewhere.

Open Source Guides reinforces the same split: the README is the first-contact surface, while contribution and community files carry separate roles.

Research support used by GO:

- `RS-README-CATS`: README studies show `what` and `how` are common, while `purpose` and `status` are often missing
- `RS-README-POP`: popular repositories more often use organized structure, links, contribution guidance, and supporting references
- `RS-DESCRIPTION`: repository descriptions work better when they are clear, concise, and purpose-led
- `RS-INSTALL`: installation sections are stronger when they cover pre-installation, installation, post-installation, help, and presentation clearly

### Public metadata and discovery

GitHub Docs recommends topics to classify intended purpose, subject area, community, or language.

GitHub Docs also treats repository description and social preview as first-contact metadata for discovery and external sharing.

### Release and download surface

GitHub Docs treats releases as the packaged form of software for wider use and recommends release notes and assets for distribution.
GitHub Docs also notes that stable source contents are best referenced by commit ID, and that releases are preferred when archive stability matters for security or distribution.

## GO-Local Policy Notes

Some GO roles are not prescribed by GitHub itself because they are shelf-design choices, not platform requirements.

These local policies are intentional:

- keep scored audit outputs out of the product repository
- keep repeat-audit mechanics in one shared shelf
- make the responsible AI the default executor
- treat agent-completable audit flow as a shelf success condition

These policies should only change if the shelf purpose changes.
