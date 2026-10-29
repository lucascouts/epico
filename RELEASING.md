# Releasing

What a version cut involves. Where a step has a known trap, the trap is named rather than left to be rediscovered.

## 1. Verify locally, before anything is pushed

Local results are the evidence that the work is done — CI confirms them, it does not produce them.

```bash
bats tests/                              # as a normal user; see the trap below
shellcheck scripts/*.sh bin/*
for e in assets/examples/*.md; do bash scripts/validate-story.sh --help >/dev/null; done
gitleaks protect --staged=false          # and `gitleaks detect --log-opts main..HEAD`
jq -e . .claude-plugin/plugin.json .claude-plugin/marketplace.json
for p in .claude-plugin/plugin.json .claude-plugin/marketplace.json skills agents; do
  claude plugin validate --strict "$p"   # the schema Claude Code itself enforces
done
CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 claude plugin eval . --no-publish --scaffold --allow-tools Skill Bash Write Edit Agent   # evals/README.md
```

**Expected — `plugin.json` warns about `CLAUDE.md` in a development checkout.** Claude Code 2.1.312 and later warn that a `CLAUDE.md` at the plugin root is not loaded as plugin context, and `--strict` turns the warning into a failure. That file is the Epico's own managed block for this repository: it is gitignored, so the published plugin has none and a clean clone — CI included — passes. Read the validate result on a clean clone, not on this tree.

**Trap — run `bats` as yourself, not as root.** Some cases make a file unreadable and require the script to refuse. Root can read a `chmod 000` file, so the refusal never fires and those cases report false failures. This is why `act -j bats` (whose image runs as root) is **not** the faithful run.

## 2. Mirror CI locally

```bash
act -l                                   # list, no run
act -j shellcheck --pull=false           # faithful
act -j validate-examples --pull=false    # faithful
```

`act -j bats` is expected to fail only the unreadable-file cases above. Any *other* failure is real.

## 3. Optional — sample the scale choice

Scale choice is a property of the model's judgement, not of a script, so the test suite cannot see its instability. When a change touches triage, sample it: run the same request several times against this tree, each in a fresh scratch directory, and read the scale each run records.

```bash
for i in 1 2 3 4 5; do
  d=$(mktemp -d) && (cd "$d" && git init -q && claude -p --plugin-dir <this repo> \
       --allowedTools Skill Bash Write Edit Agent -- '<request>')
  grep -h '^scale:' "$d"/.epico/stories/*/tasks.md
done
```

`tasks.md` is the only place the chosen scale is legible — the plain register deliberately keeps the word out of the chat — so a run can be stopped as soon as that file is written. A run stopped early never emits the `result` event that carries the cost, so count its tokens from the stream if cost matters.

It is a **monitor, never a gate**: a distribution is read by a human before cutting the release, and one run that disagrees is information, not a build failure. A model-judgement measurement can swing from never to always on an unchanged tree, so a gate on it measures the calendar instead of the diff. Assertions belong in a deterministic lint; judgement belongs in monitoring.

## 4. Cut the version

Three sites, and they must agree. `marketplace.json` carries no version: for a plugin whose source is this repository, `plugin.json` is the one source.

| File | Where |
|---|---|
| `.claude-plugin/plugin.json` | `.version` |
| `README.md` | the version line near the end |
| `ARCHITECTURE.md` | "Last verified against" |

Then in `CHANGELOG.md`: promote `[Unreleased]` to `[N.N.N] — YYYY-MM-DD`, write the entry (what changed and why), state **Minimum Claude Code**, and repoint the link block so `[Unreleased]` compares from the new tag.

```bash
grep -rn '<previous version>' --include='*.md' --include='*.json' . | grep -v CHANGELOG
```

should return nothing: every remaining mention belongs to the changelog's own history.

## 5. Ship

The repository merges by pull request, and every merge on `main` is a **merge commit** — `git log --first-parent main` shows two parents on each. A feature PR merges with a `feat: … (#N)` subject rather than the default text.

```bash
git push -u origin <branch>
gh pr create --base main --title '…' --body-file <body>
gh pr checks <N>                         # 5 checks: bats, shellcheck, validate-examples, Analyze, CodeQL
gh pr merge <N> --merge --delete-branch --subject 'feat: … (#N)'
```

`Analyze` / `CodeQL` have no local equivalent — CodeQL is the one check that genuinely cannot run here, and it is the only part of a release not verified before the push.

Then the tag, **annotated**, on the merge commit:

```bash
git checkout main && git pull --ff-only
git tag -a vN.N.N <merge-sha> -m 'Epico vN.N.N — <one line>'
git push origin vN.N.N
```

**The tag is not the release.** Every version gets a GitHub Release object: a pushed tag alone leaves the version invisible on the releases page even though the `releases/tag/…` link in the CHANGELOG still resolves — which is exactly how this step gets missed. Create it from the version's own CHANGELOG section, verbatim, titled `Epico vN.N.N`:

```bash
awk '/^## \[N\.N\.N\]/{f=1; next} /^## \[/{f=0} f' CHANGELOG.md > /tmp/notes.md
gh release create vN.N.N --title 'Epico vN.N.N' --notes-file /tmp/notes.md --verify-tag
gh release list --limit 3        # the new one must read Latest
```

`--verify-tag` refuses rather than inventing a tag that was never pushed.
