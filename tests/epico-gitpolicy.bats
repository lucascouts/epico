#!/usr/bin/env bats
# scripts/epico-gitpolicy.sh — contradiction lint.
# Contract: read-only script, run from the workspace root, emitting JSON:
#   {policy: tracked-md|local-only|undeclared, gitignore_ignores_epico: bool,
#    tracked_md: N, tracked_draft: N, verdict: consistent|contradiction|partial}
# Verdicts:
#   consistent    — reality matches the declared policy (or undeclared+untracked)
#   contradiction — tracked .epico files under an ignoring gitignore,
#                   or tracked-md declared but gitignore blocks tracking
#   partial       — .draft/ files tracked, or subset tracking
# Non-git workspace: {git: false, policy: …, verdict: "consistent"} and nothing
# else.
# Exit 0 always (except usage errors, 2). Uses real temp git repos — no
# mocked git state (fidelity: the lint's whole job is reading git reality).

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK=$(mktemp -d)
}

teardown() {
  rm -rf "$WORK"
}

init_repo() {
  cd "$WORK"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
}

make_epic_artifacts() {
  mkdir -p "$WORK/.epico/stories/001-sample/.draft"
  cat > "$WORK/.epico/stories/001-sample/story.md" <<'EOF'
---
story: sample
version: 1
created: 2026-08-02
---
# Story
EOF
  cat > "$WORK/.epico/stories/001-sample/tasks.md" <<'EOF'
---
version: 1
created: 2026-08-02
---
- [ ] 1 - Do it
EOF
  echo "wip note" > "$WORK/.epico/stories/001-sample/.draft/notes.md"
}

run_lint() {
  cd "$WORK"
  run bash "$PLUGIN_ROOT/scripts/epico-gitpolicy.sh"
}

