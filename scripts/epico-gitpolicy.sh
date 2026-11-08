#!/usr/bin/env bash
# Contradiction lint for a workspace's .epico git policy.
#
# Usage: epico-gitpolicy.sh          measure the CURRENT DIRECTORY, print JSON
#        epico-gitpolicy.sh --help
#
# Output: one JSON object on stdout —
#   {git: true, policy: tracked-md|local-only|undeclared,
#    effective: tracked-md|local-only,
#    gitignore_ignores_epico: bool, gitignore_source: "<path>"|null,
#    tracked_md: N, tracked_draft: N,
#    verdict: consistent|contradiction|partial}
# and, in a workspace that is not a git repository:
#   {git: false, policy: …, effective: …, verdict: "consistent"}
#
# `effective` is the policy the workspace runs under: the declared one, or for
# an undeclared workspace `tracked-md` when git tracks any .epico/ markdown
# artifact (tracked_md > 0) and `local-only` otherwise — .draft/ never counts.
# The checkpoint and the supervisors read it to decide whether their records
# are versioned; `policy` stays what was declared, so init still asks.
#
# CONSUMER REQUIREMENT — READ A MEASUREMENT KEY ONLY WHEN `git` IS true.
# `git`, `policy`, `effective` and `verdict` are TOTAL: every path emits all three, so they
# are safe to read unconditionally. The four MEASUREMENT keys are not —
# gitignore_ignores_epico, gitignore_source, tracked_md and tracked_draft are
# ABSENT from the non-git object, and `jq -r` renders an absent key as the
# literal text `null`, not as `false`, `""` or `0`. So the obvious
#   [[ "$(jq -r .tracked_md "$j")" -gt 0 ]]
# does NOT read false there: `-gt` evaluates its operands as arithmetic, bash
# takes the bare word `null` for a variable name, and under `set -u` the
# consumer ABORTS with "null: unbound variable" (bash 5.3).
# Gate every measurement read on `git == true`, or equivalently on
# `verdict != "consistent"` — the non-git object always reports `consistent`,
# so that gate is what keeps today's consumers safe. It is an invariant of this
# script, not of the JSON: state the gate in the consumer, do not infer it.
#
# Exit codes:
#   0  every measurement path, including "not a git repository" — a workspace
#      this cannot measure is not an error, it is a workspace with nothing to
#      say
#   2  usage error only (an argument this script does not take)
#
# WHY IT EXISTS: a workspace can commit .epico files THROUGH a .gitignore that
# says they are never committed, or change its policy and leave artifacts
# behind. Git never reports either, because both are merely self-contradictory;
# this is the one place that says so, in one line, from five measured facts.
#
# Governing principle: READ-ONLY. This script writes NO files and runs no git
# command that can mutate anything. Every git call has its non-zero status
# neutralised — `|| rc=$?` where the status is the answer, a process
# substitution where the OUTPUT is the answer (the shell never checks a
# procsub's status) — so an expected failure never trips `set -e`, and git
# stderr is silenced so the stdout JSON is the only thing consumers ever see
# (the same convention as scripts/story-git-status.sh).
#
# CONSUMERS read this with jq and nothing more: init pre-fills its question from
# `policy` + `gitignore_ignores_epico` and needs `gitignore_source` to know WHICH
# file to offer to edit, and the story list prints one header line when
# `verdict != consistent`. THAT SECOND CONSUMER IS WHY EVERY RULE BELOW IS
# WEIGHED FOR NOISE AND NOT ONLY FOR TRUTH: a verdict that fires on an ordinary
# healthy workspace fires on every single list. Where a rule had to choose, it
# chose silence, and the choice is argued at the rule.

set -euo pipefail

