# Dependency and tool caches

Read before a sub-task that installs dependencies, builds an image, runs a gate tool (SCA, SAST, the CI mirror) or sets up E2E — by the Executor and by the main agent on the inline route.

**Why it exists.** A run that downloads its dependencies, a vulnerability database or a container image again on every check spends the requester's minutes on the network and fails when Docker Hub, GitHub or a registry is slow or rate-limited — a red that says nothing about the code. Every tool below keeps a cache on the machine; the rule is to let it work. The plugin's pillars set the bound ([PURPOSE.md](../PURPOSE.md#foundation-pillars)): performance never outranks security, so **a cache never skips a security update and never turns an integrity check off.**

## The rule

1. **Never force a re-download** — no `--no-cache`, `--pull` or `--pull=always`, `go clean -modcache`, `npm cache clean`, `pip --no-cache-dir`, a deleted `~/.cache/…` — unless re-downloading is the sub-task's purpose (a cache suspected corrupt, a pinned version that must be fetched to be verified), and then say so in the report.
2. **Install offline-first, with the lockfile's integrity still checked** — the commands below read the cache before the network and still verify every hash the lockfile records.
3. **Fetch once, then run against the cache** — a dependency set is downloaded in one step and every later build, test and gate reuses it.
4. **Leave the default cache paths alone** — every tool below finds its cache by itself; pointing it at a temporary directory throws the cache away.

## Language dependencies

| Ecosystem | Install, offline-first | Cache it fills (default) |
|---|---|---|
| npm | `npm ci --prefer-offline --no-audit --no-fund` | `~/.npm` |
| pnpm | `pnpm install --frozen-lockfile --prefer-offline` | the pnpm store |
| Yarn (Berry) | `yarn install --immutable` | `~/.yarn/berry/cache`, or the project's offline cache |
| Python | `uv sync --frozen`; with pip, `pip install --require-hashes -r requirements.txt` | `~/.cache/uv`, `~/.cache/pip` |
| Go | `go mod download` once; builds and tests then reuse it | `$(go env GOMODCACHE)`, `$(go env GOCACHE)` |
| Rust | `cargo fetch` once, then `cargo build --frozen` and `cargo test --frozen` | `~/.cargo/registry` |
| PHP | `composer install` | `~/.cache/composer` |
| Ruby | `bundle install --prefer-local` | the gem directory |

**Integrity stays on.** Never `GOSUMDB=off`, or `GONOSUMDB` and `GOINSECURE` for a public module, `npm install --no-package-lock`, `pip install` without `--require-hashes` where the project pins hashes, or `--frozen-lockfile=false` to get past a cache problem: each one trades the check that a download is the one the lockfile pinned for a run that finishes.

## Tool data

- **trivy** keeps its vulnerability database in `~/.cache/trivy` and refreshes it on its own schedule (the database's `NextUpdate`, about a day). Run `trivy fs .` as is: never `--skip-db-update`, `--reset` or `clean --all` in a project's check — a stale database is a check that passes on a known CVE.
- **opengrep** fetches a registry ruleset (`--config p/<name>`) on every scan. Fetch it once into `~/.cache/epico/opengrep/<name>.yml` — `curl -fsSL https://semgrep.dev/c/p/<name> -o ~/.cache/epico/opengrep/<name>.yml` — and scan with `--config ~/.cache/epico/opengrep/<name>.yml`. Fetch it again when the file is **older than seven days** (`find ~/.cache/epico/opengrep -name '<name>.yml' -mtime -7` prints nothing), so new rules reach the scan within a week.
- **gitleaks** downloads nothing.

## Containers and the CI mirror

- A base image is pinned by digest (`image@sha256:…`) and pulled only when absent: `docker build` without `--pull`, and the digest guarantees the cached image is the pinned one.
- A Dockerfile the plugin writes copies the lockfile before the sources and installs through a BuildKit cache mount, so a source change reuses the dependency layer and a lockfile change reuses the download cache: `RUN --mount=type=cache,target=/root/.npm npm ci`, `target=/root/.cache/uv`, `target=/go/pkg/mod`, `target=/usr/local/cargo/registry`.
- The CI mirror runs `act --pull=false --action-offline-mode -j <job>`: the runner image comes from the local store and each action from `~/.cache/act`, fetched once.

## E2E browsers

Playwright keeps its browsers in `~/.cache/ms-playwright`, shared by every project on the machine. Install one only when the project's pinned Playwright revision is missing there (`npx playwright install chromium` downloads nothing when it is present); never set `PLAYWRIGHT_BROWSERS_PATH` to a project or temporary directory.

## CI workflows the plugin writes

A workflow written at `product` level caches what this reference caches locally: `actions/setup-node`, `setup-python` and `setup-go` with `cache:` keyed on the lockfile, `actions/cache` for `~/.cargo/registry` and for `~/.cache/trivy`, each pinned by commit SHA like every action ([quality-catalog.md](quality-catalog.md), *Hardened workflows*). On a runner a cache saves the download and the rate limit; the checks themselves stay the same.
