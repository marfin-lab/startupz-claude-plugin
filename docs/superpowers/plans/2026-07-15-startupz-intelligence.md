# Startupz Intelligence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Uma skill que ativa no chat e responde perguntas analíticas sobre o ecossistema BR de startups/AI/funding, ancorada nas matérias do Startupz.

**Architecture:** Retrieval em duas passadas, zero infra nova. Dois scripts bash de leitura no Supabase (`fetch-index.sh` = índice leve; `fetch-content.sh` = corpo completo por ids ou categoria) + uma SKILL.md que orquestra: índice → seleção semântica pelo Claude → content dos selecionados → resposta ancorada com citações.

**Tech Stack:** Bash, curl, jq, Supabase PostgREST (read-only, anon key), bats para testes. Skills auto-descobertas em `skills/`.

## Global Constraints

- Contrato dos scripts idêntico ao de `scripts/lib/fetch-startupz.sh`: `set -euo pipefail`, `curl -sfL`, **sempre imprime `[]` em qualquer falha, nunca quebra** (`|| { echo "[]"; return 0; }` + validação `jq empty`).
- Supabase URL/anon key: copiar **verbatim** as duas linhas de defaults de `scripts/lib/fetch-startupz.sh:8-9` (mesmo padrão `: "${VAR:=...}"`). Não inventar chave nova.
- Cada script é **sourceável** (define função) **e executável** (roda a função se chamado direto), via `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then fn "$@"; fi` — a forma `if/fi` garante exit 0 quando sourceado.
- URL pública do artigo: `https://startupz.com.br/artigo/<slug>` (confirmado, retorna 200).
- A skill invoca scripts via `${CLAUDE_PLUGIN_ROOT}` (convenção do plugin — ver `hooks/hooks.json`, `commands/setup.md`).
- Testes: bats, helper `skip_if_no_network`, sem framework novo. Rodar com `bats tests/<arquivo>.bats`.
- Skills são auto-descobertas — **não editar** `.claude-plugin/plugin.json`.
- Tudo em PT-BR.

---

### Task 1: `fetch-index.sh` — índice leve

**Files:**
- Create: `scripts/lib/fetch-index.sh`
- Test: `tests/test-index.bats`

**Interfaces:**
- Produces: `fetch_startupz_index()` — sem args. Imprime JSON array de objetos `{id, title, excerpt, category, published_at, slug}` de artigos publicados, `order=published_at.desc`. `[]` em falha. Também executável direto: `bash scripts/lib/fetch-index.sh`.

- [ ] **Step 1: Escrever o teste que falha**

Create `tests/test-index.bats`:

```bash
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

@test "cada item do índice tem os campos esperados quando há conteúdo" {
  skip_if_no_network
  result=$(fetch_startupz_index)
  count=$(echo "$result" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "$result" | jq -e '.[0] | (.id and .title and .slug and .category and .published_at)'
  fi
}

@test "índice retorna [] em erro de rede" {
  STARTUPZ_SUPABASE_URL="https://invalid-host-xxx.example" \
    run fetch_startupz_index
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "índice é executável direto e imprime JSON array" {
  skip_if_no_network
  result=$(bash scripts/lib/fetch-index.sh)
  echo "$result" | jq -e 'type == "array"'
}
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `bats tests/test-index.bats`
Expected: FAIL — `scripts/lib/fetch-index.sh` não existe (source falha).

- [ ] **Step 3: Implementar o script**

Create `scripts/lib/fetch-index.sh`. **Copie as duas linhas de defaults verbatim de `scripts/lib/fetch-startupz.sh:8-9`** (representadas abaixo como `<COPIAR: linha STARTUPZ_SUPABASE_URL>` e `<COPIAR: linha STARTUPZ_SUPABASE_ANON_KEY>`):

```bash
#!/usr/bin/env bash
# fetch-index.sh — índice leve de artigos publicados do Startupz (Supabase)
# Função:
#   fetch_startupz_index  → JSON array {id,title,excerpt,category,published_at,slug}

set -euo pipefail

