# Local Public Prep Checklist

Status: Active

Tier: 1

Evidence: `../EVIDENCE_COMMANDS.md`
Gate mapping: `../GATE_REGISTRY.md`
Judgment guide: `../JUDGMENT_GUIDE.md`

## Minimum

- [ ] baseline secret scan performed with `Gitleaks` (`G-01`)
- [ ] tracked file inventory captured with `git ls-files` (`G-02`)
- [ ] every tracked file fully read or explicitly excepted (`G-21`)
- [ ] no unnecessary large generated files remain tracked (`G-22`)
- [ ] internal-management folders are excluded by `.gitignore` (`G-04`)
- [ ] developer-only AI files are not tracked (`G-03`)
- [ ] `README.md` exists and explains what the repository is (`G-05`)
- [ ] `LICENSE` exists (`G-06`)
- [ ] `SECURITY.md` exists (`G-07`)
- [ ] `CHANGELOG.md` exists, or release history is explicitly documented elsewhere (`G-08`)
- [ ] `CODE_OF_CONDUCT.md` exists when public contribution is expected (`G-09`)
- [ ] `CONTRIBUTING.md` exists when outside contribution is expected (`G-10`)
- [ ] if AI navigation is needed, guidance is in user-facing docs such as `README.md` or `docs/`
- [ ] `.gitignore` public-prep blocks merged when needed (`templates/gitignore.public-prep.template`)

## Optional Expansion

- [ ] `git-secrets` hook route enabled when wanted
- [ ] `TruffleHog` run when deeper secret validation is required
- [ ] `git-sizer` run when repository history or assets suggest size risk
- [ ] `git filter-repo` prepared only if history rewrite is required
- [ ] `docs/` exists for broader user documentation
- [ ] examples or demo assets exist
- [ ] badges prepared for later README placement