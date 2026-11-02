#!/usr/bin/env bash
# Stop hook: an English sentence that reached the requester in a conversation
# held in another language blocks the end of the turn, once, quoting it, and
# asks the closing to say the same things again in the requester's language.
#
# Why a rewrite and not a legend: the 2026-10-30 SDD battery found English
# narration between tool calls in 10/14 epico runs, and the legend guard
# (hook-legend-guard.sh) answered "Quality gates" with a legend for a child — a
# legend explains a word, not a sentence nobody could read. A rule asking not to
# narrate in English is ignored (SKILL.md, Language), and a PostToolUse nudge
# measured no better than noise on 2026-09-27, so this hook reads what was
# actually written and asks for the rewrite where the requester will read it.
# Unmeasured against the 10/14 baseline: a battery has to show it works.
#
# Only in a session that invoked the epico (a Skill call to epico:*, or the
# /epico:epico command), and only when the requester's latest prompt — or, when
# it is too short to tell, all their prompts — is not English. The lean route
# writes no story, so the gate is the session, not a tasks.md. Fails open, so a
# guard defect never traps a turn: unreadable input, a second stop attempt
# (stop_hook_active, the documented loop guard), no transcript, or a language
# it cannot tell.

set -euo pipefail

INPUT=$(cat)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo true)
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT="${TRANSCRIPT/#\~/$HOME}"
[ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || exit 0

# One jq pass: did the session invoke the epico, the latest real prompt, every
# real prompt, and this turn's assistant text. A tool result arrives as a user
# entry too, and is neither a prompt nor the start of a turn.
FIELDS=$(jq -rs '
  def prompt: .type == "user" and (
    (.message.content | type) == "string"
    or ([.message.content[]? | select(.type == "text")] | length > 0));
  def ptext: if (.message.content | type) == "string" then .message.content
             else [.message.content[]? | select(.type == "text") | .text] | join(" ") end;
  (any(.[]; .type == "assistant" and any(.message.content[]?;
      .type == "tool_use" and .name == "Skill" and ((.input.skill // "") | test("^epico(:|$)"))))
   or any(.[]; prompt and (ptext | contains("/epico:epico")))) as $epico
  | (map(prompt) | rindex(true)) as $start
  | [ .[] | select(prompt) | ptext ] as $prompts
  | {epico: $epico,
     last: ($prompts | last // ""),
     all: ($prompts | join(" ")),
     turn: (.[(($start // -1) + 1):]
            | map(select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text)
            | join("\n"))}' "$TRANSCRIPT" 2>/dev/null || true)
[ -n "$FIELDS" ] || exit 0
[ "$(printf '%s' "$FIELDS" | jq -r '.epico')" = "true" ] || exit 0

# English function words that no Portuguese or Spanish sentence uses. "a", "as",
# "do", "no", "so" and "to" are left out: each is also a Portuguese word.
EN_WORDS="the and is are was were be been now then let lets i i'll i'm i've we we'll
it it's its this that these those with for of in on at by from into all will would
should can could need needs next done pass passes passed write writing wrote run
running ran check checking checked confirmed first before after there here what
which how why has have had does did not but if when just also my our your you they
an or test tests file files add adding fix fixed update create creating implement
implementation now please"

# en_ratio — prints "words hits" for the text on stdin.
en_ratio() {
  awk -v list="$EN_WORDS" '
    BEGIN { n = split(list, w, /[ \n]+/); for (i = 1; i <= n; i++) en[w[i]] = 1 }
    { line = tolower($0); gsub(/[^a-z'\'']+/, " ", line)
      k = split(line, t, / +/)
      for (i = 1; i <= k; i++) if (t[i] != "") { words++; if (t[i] in en) hits++ } }
    END { printf "%d %d\n", words, hits }'
}

# english — true when the prompt text on stdin reads as English.
english() {
  local words hits
  read -r words hits < <(en_ratio)
  [ "$words" -ge 3 ] || return 2
  [ $((hits * 10)) -ge $((words * 3)) ]
}

LAST=$(printf '%s' "$FIELDS" | jq -r '.last')
set +e
printf '%s\n' "$LAST" | english; verdict=$?
if [ "$verdict" -eq 2 ]; then
  printf '%s' "$FIELDS" | jq -r '.all' | english; verdict=$?
fi
set -e
# 0 = English, 2 = cannot tell: both let the turn end.
[ "$verdict" -eq 1 ] || exit 0

TURN=$(printf '%s' "$FIELDS" | jq -r '.turn')
[ -n "$TURN" ] || exit 0

# Drop fenced blocks and inline code spans — a command or program output is not
# narration — then split into sentences and keep the English ones: four words or
# more, three of them English function words, and at least 40% of the sentence.
# shellcheck disable=SC2016
FOUND=$(printf '%s\n' "$TURN" \
  | awk '/^[[:space:]]*(```|~~~)/ { f = !f; next } !f' \
  | sed -E 's/`[^`]*`//g' \
  | awk -v list="$EN_WORDS" '
      BEGIN { n = split(list, w, /[ \n]+/); for (i = 1; i <= n; i++) en[w[i]] = 1 }
      { m = split($0, s, /[.!?;]+([ \t]+|$)/)
        for (j = 1; j <= m; j++) {
          sent = s[j]; gsub(/^[ \t>*#-]+|[ \t]+$/, "", sent)
          if (sent == "") continue
          line = tolower(sent); gsub(/[^a-z'\'']+/, " ", line)
          k = split(line, t, / +/); words = 0; hits = 0
          for (i = 1; i <= k; i++) if (t[i] != "") { words++; if (t[i] in en) hits++ }
          if (words >= 4 && hits >= 3 && hits * 10 >= words * 4 && !(sent in seen)) {
            seen[sent] = 1; if (++c <= 3) print substr(sent, 1, 160)
          }
        } }')
[ -n "$FOUND" ] || exit 0

QUOTED=$(printf '%s\n' "$FOUND" | jq -Rs 'split("\n") | map(select(. != "")) | map("«" + . + "»") | join("; ")')
jq -n --argjson q "$QUOTED" '{
  decision: "block",
  reason: ("These sentences reached the requester in English, in a conversation held in their language: " + $q + ". In your closing, say the same things again in the requester'"'"'s language — a rewrite of what those sentences told them, not a legend, a translation note or an apology — then end the turn. Do not mention this check.")
}'
