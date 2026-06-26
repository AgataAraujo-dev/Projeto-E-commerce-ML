# Cartão de Contexto — Projeto ML Olist
> Cole este arquivo no início de cada nova conversa para retomar o projeto.

---

## Quem sou eu
Analista de projetos em transição de carreira para Engenheira de Dados com foco em IA.  
Iniciante em Python/SQL, sei o básico de GitHub.  
Dias bons para o projeto: **terça e quarta**. Reuniões do time: **quintas**.  
Prefiro respostas em português, tom de parceria, explicações conectadas ao projeto real.

---

## O projeto
**Nome:** Olist ML E-commerce  
**Objetivo:** Identificar clientes VIP em risco de abandono (churn) usando K-Means + RFM  
**Dataset:** Olist Brazilian E-commerce — 100k pedidos (2016–2018), Kaggle  
**Entrega final:** Modelo `.pkl` + Dashboard Streamlit  
**Prazo:** Julho/10  

---

## Stack tecnológica
- **IDE:** VS Code + extensão Supabase
- **Banco:** Supabase (PostgreSQL) — schema `silver` (limpeza) e `gold` (ML)
- **Versionamento:** GitHub
- **Linguagem:** Python (pandas, scikit-learn, matplotlib)
- **Gestão:** Jira (Scrum, sprints de 2 semanas)
- **Entrega:** Streamlit

---

## Repositórios
- **Fork do time:** `https://github.com/AgataAraujo-dev/Projeto-E-commerce-ML` (clonado em `Projetos/ML/Projeto-E-commerce-ML`)
- **Caderno pessoal:** `https://github.com/AgataAraujo-dev/olist-ml-aprendizado` (clonado em `Projetos/ML/olist-ml-aprendizado`)

---

## Ambiente local configurado ✅
- Python 3.13 instalado
- venv criada e ativada em `Projeto-E-commerce-ML`
- `pip install -r requirements.txt` executado
- `python-dotenv` e `supabase` instalados (faltam no requirements.txt — avisar Veronica)
- `.env` com `SUPABASE_URL` e `SUPABASE_KEY` configurado
- `.gitignore` protegendo o `.env`
- Conexão com Supabase testada — funciona no schema `silver`

---

## Time
- **Gestão repo/Jira:** Veronica Carneiro (tech lead) e Carla
- **Tabelas silver:** Fernanda (customers), Isabella (items), Anna Beatriz (payments), Luna (reviews)
- **Time Negócios:** Marina, Jackie, Zenith, Michele, Thais

---

## Estado atual do projeto — Junho 2026
**Fase CRISP-DM:** Data Preparation (fase 3)  
**Sprint:** 3/4  

**Tabelas no schema silver:**
- `order_customers` ✅
- `order_items` ✅
- `order_payments_silver_tratada` ✅
- `order_reviews` ✅
- `orders_dataset_silver` ✅
- `products_silver_tratada` ✅
- `tabela_analitica_vendas` ✅
- + várias views (`v_outliers_order_items`, `view_horarios_consumo`, etc.)

---

## Minhas tasks no Jira

**SCRUM-184 — Transformação tipos de dados** → Status: Em andamento  
Alterar tipos de dados das colunas conforme aba "Total de Colunas" da planilha do time.  
Planilha: `https://docs.google.com/spreadsheets/d/1zKztY2oD7UvBOtkGdS9GlUi7lg-3GTUqW2jrDgzbqlw`

**O que já foi feito:**
- `order_reviews`: `created_at` e `updated_at` → `timestamp without time zone` ✅

**O que falta executar (SQL pronto, aguardando ok da Veronica — estamos na MAIN/PRODUCTION):**

```sql
-- order_items (tem dependência: v_outliers_order_items)
DROP VIEW silver.v_outliers_order_items;
ALTER TABLE silver.order_items
  ALTER COLUMN order_item_id TYPE float,
  ALTER COLUMN price TYPE float,
  ALTER COLUMN freight_value TYPE float;
CREATE VIEW silver.v_outliers_order_items AS
WITH estatisticas AS (
  SELECT 
    percentile_cont(0.25) WITHIN GROUP (ORDER BY price) AS q1_p,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY price) AS q3_p,
    percentile_cont(0.25) WITHIN GROUP (ORDER BY freight_value) AS q1_f,
    percentile_cont(0.75) WITHIN GROUP (ORDER BY freight_value) AS q3_f
  FROM silver.order_items
),
limites AS (
  SELECT q1_p, q3_p,
    q3_p + 1.5 * (q3_p - q1_p) AS lim_sup_p,
    q1_p - 1.5 * (q3_p - q1_p) AS lim_inf_p,
    q3_f + 1.5 * (q3_f - q1_f) AS lim_sup_f,
    q1_f - 1.5 * (q3_f - q1_f) AS lim_inf_f
  FROM estatisticas
)
SELECT 
  i.order_id, i.order_item_id, i.product_id, i.seller_id,
  i.shipping_limit_date, i.price, i.freight_value,
  CASE
    WHEN i.price > l.lim_sup_p THEN 'Preço Acima do Limite'
    WHEN i.price < l.lim_inf_p THEN 'Preço Abaixo do Limite'
    WHEN i.freight_value > l.lim_sup_f THEN 'Frete Acima do Limite'
    WHEN i.freight_value < l.lim_inf_f THEN 'Frete Abaixo do Limite'
    ELSE NULL
  END AS motivo_outlier,
  l.lim_sup_p AS teto_preco,
  l.lim_sup_f AS teto_frete
FROM silver.order_items i
CROSS JOIN limites l
WHERE 
  i.price > l.lim_sup_p OR i.price < l.lim_inf_p OR
  i.freight_value > l.lim_sup_f OR i.freight_value < l.lim_inf_f;
```

**Tabelas restantes ainda sem SQL (fazer na próxima sessão):**
- `order_payments_silver_tratada`: `payment_sequential` e `payment_installments` → `integer`
- `products_silver_tratada`: 6 colunas → `float`
- `tabela_analitica_vendas`: 3 colunas → `float`, 2 colunas → `integer`
- Views: verificar se têm dependências antes de alterar

**SCRUM-131** — ver detalhes na próxima sessão

---

## O que já estudamos juntas
- **Terça 1 ✅:** CRISP-DM, Scrum, Jira — `glossario.md` gerado e commitado
- **Quarta 1 ✅:** Arquitetura Medallion, setup do ambiente, conexão Supabase, primeira task SQL

**Próximas sessões:**
- Terça 2: SQL — JOIN e GROUP BY com dados reais da Olist
- Quarta 2: ML — RFM, K-Means, Silhouette Score

---

## Pendências para resolver
- [ ] Avisar Veronica: `python-dotenv` e `supabase` faltam no `requirements.txt`
- [ ] Pedir ok da Veronica antes de rodar SQL em produção (MAIN)
- [ ] Verificar SCRUM-131
- [ ] Atualizar `CONTEXTO_PROJETO.md` no repo após cada sessão

---

## Regras da nossa parceria
- Sempre explico o conceito conectado ao projeto real
- Cada sessão gera pelo menos um arquivo para commitar
- Fins de semana só se a semana travar
- Terminal é PowerShell — comandos one-line ou separados

---

*Atualizada em: Junho 2026 — Sprint 3/4, fase Data Preparation*