# --- String quoting ---------------------------------------------------------
# `policy` and `verdict` are normalised to one of three literals and the counts
# are integers, so those are safe by construction. `gitignore_source` IS NOT:
# it is a filesystem path git hands us, so it carries whatever bytes the
# workspace (or the user's global core.excludesFile) happens to contain — the
# one externally-authored string in this document, and the reason the escaper
# is live rather than defensive. It is the FULL C0/C1 table rather than
# validate-story.sh's lighter \ " \n \r \t variant because a path may hold ANY
# byte but /, and a single unescaped control byte would make the WHOLE document
# unparseable while the script still exits 0 — an undefined consumer path,
# because exit 0 is the contract's promise that the JSON is readable. A repo
# under a directory whose name contains a newline yields a source such as
# `we<LF>ird/.gitignore`, which reaches the escaper raw. Copied from
# scripts/story-git-status.sh; see its comment for the locale argument and the
# C1 UTF-8 pairing.
#
# ONE-LINE DELTA WARNING: 8 and 12 MUST stay in the
# loop list below, because this file keeps only \ " \n \r \t as short forms and
# has no \b / \f. Copying archive-story.sh's list (which omits them) instead
# would leave 0x0C unescaped — exactly the bug the table exists to close.
JSON_ESC_RAW=()   # needle: the literal byte sequence to replace
JSON_ESC_REP=()   # replacement: its \uXXXX form
# `printf -v needle "$needle"` is a TWO-STAGE printf and the variable-as-format
# is the point: stage 1 builds the literal text `\x1b`, stage 2 makes printf
# interpret that escape into the byte itself. Writing the byte directly is not
# an option — it is what we are trying to produce.
# shellcheck disable=SC2059
_json_escape_table() {
  local i needle rep
  # C0 minus the three with a short escape (\t \n \r = 9 10 13), plus DEL (127).
  for i in 1 2 3 4 5 6 7 8 11 12 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 127; do
    printf -v needle '\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
  # C1: U+0080-U+009F, as their UTF-8 pair.
  for ((i = 128; i <= 159; i++)); do
    printf -v needle '\\xc2\\x%02x' "$i"
    printf -v needle "$needle"
    printf -v rep '\\u%04x' "$i"
    JSON_ESC_RAW+=("$needle")
    JSON_ESC_REP+=("$rep")
  done
}
_json_escape_table
unset -f _json_escape_table

json_escape() {
  local s="$1" i
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  for i in "${!JSON_ESC_RAW[@]}"; do
    s=${s//"${JSON_ESC_RAW[i]}"/"${JSON_ESC_REP[i]}"}
  done
  printf '%s' "$s"
}

# --- Usage ------------------------------------------------------------------
# This script takes NO arguments: the thing it measures is the current working
# directory, and .epico/ is always resolved relative to $PWD — never to the
# script's own location, which lives in the plugin and not in the workspace.
USAGE='Usage: epico-gitpolicy.sh
  (no arguments)  measure the .epico git policy of the current directory and
                  print the verdict as JSON on stdout
  --help, -h      this text'

if [[ "$#" -gt 1 ]]; then
  printf '%s\n' "$USAGE" >&2
  exit 2
fi
if [[ "$#" -eq 1 ]]; then
  case "$1" in
    --help | -h)
      printf '%s\n' "$USAGE"
      exit 0
      ;;
    *)
      printf '%s\n' "$USAGE" >&2
      exit 2
      ;;
  esac
fi

EPICO_DIR=".epico"
POLICY_FILE="$EPICO_DIR/.gitpolicy"

# --- Declared policy --------------------------------------------------------
# The FIRST line of .epico/.gitpolicy, whitespace- and CR-trimmed. Only the two
# known spellings are honoured; an empty, unreadable, misspelled or absent file
# is `undeclared`, which is the answer that makes init ask the question again —
# always the right outcome for a policy nothing here can read. Line 1 only, so
# the file can later grow a comment footer without changing what it declares.
#
# MEASURED BEFORE THE GIT CHECK, DELIBERATELY. This is one `-f` test and one
# `read` on a plain file — it needs no repository, and the non-git object below
# reports it. Moving this under the git check would strand init, whose
# defining workspace is a folder nobody has `git init`-ed yet, and force it to
# grow a SECOND parser for this file (first line only, CR strip, whitespace
# trim, two-value enum). One file, one parser.
POLICY="undeclared"
if [[ -f "$POLICY_FILE" ]]; then
  POLICY_RAW=""
  # `|| true`: a final line with no newline makes `read` exit 1 having read it.
  IFS= read -r POLICY_RAW < "$POLICY_FILE" || true
  POLICY_RAW=${POLICY_RAW%$'\r'}
  POLICY_RAW="${POLICY_RAW#"${POLICY_RAW%%[![:space:]]*}"}"
  POLICY_RAW="${POLICY_RAW%"${POLICY_RAW##*[![:space:]]}"}"
  case "$POLICY_RAW" in
    tracked-md | local-only) POLICY="$POLICY_RAW" ;;
  esac
