#!/usr/bin/env bats
# hook-commit-guard.sh: a finished group with no commit blocks the end of the
# turn once, naming the verbatim message; everything else fails open.
#
#   G1  finished group, commit missing → block naming story, group and message
#   G2  finished group, commit present → allow
#   G3  group still open → allow
#   G4  a header [x] counts as finished even with no sub-task listed as closed
#   G5  stop_hook_active → allow (the loop guard)
#   G6  no git identity → allow (run-mode makes no commit without one)
#   G7  not a git work tree, or no .epico/stories → allow
#   G8  a fenced example and a Quality Gates section are not groups
#   G9  hooks.json registers the guard on Stop
#   G10 a history larger than a pipe buffer still finds the subject (no SIGPIPE false miss)
#   G11 the commit made on a worktree's branch counts (a run in a worktree commits there)
#   G12 a readable transcript with no epico-close call → allow (no run in this session)
#   G13 a transcript whose Bash tool call ran epico-close → block, as with no transcript
#   G14 epico-close only quoted in a tool result (a reference read) is not a run → allow

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PLUGIN_ROOT/scripts/hook-commit-guard.sh"
  REPO=$(mktemp -d)
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name T
  git -C "$REPO" commit -q --allow-empty -m initial
  STORY="$REPO/.epico/stories/001-demo"
  mkdir -p "$STORY"
}

teardown() { rm -rf "$REPO"; }

# write_tasks <box 1.1> <box 1.2> [header box]
write_tasks() {
  local a=$1 b=$2 h=${3:- }
  cat > "$STORY/tasks.md" <<EOF
---
version: 1
scale: fast
---

## Task List
- [$h] 1 - Implement
  - Commit: "feat(001): implement the store"
  - [$a] 1.1 - Write the store
  - [$b] 1.2 - Write the CLI

## Quality Gates
- [ ] Q1 — Secrets: \`gitleaks detect\`
EOF
}

run_hook() { run bash -c "printf '%s' '$1' | bash '$HOOK'"; }

@test "G1 a finished group with no commit blocks, naming story, group and message" {
  write_tasks x x
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -r .reason | grep -qF 'story 001-demo, group 1: "feat(001): implement the store"'
  echo "$output" | jq -r .reason | grep -qF 'never `git add -A`'
}

@test "G2 the commit present with the verbatim subject allows the stop" {
  write_tasks x x
  git -C "$REPO" commit -q --allow-empty -m "feat(001): implement the store"
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G3 a group with an open sub-task owes nothing yet" {
  write_tasks x ' '
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  [ -z "$output" ]
}

@test "G4 a header marked done counts as finished" {
  write_tasks ' ' ' ' x
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  echo "$output" | jq -e '.decision == "block"'
}

@test "G5 stop_hook_active lets the turn end" {
  write_tasks x x
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": true}"
  [ -z "$output" ]
}

@test "G6 no git identity means no commit is owed" {
  write_tasks x x
  git -C "$REPO" config --unset user.email
  HOME=$(mktemp -d) run bash -c "printf '%s' '{\"cwd\": \"$REPO\"}' | GIT_CONFIG_GLOBAL=/dev/null bash '$HOOK'"
  [ -z "$output" ]
}

@test "G7 outside a git work tree, or with no stories, the hook stays silent" {
  plain=$(mktemp -d)
  run_hook "{\"cwd\": \"$plain\"}"
  [ -z "$output" ]
  rm -rf "$plain" "$REPO/.epico"
  run_hook "{\"cwd\": \"$REPO\"}"
  [ -z "$output" ]
}

@test "G8 fenced examples and the Quality Gates section are not groups" {
  cat > "$STORY/tasks.md" <<'EOF'
## Task List
```markdown
- [x] 9 - Example
  - Commit: "feat(001): only an example"
  - [x] 9.1 - Example sub-task
```
- [ ] 1 - Real
  - Commit: "feat(001): real"
  - [ ] 1.1 - Not done

## Quality Gates
- [x] 2 - Looks like a group
  - Commit: "feat(001): not a group"
EOF
  run_hook "{\"cwd\": \"$REPO\"}"
  [ -z "$output" ]
}

@test "G9 hooks.json registers the guard on Stop" {
  jq -e '.hooks.Stop[].hooks[] | select(.command | contains("hook-commit-guard.sh"))' "$PLUGIN_ROOT/hooks/hooks.json"
}

@test "G10 a history larger than a pipe buffer still finds the verbatim subject" {
  write_tasks x x
  # One old commit whose subject alone exceeds the 64 KiB pipe buffer, then the
  # owed commit on top: grep -q matches on the first line and exits while the
  # writer is still mid-stream — under pipefail that SIGPIPE read as a miss.
  head -c 200000 /dev/zero | tr '\0' a > "$REPO/.big-subject"
  git -C "$REPO" commit -q --allow-empty -F "$REPO/.big-subject"
  git -C "$REPO" commit -q --allow-empty -m "feat(001): implement the store"
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G11 the commit made on another worktree's branch allows the stop" {
  write_tasks x x
  # The story ran in a worktree and committed on its branch; the main tree's
  # HEAD never sees that commit, and blocking would order a duplicate commit.
  git -C "$REPO" worktree add -q -b story-001 "$REPO/.wt-001"
  git -C "$REPO/.wt-001" commit -q --allow-empty -m "feat(001): implement the store"
  run_hook "{\"cwd\": \"$REPO\", \"stop_hook_active\": false}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# write_transcript <command> — one assistant turn whose Bash tool call runs <command>,
# then a tool result quoting run-mode.md, which names epico-close in prose.
write_transcript() {
  TRANSCRIPT="$REPO/.transcript.jsonl"
  jq -cn --arg c "$1" '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}' > "$TRANSCRIPT"
  jq -cn '{type:"user",message:{content:[{type:"tool_result",content:"run-mode.md: epico-close <NNN> <N.N> closes one box"}]}}' >> "$TRANSCRIPT"
}

@test "G12 a session that closed no box owes no commit, whatever tasks.md says" {
  write_tasks x x
  write_transcript "git status"
  run_hook "{\"cwd\": \"$REPO\", \"transcript_path\": \"$TRANSCRIPT\"}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G13 a session that ran epico-close owes the commit" {
  write_tasks x x
  write_transcript "epico-close 001 1.2"
  run_hook "{\"cwd\": \"$REPO\", \"transcript_path\": \"$TRANSCRIPT\"}"
  echo "$output" | jq -e '.decision == "block"'
}

@test "G14 epico-close quoted in a tool result is not a run" {
  write_tasks x x
  write_transcript "cat references/run-mode.md"
  run_hook "{\"cwd\": \"$REPO\", \"transcript_path\": \"$TRANSCRIPT\"}"
  [ -z "$output" ]
}
