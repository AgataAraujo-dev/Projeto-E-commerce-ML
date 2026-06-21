## Checklist: 3 conferências antes de qualquer ALTER TABLE

**Contexto:** ao alterar `order_items` (SCRUM-184), descobrimos que existiam
**11 views dependentes** da tabela — não só a `v_outliers_order_items` que
estava documentada. Algumas usavam apenas `order_id` ou `COUNT(*)` (não
seriam bloqueadas pelo Postgres); outras usavam diretamente as colunas que
íamos alterar (`price`, `freight_value`, `order_item_id`) e *seriam*
bloqueadas. Sem checar isso antes, o risco era dropar views à toa, esquecer
de recriar alguma, ou ser surpreendida por um erro no meio da execução.

A partir disso, este é o checklist fixo a rodar **antes de qualquer
`ALTER TABLE` em produção**, não só para `order_items`.

---

### Passo 1 — Confirmar o tipo atual da(s) coluna(s)

Objetivo: ter certeza do que está no banco agora, sem confiar de memória ou
no que está escrito numa planilha/documento (que pode estar desatualizado).

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name = 'nome_da_tabela'
  AND column_name IN ('coluna1', 'coluna2', 'coluna3');
```

✅ Resultado esperado: os tipos batem com o que você espera alterar (ex:
`bigint` → vai virar `integer`, `double precision` → vai virar `float`).
Se não bater, pare e investigue antes de seguir — pode ser que a alteração
já tenha sido feita, ou que o tipo real seja diferente do documentado.

---

### Passo 2 — Mapear TODAS as views que dependem da tabela

Objetivo: não confiar apenas na documentação anterior (que pode listar só
uma dependência conhecida) — checar direto no banco quais views existem
de verdade.

```sql
SELECT viewname, definition
FROM pg_views
WHERE definition LIKE '%nome_da_tabela%'
  AND schemaname = 'silver';
```

⚠️ Atenção ao interpretar o resultado: nem toda view que aparece aqui vai
ser bloqueada pelo `ALTER TABLE`. O Postgres só bloqueia se a view usa
**diretamente** a(s) coluna(s) que está(ão) mudando de tipo. Para cada view
retornada, leia a `definition` e pergunte:

- Essa view usa a coluna que vou alterar (ex: `price`, `freight_value`)
  em algum cálculo, filtro ou seleção direta?
- Ou ela só usa `order_id`, `COUNT(*)`, ou outras colunas que não mudam?

Monte uma lista simples tipo:

| View | Usa a coluna que vou alterar? |
|---|---|
| `view_x` | ✅ Sim — vai precisar ser recriada |
| `view_y` | ❌ Não — só usa `order_id` |

---

### Passo 2.5 — Salvar um snapshot de referência ANTES de alterar

**Por que esse passo existe:** ao validar `order_items` depois do `ALTER`,
percebemos que conseguíamos confirmar que os dados *pareciam* coerentes
(sem nulos, valores plausíveis), mas não tínhamos como confirmar que eram
**exatamente os mesmos de antes** — porque não guardamos nenhum número de
referência antes de alterar. "Parece certo" não é o mesmo que "está
confirmadamente igual a antes".

Antes de rodar qualquer `ALTER TABLE`, salvar (em texto, print ou arquivo)
o resultado de uma query agregada simples na(s) coluna(s) que vão mudar:

```sql
SELECT 
  COUNT(*) AS total_linhas,
  SUM(coluna_numerica) AS soma_coluna,
  AVG(coluna_numerica) AS media_coluna,
  COUNT(*) FILTER (WHERE coluna_numerica IS NULL) AS nulos
FROM silver.nome_da_tabela;
```

Depois do `ALTER`, rodar a mesma query de novo e comparar:

- `total_linhas` deve ser **idêntico** — se mudou, alguma linha foi perdida.
- `soma_coluna` e `media_coluna` devem ser os mesmos (ou só com diferença de
  arredondamento esperada, ex: float → integer com `ROUND`).
- `nulos` deve continuar igual (idealmente 0) — se aumentou, a conversão de
  tipo "perdeu" algum valor no meio do caminho.

**Quando pular este passo:** só se a tabela for muito pequena e for possível
olhar 100% das linhas a olho nu — o que raramente é o caso em produção.

---

### Passo 3 — Conferir a definição REAL da view, direto do banco

Objetivo: nunca recriar uma view "de memória" ou só com base em documentação
antiga — sempre puxar a versão exata que está rodando agora, **antes** de
dropar.

```sql
SELECT pg_get_viewdef('silver.nome_da_view', true);
```

Compare o resultado com o que está documentado (ex: no `CONTEXTO_PROJETO.md`
ou em commits anteriores). Pequenas diferenças de formatação (parênteses
extras, `::tipo` explícito em mais lugares) são normais — é o Postgres
reescrevendo o SQL no seu próprio estilo interno, não muda o comportamento.
Mas se a **lógica** for diferente (cálculo diferente, filtro diferente,
colunas diferentes), pare e investigue antes de prosseguir — a versão real
do banco é a que vale, não a documentação.

---

### Depois dos 3 passos — ordem segura de execução

Só depois de confirmar os pontos acima:

1. Salvar o snapshot de referência da tabela (Passo 2.5)
2. Salvar a definição de cada view que será impactada (Passo 3, já feito)
3. `DROP VIEW` apenas das views que realmente usam a coluna (identificadas
   no Passo 2)
4. `ALTER TABLE` com `USING` se for conversão que perde precisão (ex:
   float → integer)
5. `CREATE VIEW` recriando cada view dropada, com a definição salva
6. Rodar o snapshot de novo e comparar com o do Passo 1 (total de linhas,
   soma, nulos) — esse é o teste que confirma que nada foi perdido, não só
   que "parece certo"

**Alternativa mais conservadora quando há muitas views suspeitas:** rodar o
`ALTER TABLE` primeiro (sem dropar nada) e deixar o Postgres recusar e
apontar exatamente qual view está bloqueando. Isso evita dropar views que
não precisavam ser tocadas — você só recria o que o próprio banco confirma
que precisa.

---

### Quando usar este checklist

Sempre que for rodar `ALTER TABLE ... TYPE ...` em qualquer tabela do schema
`silver` (ou `gold`), especialmente em produção (branch `main`). Vale também
ao revisar SQL antigo/documentado antes de executar — documentação pode
ficar desatualizada se alguém criar uma view nova depois que o SQL foi
escrito.
