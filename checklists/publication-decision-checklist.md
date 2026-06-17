# Publication Decision Checklist

Status: Active

Gate: `G-20`

Output path: `audits/<repository-slug>/publication-decision-record.md`

## Purpose

Turn `PUBLICATION_RESPONSIBILITY_MODEL.md` into a walkable gate.

Use before any repository becomes public or before a major re-publication.

## Minimum

- [ ] project-side owner is named
- [ ] shared-governance reviewer is named when this common tool is part of the release surface
- [ ] publication execution mode is explicit: `publish-by-common` or `publish-by-project`
- [ ] post-release repository-local owner is named
- [ ] post-release shared-surface owner is named when common templates or policies are in scope
- [ ] filled decision record exists at `audits/<repository-slug>/publication-decision-record.md`
- [ ] Tier 1 waivers are listed in the decision record or linked from it

## Review Questions

- [ ] did the project-side owner collect evidence, not only checklist ticks?
- [ ] did the shared-governance side review waivers explicitly?
- [ ] is it clear who performs the irreversible public-release step?
- [ ] is it clear who handles issues after release?

## Stop Conditions

Stop public release when:

- publication execution mode is still implicit
- no filled decision record exists
- a Tier 1 `blocked` item remains in `PUBLIC_PREP_GATE.md`
- both sides assume the other side will publish or maintain the repository

## Template

Copy from `templates/publication-decision-record.md.template`