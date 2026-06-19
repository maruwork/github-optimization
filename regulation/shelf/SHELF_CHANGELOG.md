# Shelf Changelog

## 1.2.8 - 2026-06-19

### Fixed

- Windows regression coverage no longer depends on JSON property order when hosted issue-template evidence is emitted.
- The hosted issue-template self-check now stays green on GitHub Actions Windows runners after release-tag timing and PowerShell serializer differences.

## 1.2.7 - 2026-06-19

### Fixed

- `gh` public-API retries no longer misclassify auth-required failures as `ABSENT`; the collectors keep them as `API_BLOCKED` unless a real 404 payload is present.
- PowerShell and Git Bash regression suites now cover the auth-required retry path and fixture initialization needed to keep shelf self-check deterministic after reruns.
- Audit orchestrator and collector docs now align with the current hosted-evidence and exit-semantics behavior.

## 1.2.6 - 2026-06-18

### Fixed

- Bash and PowerShell collector regressions now verify that access-denied Gitleaks execution-environment artifacts are reported as `SKIPPED`, not scoring `BLOCKED`.

## 1.2.5 - 2026-06-18

### Fixed

- Quickstart fixture environment names no longer use token-like wording, reducing secret-risk false positives during all-file audits.

## 1.2.4 - 2026-06-18

### Fixed

- PowerShell collector now resolves `gitleaks` from `PATH`, including CI-installed `go install` binaries, before declaring the tool unavailable.

## 1.2.3 - 2026-06-18

### Fixed

- CI Gitleaks installation now uses the current Go module path `github.com/zricethezav/gitleaks/v8`.

## 1.2.2 - 2026-06-18

### Fixed

- CI now installs `gitleaks` before running regulation tests so the stricter collector exit-code contract is tested on the authoritative baseline route.

## 1.2.1 - 2026-06-18

### Changed

- `collect-audit-evidence.*` now exits non-zero when it emits a real `result: BLOCKED` row while still preserving the full transcript.
- README, runbook, and script docs now describe `run-full-audit.*` and `run-delta-audit.*` as scaffold/evidence orchestrators, not final verdict engines.

### Fixed

- Bash collector now treats Windows Git Bash / WinGet `gitleaks.exe` access-denied artifacts as `SKIPPED`, matching the PowerShell collector and evidence rules.
- Regression tests now assert that blocked collector evidence cannot be reported with a successful exit code.

## 1.2.0 - 2026-06-18

### Added

- `regulation/reference/GO_ROLE_CRITERIA.md` as the internal pass-criteria basis behind the public GO role list
- `regulation/reference/GO_ROLE_COVERAGE.md` as the gate-to-role coverage audit
- explicit external source register with URLs and checked date for GO role criteria
- isolated quickstart fixture for manifest `env`, legacy `run`, and `path_exists` assertions
- `.gitattributes` to keep shell scripts LF-normalized across Windows and Unix

### Changed

- README, checklists, gates, and execution rules now treat role communication, rerun evidence, and reduced manual review as formal audit conditions
- hosted issue-template evidence can now be verified from repository contents when Community Profile omits the template entry
- publication-evidence rules now require a direct rerun contract and a minimum evidence bundle
- README and GO role criteria now use the same eight publication-readiness user-value axes
- evidence rules now distinguish raw collector output from final gate scoring transcripts when a managed sandbox produces a host-specific tool-path artifact

### Fixed

- PowerShell and bash evidence scripts now harden Git access against `safe.directory` and global-ignore environment drift
- quickstart runners now support shared `env`, post-run path assertions, and legacy manifest `run`
- secret-scan evidence now records an explicit blocked state when `gitleaks` is unavailable or cannot execute
- root `CHANGELOG.md` latest section now matches shelf version `1.2.0`
- tracked documentation text is ASCII-normalized to avoid terminal mojibake

All notable changes to the generic regulation shelf.

## 1.1.14 - 2026-06-17

### Added

- public-prep GitHub surface files (CoC, support, issue/PR templates)
- `ci.yml` + `codeql.yml`; retired `regulation-tests.yml` duplicate

## 1.1.13 - 2026-06-17

### Changed

- root README aligned with output paths, script pipeline, quickstart contract, and reference map

## 1.1.12 - 2026-06-17

### Fixed

- tracked-ignored fixture gitlink removed; runtime-generated `local-only.secret`

## 1.1.11 - 2026-06-17

### Fixed

- tracked-ignored-repo fixture shipped in repo (CI path missing on v1.1.10)

## 1.1.10 - 2026-06-17

### Fixed

- bash gitignore consistency severity field order; blocked exit parity with PowerShell
- bash evidence collector no longer aborts on screening/gitignore non-zero
- delta-audit bash: no python dependency; empty diff list output
- quickstart isolated copy includes dotfiles on Windows

