#!/usr/bin/env bats
# Story 028 — the security and infra rules that hold for any project, moved
# from a personal CLAUDE.md into the plugin: the CI mirror, the audit report's
# untested/verified_at keys, per-language secure-coding rules, the log rules,
# the supply-chain items and the eval/exec rule.
#
# The surface is agent-executed prose, so every case asserts keywords inside
# the block that carries the rule — a whole-file grep would pass on a mention
# in the wrong place. No case requires a sentence verbatim.
#
# Note on awk patterns: passed as strings, so no backslash escapes; literal
# punctuation goes in a bracket class.

ROOT="$BATS_TEST_DIRNAME/.."
CATALOG="$ROOT/references/quality-catalog.md"

section() { # section <file> <start regex> <end regex>
  awk -v s="$2" -v e="$3" '$0 ~ s {f=1; print; next} f && $0 ~ e {exit} f {print}' "$1"
}

row() { # row <block> <item> — the table line whose first cell is <item>
  printf '%s\n' "$1" | command grep -F -- "| $2 |" | head -1
}

has() { # has <label> <block> <extended regex> — case-insensitive
  if ! printf '%s' "$2" | command grep -Eqi -- "$3"; then
    echo "$1: expected the block to mention '$3'" >&2
    printf '%s\n' "$2" | head -20 >&2
    return 1
  fi
}

# --- R1: the CI mirror -------------------------------------------------------

@test "S1: CI mirror is a By context row with the workflows signal and act -j from the local caches" {
  ctx=$(section "$CATALOG" '^## By context' '^## ')
  r=$(row "$ctx" "CI mirror")
  [ -n "$r" ]
  has "S1 signal" "$r" '`\.github/workflows/`'
  has "S1 command" "$r" '`act --pull=false --action-offline-mode -j <job>`'
}

@test "S2: the CI mirror row mirrors the runner's clean checkout" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "CI mirror")
  has "S2 clean" "$r" 'clean checkout'
  has "S2 artifacts" "$r" 'build artifacts'
  has "S2 deps" "$r" 'dependenc'
  has "S2 env" "$r" '`\.env`'
}

@test "S3: the CI mirror row names the root false red and the normal-user run" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "CI mirror")
  has "S3 unreadable" "$r" 'unreadable'
  has "S3 root" "$r" 'root'
  has "S3 normal user" "$r" 'normal user'
}

@test "S4: product activates the CI mirror — in the catalog's level bound" {
  line=$(command grep -F 'The engineering level bounds the set' "$CATALOG")
  [ -n "$line" ]
  product=${line#*\`product\`}
  has "S4 product" "$product" 'CI mirror'
}

@test "S5: product activates the CI mirror — in engineering-level.md's product cell" {
  pays=$(section "$ROOT/references/engineering-level.md" '^## What each level pays for' '^## ')
  r=$(printf '%s\n' "$pays" | command grep -F '**Quality catalog**')
  [ -n "$r" ]
  product=$(printf '%s' "$r" | awk -F' [|] ' '{print $NF}')
  has "S5 product" "$product" 'CI mirror'
}

# --- R4: logs that cannot leak, tracing on request ---------------------------

@test "S6: the logs row forbids secrets and PII, redacted at the logger" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Structured logs and health")
  [ -n "$r" ]
  has "S6 secret" "$r" 'secret'
  has "S6 token" "$r" 'token'
  has "S6 credential" "$r" 'credential'
  has "S6 pii" "$r" 'PII'
  has "S6 at the logger" "$r" 'redact[a-z]* at the logger'
}

@test "S7: the logs row gives each level a meaning and a level switch with no redeploy" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Structured logs and health")
  has "S7 error" "$r" 'ERROR[^|]*human'
  has "S7 warn" "$r" 'WARN[^|]*(degraded|recovered)'
  has "S7 info" "$r" 'INFO[^|]*business event'
  has "S7 debug" "$r" 'DEBUG[^|]*off in production'
  has "S7 no redeploy" "$r" 'without a redeploy'
}

