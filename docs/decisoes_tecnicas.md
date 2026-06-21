# Decisões Técnicas — Projeto Olist ML E-commerce

## Contexto

Este documento registra decisões técnicas tomadas durante o desenvolvimento do projeto Olist ML E-commerce.

Objetivo:
Identificar clientes VIP em risco de abandono utilizando análise RFM e K-Means.

Arquitetura:

Raw → Silver → Gold → Machine Learning → Streamlit

---

# 1. Padronização de tipos de dados (SCRUM-184)

## Objetivo

Realizar a transformação dos tipos de dados das tabelas do schema silver conforme definição da aba "Total de Colunas".

As alterações foram realizadas utilizando SQL Editor no Supabase.

---

# 2. Critério para definição dos tipos

## Identificadores

Colunas utilizadas apenas para identificação permaneceram como texto.

Exemplos:

- order_id
- product_id
- customer_id

Motivo:

Identificadores não possuem significado matemático e não devem ser utilizados como métricas em modelos de Machine Learning.

---

## Variáveis categóricas

Colunas que representam categorias permanecem como texto.

Exemplo:

- product_category_name

Motivo:

Representam grupos/classes e serão tratadas futuramente como variáveis categóricas.

---

## Contagens

Colunas que representam quantidade foram transformadas para integer.

Exemplos:

- payment_sequential
- payment_installments

Motivo:

São valores discretos sem casas decimais.

---

## Métricas

Colunas relacionadas a valores, pesos e dimensões foram transformadas para float.

No PostgreSQL o tipo é representado como double precision.

Exemplos:

- price
- freight_value
- product_weight_g

Motivo:

São medidas utilizadas em análises estatísticas e modelos de Machine Learning.

---

# 3. Sobre double precision

No PostgreSQL, float é armazenado como double precision.

Características:

- ponto flutuante
- 64 bits
- compatível com float64 do pandas

No Python:

PostgreSQL:
double precision

Pandas:
float64

Esse formato é adequado para análises e ML.

---

# 4. Dependências identificadas

Algumas tabelas possuem views dependentes.

Exemplo:

tabela_analitica_vendas

Possui dependência:

silver.view_sazonalidade_vendas

O PostgreSQL bloqueia alterações de tipo quando uma view depende da coluna.

A alteração será realizada após validação e recriação da view.

---

# 5. Governança

Alterações estruturais devem seguir:

1. Validar dependências
2. Executar alteração
3. Validar resultado
4. Registrar no Git

O histórico das mudanças é mantido no repositório para rastreabilidade.

---

# 6. Aprendizados

Alterações em banco de dados não afetam apenas tabelas.

Views, consultas e modelos dependem da estrutura existente.

Antes de alterar schemas é necessário mapear dependências.

## Consultar múltiplas tabelas em uma única query (WHERE com OR + parênteses)

**Contexto:** Precisávamos confirmar o `data_type` de colunas em duas tabelas
diferentes (`order_payments_silver_tratada` e `order_reviews`) de uma vez,
sem rodar duas queries separadas.

**Como funciona:**

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE
  (table_name = 'order_payments_silver_tratada' AND column_name IN ('payment_sequential', 'payment_installments'))
  OR
  (table_name = 'order_reviews' AND column_name IN ('created_at', 'updated_at'))
ORDER BY table_name, column_name;
```

**Aprendizado:**
- `information_schema.columns` é uma tabela de metadados nativa do Postgres —
  guarda informação sobre todas as colunas do banco (não precisa criar).
- Para combinar condições de tabelas diferentes numa única query, cada
  "bloco" de condição (tabela + colunas que eu quero) fica entre parênteses,
  ligado por `OR`. Os parênteses são essenciais: sem eles, o `AND` interno
  pode se misturar com o `OR` externo e mudar o resultado (regra de
  precedência: `AND` "amarra" mais forte que `OR`).
- `IN ('valor1', 'valor2')` é um atalho para `coluna = 'valor1' OR coluna = 'valor2'`
  — mais legível quando há vários valores possíveis.
- `ORDER BY table_name, column_name` não muda o resultado, só a ordem de
  exibição — útil pra comparar tabelas diferentes lado a lado na tela.

**Quando reusar:** sempre que precisar checar/filtrar colunas (ou outros
dados) de mais de uma tabela numa query só, em vez de rodar uma query por
tabela.

## FLOAT vira "double precision" no Postgres — isso é normal

**Contexto:** Ao converter colunas de `products_silver_tratada` de `bigint`
para `float` (depois revertido para `integer`, ver decisão acima), o Postgres
mostrava o tipo da coluna como `double precision`, e não como `float`. Parecia
que o `ALTER` tinha rodado errado, mas não era o caso.

**Aprendizado:**
- No PostgreSQL, `FLOAT` não é um tipo "de verdade" — é um *alias* (apelido)
  para outro tipo. Quando escrevemos `TYPE float` sem especificar precisão,
  o Postgres internamente traduz isso para `double precision`.
- Ou seja: `ALTER COLUMN x TYPE float` e `ALTER COLUMN x TYPE double precision`
  fazem exatamente a mesma coisa — só muda o nome usado na hora de escrever o SQL.
- A regra do guia de boas práticas do projeto ("usar FLOAT, evitar DOUBLE
  PRECISION") se aplica a **como escrevemos o SQL** (legibilidade e padronização
  entre o time), não ao que aparece depois numa consulta de metadados
  (`information_schema.columns`) — isso sempre vai mostrar `double precision`,
  não tem como evitar.
- Só existiria diferença real se alguém escrevesse `FLOAT(1)` até `FLOAT(24)`
  (com precisão especificada) — nesse caso o Postgres usa `real` em vez de
  `double precision`. Sem precisão especificada, é sempre `double precision`.

**Como confirmar se uma conversão para FLOAT funcionou certo:**

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'silver'
  AND table_name = 'nome_da_tabela'
  AND column_name IN ('coluna1', 'coluna2');
```

Se `data_type` aparecer como `double precision`, está correto — desde que o
`ALTER COLUMN` original tenha usado `TYPE float` (e não `TYPE numeric` ou
outro tipo por engano).

**Quando lembrar disso:** toda vez que uma coluna convertida para `FLOAT`
aparecer como `double precision` numa consulta — não é erro, é o
comportamento esperado do Postgres.

