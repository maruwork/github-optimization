# GitHub Settings Checklist

Status: Active

Tier: 1

Evidence: `../EVIDENCE_COMMANDS.md`
Hosted boundary: `../HOSTED_SETTINGS_BOUNDARY.md`
Gate mapping: `../GATE_REGISTRY.md`

## Repository Metadata

- [ ] About description is filled (`G-13`)
- [ ] Topics are set (`G-14`)
- [ ] homepage or demo link is set when applicable

## Community Files

- [ ] Community Profile is reviewed (`G-15`)
- [ ] `CONTRIBUTING.md` exists when outside contribution is expected (`G-10`)
- [ ] issue template is configured (`G-11`)
- [ ] pull request template is configured when public contribution is expected (`G-12`)

## Security And Automation

- [ ] Secrets are used instead of plain-text credentials
- [ ] Dependabot decision is explicit (`G-17`)
- [ ] secret scanning decision is explicit (`G-16`)
- [ ] code scanning decision is explicit (`G-18`)
- [ ] every `conditional` item in `TOOL_VERIFICATION_MATRIX.md` has an explicit enabled/disabled/waived decision

## Release Surface

- [ ] Releases strategy is decided
- [ ] changelog route is explicit (`G-19`)
- [ ] publication decision record exists (`G-20`) at `docs/governance/publication-decision-record.md`