## 1.1.9 - 2026-06-17

### Fixed

- bash quickstart multiline manifest parse (`awk` RS + NUL records); fixes Ubuntu regulation-tests `commands run: 0`

## 1.1.8 - 2026-06-17

### Fixed

- governance path split eliminated (`docs/governance/` filled records removed)
- cross-OS quickstart manifest + evidence propagation parity
- shelf `.gitignore` AI-control patterns; tracked-file screening for governance paths

## 1.1.7 - 2026-06-17

### Fixed

- publication-decision-record output path drift across regulation files
- bash quickstart manifest id parse; collect-audit-evidence quickstart exit propagation
- AUDIT_RULES Tier 1 gate range G-21/G-22

## 1.1.6 - 2026-06-17

### Added

- gitignore consistency checker (`git ls-files -ci --exclude-standard`)
- delta re-audit orchestrator and `delta-audit-record.md.template`

### Changed

- evidence bundle includes gitignore consistency screening

### Fixed

- delta orchestrator: Windows name-status parse, Open Blockers count parse

## 1.1.5 - 2026-06-17

### Added

- `scripts/check-tracked-files.*` for unnecessary tracked-file detection
- `regulation/reference/TRACKED_FILE_SCREENING.md`

### Changed

- evidence bundle and shelf quickstart include screening output

## 1.1.4 - 2026-06-17

### Added

- `audit.manifest.yml` for shelf quickstart automation

### Fixed

- dogfood audit: `CHANGELOG.md` synced through 1.1.3
- dogfood audit: quickstart test infinite recursion when shelf has `audit.manifest.yml`
- dogfood audit: `regulation-tests` no longer deletes `audits/github-optimization/`
- `run-full-audit.*` refuses to overwrite `Status: Final` audit reports
- shelf dry-run test uses `shelf-orchestrator-dry-run` slug only
- removed hardcoded user workspace paths from README and regulation entry files

### Changed

- `docs/governance/` self-audit summary updated to release dogfood verdict

## 1.1.3 - 2026-06-17

### Changed

- moved all regulation markdown from repository root into `regulation/` subdirectories
- root now shows README + standard repo files only

## 1.1.2 - 2026-06-17

### Removed from GitHub

- shelf build history: `design/`, `roadmap/`, `tasks/`
- deprecated meta files: `APPLICATION_GUIDE.md`, `GITHUB_OPTIMIZATION_*_SUMMARY.md`
- product audit results from remote tracking (`audits/<slug>/` now gitignored)

### Changed

- shelf moved to project root (`github-optimization/`)
- GitHub remote scope: regulation files only

## 1.1.1 - 2026-06-17

### Added

- `audits/` layout and `audits/README.md` for per-repository audit results
- tracked ADOP and VEIL audit reports under `audits/adop/` and `audits/veil/`

### Changed

- output contract: audit reports belong in `audits/<repository-slug>/`, not public product repos
- `run-full-audit.*` scaffolds shelf `audits/<slug>/` with optional `-AuditSlug`
- regulation tests, templates, policies, and checklists updated to new paths

## 1.1.0 - 2026-06-17

### Added

- root policy files: `LICENSE`, `SECURITY.md`, `CHANGELOG.md`, `CONTRIBUTING.md`
- CI workflow `.github/workflows/regulation-tests.yml` and Dependabot config
- tracked shelf self-audit artifacts under `docs/governance/`
- gitleaks stderr handling fix in `collect-audit-evidence.ps1`

### Changed

- `.gitignore` allows tracked self-audit governance files only

## 1.0.0 - 2026-06-17

### Added

- complete 46-gate regulation set and `regulation/REGULATION_INDEX.md`
- agent execution model, audit runbook, and output path contract
- policy files: `regulation/execution/RE_AUDIT_POLICY.md`, `regulation/execution/AUDIT_PHASE_POLICY.md`, `regulation/execution/MULTI_REPO_ORCHESTRATION.md`, `regulation/reference/TOOL_REVIEW_CADENCE.md`
- governance templates including `accepted-risk-record.md.template`
- scripts: `validate-regulation-index.*`, `run-full-audit.*`, `collect-audit-evidence.*`, `run-audit-quickstart.*`
- regression tests: `scripts/tests/run-regulation-tests.*`
- distribution docs: `regulation/shelf/SHELF_DISTRIBUTION.md`, `regulation/shelf/SHELF_VERSION.md`
- dry-run fixture: `scripts/tests/fixtures/minimal-docs-repo/`

### Changed

- `README.md` rewritten for agent-first self-check purpose
- `domain-option/` reduced to copy templates only

### Removed

- live project-specific execution records from generic shelf