@test "local-only policy with ignoring gitignore and nothing tracked is consistent" {
  init_repo
  make_epic_artifacts
  echo ".epico/" > "$WORK/.gitignore"
  echo "local-only" > "$WORK/.epico/.gitpolicy"
  git add .gitignore
  git commit -qm "init"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.policy')" = "local-only" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}

@test "tracked-md policy with tracked artifacts and .draft ignored is consistent" {
  init_repo
  make_epic_artifacts
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  printf '.draft/\n*.wip\n' > "$WORK/.epico/.gitignore"
  git add .epico/.gitignore .epico/.gitpolicy .epico/stories/001-sample/story.md .epico/stories/001-sample/tasks.md
  git commit -qm "track epic artifacts"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.policy')" = "tracked-md" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" -gt 0 ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" = "0" ]
}

@test "tracked .epico files under an ignoring gitignore is a contradiction" {
  init_repo
  make_epic_artifacts
  echo ".epico/" > "$WORK/.gitignore"
  git add .gitignore
  git add -f .epico/stories/001-sample/story.md .epico/stories/001-sample/tasks.md
  git commit -qm "tracked through an ignoring gitignore"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "contradiction" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "true" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" -gt 0 ]
}

@test "tracked .draft files yield verdict partial" {
  init_repo
  make_epic_artifacts
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  git add .epico/.gitpolicy .epico/stories/001-sample/story.md \
    .epico/stories/001-sample/tasks.md .epico/stories/001-sample/.draft/notes.md
  git commit -qm "over-tracked: .draft in history"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "partial" ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" -gt 0 ]
}

@test "undeclared policy with nothing tracked is consistent" {
  init_repo
  make_epic_artifacts
  git commit -q --allow-empty -m "no epic tracking, no policy"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.policy')" = "undeclared" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}

@test "non-git workspace reports git:false, verdict consistent, exit 0" {
  mkdir -p "$WORK/.epico"
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.git')" = "false" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
}

# --- gitignore_source and the non-git policy key -----------------------------
# The four cases below pin `gitignore_source` on the git path and `policy` on
# the non-git path. Reference documents instruct agents to read both keys, so
# deleting either must fail the suite.
#
# 1. `gitignore_source` answers WHICH exclude file matched, which the
#    boolean beside it cannot. Git consults three sources and
#    `gitignore_ignores_epico: true` fires for any of them, but only the
#    workspace-root `.gitignore` is a file init may offer to edit:
#    references/init-mode.md gates its removal offer on
#    `gitignore_source == ".gitignore"`, reports `.git/info/exclude` as a file
#    local to the clone that it does not touch, and treats anything else as the
#    user's global core.excludesFile, which governs every repository on the
#    machine. references/list-mode.md prints the same field verbatim in its
#    notice. So the first two cases pin the two answers the boolean conflates,
#    and each is written to stay GREEN under the other's regression — a pair
#    that dies together pins one fact, not two.
#
# 2. The `null` case asserts the jq TYPE, and that is the whole case.
#    `jq -r .gitignore_source` prints the same four letters for a JSON null, for
#    the STRING "null" — a path named "null", which a consumer's `!= null` test
#    would miss, and precisely why the script emits the literal bare — and for a
#    key that is not in the document at all. Three different objects, one
#    identical line of output, so the obvious assertion cannot tell the contract
#    from two regressions. `| type` separates the string from the other two and
#    `has()` separates absent from present; both are asserted.
#
# 3. `policy` is emitted on the non-git object because the declared policy is
#    read from a plain file that needs no repository, and withholding it would
#    force init, whose defining workspace is a folder nobody has `git init`-ed
#    yet, to grow a second parser for `.epico/.gitpolicy`. The four MEASUREMENT
#    keys stay absent, because nobody measured them and because a consumer
#    reading one there aborts under `set -u`. That case therefore pins the exact key SET, not just
#    the one key.
#
# FIXTURE ISOLATION, and why only these cases carry it. A global
# core.excludesFile ignoring `.epico` — or an XDG `~/.config/git/ignore`, which
# git reads with no config entry at all — turns the "nothing ignores it" case
# into `true` with the developer's own home directory as the source, on one
# machine and not another. `isolate_git_env`
# points every exclude source git can consult at a directory that DOES NOT
# EXIST:
#   HOME + XDG_CONFIG_HOME  the global config, and the ignore file git finds at
#                           $XDG_CONFIG_HOME/git/ignore or $HOME/.config/git/
#                           ignore even when core.excludesFile is unset
#   GIT_CONFIG_NOSYSTEM     /etc/gitconfig, which may set core.excludesFile
#   GIT_TEMPLATE_DIR=       the init template, whose info/exclude is copied into
#                           every new repository
# GIT_CONFIG_GLOBAL is the more obvious spelling and is deliberately NOT used:
# redirecting HOME and XDG_CONFIG_HOME already covers every global config path,
# while GIT_CONFIG_GLOBAL would put a git >= 2.32 floor on this file for
# nothing. The directory is never created — git treats an absent HOME as an
# empty one — so the worktree under test stays pristine and `teardown` still
# reclaims everything under $WORK. The empty
# template is why the `.git/info/exclude` case creates that directory itself.

isolate_git_env() {
  export HOME="$WORK/.fixture-home"
  export XDG_CONFIG_HOME="$WORK/.fixture-home/.config"
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_TEMPLATE_DIR=
}

init_isolated_repo() {
  isolate_git_env
  init_repo
}

@test "gitignore_source names the root .gitignore when the rule lives there" {
  init_isolated_repo
  make_epic_artifacts
  echo ".epico/" > "$WORK/.gitignore"
  git add .gitignore
  git commit -qm "root gitignore ignores .epico"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "true" ]
  # The one source init may offer to edit, and the only value that unlocks the
  # removal offer in references/init-mode.md step 5.3b.
  [ "$(echo "$output" | jq -r '.gitignore_source')" = ".gitignore" ]
}

@test "gitignore_source names .git/info/exclude when the rule lives there and the root .gitignore is innocent" {
  init_isolated_repo
  make_epic_artifacts
  # The root file EXISTS and says nothing about .epico. That is the shape a
  # consumer assuming ".gitignore" gets wrong: it would quote a line that is not
  # there, or delete one that is not the rule.
  printf 'node_modules/\n*.log\n' > "$WORK/.gitignore"
  # GIT_TEMPLATE_DIR is empty, so `git init` created no .git/info; a real
  # repository always has one, so the fixture makes it the way git would.
  mkdir -p "$WORK/.git/info"
  printf '.epico/\n' >> "$WORK/.git/info/exclude"
  git add .gitignore
  git commit -qm "the exclude rule is local to this clone"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "true" ]
  [ "$(echo "$output" | jq -r '.gitignore_source')" = ".git/info/exclude" ]
}

@test "gitignore_source is JSON null, not the string 'null', when nothing ignores .epico" {
  init_isolated_repo
  make_epic_artifacts
  git commit -q --allow-empty -m "no exclude rule in any source"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "false" ]
  # NOT `jq -r .gitignore_source`: that prints `null` for the contract, for a
  # quoted "null" string and for a deleted key alike. `type` rejects the string;
  # `has` rejects the deletion. The key is emitted on every git path, present
  # and null, which is what makes init's `null` row reachable.
  [ "$(echo "$output" | jq -r '.gitignore_source | type')" = "null" ]
  [ "$(echo "$output" | jq -r 'has("gitignore_source")')" = "true" ]
}

