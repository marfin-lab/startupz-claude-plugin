#!/usr/bin/env bash
# fetch-index.sh — índice leve de artigos publicados do Startupz (Supabase)
# Função:
#   fetch_startupz_index  → JSON array {id,title,excerpt,category,published_at,slug}

set -euo pipefail

: "${STARTUPZ_SUPABASE_URL:=https://vfntyqijlrdlgcponeez.supabase.co}"
: "${STARTUPZ_SUPABASE_ANON_KEY:=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZmbnR5cWlqbHJkbGdjcG9uZWV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUyNTg3NDUsImV4cCI6MjA4MDgzNDc0NX0.zyyjWLAz1yGMBIWllFHl7RfGtDDkg9y5sI_bVpnkj5o}"

fetch_startupz_index() {
  local url="${STARTUPZ_SUPABASE_URL}/rest/v1/articles?select=id,title,excerpt,category,published_at,slug&published=eq.true&order=published_at.desc"

  local response
  response=$(curl -sfL --max-time 10 \
    -H "apikey: ${STARTUPZ_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${STARTUPZ_SUPABASE_ANON_KEY}" \
    "$url" 2>/dev/null) || { echo "[]"; return 0; }

  if echo "$response" | jq empty 2>/dev/null; then
    echo "$response"
  else
    echo "[]"
  fi
}

# ponytail: índice completo sem paginação. OK por anos ao ritmo atual (~200
# artigos hoje). Adicionar filtro/paginação só quando o índice em si estourar
# o contexto (~milhares de artigos).
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fetch_startupz_index "$@"
fi