fi

# --- Workspace check ---------------------------------------------------------
# Not a git repository → the three fields that are still TRUE here, and NOT the
# four measurements: with no index and no exclude rules there is no such thing
# as a tracked file or an ignored path, so `tracked_md: 0` and
# `gitignore_ignores_epico: false` would be measurements nobody made, dressed up
# as findings. `verdict: consistent` is what keeps the list header silent —
# "show nothing".
#
# `policy` IS emitted on the non-git object. Only the git measurements — the
# counts and the ignore probe — are omitted, because they were not measured and
# must not be faked. The declared policy is not a git measurement: it is the
# plain file read just above, it is equally true with or without a repository,
# and withholding it would force init to parse .epico/.gitpolicy a second time.
rc=0
IN_TREE=$(git rev-parse --is-inside-work-tree 2>/dev/null) || rc=$?
if [[ "$rc" -ne 0 || "$IN_TREE" != "true" ]]; then
  printf '%s\n' \
    "{" \
    "  \"git\": false," \
    "  \"policy\": \"$(json_escape "$POLICY")\"," \
    "  \"effective\": \"$( [[ "$POLICY" == undeclared ]] && echo local-only || echo "$POLICY")\"," \
    "  \"verdict\": \"consistent\"" \
    "}"
  exit 0
fi

# --- Is .epico ignored, and by what? -----------------------------------------
# THREE FACTS DECIDE THIS CALL'S EXACT SHAPE (git 2.55), and each is easy to
# undo by accident:
#
#   1. `--no-index` IS MANDATORY. Without it `git check-ignore` refuses to
#      report a path the index already knows, so the ONE workspace this lint
#      exists for — files tracked THROUGH an ignoring .gitignore, `git add -f`
#      — answers "not ignored" and the contradiction disappears:
#      `check-ignore .epico` → rc 1, `check-ignore --no-index .epico` → rc 0
#      naming `.gitignore:1:.epico/`. The flag is the whole point of the probe.
#
#   2. THE PROBED PATH KEEPS ITS TRAILING SLASH. A directory-only pattern
#      (`.epico/`, `/.epico/`) matches the pathname `.epico/` always, but matches
#      the bare `.epico` only when the directory exists on disk — git stats the
#      filesystem to decide. Probing `.epico` would therefore go quiet in the
#      exact case init cares about: a workspace whose .epico/ has not been
#      created yet. `.epico/` matches under all three common spellings —
#      `.epico`, `.epico/` and `/.epico/` — present or absent.
#
#   3. `-v -z --stdin` IS THE ONLY UNAMBIGUOUS WAY TO READ THE SOURCE, and the
#      three flags are one decision, not three. `-v` names the rule; its human
#      format is `<source>:<line>:<pattern>\t<pathname>`, from which `${x%%:*}`
#      recovers the source only while no source path contains a colon —
#      false for a source such as `we:ird/.gitignore`, and a global core.excludesFile
#      is an absolute path chosen by the user. Worse, plain `-v` C-QUOTES an
#      unusual name (a newline in a directory name comes back as the literal
#      text `"we\nird/.gitignore"`, surrounding quotes included), so the parsed
#      value would be wrong even where the split works. `-z` drops both the
#      quoting and the ambiguity, replacing every separator with NUL
#      and drops the quoting: `<source>\0<line>\0<pattern>\0<pathname>\0`, raw
#      bytes. And git refuses `-z` without `--stdin`
#      ("fatal: -z only makes sense with --stdin"), which is why the path is fed
#      in rather than passed as an argument. Do not "simplify" any one of them
#      away.
#
# SCOPE, wider than "the root .gitignore" on purpose: check-ignore answers for
# every exclude source git consults — the root .gitignore, .git/info/exclude
# and the user's global core.excludesFile.
# A rule in any of them produces the same contradiction, and asking git
# rather than parsing text also buys negations, `**` and precedence for free.
# The boolean is therefore named for what it means: git ignores .epico, whatever
# said so — and it stays that wide, because that is the predicate the
# contradiction verdict needs.
#
# WHY THE SOURCE IS REPORTED SEPARATELY: the boolean cannot answer the question
# init has to ask. Init asks consent to remove an .epico rule from the root
# .gitignore, and a bare `true` does not say WHERE the rule lives. A user whose
# GLOBAL excludesFile ignores .epico, in a repo whose root .gitignore is
# innocent, reads `true` with no line to remove; the wizard would offer a dead
# end or edit the wrong file. Distinguishable at no extra git call: root rule → `.gitignore`, repo-local rule → `.git/info/exclude`,
# nothing → no output at all.
#
# READ FROM THE FIRST NUL FIELD, NOT FROM THE EXIT STATUS, and let ONE test
# decide both keys. `$(…)` is not an option: command substitution DROPS NUL
# bytes and would splice the four fields into one word, so the answer has to be
# `read` from a process substitution, which discards git's exit status. It
# loses nothing: git prints a record only for a MATCH, so "named a source" ⇔
# rc 0. On the shape that looks most like a counter-example — `.epico/` followed
# by `!.epico/` — git prints nothing and exits 1, the same as no rule at all.
#
# DO NOT ADD `--non-matching`. It is the one flag that would print a record for
# a path that is NOT ignored, with every field empty (`::<TAB>.epico/`), and the
# equivalence above is what couples the two keys — the `-n` conjunct below is
# the belt to that brace, so `gitignore_ignores_epico: true` beside
# `gitignore_source: null` stays unreachable whatever a later edit does.
#
# Both failure modes still fail toward silence: not ignored (rc 1) and git
# could not answer (rc 128) produce no output, hence `false` and `null`, and
# the header's noise argument is why that is the right default.

