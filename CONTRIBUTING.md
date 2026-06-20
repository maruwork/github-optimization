# Contributing

## Scope

This repository contains the GitHub publication audit toolkit itself, not the repositories it audits and not a product runtime.

## Changes That Belong Here

- regulation wording that applies to every repository
- gate definitions, templates, and scripts used by all audits
- shelf self-validation and regression tests

## Changes That Do Not Belong Here

- project-specific audit reports
- live execution results from ADOP, VEIL, or other product repositories
- repository fixes that belong in the audited target repository instead of this toolkit
- product roadmaps

## Pull Request Checklist

1. update `regulation/REGULATION_INDEX.md` when adding or removing required files
2. run `scripts/validate-regulation-index.*`
3. run `scripts/tests/run-regulation-tests.*`
4. update `regulation/shelf/SHELF_CHANGELOG.md` and bump `regulation/shelf/SHELF_VERSION.md` when behavior changes
