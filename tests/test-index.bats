#!/usr/bin/env bats

setup() {
  source scripts/lib/fetch-index.sh
}

skip_if_no_network() {
  curl -sf --max-time 3 https://www.google.com >/dev/null 2>&1 || skip "sem rede"
}

@test "fetch_startupz_index retorna JSON array" {
  skip_if_no_network
  result=$(fetch_startupz_index)
  echo "$result" | jq empty
  echo "$result" | jq -e 'type == "array"'
}

@test "cada item do indice tem os campos esperados quando ha conteudo" {
  skip_if_no_network
  result=$(fetch_startupz_index)
  count=$(echo "$result" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "$result" | jq -e '.[0] | (.id and .title and .slug and .category and .published_at)'
  fi
}

@test "indice retorna [] em erro de rede" {
  STARTUPZ_SUPABASE_URL="https://invalid-host-xxx.example" \
    run fetch_startupz_index
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "indice executavel direto imprime JSON array" {
  skip_if_no_network
  result=$(bash scripts/lib/fetch-index.sh)
  echo "$result" | jq -e 'type == "array"'
}
