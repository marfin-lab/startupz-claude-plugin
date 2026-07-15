#!/usr/bin/env bash
# fetch-content.sh — corpo completo de artigos do Startupz (Supabase)
# Uso:
#   fetch_startupz_content ids <id1,id2,...>   → artigos por id
#   fetch_startupz_content category <nome>     → todos publicados da categoria

set -euo pipefail

: "${STARTUPZ_SUPABASE_URL:=https://vfntyqijlrdlgcponeez.supabase.co}"
: "${STARTUPZ_SUPABASE_ANON_KEY:=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZmbnR5cWlqbHJkbGdjcG9uZWV6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjUyNTg3NDUsImV4cCI6MjA4MDgzNDc0NX0.zyyjWLAz1yGMBIWllFHl7RfGtDDkg9y5sI_bVpnkj5o}"

fetch_startupz_content() {
  local mode="${1:-}" arg="${2:-}"
  local filter

  case "$mode" in
    ids)
      [[ -n "$arg" ]] || { echo "[]"; return 0; }
      filter="id=in.(${arg})"
      ;;
    category)
      [[ -n "$arg" ]] || { echo "[]"; return 0; }
      # ponytail: sem url-encode. Categorias hoje são palavra única
      # (Funding, Startups, Tech, Economia, Unicorns, AI). Se surgir categoria
      # com espaço, encodar o valor antes do eq.
      filter="category=eq.${arg}&published=eq.true"
      ;;
    *)
      echo "[]"; return 0 ;;
  esac

  local url="${STARTUPZ_SUPABASE_URL}/rest/v1/articles?select=title,slug,category,published_at,content&${filter}&order=published_at.desc"

  local response
  response=$(curl -sfL --max-time 15 \
    -H "apikey: ${STARTUPZ_SUPABASE_ANON_KEY}" \
    -H "Authorization: Bearer ${STARTUPZ_SUPABASE_ANON_KEY}" \
    "$url" 2>/dev/null) || { echo "[]"; return 0; }

  if echo "$response" | jq empty 2>/dev/null; then
    echo "$response"
  else
    echo "[]"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  fetch_startupz_content "$@"
fi
