-- SCRUM-184 — Transformação tipos de dados
-- 6 views: bigint → integer (colunas de contagem)
-- Executado em: Junho 2026
-- Nenhuma tinha view dependente "por cima" (confirmado via pg_views antes de alterar)
-- 3 delas (view_horarios_consumo, view_impacto_atraso_cancelamento,
-- view_sazonalidade_vendas) dependem de silver.vw_analise_vendas
-- Validado: todas recriadas com sucesso, dados coerentes, tipos = integer

DROP VIEW silver.view_horarios_consumo;
DROP VIEW silver.view_impacto_atraso_cancelamento;
DROP VIEW silver.view_sazonalidade_vendas;
DROP VIEW silver.vw_clientes_recorrentes;
DROP VIEW silver.vw_distribuicao_itens_pedido;
DROP VIEW silver.vw_multiplos_itens_pedido;

CREATE VIEW silver.view_horarios_consumo AS
SELECT EXTRACT(hour FROM data_compra) AS hora_do_dia,
  uf_cliente AS estado_cliente,
  COUNT(id_pedido)::integer AS quantidade_pedidos
FROM silver.vw_analise_vendas
GROUP BY EXTRACT(hour FROM data_compra), uf_cliente
ORDER BY COUNT(id_pedido) DESC;

CREATE VIEW silver.view_impacto_atraso_cancelamento AS
SELECT status_pedido,
  CASE
    WHEN dias_atraso > 0 THEN 'Com Atraso'
    WHEN dias_entrega_real IS NOT NULL THEN 'No Prazo'
    ELSE 'Sem informação de entrega / Retido'
  END AS situacao_logistica,
  COUNT(id_pedido)::integer AS total_pedidos
FROM silver.vw_analise_vendas
GROUP BY status_pedido,
  CASE
    WHEN dias_atraso > 0 THEN 'Com Atraso'
    WHEN dias_entrega_real IS NOT NULL THEN 'No Prazo'
    ELSE 'Sem informação de entrega / Retido'
  END;

CREATE VIEW silver.view_sazonalidade_vendas AS
SELECT to_char(data_compra, 'YYYY-MM') AS ano_mes,
  COUNT(DISTINCT id_pedido)::integer AS total_pedidos,
  SUM(faturamento_produtos)::float AS faturamento_estimado
FROM silver.vw_analise_vendas
GROUP BY to_char(data_compra, 'YYYY-MM')
ORDER BY to_char(data_compra, 'YYYY-MM');

CREATE VIEW silver.vw_clientes_recorrentes AS
WITH base AS (
  SELECT oc.customer_unique_id,
    oc.customer_city,
    oc.customer_state,
    o.order_id,
    o.data_compra,
    o.status_pedido,
    op.payment_value,
    op.payment_type
  FROM silver.order_customers oc
    JOIN silver.orders_dataset_silver o ON oc.customer_id::text = o.customer_id
    JOIN silver.order_payments_silver_tratada op ON o.order_id = op.order_id
  WHERE o.status_pedido = 'delivered'
),
agregado AS (
  SELECT base.customer_unique_id,
    base.customer_city,
    base.customer_state,
    COUNT(DISTINCT base.order_id)::integer AS total_pedidos,
    SUM(base.payment_value) AS gasto_total,
    AVG(base.payment_value) AS ticket_medio,
    MIN(base.data_compra) AS primeira_compra,
    MAX(base.data_compra) AS ultima_compra,
    EXTRACT(day FROM (MAX(base.data_compra) - MIN(base.data_compra))) AS dias_como_cliente
  FROM base
  GROUP BY base.customer_unique_id, base.customer_city, base.customer_state
  HAVING COUNT(DISTINCT base.order_id) > 1
)
SELECT customer_unique_id,
  customer_city,
  customer_state,
  total_pedidos,
  round(gasto_total::numeric, 2) AS gasto_total,
  round(ticket_medio::numeric, 2) AS ticket_medio,
  primeira_compra::date AS primeira_compra,
  ultima_compra::date AS ultima_compra,
  dias_como_cliente::integer AS dias_como_cliente,
  CASE
    WHEN total_pedidos >= 5 THEN 'VIP'
    WHEN total_pedidos >= 3 THEN 'Recorrente frequente'
    ELSE 'Retornou uma vez'
  END AS classificacao
FROM agregado
ORDER BY total_pedidos DESC, round(gasto_total::numeric, 2) DESC;

CREATE VIEW silver.vw_distribuicao_itens_pedido AS
WITH itens_por_pedido AS (
  SELECT order_items.order_id,
    COUNT(*)::integer AS quantidade_itens
  FROM silver.order_items
  GROUP BY order_items.order_id
)
SELECT quantidade_itens,
  COUNT(*)::integer AS quantidade_pedidos,
  round((100.0 * COUNT(*)::numeric) / sum(COUNT(*)) OVER (), 2) AS percentual
FROM itens_por_pedido
GROUP BY quantidade_itens
ORDER BY quantidade_itens;

CREATE VIEW silver.vw_multiplos_itens_pedido AS
WITH itens_por_pedido AS (
  SELECT order_items.order_id,
    COUNT(*)::integer AS quantidade_itens
  FROM silver.order_items
  GROUP BY order_items.order_id
)
SELECT COUNT(*)::integer AS total_pedidos,
  round(avg(quantidade_itens), 2) AS media_itens_por_pedido,
  min(quantidade_itens) AS menor_carrinho,
  max(quantidade_itens) AS maior_carrinho,
  COUNT(*) FILTER (WHERE quantidade_itens > 1)::integer AS pedidos_multiplos_itens,
  round((100.0 * COUNT(*) FILTER (WHERE quantidade_itens > 1)::numeric) / COUNT(*)::numeric, 2) AS percentual_multiplos_itens
FROM itens_por_pedido;
