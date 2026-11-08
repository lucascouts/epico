# Constitution

<!-- Cross-story rules for the Epico plugin repository. Written by /epico:epico init
     on 2026-10-23; soft constraints — a story that breaks one carries a
     [CONSTITUTION] warning, not a block. Re-run `/epico:epico init --repair` to
     refresh the managed CLAUDE.md block after editing this file. -->

## Architecture
- Scripts depend on bash, jq and git only — no new runtime dependency in the plugin's scripts
- Every script under `scripts/` speaks one JSON contract on stdout, documented in its header; exit 0/1/2 mean done/refused/bad usage
- Every script a reference tells Claude to run is called through its `bin/epico-*` wrapper by bare name, never through a path
- Hooks never block a session on their own failure; a guard that cannot decide says so instead of passing

## Testing
- TDD: the bats case is written first and seen failing (Red) before the change that makes it pass
- The suite (`tests/run-suite.sh`, or `bats tests/`) runs as a normal user — root reads `chmod 000` files and turns refusal cases into false reds
- Tests use real temp directories and real git repos; git state is never mocked
- An assertion is never a `!`-inverted command (errexit ignores it); use `run` + a status check or a count

## Naming
- Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`), one-line subject, `!` for a breaking change
- PATH commands are `epico-<verb>`; scripts are `<verb>-<noun>.sh`; tests mirror the script name
- Everything written — code, comments, docs, commits — is in English

## Quality
- Formatting — omitted: the scripts were never `shfmt`-formatted (32 files differ); adopting `shfmt -l scripts bin hooks` is a decision of its own
- Lint — `shellcheck scripts/*.sh bin/*` exits 0
- Types — omitted: bash has no type checker
- Error handling — every script runs under `set -euo pipefail` and refuses with its reason in the JSON; the story's bats cases prove the refusal paths
- Unit tests — `tests/run-suite.sh` passes, as a normal user (every file in parallel; `bats tests/` is the same suite in one process)
- Lockfile and frozen install — no dependencies: the plugin installs nothing
- Dependency vulnerabilities — no dependencies; `trivy fs .` gives the verdict
- Secrets — `gitleaks git .` reports no leaks; the pre-commit hook runs it on staged changes
- README — `README.md` names how to install and how to run the checks
- `.gitignore` and `.editorconfig` — `.gitignore` exists; `.editorconfig` missing (recommended — not written)
- Supported and declared runtime — Claude Code 2.1.295+ is declared in the README and CHANGELOG; bash, jq and git have no declaration a tool reads (recommended: `.tool-versions`)
- Dependencies justified and current — none to justify
- Hardened workflows — `.github/workflows/` present; `zizmor .github/workflows` (recommended — not installed) · `actionlint` (recommended — not installed); meanwhile `opengrep scan --config p/github-actions .github/workflows`
- Pre-commit hook — `.pre-commit-config.yaml`; `pre-commit run --all-files`
- Licence, SBOM, signing — distributed through a marketplace: `LICENSE` exists; no build artifact to SBOM or sign
- Security policy — `SECURITY.md` exists and names a private channel
- Branch protection — `gh api repos/lucascouts/epico/rules/branches/main` lists `deletion`, `non_fast_forward` and `required_status_checks` (today: none — the ruleset targets no branch)
- Minimum dependency age — Dependabot `cooldown` of 7 days on GitHub Actions
- CI mirror — build once `docker build -t epico-act:26.04 ci/act-ubuntu-26.04`, then `act -P ubuntu-26.04=epico-act:26.04 --pull=false -j <job>` for `shellcheck`, `validate-examples`, `plugin-validate` and `bats`, from a clean clone (never a git worktree: its `.git` points outside the mount). The image is the runner's Ubuntu 26.04 (uutils coreutils) as a non-root user, so all four pass; the published act images are 24.04/GNU and root
- Plugin schema — `claude plugin validate --strict` on `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills`, `agents`

## Defaults
- Data files the program creates — gitignored
- Tests in Fast stories — written silently
- Free-text fields — validated as text
- Branch for story commits — the current branch

## Security floor
- Supported and declared runtime — Claude Code 2.1.295 or newer; bash 5, jq and git from the host
- Secrets — `gitleaks git .`
- Dependency vulnerabilities — no dependencies; `trivy fs .` gives the verdict
- README — how to install it and how to check it
- Data integrity — a file the program reads back is written through a temporary file and a rename; a missing, corrupted or wrong-shaped one never crashes the program or gets overwritten, an earlier set-aside copy is never replaced, and a failed save says so (`no persisted data` when there is none)

## Reversibility
- An irreversible step — deleting data, a migration without a down, a force push, a publish, a release — runs only with a way back recorded first (a backup, a down migration, a tag) or on the user's explicit yes

## Runtime
- host — a developer's plugin: bash, jq, git and Claude Code from the machine, as CI uses them

## Invariants
- Pillars, in order — Security, Stability, Performance: on a conflict the earlier one wins; a performance shortcut carries the proof that the result stays the same, and nothing skips a security check (PURPOSE.md, Foundation pillars)