@test "S8: tracing (OpenTelemetry) is an on-request row" {
  req=$(section "$CATALOG" '^## On request' '^## ')
  r=$(row "$req" "Tracing (OpenTelemetry)")
  [ -n "$r" ]
}

# --- R5: supply-chain items --------------------------------------------------

@test "S9: the security-floor Secrets row keeps its exact text" {
  floor=$(section "$CATALOG" '^### The security floor' '^## ')
  r=$(row "$floor" "Secrets")
  [ "$r" = '| Secrets | a credential leaked from a script leaks exactly as far as one leaked from a product | `gitleaks detect` |' ]
}

@test "S10: trufflehog is the CI-side scanner of the always-tier Secrets row" {
  # `### The security floor` sits inside `## Always`, so the always tier is
  # scoped to end at that heading — a mention in the floor row must not count.
  always=$(section "$CATALOG" '^## Always' '^### The security floor')
  r=$(row "$always" "Secrets")
  [ -n "$r" ]
  has "S10 trufflehog" "$r" '`trufflehog'
  has "S10 ci" "$r" 'CI'
  has "S10 gitleaks kept" "$r" '`gitleaks'
}

@test "S11: Harden-Runner is named in the Hardened workflows row" {
  r=$(row "$(section "$CATALOG" '^## By context' '^## ')" "Hardened workflows")
  [ -n "$r" ]
  has "S11 harden-runner" "$r" 'Harden-Runner'
}

@test "S12: Scorecard and Socket are on-request rows" {
  req=$(section "$CATALOG" '^## On request' '^## ')
  [ -n "$(row "$req" "Repo posture score (OpenSSF Scorecard)")" ]
  [ -n "$(row "$req" "Behavioural malware scan (Socket)")" ]
}

# --- R1.4: the CI mirror gate without a container runtime --------------------

ci_mirror_rule() { # ci_mirror_rule <label> <block> — the rule sits on one line
  line=$(printf '%s\n' "$2" | command grep -F 'CI mirror' | command grep -F 'not run — no container runtime' | head -1)
  if [ -z "$line" ]; then
    echo "$1: no line names the CI mirror gate as 'not run — no container runtime'" >&2
    return 1
  fi
  has "$1 docker" "$line" 'docker'
  has "$1 podman" "$line" 'podman'
  has "$1 not a failure" "$line" 'never (a )?FAIL|not a failure'
}

@test "S13: validate-mode.md settles the CI mirror gate as not run without Docker or Podman" {
  part1=$(section "$ROOT/references/validate-mode.md" '^## Validation — Part 1' '^## ')
  ci_mirror_rule "S13" "$part1"
}

@test "S14: the validation protocol the Auditor runs carries the same rule" {
  proto=$(section "$ROOT/references/validation-protocol.md" '^Then settle the' '^Then write')
  ci_mirror_rule "S14" "$proto"
}

# --- R2: untested and verified_at in the audit report ------------------------

@test "S15: untested and verified_at are their own keys in auditor.md's report template, beside not_verified" {
  rep=$(section "$ROOT/agents/auditor.md" '^## The Report File' '^## ')
  yaml=$(printf '%s\n' "$rep" | awk '/^```yaml/{f=1;next} f && /^```/{exit} f')
  [ "$(printf '%s\n' "$yaml" | command grep -c '^not_verified:')" -eq 1 ]
  [ "$(printf '%s\n' "$yaml" | command grep -c '^untested:')" -eq 1 ]
  [ "$(printf '%s\n' "$yaml" | command grep -c '^verified_at:')" -eq 1 ]
}

@test "S16: auditor.md writes untested: [] explicitly and verified_at names the rung and its gap" {
  rep=$(section "$ROOT/agents/auditor.md" '^## The Report File' '^## ')
  prose=$(printf '%s\n' "$rep" | awk '/^```/{f=!f;next} !f')
  has "S16 empty" "$prose" '`untested: \[\]`'
  has "S16 never omitted" "$prose" 'untested[^.]*(never|not) (left out|omitted)|never (left out|omitted)[^.]*untested'
  has "S16 rung" "$prose" 'verified_at[^.]*rung'
  has "S16 gap" "$prose" 'verified_at[^.]*does not cover'
}