# One record of four NUL-terminated fields, or no output at all:
#   <source>\0<linenum>\0<pattern>\0<pathname>\0
epico_ignore_probe() {
  printf '%s\0' "$EPICO_DIR/" |
    git check-ignore --no-index -v -z --stdin 2>/dev/null
}

GITIGNORE_IGNORES_EPIC=false
# `read` succeeding means it FOUND the terminating NUL, i.e. git emitted a
# record; the `else` clears whatever a short read left behind, because a
# truncated path is a wrong path and `""` is the value that means "none".
if IFS= read -r -d '' GITIGNORE_SOURCE < <(epico_ignore_probe) &&
  [[ -n "$GITIGNORE_SOURCE" ]]; then
  GITIGNORE_IGNORES_EPIC=true
else
  GITIGNORE_SOURCE=""
fi

# --- Path classification ----------------------------------------------------
# TWO PREDICATES, ONE DEFINITION EACH, AND BOTH CALLERS USE THESE — the counting
# loop below and epico_has_untracked_artifacts. With inline copies, a class
# widened in one and not the other would make the reported counts and the "is anything left to add?" probe disagree about the same file,
# which is a verdict bug with no visible symptom. Predicates, not a function
# returning the class on stdout: a command substitution would fork once per
# tracked path, and this runs on every story list.

# is_draft_path <path>: succeeds for anything under a /.draft/ component.
is_draft_path() {
  case "$1" in
    */.draft/*) return 0 ;;
  esac
  return 1
}

# is_md_artifact <path>: succeeds for the artifact set the recommended policy
# tracks — *.md plus archive/manifest.yaml (story.md, design.md, tasks.md,
# EPICO.md, the archive manifest).
#
# WHAT IT DELIBERATELY EXCLUDES is as load-bearing as what it includes: the
# policy's own machinery, .epico/.gitpolicy and .epico/.gitignore, is an artifact
# of NO policy and is legitimately committed under EVERY one of them — a
# .gitpolicy nobody else can read declares nothing to a teammate, and the nested
# .gitignore is how .draft/ stays out of the index. Counting them would report a
# contradiction against the very file that declares the policy, on a local-only
# workspace that did nothing wrong. Every other non-artifact file under .epico/
# falls in the same gap for the same reason: only the artifact set can answer
# "is the declared policy real?".
is_md_artifact() {
  case "$1" in
    *.md | */archive/manifest.yaml) return 0 ;;
  esac
  return 1
}

