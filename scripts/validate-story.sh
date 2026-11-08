#!/usr/bin/env bash
# Validates an epic story directory for common issues.
# Usage: bash scripts/validate-story.sh <story-directory> [--cross-ref] [--strict]
# Exit 0 = all checks pass, Exit 1 = issues found, Exit 2 = invalid input
# Output: JSON with passed/failed checks for structured consumption

set -euo pipefail

# --- Help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage: validate-story.sh <story-directory> [--cross-ref] [--strict]

Validates epic story artifacts for structural correctness.

Arguments:
  <story-directory>  Path to the story directory containing *.md files
  --cross-ref        Enable cross-reference checks (R-numbers in tasks vs story)
  --strict           Promote warnings to errors (exit 1 on any warning).
                     Use in CI gates for stories expected to be production-ready.

Output: JSON with errors, warnings, and status (pass/fail)

Exit codes:
  0  All checks pass (or only warnings without --strict)
  1  Validation issues found (see JSON output)
  2  Invalid input (missing directory, not a story directory)
HELP
  exit 0
fi

# --- Input validation ---
STORY_DIR="${1:-.}"

if [[ ! -d "$STORY_DIR" ]]; then
  echo "Error: Directory '$STORY_DIR' not found." >&2
  echo "Usage: validate-story.sh <story-directory>" >&2
  exit 2
fi

ERRORS=()
WARNINGS=()

# --- Helpers ---
add_error() { ERRORS+=("$1"); }
add_warning() { WARNINGS+=("$1"); }

# Minimal JSON string escape: messages can embed content read from the
# artifacts (quotes, backslashes, control chars) and must never break the
# jq consumers downstream (hooks, CI).
json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}

# frontmatter_field <file> <key> — the value of a column-0 frontmatter key, or
# nothing at all when the file, the frontmatter or the key is absent.
# Same contract as the version:/status: parsing further down, factored out
# because the scale is declared in story.md OR in tasks.md and both have to be
# read: the file must OPEN with a `---` line, the block ends at the next one
# (`sed '$d'` drops that closing line — GNU-only `head -n -1` would abort the
# whole validation on BSD/macOS under set -e + pipefail), and the value is squeezed of
# whitespace. Anchored at column 0 like the templates write it, so a compound or
# nested key (`review_scale:`) can never fake a value. <key> is a caller-supplied
# literal, never user input — it is interpolated into the regex as-is.
frontmatter_field() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  head -1 "$file" | grep -q '^---$' 2>/dev/null || return 0
  # `|| true`: a key that is simply absent makes grep exit 1, and under
  # pipefail that would abort the caller's command substitution.
  sed -n '2,/^---$/p' "$file" | sed '$d' | grep -E "^$key:" | head -1 |
    sed "s/.*$key:\s*//" | tr -d '[:space:]' || true
}

# xr_in_list <needle> <haystack...> — membership test for the cross-ref check.
xr_in_list() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# --- Infer scale from files present ---
# The FALLBACK, not the source of truth: a declared `scale:` governs (see the
# block right below), and this inference is what a story with no such field
# gets — unchanged, so stories written before the field validate as before.
HAS_STORY=false
HAS_TASKS=false
IS_BUGFIX=false

[[ -f "$STORY_DIR/story.md" ]] && HAS_STORY=true
[[ -f "$STORY_DIR/tasks.md" ]] && HAS_TASKS=true

if [[ "$HAS_TASKS" == false ]]; then
  add_error "Missing tasks.md — every story must have tasks"
fi

# Detect bugfix from frontmatter
if [[ "$HAS_STORY" == true ]]; then
  if head -10 "$STORY_DIR/story.md" | grep -qi 'type:.*bugfix' 2>/dev/null; then
    IS_BUGFIX=true
  fi
fi

# --- Read the DECLARED scale ---
# Grammar rule, identical to `status:` below: fail-CLOSED on a present-but-wrong
# value (an invented scale is an error), fail-OPEN on absence (no field means
# the file inference above stands alone, with no error, no warning and no extra
# output line).
#
# One source of truth for the enum: the alternation drives both the `[[ =~ ]]`
# check and the human-readable message (a `case` pattern cannot — bash does not
# re-parse `|` from an expanded variable as alternation, only `[[ =~ ]]` does).
SCALE_ENUM='fast|standard|full|spike'
SCALE_ENUM_TEXT=${SCALE_ENUM//|/, }
DECLARED_SCALE=""       # the resolved scale; "" = no artifact declares one
DECLARED_SCALE_FILE=""  # the artifact it was read from, for the messages
# Every artifact that declared a VALID scale, and its value — parallel arrays in
# the shape the `status:` collector below uses, and for the same reason: one
# story has one scale, so artifacts that disagree about it are worth naming.
SCALE_FILES=()
SCALE_VALUES=()

# THE SHARED SCALE RULE — `tasks.md` is AUTHORITATIVE for `scale:`, and every
# reader of a story's scale resolves it that way.
# WHY tasks.md and not the story's own frontmatter: tasks.md is the one artifact
# every scale has. A fast or spike story is tasks-only and can declare its scale
# nowhere else, so a declaration there is never a leftover — whereas a story.md
# or a design.md surviving an earlier attempt at a differently-shaped story is
# exactly that, and must never be honoured over the live tasks.md.
#
# THE WRITTEN CONTRACT THIS AGREES WITH is `references/tasks.md`, section "Spike
# Scale Adaptations": it states the precedence for every scale outright —
# tasks.md is authoritative, and an artifact that disagrees is reported rather
# than honoured. If code and contract ever diverge, that document is the one to
# reconcile against.
#
# FIVE READERS RESOLVE A STORY'S SCALE AND MOVE TOGETHER, stated here in full as
# parse_verdict below states its own consumer set — an inventory listing only
# the movers is the one that goes stale in silence.
#   1. validate-story.sh (HERE) — turns the scale into validation findings.
#   2. archive-story.sh `story_scale` — the archive preflight and the `scale`
#      recorded in the manifest entry. `story_field` itself is NOT flipped:
#      `status` and `type` are the story's LIFECYCLE, which belongs to
#      story.md whenever there is one, and only `scale` moves.
#   3. cross-reference.sh — decides whether a requirements chain exists to
#      compare against at all.
# And the two that deliberately do NOT change, named so the next reader can tell
# an exception from an oversight:
#   4. monitor-stale.sh `declares_spike_scale` — already reads tasks.md and
#      nothing else.
#   5. epico-index.sh `status_cell` — deliberately keeps its own precedence, and
#      it says so at its own definition. It
#      renders a row, it gates nothing, and a renderer that disagrees costs a
#      wrong cell, not a wrong archive.
#
# There is no shared library to import the rule from: `scripts/` has none, every
# script here is invoked standalone by path. So it is duplicated, and the five
# readers move as one.
#
# EVERY declaration is enum-checked, not only the winning one: a `medium` in any
# artifact is the defect this check exists to catch and must not be swallowed by
# a valid value elsewhere. An invalid value `continue`s, so it never occupies
# the slot — `story.md: medium` beside `tasks.md: spike` resolves `spike` AND
# reports the `medium`.
#
# design.md is read and enum-checked and paired, but NEVER resolves: it
# describes the SOLUTION, not the shape of the work. It sits in the middle of
# the loop order so its error is reported in artifact order; the resolution
# skips it by name.
for SCALE_SRC in story.md design.md tasks.md; do
  SCALE_VAL=$(frontmatter_field "$STORY_DIR/$SCALE_SRC" scale)
  # No field at all: the artifact carries no opinion, so it is not paired and
  # cannot be divergent — the rule the `status:` collector states at its own
  # append below.
  if [[ -z "$SCALE_VAL" ]]; then
    continue
  fi
  if ! [[ "$SCALE_VAL" =~ ^($SCALE_ENUM)$ ]]; then
    add_error "$SCALE_SRC frontmatter 'scale' is not a story scale: found '$SCALE_VAL' — must be one of: $SCALE_ENUM_TEXT"
    # An invented value resolves to NOTHING: every later check would have to
    # guess what `medium` meant, and a guess must never dress up as a finding.
    # It is not paired either, which is the ONE deliberate divergence from the
    # `status:` collector — that one pairs a value even when it fails its enum.
    # An invalid scale already has the error above; pairing it would report one
    # defect twice in two vocabularies.
    continue
  fi
  SCALE_FILES+=("$SCALE_SRC")
  SCALE_VALUES+=("$SCALE_VAL")
  # The resolution: assign unconditionally, so the LAST valid declaration wins,
  # and tasks.md is last in the loop order. A story declaring in only one of the
  # two still resolves that one, whichever it is.
  case "$SCALE_SRC" in
    story.md|tasks.md)
      DECLARED_SCALE="$SCALE_VAL"
      DECLARED_SCALE_FILE="$SCALE_SRC"
      ;;
  esac
done

