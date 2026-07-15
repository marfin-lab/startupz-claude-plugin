#!/usr/bin/env bats

setup() {
  source scripts/lib/fetch-content.sh
}

skip_if_no_network() {
  curl -sf --max-time 3 https://www.google.com >/dev/null 2>&1 || skip "sem rede"
}

@test "content por categoria retorna artigos com content" {
  skip_if_no_network
  result=$(fetch_startupz_content category Funding)
  echo "$result" | jq -e 'type == "array"'
  count=$(echo "$result" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "$result" | jq -e '.[0] | (.title and .slug and .content)'
  fi
}

@test "content por ids retorna o artigo pedido" {
  skip_if_no_network
  id=$(bash scripts/lib/fetch-index.sh | jq -r '.[0].id')
  [ -n "$id" ] && [ "$id" != "null" ] || skip "índice vazio"
  result=$(fetch_startupz_content ids "$id")
  echo "$result" | jq -e 'length >= 1'
  echo "$result" | jq -e '.[0].content'
}

@test "modo invalido retorna []" {
  run fetch_startupz_content bogus x
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "arg vazio retorna []" {
  run fetch_startupz_content ids ""
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "content retorna [] em erro de rede" {
  STARTUPZ_SUPABASE_URL="https://invalid-host-xxx.example" \
    run fetch_startupz_content category Funding
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}
