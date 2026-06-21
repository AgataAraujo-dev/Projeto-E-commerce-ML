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