<COPIAR: linha STARTUPZ_SUPABASE_URL de fetch-startupz.sh:8>
<COPIAR: linha STARTUPZ_SUPABASE_ANON_KEY de fetch-startupz.sh:9>

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
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `bats tests/test-index.bats`
Expected: PASS (4 testes; podem virar `skip` se sem rede).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/fetch-index.sh tests/test-index.bats
git commit -m "feat: fetch-index.sh — índice leve do acervo Startupz

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DKHA3h5Nnvn6sHa7aS4uLa"
```

---

### Task 2: `fetch-content.sh` — corpo completo por ids ou categoria

**Files:**
- Create: `scripts/lib/fetch-content.sh`
- Test: `tests/test-content.bats`

**Interfaces:**
- Consumes: `bash scripts/lib/fetch-index.sh` (do Task 1) no teste, para obter um id real.
- Produces: `fetch_startupz_content(mode, arg)` — `mode ∈ {ids, category}`. `ids "1,2,3"` → `id=in.(...)`; `category "Funding"` → `category=eq.Funding&published=eq.true`. Imprime JSON array `{title, slug, category, published_at, content}`. `[]` em modo inválido, arg vazio, ou falha. Executável direto: `bash scripts/lib/fetch-content.sh category Funding`.

- [ ] **Step 1: Escrever o teste que falha**

Create `tests/test-content.bats`:

```bash
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

