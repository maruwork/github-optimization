# GitHub Settings Checklist

Status: Active

Tier: 1

Evidence: `../regulation/reference/EVIDENCE_COMMANDS.md`
Hosted boundary: `../regulation/reference/HOSTED_SETTINGS_BOUNDARY.md`
Gate mapping: `../regulation/gates/GATE_REGISTRY.md`

## Repository Metadata

- [ ] About description is filled and states project purpose clearly (`G-13`)
- [ ] Topics are set and classify intended purpose, subject area, or language (`G-14`)
- [ ] homepage or demo link is set when applicable
- [ ] social preview is set when external sharing or social linking matters

## Community Files

- [ ] Community Profile is reviewed (`G-15`)
- [ ] `CONTRIBUTING.md` exists when outside contribution is expected (`G-10`)
- [ ] issue template is configured when issues are enabled; if Community Profile omits it, verify `.github/ISSUE_TEMPLATE/*` from hosted repo contents (`G-11`)
- [ ] pull request template is configured when public contribution is expected (`G-12`)

## Security And Automation

- [ ] Secrets are used instead of plain-text credentials
- [ ] Dependabot decision is explicit and recorded with reason in the publication decision record (`G-17`)
- [ ] secret scanning decision is explicit and recorded with reason in the publication decision record (`G-16`)
- [ ] code scanning decision is explicit and recorded with reason in the publication decision record (`G-18`)
- [ ] every `conditional` item in `regulation/reference/TOOL_VERIFICATION_MATRIX.md` has an explicit enabled/disabled/waived decision

## Release Surface

- [ ] Releases strategy is decided
- [ ] changelog route is explicit (`G-19`)
- [ ] publication decision record exists (`G-20`) at `audits/<repository-slug>/publication-decision-record.md`
