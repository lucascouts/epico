#!/usr/bin/env bash
# Stop hook: a finished group whose commit was never made blocks the end of the
# turn, once, with the exact message to commit.
#
# The commit is the run's last git step and the one an instruction alone keeps
# losing: a weaker model closes a group, writes the closing and stops with the
# work uncommitted. This hook reads the disk instead of trusting the turn. For
# every live story (.epico/stories/*/tasks.md), a group is FINISHED when its
# header is `[x]` or every sub-task it owns (by number prefix, N.M under N) is
# settled — `[x]` or `[~]`. A finished group that carries a `- Commit: <msg>`
# field — under its header or its sub-tasks, since a group may be written with
# no header line — owes a commit whose subject is that message, verbatim (the pre-authored
# message carries the story's anchor; references/run-mode.md, The Commit Field).
# No such subject in `git log` → block, naming each missing message.
#
# Only a session that is running a story owes the commit: when the transcript is
# readable and no Bash tool call in it ran epico-close (the one way a run closes a
# box), the session closed nothing and the guard stays silent — a session that
# merely opens the repository, with a group someone else left uncommitted, is not
# blocked turn after turn. With no readable transcript the guard cannot tell, and
# checks as before rather than drop the protection.
#
# Fails open, so a guard defect never traps a turn: unreadable input, a second
# stop attempt (stop_hook_active, the documented loop guard), no git work tree,
# no .epico/stories, and an empty `git config user.email` — run-mode makes no
# commit without an identity, by rule, and says so in the closing instead.

set -euo pipefail

INPUT=$(cat)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
if [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ]; then
  # Captured, not piped into grep -q: the same SIGPIPE trap as SUBJECTS below.
  CLOSES=$(jq -r 'select(.type == "assistant") | .message.content[]?
    | select(.type == "tool_use" and .name == "Bash") | .input.command // empty' "$TRANSCRIPT" 2>/dev/null || true)
  grep -qE '(^|[^[:alnum:]_-])(epico-close|close-subtask\.sh)' <<<"$CLOSES" || exit 0
fi
CWD=${CWD:-$PWD}
[ -d "$CWD" ] || exit 0

ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || exit 0
[ -d "$ROOT/.epico/stories" ] || exit 0
[ -n "$(git -C "$ROOT" config user.email 2>/dev/null || true)" ] || exit 0

# --all: a run inside a worktree commits on that worktree's branch, which the
# main tree's HEAD never reaches; HEAD alone blocked every turn and ordered a
# duplicate commit (seen 26/10, story 247: 10 blocked stops in one session).
SUBJECTS=$(git -C "$ROOT" log --all --format=%s 2>/dev/null || true)

# missing_commits <tasks.md> — one line per finished group whose Commit message
# is not a commit subject: "<group>\t<message>". Fenced blocks are documentation.
missing_commits() {
  awk '
    /^[[:space:]]*(```|~~~)/ { fence = !fence; next }
    fence { next }
    /^## / { gates = ($0 ~ /^## Quality Gates/) }
    gates { next }
    match($0, /^[[:space:]]*- \[([ x~])\] ([0-9]+)(\.[0-9]+)? - /) {
      box = substr($0, index($0, "[") + 1, 1)
      rest = substr($0, index($0, "]") + 2)
      split(rest, w, " ")
      num = w[1]
      if (num ~ /\./) {
        split(num, p, "."); g = p[1] + 0; cur = g
        subs[g]++
        if (box == " ") open[g]++
      } else {
        g = num + 0; cur = g; seen[g] = 1
        if (box == "x") hdr[g] = 1
      }
      next
    }
    match($0, /^[[:space:]]*-[[:space:]]+[Cc]ommit:[[:space:]]*/) && cur != "" {
      msg = substr($0, RLENGTH + 1)
      gsub(/^["`]|["`][[:space:]]*$/, "", msg)
      if (msg != "") commit[cur] = msg
    }
    END {
      for (g in commit) {
        finished = hdr[g] || (subs[g] > 0 && open[g] == 0)
        if (finished) printf "%s\t%s\n", g, commit[g]
      }
    }
  ' "$1"
}

REASONS=()
for tasks in "$ROOT"/.epico/stories/*/tasks.md; do
  [ -f "$tasks" ] || continue
  story=$(basename "$(dirname "$tasks")")
  while IFS=$'\t' read -r group msg; do
    [ -n "$msg" ] || continue
    # A here-string, not a pipe: grep -q exits on the first match, and under
    # pipefail the writer's SIGPIPE (141) would read as "missing" once the log
    # outgrows the pipe buffer.
    if ! grep -qxF -- "$msg" <<<"$SUBJECTS"; then
      REASONS+=("story $story, group $group: \"$msg\"")
    fi
  done < <(missing_commits "$tasks")
done

[ ${#REASONS[@]} -eq 0 ] && exit 0

LIST=$(printf -- '- %s\n' "${REASONS[@]}")
jq -n --arg list "$LIST" '{
  decision: "block",
  reason: ("These finished groups have no commit yet. Commit each now, in the main tree: stage the files its sub-tasks changed by name (never `git add -A`), with the message verbatim — then end the turn. Commit silently: do not mention this check or the commits to the user beyond the saved-copy line of the closing.\n" + $list)
}'