@test "non-git workspace reports the declared policy, and only the three total keys" {
  isolate_git_env
  mkdir -p "$WORK/.epico"
  # local-only, deliberately not the tracked-md the earlier non-git case writes:
  # the value has to be READ FROM THE FILE, and a hardcoded constant would
  # satisfy a fixture that reused the same spelling.
  echo "local-only" > "$WORK/.epico/.gitpolicy"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.git')" = "false" ]
  [ "$(echo "$output" | jq -r '.policy')" = "local-only" ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
  # "Show nothing" is the other half: the four measurement keys stay absent
  # because nothing measured them. `keys` is sorted, so this pins the SET rather
  # than the emission order, which is the emitter's business and not a contract
  # any consumer reads.
  [ "$(echo "$output" | jq -r 'keys | join(",")')" = "effective,git,policy,verdict" ]
}

# --- One case per verdict arm -----------------------------------------------
# EVERY VERDICT ARM NEEDS ITS OWN CASE. The cases above reach arm 1 (artifacts
# tracked under an ignoring rule), arm 3 (tracked .draft/) and `consistent`;
# the cases below reach arms 2, 4 and 5, each of which reference documents
# instruct an agent to render a row for. The arms form an ordered chain, and an
# order no test can reach one arm at a time is enforced by nothing but a
# comment.
#
# EACH CASE PINS AN ARM *AND* ITS NEIGHBOURS. Two arms answer `contradiction`
# and three answer `partial`, so the verdict string alone never says WHICH arm
# produced it: every case below also asserts the fields that separate it from
# the arm next door — `tracked_draft` (rules out arm 3), `policy` (rules out
# arms 4 and 5), `gitignore_ignores_epico` (rules out arms 1 and 2). "It returned
# partial" is not evidence about where it came from.
#
# All four use init_isolated_repo, and not one of them could use init_repo:
# every one asserts `gitignore_ignores_epico` (three of them assert `false`), and
# a developer whose global core.excludesFile ignores .epico would flip that field — and with it the arm — on their machine and
# not on the next one.

@test "tracked-md declared while an exclude rule blocks .epico, with nothing tracked, is a contradiction" {
  # ARM 2 — arm 1's silent twin. Arm 1 needs a file to have got into the index anyway; here nothing
  # did, and nothing ever will: the policy file says track, the exclude rules
  # forbid it, and every future `git add .epico` will report success while adding
  # nothing at all. Git will never mention it, which is the whole reason this
  # script exists.
  # Delete this case and arm 2 can be dropped as "redundant with arm 1" with the
  # suite fully green — after which this workspace reads `consistent`, i.e. the
  # lint blesses a declaration it can prove is unreachable.
  # references/list-mode.md:77 is the row an agent is instructed to render for
  # it, and the sole consumer of the "no artifact can be committed" wording.
  init_isolated_repo
  make_epic_artifacts
  echo ".epico/" > "$WORK/.gitignore"
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  git add .gitignore
  git commit -qm "declared tracked-md, but the root gitignore forbids it"
  run_lint
  [ "$status" -eq 0 ]
  echo "$output" | jq -e . > /dev/null
  [ "$(echo "$output" | jq -r '.verdict')" = "contradiction" ]
  # THE TWO ZEROES ARE WHAT SAY "ARM 2" RATHER THAN ARM 1, which answers with
  # the same word: arm 1 fires only when tracked_md + tracked_draft > 0, so a
  # fixture that accidentally tracked one artifact would return an identical
  # verdict from the wrong arm and prove nothing about this one. They are also
  # what selects list-mode.md's row 77 over row 76.
  [ "$(echo "$output" | jq -r '.tracked_md')" = "0" ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" = "0" ]
  [ "$(echo "$output" | jq -r '.policy')" = "tracked-md" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "true" ]
  # Row 77 prints <source> verbatim; the row's fallback wording ("an exclude
  # rule") is for a null that this arm must never produce.
  [ "$(echo "$output" | jq -r '.gitignore_source')" = ".gitignore" ]
}

@test "tracked-md declared with the artifacts still untracked and nothing blocking is partial" {
  # ARM 4, AND THE MOST REACHABLE NON-CONSISTENT VERDICT IN THE PRODUCT.
  # references/init-mode.md:209 tells EVERY user who picks the recommended
  # option that this is the state they will be in the moment init finishes: init
  # records the intent and stages nothing, so the very next run of the lint
  # reports `partial` until one commit settles it.
  # Delete it and arm 4 can quietly collapse into `consistent`; the promise at
  # init-mode.md:209 and the `→` row at references/list-mode.md:79 — the one row
  # in that table that is a next step and not a warning — would then render for
  # nobody, and the follow-up commit would never be suggested.
  init_isolated_repo
  make_epic_artifacts
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  # The declaration exists, the artifacts are on disk, the index is empty of
  # them, and no exclude rule is in the way. That is the entire state, and it is
  # exactly what `/epico:epico init` leaves behind.
  git commit -q --allow-empty -m "policy recorded; first artifact commit not made yet"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "partial" ]
  # FOUR FIELDS, EACH RULING OUT ONE NEIGHBOUR:
  #   tracked_draft 0   arm 3 needs it > 0 and answers `partial` too
  #   policy tracked-md arm 5 needs local-only and answers `partial` too
  #   ignores false     arm 2 matches this same policy+count pair and would have
  #                     claimed the fixture FIRST, returning contradiction
  #   tracked_md 0      the arm's own first guard, and the reason the `→` row
  #                     may print the literal "0 tracked"
  [ "$(echo "$output" | jq -r '.tracked_md')" = "0" ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" = "0" ]
  [ "$(echo "$output" | jq -r '.policy')" = "tracked-md" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "false" ]
}

@test "tracked-md declared in a workspace with no artifacts at all stays consistent" {
  # THE GUARD, NOT THE ARM — and it needs its own case because the difference is
  # invisible in the JSON. Arm 4 carries two conjuncts and the case above
  # satisfies both, so it stays green if either is deleted. This fixture differs
  # from that one in a single fact: there is nothing under .epico/ to add. That
  # fact appears in NO reported field — both objects read `tracked_md: 0`,
  # `tracked_draft: 0`, `policy: tracked-md`, `gitignore_ignores_epico: false`,
  # `gitignore_source: null`, and differ ONLY in the verdict. The pair is
  # therefore the one way to pin epico_has_untracked_artifacts(), whose only
  # caller in the whole script is that arm.
  # Delete this and "there is something to add" can be dropped from arm 4 with
  # the suite green — after which every freshly initialised workspace, before it
  # has written a single story, is told on every listing to
  # `git add .epico && git commit` (references/list-mode.md:79) a directory with
  # nothing in it to add. That is the false positive the guard was written to
  # prevent, and a banner that fires on healthy workspaces is precisely how a
  # true signal teaches people to skip the line.
  init_isolated_repo
  mkdir -p "$WORK/.epico"
  echo "tracked-md" > "$WORK/.epico/.gitpolicy"
  # No make_epic_artifacts: the declaration, and not one story behind it.
  git commit -q --allow-empty -m "initialised workspace, no stories written yet"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "consistent" ]
  # Both of arm 4's other conditions ARE met here, which is what makes the
  # missing artifacts the only possible explanation for the silence.
  [ "$(echo "$output" | jq -r '.policy')" = "tracked-md" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" = "0" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "false" ]
}

@test "local-only declared with artifacts tracked anyway is partial" {
  # ARM 5: no exclude rule is being fought and git reports a perfectly clean tree — the
  # user simply changed their mind about tracking and never said so in the policy
  # file. Only the declaration and the index disagree, and this is the one place
  # that says so.
  # Delete this case and arm 5 can go; every workspace that reversed its own
  # local-only declaration then reads `consistent`, and the stale artifacts it
  # leaves behind go unreported.
  # references/list-mode.md:80 renders it, and it is the only row that prints
  # <tracked_md> against a declared local-only.
  init_isolated_repo
  make_epic_artifacts
  echo "local-only" > "$WORK/.epico/.gitpolicy"
  # The nested ignore is what keeps .draft/ out of the index, as a real
  # workspace's does. Without it a broad `git add .epico` would track notes.md,
  # tracked_draft would go > 0, and ARM 3 — a different arm, with the same
  # verdict and a different rendered row — would answer first.
  printf '.draft/\n' > "$WORK/.epico/.gitignore"
  git add .epico/.gitignore .epico/.gitpolicy \
    .epico/stories/001-sample/story.md .epico/stories/001-sample/tasks.md
  git commit -qm "local-only declared, artifacts committed anyway"
  run_lint
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.verdict')" = "partial" ]
  # policy local-only + tracked_md > 0 is arm 5 and no other arm; tracked_draft 0
  # rules out arm 3, and `ignores false` rules out arm 1, which would have turned
  # this very same tracked set into a contradiction.
  [ "$(echo "$output" | jq -r '.policy')" = "local-only" ]
  [ "$(echo "$output" | jq -r '.tracked_md')" -gt 0 ]
  [ "$(echo "$output" | jq -r '.tracked_draft')" = "0" ]
  [ "$(echo "$output" | jq -r '.gitignore_ignores_epico')" = "false" ]
  # The policy file and the nested .gitignore are tracked here too and are
  # deliberately NOT counted (is_md_artifact excludes them): counting them would
  # report a contradiction against the very file that declares the policy.
  [ "$(echo "$output" | jq -r '.tracked_md')" = "2" ]
}