@test "modo inválido retorna []" {
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
```

- [ ] **Step 2: Rodar o teste e ver falhar**

Run: `bats tests/test-content.bats`
Expected: FAIL — `scripts/lib/fetch-content.sh` não existe.

- [ ] **Step 3: Implementar o script**

Create `scripts/lib/fetch-content.sh` (mesma cópia verbatim das linhas de defaults de `fetch-startupz.sh:8-9`):

```bash
#!/usr/bin/env bash
# fetch-content.sh — corpo completo de artigos do Startupz (Supabase)
# Uso:
#   fetch_startupz_content ids <id1,id2,...>   → artigos por id
#   fetch_startupz_content category <nome>     → todos publicados da categoria

set -euo pipefail

<COPIAR: linha STARTUPZ_SUPABASE_URL de fetch-startupz.sh:8>
<COPIAR: linha STARTUPZ_SUPABASE_ANON_KEY de fetch-startupz.sh:9>

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
```

- [ ] **Step 4: Rodar o teste e ver passar**

Run: `bats tests/test-content.bats`
Expected: PASS (5 testes; rede-dependentes viram `skip` sem rede).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/fetch-content.sh tests/test-content.bats
git commit -m "feat: fetch-content.sh — corpo de artigos por ids ou categoria

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DKHA3h5Nnvn6sHa7aS4uLa"
```

---

### Task 3: `SKILL.md` — a skill de inteligência

**Files:**
- Create: `skills/startupz-intelligence/SKILL.md`

**Interfaces:**
- Consumes: `${CLAUDE_PLUGIN_ROOT}/scripts/lib/fetch-index.sh` (Task 1) e `${CLAUDE_PLUGIN_ROOT}/scripts/lib/fetch-content.sh` (Task 2).
- Produces: skill auto-descoberta que ativa em perguntas analíticas no chat.

- [ ] **Step 1: Criar o SKILL.md**

Create `skills/startupz-intelligence/SKILL.md`:

```markdown
---
name: startupz-intelligence
description: Responde perguntas analíticas sobre o ecossistema BR de startups, VCs, funding e AI a partir do acervo de matérias do Startupz. Use quando o usuário perguntar no chat sobre padrões de investimento, quais VCs/investidores mais aparecem, que setores/tipos de startup mais recebem funding, tendências do ecossistema, ou o que o Startupz publicou sobre um tema. NÃO use para gerar o briefing diário (isso é /startupz:morning).
---

# Startupz Intelligence

Você responde perguntas analíticas sobre o ecossistema brasileiro de startups, AI
e funding usando **exclusivamente** o acervo de matérias do Startupz (tabela
`articles` no Supabase). Você é a voz editorial do Startupz — nunca se refira a
IA, modelo, Anthropic ou ferramentas.

## Procedimento (retrieval em duas passadas)

1. **Puxe o índice leve** de todos os artigos publicados:

       bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib/fetch-index.sh"

   Retorna JSON array com `id, title, excerpt, category, published_at, slug`.

2. **Selecione os artigos relevantes** pra pergunta, lendo título/excerpt/categoria:
   - Pergunta pontual/semântica ("o que o Startupz falou sobre X?") → escolha
     ~10-20 artigos mais relevantes e anote os `id`.
   - Pergunta agregada (contagem/ranking: "quais VCs mais aparecem?", "que setor
     mais recebe investimento?") → identifique a(s) categoria(s) relevante(s)
     (ex: `Funding`) e puxe a categoria inteira.

3. **Puxe o content completo** só dos selecionados:

       bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib/fetch-content.sh" ids 1,2,3
       # ou, para agregações:
       bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib/fetch-content.sh" category Funding

   Retorna `title, slug, category, published_at, content`.

4. **Responda em PT-BR, ancorado nos artigos lidos.**

## Regras (não-negociáveis)

- **Ancore estritamente no acervo.** Nunca apresente conhecimento externo como se
  viesse das matérias. Sem inventar números, VCs, valores ou datas.
- **Sempre cite as matérias usadas:** título + link
  `https://startupz.com.br/artigo/<slug>`.
- **Se o acervo não cobre a pergunta, diga "não temos matéria sobre isso"** e, se
  útil, o que existe de mais próximo. Precisão > cobertura.
- Para rankings/contagens, mostre a base: "em N matérias de Funding, o fundo X
  aparece em K rounds". Não extrapole além do que os artigos dizem.
- Tom direto, founder-to-founder. Sem clichês de newsletter, sem emojis no corpo.

<!-- ponytail: teto conhecido — agregação por contagem exata varre a categoria
     inteira e só escala enquanto o content couber no contexto (~200 artigos hoje
     OK; ~2000+ não). Upgrade path: pipeline de extração → base estruturada
     (Fase 2 do spec 2026-07-15-startupz-intelligence-design.md). Não construir
     agora. -->
```

- [ ] **Step 2: Verificar que os paths referenciados existem**

Run:
```bash
test -f scripts/lib/fetch-index.sh && \
test -f scripts/lib/fetch-content.sh && \
grep -q 'fetch-index.sh' skills/startupz-intelligence/SKILL.md && \
grep -q 'fetch-content.sh' skills/startupz-intelligence/SKILL.md && \
echo OK
```
Expected: `OK`

- [ ] **Step 3: Confirmar que o manifest do plugin segue válido**

Run: `bats tests/test-manifest.bats`
Expected: PASS (a nova skill é auto-descoberta; nada em `plugin.json` muda).

- [ ] **Step 4: Rodar a suíte inteira**

Run: `bats tests/`
Expected: todos PASS (rede-dependentes podem `skip`).

- [ ] **Step 5: Smoke manual da skill (ponta a ponta)**

Numa sessão do Claude Code com o plugin instalado, pergunte:
> "quais VCs mais aparecem investindo segundo o Startupz?"

Verifique que a skill: (a) roda `fetch-index.sh`, (b) puxa `content` da categoria
Funding, (c) responde com ranking ancorado e links `startupz.com.br/artigo/<slug>`,
(d) não inventa dados fora do acervo.

- [ ] **Step 6: Commit**

```bash
git add skills/startupz-intelligence/SKILL.md
git commit -m "feat: skill startupz-intelligence — Q&A ancorado no acervo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DKHA3h5Nnvn6sHa7aS4uLa"
```

---

### Task 4: Documentar no README

**Files:**
- Modify: `README.md` (seção "Comandos" e/ou nova seção "Inteligência")

**Interfaces:**
- Consumes: a skill do Task 3.

- [ ] **Step 1: Adicionar seção no README**

Após a tabela de comandos em `README.md`, adicione:

```markdown
## Inteligência sobre o acervo

Pergunte no chat sobre o ecossistema e o Startupz responde a partir das matérias
publicadas — sem comando, a skill ativa sozinha:

- "quais VCs mais aparecem investindo?"
- "que tipo de startup mais recebe investimento?"
- "o que o Startupz publicou sobre fintech B2B?"

Respostas são ancoradas nas matérias (com link) e admitem quando o acervo não
cobre o tema. Cobertura cresce conforme novas matérias são publicadas.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README — seção de inteligência sobre o acervo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01DKHA3h5Nnvn6sHa7aS4uLa"
```

---

## Notas de execução

- Tasks 1 e 2 são independentes entre si na implementação, mas o **teste** do
  Task 2 usa `fetch-index.sh` — implemente na ordem 1 → 2.
- Task 3 depende de 1 e 2 (a skill os invoca). Task 4 depende de 3.
- Nenhuma dependência nova instalada. `jq` e `bats` já são pré-requisitos do repo.
