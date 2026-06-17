# GitHub Publication Responsibility Model

Status: Active

## Purpose

Define who prepares, who approves, who publishes, and who maintains repositories when projects are released on GitHub.

## Recommended Default

Use a split model:

- `project-side owner`
  - repository-local preparation
  - project-specific file placement
  - project-specific README and docs
  - local validation and evidence gathering
- `shared-governance side`
  - shared tool-application review
  - publication-gate review
  - release-consistency review across repositories
  - final public-release execution or explicit publication approval

Default execution model: agents run audits and gather evidence. Humans approve or reject when policy requires it.

Read: `regulation/execution/AGENT_EXECUTION_MODEL.md`

Do not rely on only one side for the entire flow.

## Why This Model

If the project-side owner alone publishes:

- project-specific context is stronger
- but cross-project quality and consistency drift more easily

If the shared-governance side alone publishes:

- shared quality is stronger
- but project-specific placement, history, and intent are easier to misread

If both sides can act without a fixed split:

- responsibility becomes ambiguous
- later maintenance becomes harder

## Default Flow

### 1. Project Preparation

The project-side owner:

- aligns file and folder rules
- applies approved common tools
- prepares repository-local public files
- collects required evidence

### 2. Shared Review

The shared-governance side:

- checks whether the required shared baselines and optimization tools were applied correctly
- checks release and publication checklists
- checks whether the repository is consistent with shared public-prep rules

### 3. Publication Decision

Choose one of these explicitly:

- `publish-by-common`
  - the shared-governance side performs the actual public-release step
- `publish-by-project`
  - the project-side owner performs the actual public-release step after shared review approval

Do not leave this implicit.

## Recommended Default Decision

Use `publish-by-common` as the default for repositories meant to represent shared quality.

Reason:

- public release is the highest-risk irreversible step
- the shared side already owns cross-project publication standards
- the project side should still own preparation and evidence

## Post-Release Management

Use another split:

- `project-side owner`
  - repository-local issues
  - project-specific roadmap and docs
  - domain-specific fixes
- `shared-governance side`
  - shared template and optimization updates
  - cross-project release discipline
  - shared public-file quality
  - common policy changes

## What Must Not Happen

- the project-side owner publishes without shared review when common tools are part of the release surface
- the shared-governance side rewrites repository-local structure without the project shelf rules
- both sides assume the other side will handle post-release maintenance

## Minimum Decision Record

Before a repository is made public, record:

- who prepared it
- who reviewed it
- who executes the public-release step
- who owns post-release repository-local maintenance
- who owns shared-surface maintenance

Walkable gate: `checklists/publication-decision-checklist.md`

Template: `templates/publication-decision-record.md.template`

Store the filled record in the target project management surface, not in this common shelf.