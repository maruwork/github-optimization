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

## After First Audit

If quickstart evidence succeeded and the repository is runnable, the responsible AI should:

1. copy `templates/audit.manifest.yml.template` to target `audit.manifest.yml`
2. replace placeholders with the commands that actually passed
3. record the manifest path in the audit report

## Gate Mapping

| Gate | Evidence |
|---|---|
| R-08 | install/setup command from manifest or README transcript |
| R-09 | `run-audit-quickstart` output or README-derived transcript |

## Failure Rule

Do not score R-09 `pass` without execution transcript.