# --- Read the DECLARED engineering level ---
# `engineering:` is one of four values, defined once in
# references/engineering-level.md. It is read the way `scale:` is — tasks.md
# first, because it is the one artifact every scale has. Fail-CLOSED on a value
# outside the four (an invented level is an error naming the set), fail-OPEN on
# absence. A disagreement between artifacts is not reported: tasks.md wins, as
# it does for the scale.
ENGINEERING_ENUM='experiment|tool|project|product'
ENGINEERING_ENUM_TEXT=${ENGINEERING_ENUM//|/, }
DECLARED_ENGINEERING=""
for ENG_SRC in tasks.md story.md design.md; do
  ENG_VAL=$(frontmatter_field "$STORY_DIR/$ENG_SRC" engineering)
  [[ -n "$ENG_VAL" ]] || continue
  if ! [[ "$ENG_VAL" =~ ^($ENGINEERING_ENUM)$ ]]; then
    add_error "$ENG_SRC frontmatter 'engineering' is not an engineering level: found '$ENG_VAL' — must be one of: $ENGINEERING_ENUM_TEXT"
    continue
  fi
  [[ -n "$DECLARED_ENGINEERING" ]] || DECLARED_ENGINEERING="$ENG_VAL"
done

# --- Read the declared requester level ---
# `requester:` is the level triage read (references/triage.md), written to
# tasks.md at every scale for the legend guard. Fail-OPEN on absence,
# fail-CLOSED on a value outside the two.
REQUESTER_VAL=$(frontmatter_field "$STORY_DIR/tasks.md" requester)
if [[ -n "$REQUESTER_VAL" ]] && ! [[ "$REQUESTER_VAL" =~ ^(layperson|developer)$ ]]; then
  add_error "tasks.md frontmatter 'requester' is not a requester level: found '$REQUESTER_VAL' — must be one of: layperson, developer"
fi

# --- Read the declared run model ---
# `run-model:` is the model the user chose at clarify to run a Standard or Full
# story (references/clarify.md, The run model). tasks.md only, fail-OPEN on
# absence and fail-CLOSED on a value outside the three, the rule every field the
# plugin added follows.
RUN_MODEL_ENUM='sonnet|opus|haiku'
RUN_MODEL_VAL=$(frontmatter_field "$STORY_DIR/tasks.md" run-model)
if [[ -n "$RUN_MODEL_VAL" ]] && ! [[ "$RUN_MODEL_VAL" =~ ^($RUN_MODEL_ENUM)$ ]]; then
  add_error "tasks.md frontmatter 'run-model' is not a run model: found '$RUN_MODEL_VAL' — must be one of: ${RUN_MODEL_ENUM//|/, }"
fi

# --- Read the declared roadmap tasks ---
# `roadmap:` lists the ROADMAP task IDs this story works on, as a flow list
# (`roadmap: [2.4.1, 2.4.2]`), in tasks.md like every field the plugin added.
# A WARNING, NEVER AN ERROR: this validator runs on every artifact write, and a
# typo in a cross-reference to a document the plugin does not own must not block
# the story. Fail-open on absence. When the project has a ROADMAP or stage files,
# an ID they do not hold is named too — the checkpoint reconciles stories against
# those IDs, so an ID nobody can find is a closure nobody will record.
ROADMAP_VAL=$(frontmatter_field "$STORY_DIR/tasks.md" roadmap)
if [[ -n "$ROADMAP_VAL" ]]; then
  ROADMAP_ID_RE='[0-9]+(\.[0-9]+)+'
  if ! [[ "$ROADMAP_VAL" =~ ^\[[[:space:]]*(${ROADMAP_ID_RE}([[:space:]]*,[[:space:]]*${ROADMAP_ID_RE})*)?[[:space:]]*\]$ ]]; then
    add_warning "tasks.md frontmatter 'roadmap' is not a list of task IDs: found '$ROADMAP_VAL' — write it as roadmap: [2.4.1, 2.4.2]"
  else
    # The project root is the parent of the .epico/ directory the story sits in.
    PROJECT_ROOT=""
    case "$STORY_DIR" in */.epico/*) PROJECT_ROOT="${STORY_DIR%%/.epico/*}" ;; esac
    if [[ -n "$PROJECT_ROOT" ]]; then
      ROADMAP_DOCS=()
      for f in "$PROJECT_ROOT/ROADMAP.md" "$PROJECT_ROOT/docs/ROADMAP.md" "$PROJECT_ROOT"/docs/stages/*.md; do
        [[ -f "$f" ]] && ROADMAP_DOCS+=("$f")
      done
      if [[ ${#ROADMAP_DOCS[@]} -gt 0 ]]; then
        # Task IDs as the ROADMAP writes them: a task line `- [ ] **2.4.1 …` or a table row `| 2.4.1 |`.
        KNOWN_IDS=$(sed -nE 's/^[[:space:]]*- \[.\] \*\*([0-9]+(\.[0-9]+)+) .*/\1/p; s/^\| ([0-9]+(\.[0-9]+)+) \|.*/\1/p' "${ROADMAP_DOCS[@]}" | sort -u)
        if [[ -n "$KNOWN_IDS" ]]; then
          for id in $(printf '%s' "$ROADMAP_VAL" | tr -d '[] ' | tr ',' ' '); do
            printf '%s\n' "$KNOWN_IDS" | command grep -qxF "$id" \
              || add_warning "tasks.md frontmatter 'roadmap' names task $id, which no ROADMAP or stage file holds"
          done
        fi
      fi
    fi
  fi
fi

# --- Read the declared refs ---
# `refs:` names the document sections the story starts from, as `<doc>#<anchor>`
# (references/context-discovery.md). A WARNING, NEVER AN ERROR, for the reason
# `roadmap:` gives above, and because a ref is a hint: the story can run without
# it. The resolution is resolve-refs.sh's, never a second parser here.
REFS_VAL=$(frontmatter_field "$STORY_DIR/tasks.md" refs)
if [[ -n "$REFS_VAL" ]]; then
  if ! [[ "$REFS_VAL" =~ ^\[.*\]$ ]]; then
    add_warning "tasks.md frontmatter 'refs' is not a list: found '$REFS_VAL' — write it as refs: [ARCHITECTURE#5.2, ADR-0012#decision]"
  elif [[ "$STORY_DIR" == */.epico/* ]]; then
    while IFS=$'\t' read -r ref_name ref_status; do
      [[ -n "$ref_name" ]] && add_warning "tasks.md frontmatter 'refs' names $ref_name, which does not resolve ($ref_status) — epico-refs --story <dir> shows the candidates"
    done < <(bash "$(dirname "${BASH_SOURCE[0]}")/resolve-refs.sh" --story "$STORY_DIR" 2>/dev/null \
      | jq -r '.refs[] | select(.status != "found") | [.ref, .status] | @tsv' 2>/dev/null || true)
  fi
fi

# --- Artifacts disagreeing about the scale ---
# One story, one scale, so artifacts declaring different values disagree about
# the SHAPE OF THE WORK — the same defect the `status:` collector below reports
# for the lifecycle state, reported the same way: compare every collected value
# against element 0, and name each `file=value` pair.
#
# WHAT THIS ONE ADDS to that sibling is the RESOLUTION. There, the artifacts are
# equals and there is nothing to disclose; here one of the declarations is
# already in force for every check downstream, and naming the disagreement
# without naming the value in force tells the author there is a problem but not
# which half of it is being acted on.
#
# It does NOT say which artifact is wrong, and that is the whole reason it is a
# warning rather than an error: `tasks.md` is authoritative for `scale:`, so its
# value is the one in force WHENEVER IT DECLARES ONE — but the stale line can
# just as easily be the one sitting in tasks.md itself. Picking a side would be
# a guess dressed up as a finding, and the scale-mismatch warning right below
# declines to pick one for exactly the same reason.
#
# EMITTED AHEAD OF THAT MISMATCH BLOCK, deliberately: the disagreement is the
# reason two values exist at all, so it is read before the consequence of the
# resolved one. That fixes its position in `warnings[]`.
#
# THE ONLY PLACE design.md's declaration IS OBSERVABLE: it is compared
# here like any other declaring artifact and never resolves, so a `design.md:
# full` beside a `tasks.md: spike` warns naming `design.md=full` while the
# resolved scale stays `spike`.
#
# AGREEMENT IS SILENT: three artifacts carrying the same value collect three
# identical elements and diverge from none of them. That is not a nicety —
# uniform declarations are the normal case, so the tempting "warn whenever two
# artifacts declare" variant would fire on every well-formed story.
#
# ${SCALE_VALUES[@]+"${SCALE_VALUES[@]}"} rather than a bare "${SCALE_VALUES[@]}",
# and the whole block gated on a non-empty array: expanding an empty array —
# or reading its element 0 — is an unbound-variable abort under `set -u` on
# bash < 4.4 (macOS ships 3.2), the same hazard archive-story.sh guards. The
# empty case is the COMMON one here, not the corner: no artifact of a legacy
# story declares a scale at all.
if [[ ${#SCALE_VALUES[@]} -gt 0 ]]; then
  SCALE_DIVERGED=false
  for sc_v in ${SCALE_VALUES[@]+"${SCALE_VALUES[@]}"}; do
    [[ "$sc_v" == "${SCALE_VALUES[0]}" ]] || SCALE_DIVERGED=true
  done
  if [[ "$SCALE_DIVERGED" == true ]]; then
    # The `${VAR:+, }` separator idiom of the `status:` sibling: the comma is
    # written by the element that FOLLOWS one, so no trailing separator exists to
    # strip and the single-pair case needs no special arm.
    SCALE_PAIRS=""
    for sc_i in "${!SCALE_FILES[@]}"; do
      SCALE_PAIRS+="${SCALE_PAIRS:+, }${SCALE_FILES[$sc_i]}=${SCALE_VALUES[$sc_i]}"
    done
    # DECLARED_SCALE is necessarily non-empty on this branch: two differing
    # values need two declaring artifacts, and design.md — the one artifact that
    # never resolves — can only ever be one of them, so any divergence contains
    # a story.md or a tasks.md and that one has resolved.
    add_warning "Artifacts of this story declare different 'scale' values ($SCALE_PAIRS) — every artifact must declare the same scale; until they do, the resolved scale is '$DECLARED_SCALE' (from $DECLARED_SCALE_FILE)"
  fi
fi

# scale_has_requirements_chain — does the resolved scale owe an R-chain?
# WRITTEN AS THE FALSE SET ON PURPOSE, and the direction is the whole point
# because it is the kind of rule that is easy to state backwards. A positive
# list — `standard|full|"") return 0 ;; *) return 1` — reads identically today
# and behaves the opposite way tomorrow: every FUTURE enum member would fall
# through `*` and be classified as carrying NO chain, opted OUT of the coverage
# gate below in silence. Silence is the failure mode nobody files a bug about.
#
# The false set inverts exactly that: a scale this function has never heard of
# falls to `*`, is treated as CARRYING a chain, and a tasks-only newcomer is
# told to add `Requirements:` fields on the very first run that validates one.
# That is a wrong message, loudly, on day one — which someone fixes. Loud and
# wrong beats quiet and wrong.
#
# IT ALSO DECIDES THE UNDECLARED CASE ON PURPOSE RATHER THAN BY ACCIDENT. A
# story that declares no `scale` in any artifact leaves DECLARED_SCALE empty;
# the empty string falls to `*` and keeps its requirements chain BECAUSE THE
# RULE SAYS SO. Under a positive list, stories without the field would be
# correct only because someone remembered to spell `""` into the list — a
# contract held up by a habit, which the legacy golden in
# tests/scale-validation.bats exists to catch when the habit lapses.
#
# A pure function of DECLARED_SCALE and nothing else, named rather than inlined
# so the question is spelled ONCE and cannot be answered two ways: the argument
# scale_mismatch below makes for its warning skeleton, and no_r_chain further
# down makes for its sentence. It must never be answered from FILE PRESENCE:
# two gates answering it differently — one from the files, one from the
# declaration — contradict each other on the same story (see the coverage
# gate's own comment).
scale_has_requirements_chain() {
  case "$DECLARED_SCALE" in
    fast | spike) return 1 ;;
    *) return 0 ;;
  esac
}

# --- Declared scale vs files present ---
# Each scale names an artifact set (references/tasks.md): fast and spike are
# tasks-only, standard adds story.md, full adds design.md on top. A declaration
# that contradicts the files on disk means ONE of the two sides is wrong, and
# which one is the author's call — so it is a warning naming BOTH sides, never
# an error that picks a winner.
# Skipped whole when nothing was declared, which is the fail-open rule made
# structural rather than merely restated.
#
# scale_mismatch <what the scale implies> <what the files show> <the fix>
# ONE skeleton for all three shapes, so "names BOTH sides" is guaranteed by
# construction and not by three authors remembering it: the declaration and the
# file it lives in on the left, the filesystem on the right, and a fix for each
# side — the warning deliberately does not pick which one is wrong.
scale_mismatch() {
  add_warning "declared scale '$DECLARED_SCALE' (in $DECLARED_SCALE_FILE) contradicts the files present: $1, but $2 — $3, or declare the scale the files actually describe"
}

if [[ -n "$DECLARED_SCALE" ]]; then
  # SCALE_ARTIFACT is the file being CONTRADICTED, never the one the
  # declaration was read from (that is DECLARED_SCALE_FILE).
  case "$DECLARED_SCALE" in
    fast|spike)
      for SCALE_ARTIFACT in story.md design.md; do
        if [[ -f "$STORY_DIR/$SCALE_ARTIFACT" ]]; then
          scale_mismatch "a '$DECLARED_SCALE' story is tasks-only" \
            "$SCALE_ARTIFACT is present" "remove $SCALE_ARTIFACT"
        fi
      done
      ;;
    standard)
      # design.md is OPTIONAL at standard scale, so its presence says nothing;
      # only a missing story.md contradicts the declaration.
      if [[ ! -f "$STORY_DIR/story.md" ]]; then
        scale_mismatch "a 'standard' story carries story.md + tasks.md" \
          "there is no story.md" "add it"
      fi
      ;;
    full)
      for SCALE_ARTIFACT in story.md design.md; do
        if [[ ! -f "$STORY_DIR/$SCALE_ARTIFACT" ]]; then
          scale_mismatch "a 'full' story carries story.md + design.md + tasks.md" \
            "there is no $SCALE_ARTIFACT" "add it"
        fi
      done
      ;;
  esac
fi

# --- Validate story.md ---
if [[ "$HAS_STORY" == true ]]; then
  STORY_FILE="$STORY_DIR/story.md"

  # Check for SHOULD (should be SHALL).
  #
  # CASE-SENSITIVE, deliberately: an EARS keyword is written in UPPERCASE, and
  # that capitalization is the whole signal that a line states an obligation
  # rather than describing something. Lowercase "should" is ordinary English
  # prose — "auth errors should fail immediately" in a bugfix's Summary is a
  # description of correct behaviour, not a weakened requirement. A `-i` here
  # cannot tell the two apart and would turn every such sentence into a hard
  # ERROR — failing even assets/examples/bugfix-complete.md, the very document
  # authors are told to imitate, on its own Summary line.
  # The obligation lines it was written to catch — "The system SHOULD retry" —
  # are still caught: those shout, which is exactly why the check can afford
  # to listen only for shouting.
  SHOULD_COUNT=$(grep -c '\bSHOULD\b' "$STORY_FILE" 2>/dev/null || true)
  if [[ "$SHOULD_COUNT" -gt 0 ]]; then
    add_error "Found $SHOULD_COUNT uses of SHOULD in story.md — use SHALL instead"
  fi

  # Check for SHALL — case-sensitive for the same reason, and here it closes the
  # mirror-image hole: a story whose only "shall" is lowercase prose is not a
  # story written in EARS, and a case-insensitive count would have silently
  # accepted it as one.
  SHALL_COUNT=$(grep -c '\bSHALL\b' "$STORY_FILE" 2>/dev/null || true)
  if [[ "$SHALL_COUNT" -eq 0 ]]; then
    add_warning "No SHALL found in story.md — requirements may not use EARS notation"
  fi

  # Check hierarchical numbering
  if ! grep -qE '^###\s+R[0-9]+' "$STORY_FILE" 2>/dev/null; then
    add_warning "No hierarchical requirement numbering (R1, R2...) found in story.md"
  fi

  # --- EARS form lint ---
  #
  # THREE CHECKS, ONE SEVERITY EACH, and the split is a rule rather than a
  # preference: only (a) is an error, because only (a) makes a
  # criterion invisible to the whole traceability chain — an unlabeled bullet
  # cannot be referenced by a task, so cross-reference.sh cannot see it and the
  # Auditor cannot trace it. (b) and (c) are shape advice about a criterion
  # everything downstream can still find, so they warn.
  #
  #   (a) a criterion bullet with no `Rn.m:` label ......... ERROR
  #   (b) a labeled criterion carrying 2+ SHALL ............ warning
  #   (c) a labeled criterion with no EARS trigger, whose
  #       opening is not the ubiquitous form ............... warning
  #
  # WHERE IT LOOKS. Only bullets under a `#### Acceptance Criteria` heading,
  # and the block ends at the next heading of any level. A fenced block
  # is never scanned: an illustrative criterion inside a fence is documentation
  # showing the shape, not a claim about this story. The fence state is tracked
  # with the same idiom and the same regex the checkbox walker below uses, so
  # this file keeps ONE fence policy rather than two that can drift.
  #
  # WHY CONTINUATION LINES ARE JOINED. A criterion routinely wraps across
  # several lines — the SHALL is often not on the bullet's first line at all.
  # Evaluating the first line alone would report most criteria as
  # trigger-less, which is how a lint teaches people to ignore it. The bullet and its continuations are therefore
  # buffered and evaluated as one criterion, and the line reported is the
  # bullet's own first line, which is where an author would go to fix it.
  #
  # SCALE GATING. The whole block is skipped for fast and spike, which
  # have no requirements chain — a leftover story.md in a Fast story is not a
  # requirements document and must not be linted as one.
  #
  # --strict PROMOTION. Under `--strict`, warnings are promoted to errors, so
  # (b) and (c) become blocking there. That is the flag's existing meaning and
  # is stated here because this block is the largest source of warnings in the
  # script.
  #
  # BSD-SAFE SPELLINGS ONLY: no `\b`, no `\d`, no `\s` in any pattern below.
  if scale_has_requirements_chain; then
    ears_fence_re='^(```|~~~)'
    ears_heading_re='^#{1,6}[[:space:]]'
    ears_ac_re='^####[[:space:]]+Acceptance[[:space:]]+Criteria[[:space:]]*$'
    ears_bullet_re='^[[:space:]]*-[[:space:]]+'
    ears_label_re='^[[:space:]]*-[[:space:]]+R[0-9]+\.[0-9]+:'
    ears_trigger_re='(^|[^[:alnum:]_])(WHEN|WHILE|WHERE|IF)([^[:alnum:]_]|$)'
    # The ubiquitous form keeps its component slot: `THE <COMPONENT> SHALL` is
    # legal EARS, and subject drift beyond that is not checked.
    # Case is load-bearing — EARS keywords are CAPS, so a prose opener like
    # "The exporter SHALL" is not the ubiquitous form and does warn.
    ears_ubiquitous_re='^[[:space:]]*-[[:space:]]+R[0-9]+\.[0-9]+:[[:space:]]+THE[[:space:]]+[A-Z][A-Z0-9_ -]*SHALL([^[:alnum:]_]|$)'

    ears_in_fence=false
    ears_in_ac=false
    ears_buf=""
    ears_buf_line=0
    ears_line_no=0

    # Evaluates one buffered criterion. Called when the buffer closes, which is
    # at the next bullet, the next heading, a fence, a blank line, or EOF —
    # never from inside the loop's own accumulation branch.
    ears_flush() {
      local text="$1" line="$2" shall_count bare
      [[ -n "$text" ]] || return 0
      # An inline code span is a MENTION, not an obligation — the same rule the
      # fence applies to a block, applied to a span. Without it, a criterion
      # that merely names `SHALL` while stating a rule about SHALL ("WHEN a
      # labeled criterion contains more than one `SHALL` THE SYSTEM SHALL warn")
      # counts as compound and warns. A lint that reddens on prose describing
      # itself is a lint people learn to ignore. Stripping is symmetric: a
      # trigger word mentioned inside a span is likewise not a trigger.
      # SC2016 is silenced on the next line: the backticks are the LITERAL span
      # delimiters sed strips, not a command substitution, so single quotes are
      # the correct quoting — and CI's shellcheck exits 1 even at info level.
      # shellcheck disable=SC2016
      bare=$(printf '%s' "$text" | sed 's/`[^`]*`//g')
      if [[ ! "$text" =~ $ears_label_re ]]; then
        add_error "story.md line $line: acceptance criterion has no Rn.m label — an unlabeled criterion cannot be referenced by a task, so nothing downstream can trace it"
        return 0
      fi
      # SHALL CONTINUE TO is the bugfix Unchanged-Behavior verb, not a second
      # obligation, so it is removed before the count rather than matched around.
      shall_count=$(printf '%s' "${bare//SHALL CONTINUE TO/}" | grep -o 'SHALL' | grep -c 'SHALL' || true)
      if [[ "$shall_count" -gt 1 ]]; then
        add_warning "story.md line $line: acceptance criterion carries $shall_count SHALL obligations — one condition per requirement, each independently testable"
      fi
      if [[ ! "$bare" =~ $ears_trigger_re && ! "$text" =~ $ears_ubiquitous_re ]]; then
        add_warning "story.md line $line: acceptance criterion has no EARS trigger (WHEN/WHILE/WHERE/IF) — the accepted exception is the ubiquitous form, THE SYSTEM SHALL ..."
      fi
    }

    while IFS= read -r ears_line || [[ -n "$ears_line" ]]; do
      ears_line_no=$((ears_line_no + 1))

      if [[ "$ears_line" =~ $ears_fence_re ]]; then
        ears_flush "$ears_buf" "$ears_buf_line"; ears_buf=""
        if [[ "$ears_in_fence" == true ]]; then ears_in_fence=false; else ears_in_fence=true; fi
        continue
      fi
      [[ "$ears_in_fence" == false ]] || continue

      if [[ "$ears_line" =~ $ears_heading_re ]]; then
        ears_flush "$ears_buf" "$ears_buf_line"; ears_buf=""
        if [[ "$ears_line" =~ $ears_ac_re ]]; then ears_in_ac=true; else ears_in_ac=false; fi
        continue
      fi
      [[ "$ears_in_ac" == true ]] || continue

      if [[ "$ears_line" =~ $ears_bullet_re ]]; then
        ears_flush "$ears_buf" "$ears_buf_line"
        ears_buf="$ears_line"
        ears_buf_line=$ears_line_no
      elif [[ -z "${ears_line// /}" ]]; then
        ears_flush "$ears_buf" "$ears_buf_line"; ears_buf=""
      elif [[ -n "$ears_buf" ]]; then
        ears_buf="$ears_buf $ears_line"
      fi
    done < "$STORY_FILE"
    ears_flush "$ears_buf" "$ears_buf_line"
  fi

  # Bugfix: check Unchanged Behavior section
  if [[ "$IS_BUGFIX" == true ]]; then
    if ! grep -qi 'unchanged behavior' "$STORY_FILE" 2>/dev/null; then
      add_error "Bugfix story.md is missing mandatory 'Unchanged Behavior' section"
    else
      CONTINUE_COUNT=$(grep -ci 'SHALL CONTINUE TO' "$STORY_FILE" 2>/dev/null || true)
      if [[ "$CONTINUE_COUNT" -lt 2 ]]; then
        add_error "Bugfix Unchanged Behavior section needs minimum 2 items (found $CONTINUE_COUNT)"
      fi
    fi
  fi
fi

# --- Validate tasks.md ---
if [[ "$HAS_TASKS" == true ]]; then
  TASKS_FILE="$STORY_DIR/tasks.md"

  # --- Why the scale rose ---------------------------------------------------
  # `fast` is the floor; every other scale owes one line naming what in the
  # request made the smaller shape insufficient. The reason is read from the
  # same artifact the resolved value came from, so the two cannot drift apart.
  # (Which artifact that is, and why, is settled above — not restated here: the
  # comment lint counts statements of that rule and a fourth one false-Reds.)
  #
  # WARNING, NEVER AN ERROR, and fail-OPEN on absence: the scale is the
  # author's call, and a story written before the field validates as it did.
  # Silent at `fast`, where there is nothing to justify.
  #
  # WHY IT EXISTS: the scale is the decision that moves a story's cost most,
  # and it is easily never stated, surfacing only in the recorded line after
  # the plan is written. Requiring one line of reason makes that decision
  # explicit.
  # ABSENCE IS SILENT, and that is not laxity — it is this file's rule for every
  # new field: fail-OPEN on absence, fail-CLOSED on a value that is present and
  # wrong. A story written before the field must validate exactly as it did,
  # and a test pins that. What is checked is the field an author STARTED and
  # left empty — `scale_reason:` with nothing after it is not a legacy story,
  # it is an unfinished one.
  if [[ -n "$DECLARED_SCALE" && "$DECLARED_SCALE" != "fast" ]] \
     && grep -qE '^scale_reason:' "$TASKS_FILE" 2>/dev/null; then
    SCALE_REASON="$(awk '
      NR == 1 && $0 != "---" { exit }
      NR > 1 && $0 == "---" { exit }
      /^scale_reason:[[:space:]]*/ { sub(/^scale_reason:[[:space:]]*/, ""); print; exit }
    ' "$TASKS_FILE" 2>/dev/null || true)"
    SCALE_REASON="${SCALE_REASON#"${SCALE_REASON%%[![:space:]]*}"}"
    if [[ -z "$SCALE_REASON" ]]; then
      add_warning "tasks.md declares scale '$DECLARED_SCALE' and an empty 'scale_reason:' — 'fast' is the floor, and rising above it owes one line naming what made the smaller shape insufficient (references/tasks.md, Why the Scale Rose)"
    fi
  fi

  # Check task title format (new format: - [ ] N - Name)
  OLD_FORMAT_COUNT=$(grep -cE '^\s*- \[[ x~]\].*\*\*\[T[0-9]\]\*\*' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$OLD_FORMAT_COUNT" -gt 0 ]]; then
    add_warning "Found $OLD_FORMAT_COUNT tasks using old [T1]/[T2]/[T3] prefix format — use new format: - [ ] N - Name"
  fi

  # --- Commit-field anchor lint ---
  # A `Commit:` message whose subject is not scoped with this story's number is
  # INVISIBLE to integration detection: scripts/story-git-status.sh finds a
  # story's work through `(NNN)` in a subject or a merged `feat/NNN-*` branch and
  # through nothing else, so `feat: add the thing` is a commit no reader can ever
  # attribute back to the story that authored it. references/tasks.md
  # recommends the anchor; this lint makes the recommendation observable.
  #
  # A WARNING, NEVER AN ERROR, and the severity is the point rather than a
  # softening: a foreign commit convention stays perfectly usable — the plugin
  # does not own its host repository's commit style — but drift stops being
  # silent. Every scale is linted, fast and spike included: those commit too.
  # It also has to be quiet by default because scripts/close-subtask.sh
  # self-invokes this validator on every box it closes, so a lint that fires
  # loosely would surface on every marking in the system.
  #
  # THE FIELD IS WHAT IS MATCHED, NEVER THE CHECKBOX. The message can live in
  # the body of a Commit sub-task (`- [ ] 1.6 - Commit` / `  - Commit: "…"`) or
  # as a group-level `- Commit: "…"` on the parent task body, with no box at
  # all. Both shapes are the SAME line — `- Commit:` in a body — so keying on
  # the field rather than on the box covers both without knowing which one a
  # story uses.
  #
  # THIS STORY'S NUMBER COMES FROM THE DIRECTORY NAME, as it does for every other
  # reader of a story's identity (story-git-status.sh derives the same
  # two tokens the same way): no artifact's frontmatter carries the number, so
  # the directory is the only place it exists. A directory with no leading number
  # — `story`, a bare slug, a checkout root — yields nothing to anchor against,
  # and the lint is then SKIPPED WHOLE rather than guessed at: not computable
  # must never dress up as a finding (references/validate-mode.md).
  #
  # TWO SPELLINGS OF ONE NUMBER, and both are needed. NUM is padding-free and
  # feeds the regex through a leading `0*`, so `010-x` accepts `feat(010):` and
  # `fix(10):` alike — zero-padded and unpadded both. LABEL is the number
  # AS THE DIRECTORY SPELLS IT and is what the message quotes — the same rule the
  # group-header check above states for its own label, so grepping the file for
  # the number the warning names finds the line it names.
  COMMIT_STORY_NAME="$STORY_DIR"
  while [[ "$COMMIT_STORY_NAME" == */ ]]; do
    COMMIT_STORY_NAME="${COMMIT_STORY_NAME%/}"
  done
  COMMIT_STORY_NAME="${COMMIT_STORY_NAME##*/}"
  # `.` and `..` name a directory without spelling it, and `validate-story.sh`
  # with no argument defaults to `.` — resolve those to the real basename so a
  # run from inside the story dir lints exactly like a run from outside it. The
  # subshell cannot leak a `cd` and a failure leaves the name empty, which the
  # skip below already handles.
  if [[ -z "$COMMIT_STORY_NAME" || "$COMMIT_STORY_NAME" == "." || "$COMMIT_STORY_NAME" == ".." ]]; then
    COMMIT_STORY_NAME=$(cd "$STORY_DIR" 2>/dev/null && printf '%s' "${PWD##*/}") ||
      COMMIT_STORY_NAME=""
  fi
  COMMIT_STORY_LABEL=""  # `010` — the number as the directory spells it
  COMMIT_STORY_NUM=""    # `10`  — the same number with its padding stripped
  commit_anchor_re=""    # empty = no number to anchor against, so no lint
  if [[ "$COMMIT_STORY_NAME" =~ ^(0*)([0-9]+)(-.*)?$ ]]; then
    COMMIT_STORY_LABEL="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    COMMIT_STORY_NUM="${BASH_REMATCH[2]}"
    # The conventional-commit prefix with this story's number as its scope:
    # `type(0*NNN):`, with the optional `!` a breaking change carries. Built
    # once, and COMMIT_STORY_NUM is a digit run captured above — never input.
    commit_anchor_re="^[[:alnum:]][[:alnum:]_-]*\(0*${COMMIT_STORY_NUM}\)!?:"
    # The expected shape the warning names, spelled ONCE and hoisted out
    # of the loop: it is a constant of the run, not of the offending line.
    # The second example is CONDITIONAL because the two spellings collapse into
    # one for a directory that writes its number unpadded — `10-slug` has
    # LABEL == NUM, and an unguarded skeleton then offers `feat(10)` and
    # `fix(10)` as if they were alternatives, which reads as a bug in the
    # message. Padding stays flexible either way, so the parenthetical does not.
    COMMIT_ANCHOR_HINT="'type($COMMIT_STORY_LABEL): <subject>' (zero-padded or not"
    if [[ "$COMMIT_STORY_LABEL" != "$COMMIT_STORY_NUM" ]]; then
      COMMIT_ANCHOR_HINT+=" — 'fix($COMMIT_STORY_NUM): …' anchors too"
    fi
    COMMIT_ANCHOR_HINT+=")"
  fi
  # The FIELD in a body — `- Commit: <message>` at any indent — and never the
  # `- [ ] N.M - Commit` header, whose next character after the dash is `[`.
  # `[Cc]` rather than a lowercased comparison because the VALUE is reported
  # verbatim and must not be case-folded; same idiom as `[Vv]erdict` below.
  commit_field_re='^[[:space:]]*-[[:space:]]+[Cc]ommit:[[:space:]]*(.*)$'
  # Trailing whitespace is what this actually removes — the capture above already
  # starts at the first non-space. The leading half is kept anyway so the two
  # regexes stay independent: the anchor test is `^`-anchored, and it would fail
  # on a leading space the day someone loosens the field regex.
  commit_trim_re='^[[:space:]]*(.*[^[:space:]])[[:space:]]*$'

  # --- Checkbox census ---
  # One line grammar, three box states:
  #   - [ ] open   - [x] closed   - [~] closed WITHOUT doing the work.
  # A `[~]` MUST say why on the same line, with one of the four qualifiers —
  # that check is the whole reason this loop reads qualifiers at all.
  #
  # BOX_CLOSED IS NOT SPLIT into terminal vs deferred in the output: `closed`
  # below means "not open, and correctly qualified", because no check reads a
  # closed-by-kind breakdown and a new count key would break every existing
  # golden. That constraint is on the JSON, not on this script's internals:
  # BOX_DEFERRED below is never emitted.
  #
  # WHY THE DEFERRED COUNTER EXISTS: the status-behind-the-checkboxes warning
  # below consumes it. It cannot be written without the count, because rule 1
  # of references/run-mode.md makes `done` conditional on "no `[ ]` AND no
  # deferred `[~]`" — a deferred box blocks `done` deliberately, so a story
  # resting at `in-progress` with deferred work owed is CORRECT and must not be
  # warned about. Fold deferred into closed and that story warns falsely; the
  # hostile case in tests/validate-story-status.bats reddens on exactly that
  # fold.
  #
  # BOX_OPEN counts `[ ]`, and only `[ ]`. It has two consumers: the
  # ahead-of-checkboxes warning and, with BOX_DEFERRED, its converse.
  # Counters are plain integers incremented in the loop, never ${#assoc[@]} on
  # a possibly-empty associative array (that trips set -u on bash 5.3 — the
  # same reason REQ_KEYS exists in cross-reference.sh).
  BOX_OPEN=0         # [ ]
  BOX_CLOSED=0       # [x] plus every qualified [~], terminal or deferred alike
  BOX_DEFERRED=0     # the deferred SUBSET of BOX_CLOSED — internal, never emitted
  BOX_UNQUALIFIED=0  # [~] with no recognized qualifier: a grammar error
  LINE_NO=0
  box_re='^[[:space:]]*- \[([ x~])\]'
  # A qualifier is a token in its own right: `(n-a: ...)` qualifies, the tail
  # of a word like `man-a:` does not.
  deferred_re='(^|[^[:alnum:]_-])deferred:'
  terminal_re='(^|[^[:alnum:]_-])(waived|n-a|superseded-by):'
  tilde_forms="'deferred: <reason>', 'waived: <reason>', 'n-a: <reason>', 'superseded-by: NNN'"

  # --- Group-header consistency, gathered in the same pass ---
  # A group header is a CLAIM about its own sub-tasks, so it can be wrong in two
  # ways and both are the same error (see the verdict right after this loop).
  # Ownership is by NUMBER PREFIX, never by indentation or file order: group 1
  # owns 1.1 and 1.2, and does NOT own 10.1. These are sparse indexed arrays
  # keyed by the group number itself — no associative array, per the counter
  # note above. The key is the arithmetic value (`10#` forces base 10, so a
  # stray `08` is neither octal nor a second group 8); the MESSAGE quotes the
  # spelling instead, so grepping the file for the number it names finds the
  # line it names.
  GRP_LINES=()  # [n] = header line numbers, space-joined — one token per header
  GRP_BOX=()    # [n] = FIRST header's box char
  GRP_LABEL=()  # [n] = FIRST header's number as spelled in the file, e.g. `08`
  GRP_SUBS=()   # [n] = how many sub-tasks group n owns
  GRP_OPEN=()   # [n] = how many of those are `[ ]`
  GRP_BAD=()    # [n] = how many are an unqualified [~], i.e. of unreadable state
  # ONE regex for both shapes, because they differ by one optional group and the
  # number that keys them is the same capture: `N - Title` is the header, and
  # `N.M - Title` is a sub-task of that same N. Splitting it in two would
  # duplicate the digit guard and the `10#` below, and a guard kept in two
  # places is a guard that eventually gets applied in one. (`1.2.3` matches
  # neither: three-level numbering is out of scope here.)
  task_num_re='^[[:space:]]*- \[([ x~])\][[:space:]]+([0-9]+)(\.[0-9]+)?[[:space:]]+-[[:space:]]'
  # A digit run longer than this is not a task number. Past 2^63 it wraps to a
  # NEGATIVE array subscript, which bash treats as fatal — under set -euo
  # pipefail the script would die before reaching the emitter and print NO JSON
  # AT ALL, to consumers that all parse that JSON. Guard the digits before they
  # ever become a subscript; `10#` still handles everything that gets through.
  GRP_MAX_DIGITS=9

  # Quality Gates share the checkbox grammar by design (references/tasks.md), so
  # `- [ ] 3 - Coverage >= 80%` is a legal gate AND is shaped exactly like a
  # group header. Reading the whole document would let such a line overwrite a
  # real header's state, silencing true violations and inventing false ones.
  #
  # The exclusion is deliberately NOT section arithmetic. Scoping the gathering
  # to `## Task List` and ending it at the next heading means deciding where a
  # markdown section ENDS, which is genuinely hard and fails silently in every
  # direction: a decorated or differently-cased heading, a `###` Quality Gates,
  # or a column-0 `#` inside a fenced block each mis-scope it — and can hide the
  # exact violation this rule exists to catch. So group state is gathered EVERYWHERE
  # except two places, each decided by ONE line in isolation:
  #
  #   1. from the first `Quality Gates` HEADING onward, to end of file. One way,
  #      no re-entry, no end to locate. Level-agnostic and case-insensitive so
  #      it agrees with the validator's own `grep -qi 'Quality Gates'` presence
  #      check below instead of disagreeing with it.
  #   2. inside a fenced code block. An illustrative task list in a fence is
  #      documentation, not a claim — and a `#` in a fence is not a heading.
  #
  # Nothing depends on how `## Task List` is spelled. NOTE the census above is
  # deliberately NOT excluded from either: it counts every box in the document.
  # Matched against the LOWERCASED line, so the case-insensitivity is exact
  # rather than a hand-written [Qq] approximation — the presence check below is
  # `grep -qi`, and the two must not disagree about where the gates section is.
  gates_re='^#{1,6}.*quality gates'
  # Column-0 fence, 3+ chars, either flavour. An unclosed fence therefore runs
  # to end of file, which is what CommonMark says it means, not an oversight.
  fence_re='^(```|~~~)'
  in_gates=false
  in_fence=false

  # --- The security floor, checked as gates (references/quality-catalog.md) ---
  #
  # The floor is the five items NO engineering level drops: the supported and
  # declared runtime, secrets, the README, the dependency-vulnerability scan
  # (SCA) and data integrity. `experiment` activates nothing else and still
  # activates these. Data integrity is owed as a gate even by a program with no
  # data file — the gate then records `no persisted data`, the same verdict SCA
  # takes on an empty manifest — so the lint stays a presence check and never
  # has to guess whether the program persists anything.
  #
  # WHY A LINT AND NOT PROSE. The chain that carries the floor is entirely
  # written down and entirely unexecuted: the story's `## Quality Requirements`
  # legend names the item, `tasks.md` generates one `Qn` gate per legend line
  # (references/tasks.md, Generated Quality Gates), and Validate settles that
  # gate by running its command (references/validate-mode.md). Every link is a
  # sentence an agent is asked to honour. Nothing checked that the first link
  # was ever written, so without this check a story whose legend omits the
  # floor produces no gate, gives Validate nothing to run, and passes. A floor
  # that is requested and never verified is not a floor; this is the check that
  # makes the difference observable.
  #
  # MATCHED ON THE ITEM, NOT ON A COMMAND. A gate reads
  # `- [ ] Qn — <item>: <command>`, and the command is the project's own —
  # `trivy fs .`, `cargo audit` and `govulncheck ./...` all prove SCA, and
  # naming one would fail the two others. So each pattern is a distinctive
  # substring of the catalog row's NAME, matched case-insensitively against the
  # lowercased line. `sca` is bounded by non-letters so it cannot be found
  # inside a word.
  #
  # SCOPED TO THE GATES SECTION, reusing the `in_gates`/`in_fence` state this
  # loop already tracks rather than locating the section a second time — the
  # comment above says in full why two answers to "where do the gates start"
  # must not be allowed to drift apart. Scope is also precision: a sub-task
  # titled `1.2 - Write the README` is work planned, not a check that runs, and
  # a whole-file grep would read it as the item covered.
  FLOOR_LABELS=(
    'Supported and declared runtime'
    'Secrets'
    'README'
    'Dependency vulnerabilities (SCA)'
    'Data integrity'
  )
  FLOOR_RE=(
    'runtime'
    'secret'
    'readme'
    'dependency vulnerabilit|(^|[^a-z])sca([^a-z]|$)'
    'data integrit'
  )
  FLOOR_SEEN=(false false false false false)

  # A GATE THAT LEADS WITH A VERSION. validate-run.sh runs a gate's first
  # backtick span, so `go 1.27` declared in `go.mod` ran `go 1.27`, a usage
  # error, and recorded a false FAIL (0.28 battery, 2026-11-08). A WARNING, not
  # an error: the plan is still valid, and the fix is one rewrite of the line.
  # shellcheck disable=SC2016  # the backticks are literal Markdown, not expansion
  gate_span_re='^- \[[ x~]\] [^`]*`([^`]+)`'
  version_only_re='^([A-Za-z][A-Za-z0-9_.+-]*[[:space:]]*)?[v~^>=<]*[[:space:]]*[0-9]+(\.[0-9x*]+)*$'

  while IFS= read -r line || [[ -n "$line" ]]; do
    LINE_NO=$((LINE_NO + 1))
    # The two exclusions have to see EVERY line, so they precede the box filter:
    # a fence and a heading are not checkboxes. A fence line is itself never
    # content, and a `## Quality Gates` INSIDE a fence is documentation — so the
    # fence is tested first and wins.
    if [[ "$line" =~ $fence_re ]]; then
      if [[ "$in_fence" == true ]]; then in_fence=false; else in_fence=true; fi
    elif [[ "$in_fence" == false && "$in_gates" == false && "${line,,}" =~ $gates_re ]]; then
      in_gates=true
    fi
    # The floor sweep rides here, above the checkbox filter, for the same
    # reason the Commit-field lint does: it reads a LINE, and the filter below
    # discards every line that is not a box. A gate that has lost its checkbox
    # is a defect of a different kind, and this check should still see the item.
    # A flag already true is never re-tested: the first gate naming an item
    # settles it, and a second naming it again is not a second answer.
    if [[ "$in_fence" == false && "$in_gates" == true ]]; then
      floor_line_lc="${line,,}"
      for floor_i in "${!FLOOR_RE[@]}"; do
        [[ "${FLOOR_SEEN[floor_i]}" == false ]] || continue
        # A plain `if`, never `[[ … ]] && …`: a trailing AND-list that fails
        # hands its non-zero status up, and this script runs under `set -e`.
        if [[ "$floor_line_lc" =~ ${FLOOR_RE[floor_i]} ]]; then
          FLOOR_SEEN[floor_i]=true
        fi
      done
      if [[ "$line" =~ $gate_span_re ]] && [[ "${BASH_REMATCH[1]}" =~ $version_only_re ]]; then
        add_warning "tasks.md line $LINE_NO: the gate's first backtick span is only a version, \`${BASH_REMATCH[0]}\` — Validate runs that span as the check and records a false FAIL; lead with the command that reads the declaration, e.g. \`grep -Eq '^go [0-9]' go.mod\` (references/quality-catalog.md, Supported and declared runtime)"
      fi
    fi
    # The Commit-field anchor lint, argued in full at its own section
    # above. It rides THIS loop rather than opening a second pass for one
    # reason: the fence state is already tracked here, and an illustrative
    # `- Commit:` inside a fenced block is documentation showing the format, not
    # a claim about a commit — exactly the reading the group-state gathering
    # below applies to a fenced checkbox. Reusing that state is what keeps the
    # file to ONE fence policy instead of two that can drift apart.
    # It sits ABOVE the checkbox filter because it reads a FIELD: the filter
    # discards every line that is not a box, and no Commit field is one.
    # `in_gates` is deliberately NOT consulted — that exclusion exists because a
    # numbered Quality Gate is shaped exactly like a group header and has to be
    # disambiguated from one. A `- Commit:` field collides with no gate syntax,
    # so there is nothing to disambiguate and nothing to suppress.
    if [[ -n "$commit_anchor_re" && "$in_fence" == false && "$line" =~ $commit_field_re ]]; then
      commit_msg="${BASH_REMATCH[1]}"
      # Trim, then take what the QUOTES enclose: the template writes the message
      # quoted (`- Commit: "feat(NNN): …"`), so the quotes are the field's
      # punctuation and the subject being checked is what sits between them.
      #
      # UP TO THE CLOSING QUOTE, not "strip a matching outer pair": a correctly
      # anchored message may carry an editorial note after its closing quote
      # (`- Commit: "fix(NNN): …" — widened from the planned "…"`). That value
      # neither starts nor ends as a matched pair, so a pair-strip would leave
      # the leading `"` in place, the anchor regex could not see the `fix(`
      # behind it, and a properly anchored field would warn. Reading to the
      # first closing quote gets the message right for both shapes, and an
      # unquoted or unterminated value simply keeps what it has.
      if [[ "$commit_msg" =~ $commit_trim_re ]]; then commit_msg="${BASH_REMATCH[1]}"; fi
      case "$commit_msg" in
        '"'*) commit_msg="${commit_msg#\"}"; commit_msg="${commit_msg%%\"*}" ;;
        "'"*) commit_msg="${commit_msg#\'}"; commit_msg="${commit_msg%%\'*}" ;;
      esac
      if ! [[ "$commit_msg" =~ $commit_anchor_re ]]; then
        add_warning "tasks.md line $LINE_NO: Commit message carries no story anchor — expected the subject scoped with this story's number, $COMMIT_ANCHOR_HINT, found: $commit_msg — without the anchor story-git-status.sh cannot see this commit"
      fi
    fi
    [[ "$line" =~ $box_re ]] || continue
    box_char="${BASH_REMATCH[1]}"
    box_unknown=false   # an unqualified [~]: a box whose state cannot be read
    case "$box_char" in
      ' ') BOX_OPEN=$((BOX_OPEN + 1)) ;;
      'x') BOX_CLOSED=$((BOX_CLOSED + 1)) ;;
      '~')
        if [[ "$line" =~ $deferred_re || "$line" =~ $terminal_re ]]; then
          BOX_CLOSED=$((BOX_CLOSED + 1))
          # `deferred:` WINS over a terminal qualifier on the same line, which is
          # the same precedence references/supersede-mode.md gives it: a line
          # carrying both stays owed. Tested as its own case — a `[~] (deferred:
          # …) (superseded-by: NNN)` line is deferred, not terminal.
          # Written as a plain `if`, not `[[ … ]] && …`: a trailing AND-list that
          # fails hands its non-zero status up to the enclosing `case`, and this
          # script runs under `set -e`.
          if [[ "$line" =~ $deferred_re ]]; then
            BOX_DEFERRED=$((BOX_DEFERRED + 1))
          fi
        else
          BOX_UNQUALIFIED=$((BOX_UNQUALIFIED + 1))
          box_unknown=true
          add_error "tasks.md line $LINE_NO: [~] checkbox has no qualifier — a box closed without doing the work must say why on the same line, one of: $tilde_forms"
        fi
        ;;
    esac
    # Everything from here is group state, and the two exclusions apply to it
    # alone — the census above has already counted this box.
    [[ "$in_gates" == false && "$in_fence" == false ]] || continue
    if [[ "$line" =~ $task_num_re ]] && (( ${#BASH_REMATCH[2]} <= GRP_MAX_DIGITS )); then
      grp_n=$((10#${BASH_REMATCH[2]}))       # the key: `08` and `8` are one group
      grp_spelling="${BASH_REMATCH[2]}"      # what the author actually wrote
      if [[ -n "${BASH_REMATCH[3]:-}" ]]; then
        # `N.M` — a sub-task, owned by the number BEFORE the dot, which is why
        # group 1 owns 1.1 and never owns 10.1.
        GRP_SUBS[grp_n]=$(( ${GRP_SUBS[grp_n]:-0} + 1 ))
        # Readability first: a box the census has just rejected cannot be
        # classified open or closed at all, and it makes its group's verdict not
        # computable. Only then does `[ ]` mean open — and nothing else does,
        # since references/tasks.md makes it the only state that counts as
        # pending.
        if [[ "$box_unknown" == true ]]; then
          GRP_BAD[grp_n]=$(( ${GRP_BAD[grp_n]:-0} + 1 ))
        elif [[ "$box_char" == ' ' ]]; then
          GRP_OPEN[grp_n]=$(( ${GRP_OPEN[grp_n]:-0} + 1 ))
        fi
      else
        # `N` — the group's own header. The FIRST one wins the box, the spelling
        # and the reported line, so a later one cannot overwrite a
        # violation into silence. Every header still contributes its line
        # number: more than one token IS the duplicate, and the tokens are the
        # lines the author has to go and look at.
        if [[ -z "${GRP_LINES[grp_n]:-}" ]]; then
          GRP_BOX[grp_n]="$box_char"
          GRP_LABEL[grp_n]="$grp_spelling"
          GRP_LINES[grp_n]="$LINE_NO"
        else
          GRP_LINES[grp_n]+=" $LINE_NO"
        fi
      fi
    fi
  done < "$TASKS_FILE" 2>/dev/null || true

  # --- The security floor: every item owes a gate ---
  #
  # GATED ON A DECLARED `engineering:`, which is this file's rule for every
  # field the plugin added rather than inherited: fail-OPEN on absence,
  # fail-CLOSED on a value that is present. The field is what marks a story as
  # subject to the floor: a story without it validates exactly as it did, and
  # no legacy artifact is retroactively accused of missing a rule that did not
  # exist when it was written.
  #
  # AN ERROR, NOT A WARNING. A warning is just another sentence asking to be
  # honoured, and an unverified floor is exactly what this check catches. The story declares a level; the
  # catalog says that level activates these five whatever else it drops; a gates
  # section without them contradicts the story's own frontmatter. One message
  # names every missing item, because an author who lost the legend lost all of
  # them at once and should fix them in one pass, not five.
  if [[ -n "$DECLARED_ENGINEERING" ]]; then
    FLOOR_MISSING=()
    for floor_i in "${!FLOOR_LABELS[@]}"; do
      if [[ "${FLOOR_SEEN[floor_i]}" == false ]]; then
        FLOOR_MISSING+=("${FLOOR_LABELS[floor_i]}")
      fi
    done
    if [[ ${#FLOOR_MISSING[@]} -gt 0 ]]; then
      # Joined by hand, not with `IFS`: `"${arr[*]}"` joins on the FIRST
      # character of IFS alone, so `IFS='; '` yields `a;b` — a separator the
      # message does not want and a reader would misread as one token.
      FLOOR_LIST=""
      for floor_i in "${!FLOOR_MISSING[@]}"; do
        [[ -z "$FLOOR_LIST" ]] || FLOOR_LIST+="; "
        FLOOR_LIST+="${FLOOR_MISSING[floor_i]}"
      done
      add_error "tasks.md declares engineering '$DECLARED_ENGINEERING' but its Quality Gates carry no gate for ${#FLOOR_MISSING[@]} of the five security-floor items: $FLOOR_LIST — the floor is the set no level drops (references/quality-catalog.md, The security floor), and an item with no gate is never run and never settled"
    fi
  fi

  # The verdict needs every child of a group, so it can only be reached once the
  # loop has ended. The rule is an IDENTITY and is therefore enforced in BOTH
  # directions — half of an identity is not the identity.
  #   - a `[ ]` header with no open sub-task claims work still owed that none of
  #     its own sub-tasks still owes;
  #   - a `[x]` header over ANY open sub-task claims work done that is still
  #     owed.
  # Two states are named, and there are THREE: a `[~]` header is closed without
  # doing the work, which the grammar allows, and NEITHER direction may touch
  # it — hence a `case` with no `~` branch rather than an if/else over `[x]`.
  # Two shapes make the verdict NOT COMPUTABLE and are skipped rather than
  # guessed, because not-computable must never dress up as a finding
  # (references/validate-mode.md): a duplicated group number, and a child whose
  # own box the census has already rejected.
  # GRP_BOX and GRP_LABEL are written in the same branch that first writes
  # GRP_LINES, so every key iterated here carries all three. The ${#} guard
  # keeps the expansion legal under set -u, matching the STATUS_VALUES guard
  # below.
  if [[ ${#GRP_LINES[@]} -gt 0 ]]; then
    for grp_n in "${!GRP_LINES[@]}"; do
      grp_label=${GRP_LABEL[grp_n]}
      grp_lines=${GRP_LINES[grp_n]}
      grp_first=${grp_lines%% *}
      # One number, one group. Two headers claiming it is an identity violation
      # in its own right, and it is the mechanism by which a real violation can
      # be overwritten into silence — so it is reported, and the consistency
      # verdict for that number is not attempted.
      if [[ "$grp_lines" == *' '* ]]; then
        add_error "tasks.md line $grp_first: group $grp_label has more than one header (lines ${grp_lines// /, }) — a group number names one group, and its state cannot be read while two headers claim it"
        continue
      fi
      # Read both tallies once: a group the loop never saw a sub-task for has
      # no entry at all, and nothing to be consistent with either.
      grp_subs=${GRP_SUBS[grp_n]:-0}
      grp_open=${GRP_OPEN[grp_n]:-0}
      (( grp_subs > 0 )) || continue
      # A child whose box is invalid has no readable state, so neither does its
      # group. An error here would accuse a header that may well be right, and
      # the accusation would evaporate the moment the author fixed the real
      # error the honest way, by writing `- [ ] N.M`.
      (( ${GRP_BAD[grp_n]:-0} == 0 )) || continue
      case "${GRP_BOX[grp_n]}" in
        ' ')
          if (( grp_open == 0 )); then
            # State the condition that was TESTED, not an inference from it:
            # "already done" would be exactly backwards for a deferred child —
            # `[~] deferred:` is nothing pending AND the work not done.
            add_error "tasks.md line $grp_first: group $grp_label is open ([ ]) but no sub-task is still open ([ ]) — a group header must not claim work that none of its sub-tasks still owes; close it with [x], or with [~] and a qualifier if the work was not done"
          fi
          ;;
        'x')
          if (( grp_open > 0 )); then
            # The count is 1 far more often than not, so the subject and its
            # verb are built together rather than hard-coded plural.
            if (( grp_open == 1 )); then
              grp_subject="1 of its sub-tasks is"
            else
              grp_subject="$grp_open of its sub-tasks are"
            fi
            add_error "tasks.md line $grp_first: group $grp_label is closed ([x]) but $grp_subject still open ([ ]) — a group header must not claim work that is still owed"
          fi
          ;;
      esac
    done
  fi

  # Count all tasks (parent + sub-tasks) = every box whatever its state;
  # needed by checks inside and outside the HAS_STORY branch below — define
  # once here so set -u doesn't trip Fast mode validation (tasks.md without
  # story.md).
  TASK_COUNT=$(( ${BOX_OPEN:-0} + ${BOX_CLOSED:-0} + ${BOX_UNQUALIFIED:-0} ))

  # A tasks.md with ZERO parseable checkbox tasks must never pass: every
  # downstream check is gated on TASK_COUNT > 0, so an unrecognized dialect
  # would otherwise pass with 0 errors. Name the variant when we can.
  if [[ "$TASK_COUNT" -eq 0 ]]; then
    VARIANT_HINT=""
    if grep -qE '^\s*-?\s*\*\*Covers:\*\*|^Covers:' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected 'Covers:' dialect)"
    elif grep -qE '^#{2,3}\s+T?[0-9]+(\.[0-9]+)?[[:space:]]' "$TASKS_FILE" 2>/dev/null; then
      VARIANT_HINT=" (detected heading-based task dialect)"
    fi
    add_error "tasks.md has no parseable checkbox tasks (- [ ] N - ...)${VARIANT_HINT} — unrecognized format, nothing was validated"
  fi

  # Check Requirements field — only when story.md exists AND the resolved scale
  # is one that owes a requirements chain.
  #
  # THIS GATE AND THE SPIKE R-CHAIN CHECK FURTHER DOWN MUST ANSWER FROM THE SAME
  # SOURCE, the declared scale. Inferring it here from FILE PRESENCE would tell
  # a spike carrying a leftover story.md to add `Requirements:` fields, while
  # the spike R-chain check calls a `Requirements:` field an error — obeying
  # either instruction would break the other.
  #
  # `fast` is tasks-only for exactly the same reason a spike is, and
  # references/tasks.md tells a fast author to omit the `Requirements:` field.
  # So the exemption comes from the predicate scale_has_requirements_chain
  # above rather than a literal scale name: the answer comes from the
  # DECLARATION for every scale at once, and a future scale is classified in
  # ONE place. Note what that does and does not buy: a NEW tasks-only scale is
  # still not exempt automatically — the predicate's `*` arm demands a chain
  # from anything it has not been taught, loudly, on the first run. That is the
  # deliberate direction, not an oversight; the argument is above the function.
  #
  # What goes away is the ADVICE, not the finding: those stories are still
  # malformed, and the scale-mismatch warning above still reports each of them
  # — naming both sides and leaving the author to decide which is wrong (remove
  # story.md, or declare the scale the files actually describe).
  #
  # CONSEQUENCE, stated so it is not mistaken for a defect: a spike or fast
  # story with a leftover story.md exits 0 non-strict, with only the mismatch
  # warning. So a consumer that blocks on exit 1 and reads .error_details[]
  # only lets BOTH shapes through, and so does the CI loop references/ci-mode.md
  # documents without --strict. Under --strict the mismatch warning still fails
  # the run, for both.
  # That trade is deliberate: scale-vs-files is a WARNING because which side is
  # wrong is the author's call, and an error here would say something the spike
  # contract (for spike) and references/tasks.md (for fast) make wrong to obey.
  # A gate that blocks on advice you must not follow is not a gate worth
  # keeping.
  #
  # Gated on the DECLARED scale and never on the absence of the field itself: a
  # standard story that simply forgot its `Requirements:` fields is precisely
  # what this check exists to catch, so reading "no fields" as "no chain wanted"
  # would silence its real job. standard, full and an undeclared legacy story
  # (DECLARED_SCALE == "", which the predicate routes through `*`) keep the
  # check unchanged — the legacy golden in tests/scale-validation.bats pins that
  # last one, the spike+story.md shape is pinned in
  # tests/spike-validation.bats, and the fast+story.md shape in
  # tests/scale-resolution.bats.
  if [[ "$HAS_STORY" == true ]] && scale_has_requirements_chain; then
    # Accept both old format (Requirements Coverage) and new format (Requirements:)
    COVERAGE_COUNT_NEW=$(grep -ci '^\s*- Requirements:' "$TASKS_FILE" 2>/dev/null || true)
    COVERAGE_COUNT_OLD=$(grep -ci 'Requirements Coverage' "$TASKS_FILE" 2>/dev/null || true)
    COVERAGE_COUNT=$((COVERAGE_COUNT_NEW + COVERAGE_COUNT_OLD))
    if [[ "$TASK_COUNT" -gt 0 && "$COVERAGE_COUNT" -eq 0 ]]; then
      add_error "tasks.md has $TASK_COUNT tasks but no 'Requirements:' fields"
    fi
  fi

  # Check Quality Gates section
  if ! grep -qi 'Quality Gates' "$TASKS_FILE" 2>/dev/null; then
    add_warning "tasks.md is missing 'Quality Gates' section"
  fi

  # Check for metadata lines (italic format)
  PARENT_TASK_COUNT=$(grep -cE '^\s*- \[[ x~]\]\s+[0-9]+\s+-\s+' "$TASKS_FILE" 2>/dev/null || true)
  METADATA_COUNT=$(grep -cE '^\s*- _Complexity:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$METADATA_COUNT" -eq 0 ]]; then
    add_warning "No metadata lines found (expected _Complexity: ... | Tests: ... | ..._) on parent tasks"
  fi

  # Check for Commit fields or sub-tasks
  COMMIT_COUNT=$(grep -ci '^\s*- Commit:' "$TASKS_FILE" 2>/dev/null || true)
  COMMIT_SUBTASK_COUNT=$(grep -ciE '^\s*- \[[ x~]\].*[Cc]ommit' "$TASKS_FILE" 2>/dev/null || true)
  # TWO COUNTS, because the two questions are not the same question.
  #
  # The count above is DELIBERATELY loose: it answers "does this group have a
  # commit point at all", and for that purpose any box that mentions a commit
  # counts. The count below is the one the legacy nudge may use, and it is the
  # migrator's own COMMIT_BOX_RE verbatim (scripts/migrate-story.sh) — a box
  # titled exactly `N.M - Commit` and nothing else.
  #
  # They must not be the same number, because the nudge NAMES A TOOL and tells
  # the reader to run it. The loose pattern also counts sub-tasks that merely
  # mention the word — `- [x] 2.3 - Variant 5: Commit sub-task → group field` —
  # and `migrate --apply` does not convert those: it converts the exact shape,
  # so the reader would run the tool, see `commit_subtasks: 0`, and get the
  # identical warning again. An advisory that survives doing what it asks is
  # worse than no advisory.
  COMMIT_LEGACY_COUNT=$(grep -cE '^[[:space:]]*-[[:space:]]+\[[ x~]\][[:space:]]+[0-9]+\.[0-9]+[[:space:]]+-[[:space:]]+Commit[[:space:]]*$' "$TASKS_FILE" 2>/dev/null || true)
  TOTAL_COMMITS=$((COMMIT_COUNT + COMMIT_SUBTASK_COUNT))
  if [[ "$PARENT_TASK_COUNT" -gt 0 && "$TOTAL_COMMITS" -eq 0 ]]; then
    add_warning "No Commit fields or Commit sub-tasks found — every task group should have a commit point"
  fi

  # The legacy nudge. A Commit CHECKBOX is still accepted — existing stories
  # carry the shape and none of them is wrong — but it is the form
  # `migrate-story.sh` converts, and a checkbox that is never the unit of work
  # makes every group read as partially open. The nudge names both
  # the shape and the tool, so the reader is not left to search for either.
  if [[ "$COMMIT_LEGACY_COUNT" -gt 0 ]]; then
    add_warning "tasks.md carries $COMMIT_LEGACY_COUNT Commit sub-task checkbox(es) — the legacy shape. The canonical form is a group-level 'Commit:' field; 'bash scripts/migrate-story.sh <NNN> --apply' converts it, message verbatim"
  fi

  # --- Authoring ceiling (bytes) ---
  #
  # The threshold has ONE home, references/tasks.md § Authoring Ceiling, and
  # the warning CITES it rather than restating the number. A value repeated in
  # a message is a second place to edit and a second place to be wrong.
  #
  # WHY BYTES AND NOT A BOX COUNT. A checkbox is not a unit of work —
  # ".gitignore" and a whole module are each one box. How many tasks a story has
  # follows from the work, not from its level; the bound is on the unit (a sub-task is one Executor pass with a Validation command
  # that proves it alone), which the Validation-field check below already sees.
  #
  # A WARNING, NEVER AN ERROR: an oversized plan is a judgement call the author
  # is entitled to make. This site exists so a plan that shipped oversized stays
  # visible after authoring time, not only at the Phase 3 offer.
  CEILING_BYTES=32768
  TASKS_BYTES=$(wc -c < "$TASKS_FILE" 2>/dev/null | tr -d '[:space:]' || echo 0)
  if [[ "${TASKS_BYTES:-0}" -gt "$CEILING_BYTES" ]]; then
    add_warning "tasks.md is ${TASKS_BYTES} bytes, past the authoring ceiling — see references/tasks.md (Authoring Ceiling) for the threshold and the split offer"
  fi

  # Check for Validation fields
  VALIDATION_COUNT=$(grep -ci '^\s*- Validation:' "$TASKS_FILE" 2>/dev/null || true)
  if [[ "$TASK_COUNT" -gt 0 && "$VALIDATION_COUNT" -eq 0 ]]; then
    add_warning "No 'Validation:' fields found — sub-tasks should have testable validation criteria"
  fi
fi

# --- The spike contract: a Verdict, and no requirements chain ---
# A spike is a time-boxed probe whose deliverable is the ANSWER, not shipped
# code (references/tasks.md, Spike Scale Adaptations). Two consequences, and
# this section enforces exactly those two, no more:
#   1. it concludes through a mandatory `## Verdict` section rather than through
#      a lifecycle status, so a missing or unreadable one is an error — a spike
#      without a conclusion is the leak this scale exists to prevent;
#   2. it has no story.md, so every R-number written in it points at nothing —
#      a dangling pointer wearing traceability's clothes.
# What it deliberately does NOT enforce: `Tests` and `Acceptance` are optional
# at spike scale, and `Validation` plus the Quality Gates section are already
# checked for every scale above.
#
# ONE `if` guards the whole thing, which makes the fail-open rule structural
# rather than merely promised: a story that declares no scale must produce
# exactly the output it would without this section, and a guard satisfiable only by a DECLARED `spike` cannot leak
# into that path.

# parse_verdict <tasks.md> — the spike's conclusion:
#   ## Verdict
#   - status: open | promote | wont-do
#   - conclusion: <what was learned>
#   - promoted-to: NNN   # required when status: promote
# Only the first value of each key inside the section is read. `promoted-to`
# must start with a digit — that is what "the target is recorded" means, and it
# rejects the unfilled `NNN` placeholder of the template (fail-closed), which is
# precisely what makes the promote-without-target error fire on a copy-pasted
# template.
#
# The GRAMMAR — these four regexes — is shared VERBATIM with the parse_verdict
# of archive-story.sh AND of epico-index.sh, exactly as the checkbox census above
# shares its grammar with epico-index.sh and hook-session-restore.sh. THREE full
# consumers, plus a PARTIAL fourth — monitor-stale.sh's verdict_status,
# which copies the first three regexes verbatim and deliberately omits
# `promoted-to` (staleness keys on the status alone). If the grammar is ever
# amended, all four move together. The AGGREGATION is per-consumer and differs
# on purpose: archive-story.sh turns the verdict into a completion verdict (may
# this story be archived?), epico-index.sh RENDERS it for a human,
# monitor-stale.sh turns it into a deadline (has this probe concluded yet?), and
# this script turns it into validation errors.
VERDICT_STATUS=""
VERDICT_PROMOTED_TO=""
parse_verdict() {
  local file="$1" line in_verdict=false
  local heading_re='^#{2,}[[:space:]]'
  local verdict_re='^#{2,}[[:space:]]+[Vv]erdict([[:space:]].*)?$'
  local status_re='^[[:space:]]*(-[[:space:]]+)?status:[[:space:]]*([^[:space:]|]+)'
  local promoted_re='^[[:space:]]*(-[[:space:]]+)?promoted-to:[[:space:]]*([0-9][^[:space:]#]*)'
  VERDICT_STATUS=""
  VERDICT_PROMOTED_TO=""
  [[ -f "$file" ]] || return 0
  {
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ $heading_re ]]; then
        if [[ "$line" =~ $verdict_re ]]; then in_verdict=true; else in_verdict=false; fi
        continue
      fi
      [[ "$in_verdict" == true ]] || continue
      if [[ -z "$VERDICT_STATUS" && "$line" =~ $status_re ]]; then
        VERDICT_STATUS="${BASH_REMATCH[2]}"
      elif [[ -z "$VERDICT_PROMOTED_TO" && "$line" =~ $promoted_re ]]; then
        VERDICT_PROMOTED_TO="${BASH_REMATCH[2]}"
      fi
    done
    :
  } 2>/dev/null < "$file" || return 1
  return 0
}

# The three verdicts, one source of truth for the check and the message, like
# SCALE_ENUM above and STATUS_ENUM below. `promote` (with its target recorded)
# and `wont-do` are terminal and make the spike archivable; `open` is not.
VERDICT_ENUM='open|promote|wont-do'
VERDICT_ENUM_TEXT=${VERDICT_ENUM//|/, }

# no_r_chain <line number> <what was found> — ONE skeleton for both shapes an
# R-chain takes, so the sanctioned wording is spelled once, exactly as
# scale_mismatch above spells its "names BOTH sides" once: the spike contract
# pins the sentence, and a sentence kept in two places is a sentence that eventually gets
# edited in one.
no_r_chain() {
  add_error "tasks.md line $1: found $2 — spikes have no requirements chain — promote to a story for traceability"
}

# HAS_TASKS is part of the guard, not an afterthought: a spike with no tasks.md
# has no Verdict because it has no file, and the missing-tasks.md error above
# already says the only useful thing there is to say. Piling "no Verdict" on top
# would report the same absence twice.
if [[ "$DECLARED_SCALE" == "spike" && "$HAS_TASKS" == true ]]; then
  SPIKE_TASKS="$STORY_DIR/tasks.md"

  # Unreadable and absent land in the same place, as they do for the other two
  # consumers: `|| true` keeps a failed read from aborting the run under set -e,
  # and the empty status below reports it as "no Verdict". Neither is a verdict.
  parse_verdict "$SPIKE_TASKS" || true
  if [[ -z "$VERDICT_STATUS" ]]; then
    add_error "tasks.md has no readable '## Verdict' section with a 'status:' line — a spike concludes through its Verdict, not through a lifecycle status; record one of: $VERDICT_ENUM_TEXT"
  elif ! [[ "$VERDICT_STATUS" =~ ^($VERDICT_ENUM)$ ]]; then
    add_error "tasks.md '## Verdict' status is not a spike verdict: found '$VERDICT_STATUS' — must be one of: $VERDICT_ENUM_TEXT"
  elif [[ "$VERDICT_STATUS" == "promote" && -z "$VERDICT_PROMOTED_TO" ]]; then
    add_error "tasks.md '## Verdict' says 'promote' with no 'promoted-to:' story recorded — name the follow-up story number; the template's unreplaced 'NNN' is not a number and counts as no target"
  fi

  # No requirements chain. The scan reads the WHOLE file — frontmatter
  # and fenced blocks included — because that is exactly what the contract
  # promises ("write no R-number anywhere in the file") and because a dangling
  # pointer is no less dangling inside a fence. The Verdict's own prose is in
  # scope for the same reason: `conclusion: pending, see R2.1 upstream` is a
  # reference to a requirement that does not exist here either.
  #
  # ONE error per offending LINE, not per token: the line is what the author
  # edits, and a line carrying both shapes (`- Requirements: R1.1`) is one
  # mistake — so the field wins the description and its token is not re-reported.
  spike_req_re='^[[:space:]]*(-[[:space:]]+)?(\*\*)?[Rr]equirements:'
  # A token in its own right, with an explicit boundary on each side. Same shape
  # the cross-reference check below greps for with `\b`, spelled out because
  # `\b` is a GNU extension and this script also runs on BSD/macOS: `R2D2` is
  # not an R-token, `see R1.` is one.
  spike_r_re='(^|[^[:alnum:]_])(R[0-9]+(\.[0-9]+)?)([^[:alnum:]_]|$)'
  spike_line_no=0
  while IFS= read -r spike_line || [[ -n "$spike_line" ]]; do
    spike_line_no=$((spike_line_no + 1))
    if [[ "$spike_line" =~ $spike_req_re ]]; then
      no_r_chain "$spike_line_no" "a 'Requirements:' field"
    elif [[ "$spike_line" =~ $spike_r_re ]]; then
      no_r_chain "$spike_line_no" "the R-number token '${BASH_REMATCH[2]}'"
    fi
  done < "$SPIKE_TASKS" 2>/dev/null || true
fi

# --- Validate frontmatter (version, status) ---
# `status:` is the story's single lifecycle state, shared by every artifact.
# Grammar rule: fail-CLOSED on a present-but-wrong value (an invented dialect
# is an error), fail-OPEN on absence (a story without status: must validate
# exactly as before — no error, no warning, no extra line).
# One source of truth for the enum: the alternation drives both the check and
# the human-readable message (a `case` pattern cannot — bash does not re-parse
# `|` from an expanded variable as alternation, only `[[ =~ ]]` does).
STATUS_ENUM='draft|in-progress|done|validated|superseded|archived'
STATUS_ENUM_TEXT=${STATUS_ENUM//|/, }
# The states that claim the work is finished — the ones a leftover `[ ]` box
# contradicts.
STATUS_COMPLETE='done|validated'
# The states that claim the work is UNFINISHED — the ones an empty box census
# contradicts. `superseded` and `archived` are deliberately in NEITHER set: both
# are terminal, both legitimately sit over a fully-closed census, and neither is
# a state rule 1 would overwrite with `done`.
STATUS_BEHIND='draft|in-progress'
STATUS_FILES=()   # basenames of the artifacts that actually carry the field
STATUS_VALUES=()  # their values, parallel to STATUS_FILES

for f in "$STORY_DIR"/*.md; do
  [[ -f "$f" ]] || continue
  BASENAME=$(basename "$f")
  if head -1 "$f" | grep -q '^---$' 2>/dev/null; then
    # Check required frontmatter fields ($d is POSIX; GNU-only `head -n -1`
    # would abort the whole validation on BSD/macOS under set -e + pipefail)
    FRONT=$(sed -n '2,/^---$/p' "$f" | sed '$d')
    if ! echo "$FRONT" | grep -q 'version:'; then
      add_warning "$BASENAME frontmatter missing 'version' field"
    fi
    if ! echo "$FRONT" | grep -q 'created:'; then
      add_warning "$BASENAME frontmatter missing 'created' field"
    fi
    # Validate version is integer
    VERSION_VAL=$(echo "$FRONT" | grep 'version:' | head -1 | sed 's/.*version:\s*//' | tr -d '[:space:]' || true)
    if [[ -n "$VERSION_VAL" ]] && ! [[ "$VERSION_VAL" =~ ^[0-9]+$ ]]; then
      add_error "$BASENAME frontmatter 'version' must be an integer, found: $VERSION_VAL"
    fi
    # Lifecycle state. Anchored at column 0 like the templates write it, so a
    # compound or nested key (`review_status:`) can never fake a status value.
    STATUS_VAL=$(echo "$FRONT" | grep -E '^status:' | head -1 | sed 's/.*status:\s*//' | tr -d '[:space:]' || true)
    if [[ -n "$STATUS_VAL" ]]; then
      if ! [[ "$STATUS_VAL" =~ ^($STATUS_ENUM)$ ]]; then
        add_error "$BASENAME frontmatter 'status' is not a lifecycle state: found '$STATUS_VAL' — must be one of: $STATUS_ENUM_TEXT"
      fi
      # An artifact without the field carries no opinion, so it is never
      # divergent: only artifacts that declare a status are compared.
      STATUS_FILES+=("$BASENAME")
      STATUS_VALUES+=("$STATUS_VAL")
    fi
  else
    add_warning "$BASENAME is missing version frontmatter"
  fi
done

# --- Story-level status consistency ---
# Entered only when at least one artifact declared a status: a story with no
# status: field skips this block whole, which is the fail-open rule made
# structural (no error, no warning, output byte-identical to a story without
# the field).
if [[ ${#STATUS_VALUES[@]} -gt 0 ]]; then
  # BOX_OPEN comes from the checkbox census, which runs only when tasks.md
  # exists; under set -u a story without tasks.md would abort here without the
  # ${VAR:-0} guard used throughout this script.
  OPEN_BOXES=${BOX_OPEN:-0}

  # The status lies about the work: it claims done while `[ ]` boxes remain.
  # `[~]` boxes are closed by grammar and must NOT count as open here.
  if [[ "$OPEN_BOXES" -gt 0 ]]; then
    for st_i in "${!STATUS_VALUES[@]}"; do
      if [[ "${STATUS_VALUES[$st_i]}" =~ ^($STATUS_COMPLETE)$ ]]; then
        add_warning "status is ahead of the checkboxes: ${STATUS_FILES[$st_i]} says '${STATUS_VALUES[$st_i]}' but $OPEN_BOXES task checkbox(es) are still open ([ ])"
        break  # one story, one lie — do not repeat it per artifact
      fi
    done
  fi

  # The converse: the work is finished and the status has not caught up. Rule 1
  # of references/run-mode.md writes `done` when a marking leaves "no `[ ]` and
  # no deferred `[~]`" — so a story satisfying that condition while still
  # declaring `draft` or `in-progress` is a rule-1 write that never happened.
  #
  # WHY THIS EXISTS AT ALL. The condition above is PREVENTED by rule 1 but
  # DETECTED by nothing else, so when the prevention silently fails to fire the
  # story still passes validation. The archive offer gated on "rule 1 wrote it
  # in this run" never fires there either, so the story is not merely
  # mislabelled: it falls out of the lifecycle.
  #
  # A WARNING, NOT AN ERROR. Warning matches its two siblings in this
  # block (ahead-of-checkboxes, divergent-status), and a legitimate transient
  # exists: a validate run between the last checkbox marking and rule 1's status
  # write lands exactly here, and should say so rather than fail.
  #
  # THE DEFERRED ARM IS THE HOSTILE HALF, not a refinement. references/run-mode.md
  # is explicit that a deferred box BLOCKS `done` — a story whose only remaining
  # non-`[x]` boxes are `[~] (deferred: …)` stays `in-progress` on purpose, and
  # its completeness surfaces as the computed condition `done-except-external`,
  # which is never persisted. Warning there would tell the author to write a
  # status the state machine forbids.
  if [[ "$OPEN_BOXES" -eq 0 && "${BOX_DEFERRED:-0}" -eq 0 && "${TASK_COUNT:-0}" -gt 0 ]]; then
    for st_i in "${!STATUS_VALUES[@]}"; do
      if [[ "${STATUS_VALUES[$st_i]}" =~ ^($STATUS_BEHIND)$ ]]; then
        add_warning "status is behind the checkboxes: ${STATUS_FILES[$st_i]} says '${STATUS_VALUES[$st_i]}' but no task checkbox is still open and none is deferred — run-mode rule 1 writes 'done' at that point"
        break  # one story, one lag — do not repeat it per artifact
      fi
    done
  fi

  # One story, one status: artifacts declaring different values disagree about
  # where the story is.
  STATUS_DIVERGED=false
  for st_v in "${STATUS_VALUES[@]}"; do
    [[ "$st_v" == "${STATUS_VALUES[0]}" ]] || STATUS_DIVERGED=true
  done
  if [[ "$STATUS_DIVERGED" == true ]]; then
    STATUS_PAIRS=""
    for st_i in "${!STATUS_FILES[@]}"; do
      STATUS_PAIRS+="${STATUS_PAIRS:+, }${STATUS_FILES[$st_i]}=${STATUS_VALUES[$st_i]}"
    done
    add_warning "Artifacts of this story declare different 'status' values ($STATUS_PAIRS) — every artifact must carry the same lifecycle state"
  fi
fi

# --- Flag parsing ---
CROSS_REF=false
STRICT=false
for arg in "$@"; do
  [[ "$arg" == "--cross-ref" ]] && CROSS_REF=true
  [[ "$arg" == "--strict" ]] && STRICT=true
done

# --- Cross-reference: the R-numbers on each side, compared ---
# THE SCALE GATES THE WHOLE BLOCK, not just the `elif` arm at the bottom — one
# conjunct, but WHERE it goes is the decision. A tasks-only scale whose
# tasks.md happens to contain R-tokens takes the LOOPS' branch instead of the
# `elif`, and would collect one warning per orphan and one per phantom, each of
# them advice that the spike's no-requirements-chain rule makes an ERROR to
# obey. Gating only the `elif` arm would leave that branch standing.
#
# WHAT GOES AWAY IS THE ADVICE, NOT THE FINDING, as at the coverage gate above:
# the same run still reports the leftover artifact through the
# scale-vs-files warning, and still errors on each R-token itself under the spike
# R-chain rule. This block simply stops being a second, contradicting voice.
#
# WHY THE HELPER IS CALLABLE FROM HERE — asked because the flag parsing sitting
# between its definition and this line makes the call look out of order: a shell
# function is in scope from the moment its definition is parsed until the end of
# the script, so parsing CROSS_REF/STRICT this late constrains those VARIABLES
# and nothing else. scale_has_requirements_chain is defined far above, beside
# the resolution it reads; the direction it is written in, and why that
# direction, is argued there and deliberately not repeated.
#
# The call sits outside the `[[ ]]` because bash cannot invoke a function inside
# a conditional expression. The requirements-coverage gate above spells its call
# the same way, so the predicate's two consumers read alike.
if [[ "$CROSS_REF" == true && "$HAS_STORY" == true && "$HAS_TASKS" == true ]] && scale_has_requirements_chain; then
  # Requirements are hierarchical: a group header `### Rn.` and its leaf
  # criteria `Rn.m`. Tasks reference the leaves. A one-level token Rn is a
  # requirement of its own only when story.md defines no child Rn.m for it;
  # otherwise Rn is a group header, covered via its leaves. Counting a header
  # as a leaf would produce a false orphan for every `### Rn.` heading.
  mapfile -t XR_STORY_LEAVES < <(grep -oE '\bR[0-9]+\.[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_STORY_ONELEVEL < <(grep -oE '\bR[0-9]+\b' "$STORY_DIR/story.md" 2>/dev/null | sort -u || true)
  mapfile -t XR_TASK_TOKENS < <(grep -oE '\bR[0-9]+(\.[0-9]+)?\b' "$STORY_DIR/tasks.md" 2>/dev/null | sort -u || true)

  XR_STORY_REQS=("${XR_STORY_LEAVES[@]}")
  XR_STORY_GROUPS=()
  for xr_tok in "${XR_STORY_ONELEVEL[@]}"; do
    xr_has_child=false
    for xr_leaf in "${XR_STORY_LEAVES[@]}"; do
      if [[ "$xr_leaf" == "$xr_tok".* ]]; then
        xr_has_child=true
        break
      fi
    done
    if [[ "$xr_has_child" == true ]]; then
      XR_STORY_GROUPS+=("$xr_tok")
    else
      XR_STORY_REQS+=("$xr_tok")
    fi
  done


  # --- satisfied-by: the sanctioned non-code deliverable ---
  #
  # A criterion whose deliverable is NOT code — a regression guard, a feasibility
  # verdict, a decision record — has no task to reference it and therefore reads
  # as an orphan. The suffix makes the intent declarable:
  #
  #   - R1.2: THE SYSTEM SHALL keep the regression guarded (satisfied-by: tests/regression.bats)
  #
  # TOKEN-ANCHORED, like the `[~]` qualifier it is modelled on: the artifact is
  # read from `(satisfied-by: ...)`, and the leaf it binds to is the most recent
  # `- Rn.m:` label, so a criterion wrapped over four lines can still carry the
  # suffix at its end. A heading resets the binding — a suffix cannot reach
  # across a requirement group into the next one.
  #
  # AN EMPTY ARTIFACT DOES NOT SATISFY. `(satisfied-by: )` names nothing, so the
  # leaf stays an orphan and validate-story.sh warns about the blank. The
  # class legalizes a deliverable, not a way to silence the check.
  #
  # MOVERS — this parser is duplicated, deliberately (no shared library):
  #   1. scripts/cross-reference.sh  — the orphan_requirements/satisfied_by split (the JSON side)
  #   2. scripts/validate-story.sh   — the --cross-ref orphan advisory
  # Both read the same grammar and must move together.
  declare -A XR_SATISFIED=()
  while IFS='|' read -r xr_leaf xr_art; do
    [[ -n "$xr_leaf" ]] && XR_SATISFIED["$xr_leaf"]="$xr_art"
  done < <(awk '
  /^[[:space:]]*-[[:space:]]+R[0-9]+\.[0-9]+:/ { cur = $0; sub(/^[[:space:]]*-[[:space:]]+/, "", cur); sub(/:.*/, "", cur) }
  /^#/ { cur = "" }
  {
    if (cur != "" && match($0, /\(satisfied-by:[^)]*\)/)) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^\(satisfied-by:[[:space:]]*/, "", s); sub(/\)$/, "", s)
      gsub(/[[:space:]]+$/, "", s)
      print cur "|" s
      cur = ""
    }
  }' "$STORY_DIR/story.md" 2>/dev/null || true)

  for xr_leaf in "${!XR_SATISFIED[@]}"; do
    if [[ -z "${XR_SATISFIED[$xr_leaf]}" ]]; then
      add_warning "Requirement $xr_leaf carries an empty 'satisfied-by:' suffix — name the artifact that answers for it, or drop the suffix"
    fi
  done

  if [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -gt 0 ]]; then
    # Story leaf requirements with no matching task reference (orphans), minus
    # those a non-empty satisfied-by suffix answers for.
    for xr_req in "${XR_STORY_REQS[@]}"; do
      if ! xr_in_list "$xr_req" "${XR_TASK_TOKENS[@]}" && [[ -z "${XR_SATISFIED[$xr_req]:-}" ]]; then
        add_warning "Requirement $xr_req in story.md has no matching reference in tasks.md"
      fi
    done
    # Task references matching no story requirement (phantoms).
    for xr_tok in "${XR_TASK_TOKENS[@]}"; do
      if ! xr_in_list "$xr_tok" "${XR_STORY_REQS[@]}" && ! xr_in_list "$xr_tok" "${XR_STORY_GROUPS[@]}"; then
        add_warning "Requirement $xr_tok referenced in tasks.md does not exist in story.md"
      fi
    done
  elif [[ ${#XR_STORY_REQS[@]} -gt 0 && ${#XR_TASK_TOKENS[@]} -eq 0 ]]; then
    add_warning "story.md has requirements but tasks.md has no R-number references"
  fi
fi

# --- Output ---
TOTAL_ERRORS=${#ERRORS[@]}
TOTAL_WARNINGS=${#WARNINGS[@]}

echo "{"
echo "  \"story\": \"$(json_escape "$STORY_DIR")\","
echo "  \"errors\": $TOTAL_ERRORS,"
echo "  \"warning_count\": $TOTAL_WARNINGS,"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  echo "  \"error_details\": ["
  for i in "${!ERRORS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_ERRORS - 1)) ]] && COMMA=""
    echo "    \"$(json_escape "${ERRORS[$i]}")\"$COMMA"
  done
  echo "  ],"
else
  echo "  \"error_details\": [],"
fi

# `warnings` is the list and `warning_count` its length, as `errors` will be.
# `warning_details` repeats the list for one release (deprecated in 0.14.0).
WARNING_LIST="[]"
if [[ $TOTAL_WARNINGS -gt 0 ]]; then
  WARNING_LIST="["
  for i in "${!WARNINGS[@]}"; do
    COMMA=","
    [[ $i -eq $((TOTAL_WARNINGS - 1)) ]] && COMMA=""
    WARNING_LIST+=$'\n'"    \"$(json_escape "${WARNINGS[$i]}")\"$COMMA"
  done
  WARNING_LIST+=$'\n'"  ]"
fi
echo "  \"warnings\": $WARNING_LIST,"
echo "  \"warning_details\": $WARNING_LIST,"

# In --strict mode, warnings count as failures for the status and exit code.
if [[ "$STRICT" == true && $TOTAL_WARNINGS -gt 0 ]]; then
  STATUS_STR="fail"
elif [[ $TOTAL_ERRORS -gt 0 ]]; then
  STATUS_STR="fail"
else
  STATUS_STR="pass"
fi

echo "  \"strict\": $STRICT,"
echo "  \"status\": \"$STATUS_STR\""
echo "}"

if [[ $TOTAL_ERRORS -gt 0 ]]; then
  exit 1
elif [[ "$STRICT" == true && $TOTAL_WARNINGS -gt 0 ]]; then
  exit 1
else
  exit 0
fi
