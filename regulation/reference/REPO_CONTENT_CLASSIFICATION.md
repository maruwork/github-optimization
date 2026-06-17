# Repository Content Classification

Status: Active

## Principle

Every file in a repository is something users can download.
Before publication, ask of every tracked file: should the user receive this file?

Check command:

```bash
git ls-files
```

Machine screening (supports `G-03`, `G-04`, `G-21`):

```bash
# from regulation shelf scripts/
./scripts/check-tracked-files.sh <target-repo>
```

Read: `regulation/reference/TRACKED_FILE_SCREENING.md`

## Four Classes

| Class | Keep in repository | Examples |
|---|---|---|
| User-facing | yes | runtime scripts, skills, documents, installers |
| GitHub standard | yes | `README.md`, `LICENSE`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md` when support routing is needed, `.github/` |
| Developer-only settings | no | `AGENTS.md`, `CLAUDE.md`, `.claudeignore`, AI-tool settings |
| Internal management | no | work history, project-management folders, developer-only logs |

## AI Guidance Rule

If a public repository needs AI-related navigation help, publish it as normal user-facing docs such as `README.md`, `docs/`, or explicit operator guides.

Do not publish developer-only AI control files such as:

- `AGENTS.md`
- `CLAUDE.md`
- `.claudeignore`
- local AI-tool settings

## When To Set `.gitignore`

Add internal-management folders to `.gitignore` **when the project is created**.
Once something has been tracked with `git add`, untracking it later requires `git rm --cached`.

Typical exclusion targets:

```text
/common/
/index/
/archive/
/workspace/
```

## Scope

Apply this rule to every public repository, whether it is a tool, library, or script collection.
