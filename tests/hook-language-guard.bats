#!/usr/bin/env bats
# hook-language-guard.sh: an English sentence that reached the requester in a
# conversation held in another language blocks the end of the turn once, asking
# for a rewrite in their language — not a legend. Everything else fails open.
#
# 2026-10-30 SDD battery: English narration between tool calls in 10/14 epico
# runs; the legend guard answered "Quality gates" with a legend for a child.
#
#   G1  epico session, Portuguese prompts, an English sentence → block, quoting it
#   G2  the same turn written in Portuguese → allow
#   G3  an English conversation → allow
#   G4  a session that never invoked the epico → allow
#   G5  stop_hook_active → allow
#   G6  English inside a code span or a fenced block → allow
#   G7  an English sentence from an EARLIER turn does not count
#   G8  a short English label (under four words) → allow — the legend guard's case
#   G9  no transcript → allow
#   G10 hooks.json registers it on Stop

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$PLUGIN_ROOT/scripts/hook-language-guard.sh"
  PROJ=$(mktemp -d)
  TR="$PROJ/transcript.jsonl"
}

teardown() { rm -rf "$PROJ"; }

# transcript <prompt> <epico: yes|no> <assistant text of this turn...> — one
# prior turn with an English sentence, then the current prompt, a tool round
# trip, and the given text blocks.
transcript() {
  local prompt=$1 epico=$2; shift 2
  {
    jq -cn '{type:"user", message:{content:"quero uma pokedex com site"}}'
    if [ "$epico" = yes ]; then
      jq -cn '{type:"assistant", message:{content:[{type:"tool_use", id:"s1", name:"Skill", input:{skill:"epico:epico", args:"pokedex"}}]}}'
      jq -cn '{type:"user", message:{content:[{type:"tool_result", tool_use_id:"s1", content:"loaded"}]}}'
    fi
    jq -cn '{type:"assistant", message:{content:[{type:"text", text:"Now I will write the tests for the save file."}]}}'
    jq -cn --arg p "$prompt" '{type:"user", message:{content:$p}}'
    jq -cn '{type:"assistant", message:{content:[{type:"tool_use", id:"t1", name:"Bash", input:{}}]}}'
    jq -cn '{type:"user", message:{content:[{type:"tool_result", tool_use_id:"t1", content:"ok"}]}}'
    for t in "$@"; do jq -cn --arg t "$t" '{type:"assistant", message:{content:[{type:"text", text:$t}]}}'; done
  } > "$TR"
}

run_hook() { run bash -c "jq -cn --arg tr '$TR' --arg cwd '$PROJ' --argjson a ${1:-false} '{transcript_path:\$tr, cwd:\$cwd, stop_hook_active:\$a}' | bash '$HOOK'"; }

@test "G1 an English sentence in a Portuguese epico conversation blocks, quoting it" {
  transcript 'agora faz o site pra mim' yes 'Now the implementation, then I will run all the tests.' 'Pronto! Seu site funciona.'
  run_hook
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"'
  echo "$output" | jq -r .reason | grep -qF 'Now the implementation, then I will run all the tests'
  echo "$output" | jq -r .reason | grep -qiF 'rewrite'
  echo "$output" | jq -r .reason | grep -qF 'not a legend'
  echo "$output" | jq -r .reason | grep -qF 'Do not mention this check'
}

@test "G2 the same turn written in Portuguese lets the turn end" {
  transcript 'agora faz o site pra mim' yes 'Agora a parte do site, depois rodo todos os testes.' 'Pronto! Seu site funciona.'
  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G3 an English conversation lets the turn end" {
  transcript 'now build the website for me please' yes 'Now the implementation, then I will run all the tests.'
  run_hook
  [ -z "$output" ]
}

@test "G4 a session that never invoked the epico lets the turn end" {
  transcript 'agora faz o site pra mim' no 'Now the implementation, then I will run all the tests.'
  run_hook
  [ -z "$output" ]
}

@test "G5 stop_hook_active lets the turn end" {
  transcript 'agora faz o site pra mim' yes 'Now the implementation, then I will run all the tests.'
  run_hook true
  [ -z "$output" ]
}

@test "G6 English inside a code span or a fenced block is not narration" {
  transcript 'agora faz o site pra mim' yes 'Rodei `npm test -- --run all the tests now` e passou.' 'Saída:
```
All the tests passed and the file is saved to disk.
```'
  run_hook
  [ -z "$output" ]
}

@test "G7 an English sentence from an earlier turn does not count" {
  transcript 'agora faz o site pra mim' yes 'Pronto! Seu site funciona.'
  run_hook
  [ -z "$output" ]
}

@test "G8 a short English label is left to the legend guard" {
  transcript 'agora faz o site pra mim' yes 'Quality gates ok.' 'Pronto! Seu site funciona.'
  run_hook
  [ -z "$output" ]
}

@test "G9 no transcript lets the turn end" {
  run bash -c "jq -cn '{transcript_path:\"/nonexistent/x.jsonl\", stop_hook_active:false}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "G10 hooks.json registers it on Stop" {
  jq -e '.hooks.Stop[].hooks[] | select(.command | contains("hook-language-guard.sh"))' "$PLUGIN_ROOT/hooks/hooks.json"
}