# --- Tracked-file counts ----------------------------------------------------
# THE TWO COUNTS ARE DISJOINT AND MUST STAY THAT WAY. A .draft note is very
# often a .md file — .epico/stories/NNN-x/.draft/notes.md is the standard one —
# so "is it markdown?" and "is it a draft?" are not independent questions and
# cannot be asked in either order without a rule. The rule: ANY path with a
# /.draft/ component is a draft and nothing else, whatever its extension. The
# if/elif is what enforces it; asking the two predicates independently would
# double-count every draft note and turn the ordinary working state of a
# tracked-md workspace into an over-tracking report.
#
# `-z` with process substitution, never `$(…)`: bash command substitution DROPS
# NUL bytes, which would splice every path into one string. Without -z git
# C-quotes unusual names ("a\nb"), and a quoted path no longer ends in .md — so
# the classification, not just the splitting, depends on this.
# The loop runs in THIS shell (the subshell is the producer), so the counters
# survive it. An unreadable index yields zero counts rather than an error: this
# lint fails toward silence.
TRACKED_MD=0
TRACKED_DRAFT=0
while IFS= read -r -d '' TRACKED_PATH; do
  # Assignment, not (( x++ )): a post-increment whose OLD value is 0 returns
  # status 1 and would trip `set -e` on the very first hit.
  if is_draft_path "$TRACKED_PATH"; then
    TRACKED_DRAFT=$((TRACKED_DRAFT + 1))
  elif is_md_artifact "$TRACKED_PATH"; then
    TRACKED_MD=$((TRACKED_MD + 1))
  fi
done < <(git ls-files -z -- "$EPICO_DIR" 2>/dev/null)
TRACKED_ANY=$((TRACKED_MD + TRACKED_DRAFT))
EFFECTIVE="$POLICY"
if [[ "$POLICY" == undeclared ]]; then
  if [[ "$TRACKED_MD" -gt 0 ]]; then EFFECTIVE=tracked-md; else EFFECTIVE=local-only; fi
fi

# epico_has_untracked_artifacts: succeeds when at least one md-class artifact
# exists under .epico/ that git is NOT tracking and is NOT ignoring. Existence
# only — it stops at the first hit and never counts.
# Called from ONE verdict arm and only there, so the common path stays at a
# single ls-files call. `--exclude-standard` is what keeps a .draft/ note the
# nested .epico/.gitignore already excludes from posing as an untracked artifact;
# the is_draft_path conjunct repeats that guarantee for a workspace that has no
# nested ignore file at all, and keeps the same draft-beats-md precedence the
# counting loop uses.
epico_has_untracked_artifacts() {
  local p
  while IFS= read -r -d '' p; do
    if ! is_draft_path "$p" && is_md_artifact "$p"; then
      return 0
    fi
  done < <(git ls-files -z --others --exclude-standard -- "$EPICO_DIR" 2>/dev/null)
  return 1
}

# --- Verdict -----------------------------------------------------------------
# ONE ORDERED CHAIN, FIRST MATCH WINS, AND THE ORDER IS THE SPECIFICATION —
# not an artefact of how the arms happened to be written.
#
# CONTRADICTION OUTRANKS PARTIAL. A workspace can be both at once (tracked
# .draft/ files under an ignoring .gitignore) and it must report the
# contradiction: over-tracking is a housekeeping mistake the user can fix with
# one `git rm --cached`, while configuration fighting itself is the state that
# silently produces self-contradictory repositories. Reordering these arms
# would keep every current test green and quietly downgrade the one verdict
# this script was written to produce — do not.
#
# Each arm carries the noise argument for firing, because the story list shows
# a header line for every verdict that is not `consistent`.
VERDICT="consistent"
if [[ "$GITIGNORE_IGNORES_EPIC" == true && "$TRACKED_ANY" -gt 0 ]]; then
  # The .gitignore says these files are never committed; the index says some
  # of them are. Whichever the user meant, one of the two is a lie, and
  # nothing in git will ever mention it.
  VERDICT="contradiction"
elif [[ "$GITIGNORE_IGNORES_EPIC" == true && "$POLICY" == "tracked-md" && "$TRACKED_MD" -eq 0 ]]; then
  # The declared policy is unreachable: tracking was chosen, the exclude rules
  # forbid it, and every future `git add .epico` will silently do nothing. The
  # arm above already covers the version where something got in anyway.
  VERDICT="contradiction"
