# Contributing

## Before you open a pull request

```bash
tests/run.sh
```

Nineteen checks across four groups — privacy, build, lint and docs. Builds run
in a throwaway copy of the working tree, so the suite never touches your own
`resume.md`. A check whose tool is missing is skipped rather than failed, so
this works without `shellcheck` and `ruff` installed; CI runs them regardless.

You need Pandoc 2.17 or newer and Python 3.9 or newer. See the README's
[Installing Pandoc](README.md#installing-pandoc) section.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org).
CI runs [commitlint](https://github.com/conventional-changelog/commitlint)
against every commit in a pull request, so a message that doesn't parse will
fail the build.

```
<type>(<optional scope>): <subject>

<optional body>

<optional footer>
```

The subject starts lower-case and takes no full stop. Types:

| Type | Use for |
|---|---|
| `feat` | A new capability |
| `fix` | A bug fix |
| `docs` | README, this file, comments |
| `style` | Formatting that does not change behaviour |
| `refactor` | Restructuring that neither fixes a bug nor adds a feature |
| `perf` | A performance improvement |
| `test` | Anything under `tests/` |
| `build` | `build.sh`, `make_reference.py`, the design pipeline itself |
| `ci` | `.github/workflows/`, lint configuration |
| `chore` | Housekeeping that fits nothing above |

Real examples from this repository:

```
ci: add privacy, build, lint and docs checks
style: fix lint findings and pin the ruff contract
fix: resolve pandoc "latest" without the GitHub API
```

A breaking change takes a `!` before the colon — `build!: drop Python 3.9` —
and should explain the migration in the body.

### Checking before you push

```bash
npx --yes @commitlint/cli@21.2.2 --from origin/main --to HEAD --verbose
```

`tests/run.sh lint` runs the same check automatically when commitlint is
available locally, and skips it otherwise.

## What the checks will not let through

Two rules encode decisions rather than style, and the test suite enforces both:

- **No personal content.** Nothing matching a resume filename may be tracked.
  This repository is public and a rendered resume carries a phone number and
  an email address.
- **No bullet carries an `@@` date.** A bullet's right indent moves its tab
  stop inward, so a date on a bullet stops short of every other date on the
  page.
