# Startupz Intelligence — Q&A sobre o acervo

**Data:** 2026-07-15
**Status:** Aprovado, pronto pra plano de implementação

## Problema

O plugin gera um briefing diário a partir da tabela `articles` do Supabase, mas
não permite consultar o acervo. O usuário quer perguntar no chat coisas como
"quais VCs mais aparecem investindo?" ou "que setor mais recebe investimento?" e
transformar o Startupz numa ferramenta de inteligência sobre o ecossistema BR de
startups, AI e funding.

## Decisão de escopo

Fase 1 (este spec): **Q&A on-the-fly** sobre os artigos existentes. Zero
infraestrutura nova — a base já existe (campo `content` da tabela `articles`); o
Claude vira o motor de consulta.

Fase 2 (adiada, fora deste spec): pipeline de extração de entidades → base
estruturada para agregações exatas em todo o histórico. Só se justifica quando o
corpus não couber mais no contexto (ver Limitações).

## Dados disponíveis

Tabela `articles` no Supabase (read-only via anon key já usada por
`fetch-startupz.sh`):
- `id, title, slug, excerpt, category, published_at, author_name, content, published, featured`
- `content` = corpo completo do artigo (~2600 chars/artigo no exemplo).
- Acervo atual: 206 artigos publicados (71 Funding, 64 Startups, 31 Tech,
  31 Economia, 7 Unicorns, 2 AI). Cresce alguns por dia.

## Arquitetura — duas passadas

```
Pergunta analítica no chat sobre o ecossistema
   ↓
[1] skill ativa → fetch-index.sh
       índice leve de TODOS os publicados
       (id, title, excerpt, category, published_at, slug)  ~15k tokens hoje
   ↓
[2] Claude seleciona os artigos relevantes pra pergunta (julgamento semântico)
   ↓
[3] fetch-content.sh <ids | categoria>
       content completo só dos selecionados
   ↓
[4] Claude responde em PT-BR, ancorado nos artigos, com citações + links
       se o acervo não cobre → admite a lacuna, não inventa
```

Por que duas passadas: 206 artigos com `content` ≈ 140k tokens — muito pra ler de
uma vez e cresce. O índice (título+excerpt+categoria) fica pequeno por anos e
permite o Claude escolher só o que importa antes de puxar texto completo.

## Componentes

| Peça | Responsabilidade | Depende de |
|---|---|---|
| `skills/startupz-intelligence/SKILL.md` | QUANDO ativa + passo-a-passo (índice → seleção → content → resposta ancorada) | os 2 scripts |
| `scripts/lib/fetch-index.sh` | 1 curl: índice leve de publicados, `order=published_at.desc` | Supabase (URL/key de `fetch-startupz.sh`) |
| `scripts/lib/fetch-content.sh` | 1 curl: `content` completo por lista de ids **ou** por categoria | mesmo Supabase |

Ambos os scripts reusam `STARTUPZ_SUPABASE_URL` / `STARTUPZ_SUPABASE_ANON_KEY`
(mesmos defaults de `fetch-startupz.sh`). Só leitura, sem escrita.

### fetch-index.sh
- Sem argumentos.
- `select=id,title,excerpt,category,published_at,slug&published=eq.true&order=published_at.desc`
- Retorna JSON array (ou `[]` em falha, como `fetch-startupz.sh`).

### fetch-content.sh
- Aceita `ids <id1,id2,...>` OU `category <nome>`.
- ids: `id=in.(...)`; category: `category=eq.<nome>&published=eq.true`.
- `select=title,slug,category,published_at,content`.
- Retorna JSON array (ou `[]` em falha).

## Comportamento da skill (SKILL.md)

Ativa quando o usuário faz uma pergunta **analítica sobre o ecossistema BR de
startups / AI / funding** no chat (ex: "quais VCs mais aparecem?", "que tipo de
startup mais recebe investimento?", "o que o Startupz falou sobre X?"). NÃO ativa
pra pedidos de briefing (isso é `/startupz:morning`).

Regras de resposta (não-negociáveis):
- Ancorar **estritamente** nos artigos lidos. Nada de conhecimento externo
  apresentado como se fosse do acervo.
- Sempre citar as matérias usadas (título + link `https://startupz.com.br/<slug>`
  — confirmar o padrão de URL na implementação).
- Se o acervo não cobre a pergunta, dizer "não temos matéria sobre isso" em vez
  de inventar. Precisão > cobertura.
- Responder em PT-BR.

Estratégia de seleção:
- Pergunta pontual/semântica → escolher ~10-20 artigos pelo índice, puxar por ids.
- Pergunta agregada (contagem/ranking) → puxar `content` da categoria inteira
  relevante (ex: `category Funding`) e agregar na leitura.

## Limitações e caminho de upgrade

`ponytail:` teto conhecido — perguntas que exigem contagem exata varrendo *todo*
o histórico escalam só até o corpus caber no contexto (hoje ~206 artigos OK;
~2000+ não). Upgrade path = Fase 2 (extração → base estruturada). Marcar esse
teto num comentário no SKILL.md. Não construir a Fase 2 agora (YAGNI).

Outras:
- Índice completo sem paginação. OK por anos ao ritmo atual; adicionar filtro/
  paginação só quando o índice em si estourar o contexto.
- Precisão de agregação depende de o texto do artigo nomear VC/valor/setor
  explicitamente. Sem NER; é leitura direta do Claude.

## Testes

- `fetch-index.sh` retorna JSON não-vazio com as colunas esperadas (smoke contra
  Supabase real ou fixture).
- `fetch-content.sh ids <id>` e `fetch-content.sh category Funding` retornam
  `content`.
- Ambos retornam `[]` sem quebrar quando o curl falha (mesmo contrato de
  `fetch-startupz.sh`).
- Nada de framework novo — bats, alinhado aos testes existentes.

## Fora de escopo

- Fase 2 (extração/base estruturada).
- Escrita no Supabase.
- Comando explícito `/startupz:ask` (a skill no chat é a interface escolhida).
- Embeddings / vector search.