elif [[ "$TRACKED_DRAFT" -gt 0 ]]; then
  # Over-tracking. .draft/ is scratch space and is in NO policy's tracked set,
  # so this is a mismatch under
  # tracked-md, local-only and undeclared alike, and needs no declaration to be
  # wrong. Cheap to say and cheap to fix, so it is worth one line.
  VERDICT="partial"
elif [[ "$POLICY" == "tracked-md" && "$TRACKED_MD" -eq 0 ]] && epico_has_untracked_artifacts; then
  # Declared tracking that never happened: the whole
  # artifact set is sitting untracked while the policy file says otherwise, and
  # nothing is blocking it (the second arm above owns the blocked variant), so
  # one `git add` settles it.
  # THE TWO GUARDS ARE BOTH NOISE CONTROL, and each removes a false positive a
  # plainer reading of "subset tracking" would produce:
  #   * tracked_md == 0 — the TOTAL subset, never a partial one. A working tree
  #     with some artifacts committed and a new story not yet committed is the
  #     normal state of every repository on earth; comparing the tracked set to
  #     the on-disk set would flag it on every list until the next commit.
  #   * untracked artifacts exist — a freshly initialised workspace that has no
  #     stories yet has nothing to add, so telling it to add something is a
  #     banner with no possible action behind it.
  VERDICT="partial"
elif [[ "$POLICY" == "local-only" && "$TRACKED_MD" -gt 0 ]]; then
  # Declared local-only, artifacts committed anyway. Not a contradiction — no
  # exclude rule is being fought, the user may simply have changed their mind
  # and not said so — but the declaration and the repository disagree, which is
  # precisely the kind of policy change that leaves stale artifacts behind.
  VERDICT="partial"
fi
# Everything else is `consistent`, and two members of that set are worth naming
# because they are the common ones and both MUST stay silent:
#   * undeclared with nothing tracked — the default workspace. A verdict here
#     would fire on every list.
#   * undeclared with artifacts tracked and no exclude rule fighting them — a
#     perfectly coherent repository that simply never wrote the policy file
#     down. `undeclared` is low-signal by design and is surfaced by `stories
#     full` alone; init is the consumer that acts on it, by asking.

# --- JSON emission ----------------------------------------------------------
# `git: true` is emitted on this path so the `git` flag is TOTAL: a consumer testing `[ "$(jq -r .git)" = true ]` and one
# testing `= false` both work, and neither has to tell an absent key (jq prints
# `null`) from a measured `false`.
# Booleans and counts are emitted BARE — never quoted — so `jq -r` yields
# true/false and an integer that `-gt` can compare. `gitignore_source` is bare
# too when there is nothing to name: JSON `null` is a literal, and `"null"`
# would be a path called "null" that a consumer's `!= null` test would miss.
# It keys off the BOOLEAN, not off a second emptiness test, so the two fields
# cannot drift apart — the probe above owns that predicate.
if [[ "$GITIGNORE_IGNORES_EPIC" == true ]]; then
  GITIGNORE_SOURCE_JSON="\"$(json_escape "$GITIGNORE_SOURCE")\""
else
  GITIGNORE_SOURCE_JSON="null"
fi

# `printf '%s\n'`, NOT `echo`, on every line of both objects. Escaped output is
# made of backslashes, and `echo` is only backslash-safe while `xpg_echo` is
# off — an option bash reads from the inherited BASHOPTS at startup, so it is
# not this script's to assume. Under it, `echo` would re-interpret the very
# `\uXXXX` and `\n` sequences json_escape just produced and emit the raw
# control byte back into the document. Uniform on purpose: a mixed block is an
# invitation to add the next line with the unsafe one.
printf '%s\n' \
  "{" \
  "  \"git\": true," \
  "  \"policy\": \"$(json_escape "$POLICY")\"," \
  "  \"effective\": \"$(json_escape "$EFFECTIVE")\"," \
  "  \"gitignore_ignores_epico\": $GITIGNORE_IGNORES_EPIC," \
  "  \"gitignore_source\": $GITIGNORE_SOURCE_JSON," \
  "  \"tracked_md\": $TRACKED_MD," \
  "  \"tracked_draft\": $TRACKED_DRAFT," \
  "  \"verdict\": \"$(json_escape "$VERDICT")\"" \
  "}"

exit 0
