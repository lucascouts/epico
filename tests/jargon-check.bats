#!/usr/bin/env bats
# epico-jargon: process words in a layperson-facing closing.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CHECK="$PLUGIN_ROOT/scripts/jargon-check.sh"
}

@test "a plain closing passes, a command in backticks included" {
  run bash -c "printf 'Pronto! Digite \`npm start\` para abrir.\nEle guarda suas cartas num arquivo.\nNão testei no celular.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true and .hits == []'
}

@test "process words are found and named as written, with counts" {
  run bash -c "printf 'Fechei a sub-task dois, o Executor fez o commit e outro commit.\nRed confirmado em R1.2, veja tasks.md.\n' | bash '$CHECK'"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.pass == false'
  echo "$output" | jq -e '[.hits[].term] | sort == ["Executor","R1.2","Red","commit","sub-task","tasks.md"]'
  echo "$output" | jq -e '.hits[] | select(.term == "commit") | .count == 2'
}

@test "case-sensitive terms do not flag ordinary words; fenced blocks are skipped" {
  run bash -c "printf 'The red button turns green when saved.\n\`\`\`\ngit commit -m x\n\`\`\`\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
}

@test "--file reads a file; bad usage exits 2" {
  f=$(mktemp)
  printf 'The orchestrator ran triage.\n' > "$f"
  run bash "$CHECK" --file "$f"
  [ "$status" -eq 1 ]
  rm -f "$f"
  run bash "$CHECK" --bogus
  [ "$status" -eq 2 ]
}

@test "every left-column group of the plain-register table is represented in the term list" {
  for t in 'executor' 'tasks\.md' 'closing block' 'Red' 'commit' 'quality gates' 'engineering level' 'MCP'; do
    command grep -qF -- "$t" "$PLUGIN_ROOT/assets/jargon-terms.txt" || { echo "term list lacks: $t"; return 1; }
  done
}

@test "a term with its legend in the same text passes, and is reported as explained" {
  run bash -c "printf 'O teste ficou Red antes do código.\n*Red* — o teste foi escrito antes e falha de propósito.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true and .hits == [] and .explained == ["Red"]'
}

@test "a legend explains only its own term; the others are still hits" {
  run bash -c "printf 'Ficou Red e fiz um commit.\n*Red* — o teste falha de propósito antes do código.\n' | bash '$CHECK'"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '[.hits[].term] == ["commit"] and .explained == ["Red"]'
}

@test "legend forms: bold, colon, hyphen, quote and list markers; a plural is covered by its singular" {
  text='Salvei dois commits na worktree.\n> **commit**: uma cópia salva do projeto.\n- *worktree* - uma pasta separada para trabalhar.\n'
  run bash -c "printf '$text' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.explained | sort == ["commits","worktree"]'
}

@test "the legend line is not itself scanned as a use of the term" {
  run bash -c "printf 'Tudo pronto.\n*commit* — uma cópia salva do projeto.\n' | bash '$CHECK'"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hits == []'
}

@test "plain-register states the legend rule and its format" {
  grep -qF 'carries its legend' "$PLUGIN_ROOT/references/plain-register.md"
  grep -qF '*term* — what it means here' "$PLUGIN_ROOT/references/plain-register.md"
}

@test "the leaks the blind judge quoted in the 1.1 validation are caught" {
  for t in 'Vou ler as referências do modo instant' 'Sigo as regras de triagem' 'Now the gates, run report' 'Agora fecho as caixas do plano' 'Fixing the stub'; do
    run bash -c "printf '%s\n' '$t' | bash '$CHECK'"
    [ "$status" -eq 1 ] || { echo "not caught: $t"; return 1; }
  done
}

@test "a legend list larger than a pipe buffer still finds the explained term (no SIGPIPE false miss)" {
  # The explained term sorts first, then ~90 KiB of other legends: grep -q
  # matches on line one and exits while the writer is mid-stream — under
  # pipefail that SIGPIPE read as "not explained".
  f=$(mktemp)
  { printf 'Fiz o commit.\n*commit* — uma versão salva\n'
    for i in $(seq 1 6000); do printf '*zzz%05d* — x\n' "$i"; done; } > "$f"
  run bash "$CHECK" --file "$f"
  rm -f "$f"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true'
}

@test "--max-chars fails a closing longer than the ceiling and reports its length" {
  # 2026-10-30 battery: "mto texto" in 13/14 runs; the closing ceiling is ~600.
  long=$(printf 'Pronto, a sua Pokédex já funciona e guarda tudo. %.0s' $(seq 1 15))
  run bash -c "printf '%s\n' '$long' | bash '$CHECK' --max-chars 600"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.pass == false and .hits == [] and .chars > 600 and .max_chars == 600'
}

@test "--max-chars passes a short closing and counts characters, not bytes" {
  run bash -c "printf 'Pronto! Digite \`npm start\` para abrir. Não testei no celular.\n' | bash '$CHECK' --max-chars 61"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.pass == true and .chars == 61'
}

@test "--max-chars without a positive number is bad usage" {
  run bash -c "printf 'oi\n' | bash '$CHECK' --max-chars abc"
  [ "$status" -eq 2 ]
}
