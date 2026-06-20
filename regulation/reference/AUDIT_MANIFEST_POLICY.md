# Audit Manifest Policy

Status: Active

## Purpose

Define when `audit.manifest.yml` is required in the target repository.

## Policy

| Situation | Requirement |
|---|---|
| first audit of a runnable tool | agent executes README-derived quickstart and records transcript |
| repeat audit of a runnable tool | `audit.manifest.yml` should exist at repository root |
| docs-only repository | manifest not required |
| `release` or `strict-product` mode | R-09 requires execution evidence; manifest preferred |

## Manifest Command Fields

| Field | Use |
|---|---|
| `run_windows` | command for Windows runners (`run-audit-quickstart.ps1`) |
| `run_unix` | command for Linux/macOS runners (`run-audit-quickstart.sh`) |
| `run` | legacy single-platform fallback when OS-specific fields are omitted |

Provide both `run_windows` and `run_unix` when CI spans multiple operating systems.

Optional manifest sections:

| Section | Use |
|---|---|
| `env` | environment variables applied to every quickstart command |
| `assertions[].path_exists` | verify that a quickstart-created relative path exists before the run is scored `pass` |
| `primary_ci_workflow` | repository-relative workflow path to treat as the primary CI signal for `R-02` when filename heuristics are insufficient |

## After First Audit

If quickstart evidence succeeded and the repository is runnable, the responsible AI should:

1. copy `templates/audit.manifest.yml.template` to target `audit.manifest.yml`
2. replace placeholders with the commands that actually passed on each OS
3. record the manifest path in the audit report

## Gate Mapping

| Gate | Evidence |
|---|---|
| R-08 | install/setup command from manifest or README transcript |
| R-09 | `run-audit-quickstart` output or README-derived transcript |

## Failure Rule

Do not score R-09 `pass` without execution transcript.