@test "S17: validate-mode.md's audit template carries both keys beside not_verified" {
  part2=$(section "$ROOT/references/validate-mode.md" '^## Audit — Part 2' '^## ')
  [ "$(printf '%s\n' "$part2" | command grep -c '^> not_verified:')" -eq 1 ]
  [ "$(printf '%s\n' "$part2" | command grep -c '^> untested:')" -eq 1 ]
  [ "$(printf '%s\n' "$part2" | command grep -c '^> verified_at:')" -eq 1 ]
}

@test "S18: the step that presents not_verified presents untested and verified_at too" {
  step=$(command grep -E '^5\. Present the combined results' "$ROOT/references/validate-mode.md")
  [ -n "$step" ]
  has "S18 not_verified" "$step" 'not_verified'
  has "S18 untested" "$step" 'untested'
  has "S18 verified_at" "$step" 'verified_at'
}

# --- R3: secure-coding rules per language ------------------------------------

LANGS="$ROOT/references/language-rules.md"

lang() { # lang <heading> — one `## <heading>` section, nothing past the next
  section "$LANGS" "^## $1\$" '^## '
}

@test "S19: language-rules.md has exactly the eight language sections" {
  [ -f "$LANGS" ]
  got=$(command grep -E '^## ' "$LANGS" | sed 's/^## //' | paste -sd'|')
  [ "$got" = "Go|Rust|Python|JavaScript/TypeScript|PHP|Shell|SQL|Docker" ]
}

@test "S20: Go — -race, a context timeout on network I/O, %w" {
  s=$(lang Go); [ -n "$s" ]
  has "S20 race" "$s" '-race'
  has "S20 timeout" "$s" 'context[^.]*timeout[^.]*network'
  has "S20 wrap" "$s" '%w'
}

@test "S21: Rust — no unwrap/expect in production, cargo audit" {
  s=$(lang Rust); [ -n "$s" ]
  has "S21 unwrap" "$s" 'unwrap'
  has "S21 expect" "$s" 'expect'
  has "S21 production" "$s" 'production'
  has "S21 audit" "$s" 'cargo audit'
}

@test "S22: Python — no shell=True with input, raise … from" {
  s=$(lang Python); [ -n "$s" ]
  has "S22 shell" "$s" 'shell=True'
  has "S22 raise from" "$s" 'raise [^ ]+ from'
}

@test "S23: JavaScript/TypeScript — strict, no any, schema validation of external data" {
  s=$(lang JavaScript/TypeScript); [ -n "$s" ]
  has "S23 strict" "$s" 'strict'
  has "S23 any" "$s" '`any`'
  has "S23 schema" "$s" 'schema[^.]*external|external[^.]*schema'
}

@test "S24: PHP — PDO prepared statements, htmlspecialchars" {
  s=$(lang PHP); [ -n "$s" ]
  has "S24 pdo" "$s" 'PDO[^.]*prepared'
  has "S24 escape" "$s" 'htmlspecialchars'
}

@test "S25: Shell — set -euo pipefail, quoted expansions" {
  s=$(lang Shell); [ -n "$s" ]
  has "S25 strict mode" "$s" 'set -euo pipefail'
  has "S25 quoted" "$s" 'quote[a-z]* every expansion|quoted expansion'
}

@test "S26: SQL — parameterized only" {
  s=$(lang SQL); [ -n "$s" ]
  has "S26 param" "$s" 'parameteri[sz]ed'
  has "S26 never concat" "$s" 'never (concatenat|interpolat)'
}

@test "S27: Docker — digest pin, multi-stage, .dockerignore, non-root, no secret in the image" {
  s=$(lang Docker); [ -n "$s" ]
  has "S27 digest" "$s" 'sha256:'
  has "S27 multi-stage" "$s" 'multi-stage'
  has "S27 dockerignore" "$s" '\.dockerignore'
  has "S27 non-root" "$s" 'non-root'
  has "S27 secret" "$s" 'secret[^.]*image|image[^.]*secret'
}

RUN_MODE="$ROOT/references/run-mode.md"

@test "S28: the Executor prompt template names language-rules.md per detected language" {
  tpl=$(section "$RUN_MODE" '^### Executor Prompt Template' '^### ')
  has "S28 file" "$tpl" 'language-rules\.md'
  has "S28 per language" "$tpl" 'each detected language|per detected language'
}

@test "S29: the delegated route builds the prompt with those sections" {
  del=$(section "$RUN_MODE" '^### Delegated Route' '^### ')
  step1=$(printf '%s\n' "$del" | command grep -E '^1\. ')
  has "S29 step 1" "$step1" 'language-rules\.md'
}

@test "S30: the inline route reads the same sections before implementing" {
  inl=$(section "$RUN_MODE" '^### Inline Route' '^### ')
  has "S30 file" "$inl" 'language-rules\.md'
  has "S30 before" "$inl" 'language-rules\.md[^.]*before implement|before implement[^.]*language-rules'
}

@test "S31: a language with no section names none, says so in one line, invents nothing" {
  det=$(section "$RUN_MODE" '^## Tech Stack Detection' '^## ')
  line=$(printf '%s\n' "$det" | command grep -F 'language-rules.md' | command grep -iE 'no section' | head -1)
  [ -n "$line" ]
  has "S31 none" "$line" 'name[s]? none'
  has "S31 one line" "$line" 'one line'
  has "S31 invent" "$line" 'never invent|without inventing'
}

@test "S32: the Tech Reviewer prompt template names the language-rules.md sections under review" {
  tpl=$(section "$ROOT/references/run-tech-review.md" '^### Tech Reviewer Prompt Template' '^### ')
  has "S32 file" "$tpl" 'language-rules\.md'
  has "S32 under review" "$tpl" 'under review'
}

@test "S33: the no-match line applies to the reviewer prompt" {
  tpl=$(section "$ROOT/references/run-tech-review.md" '^### Tech Reviewer Prompt Template' '^### ')
  has "S33 no section" "$tpl" 'no language-rules\.md section for'
}

@test "S34: tech-reviewer.md's Protocol points at the named sections" {
  proto=$(section "$ROOT/agents/tech-reviewer.md" '^## Protocol' '^## ')
  has "S34 pointer" "$proto" 'language-rules\.md'
}

# --- R5.1–R5.3: never eval or exec input --------------------------------------

eval_rule() { # eval_rule <label> <block>
  has "$1 eval" "$2" 'never `?eval`?/?`?exec`?[^.]*input'
  has "$1 build" "$2" 'never build a command or (a )?query from it'
}

@test "S35: the Executor's implementation step forbids eval/exec of input" {
  step2=$(section "$ROOT/agents/executor.md" '^### Step 2' '^### ')
  eval_rule "S35" "$step2"
}

@test "S36: the Tech Reviewer states it beside the parameterized-SQL rule" {
  sql=$(section "$ROOT/agents/tech-reviewer.md" '^[*][*]For SQL' '^[*][*]For API')
  has "S36 sql kept" "$sql" 'parameterized placeholders'
  eval_rule "S36" "$sql"
}

@test "S37: the managed CLAUDE.md block carries it in Code rules, and stays under 100 lines" {
  R=$(mktemp -d)
  git -C "$R" init -q
  mkdir -p "$R/.epico"
  cp "$ROOT/.epico/constitution.md" "$R/.epico/constitution.md"
  run bash "$ROOT/scripts/claude-md.sh" write --root "$R"
  [ "$status" -eq 0 ]
  lines=$(printf '%s' "$output" | jq -r '.lines')
  rules=$(section "$R/CLAUDE.md" '^### Code rules' '^#')
  rm -rf "$R"
  eval_rule "S37" "$rules"
  [ "$lines" -lt 100 ]
}
