-- SCRUM-184 — Transformação tipos de dados
-- Tabela: silver.order_items (order_item_id, price, freight_value → float)
-- Executado em: Junho 2026
-- Views dependentes identificadas e recriadas: 7
--   v_outliers_order_items, vw_padrao_dos_carrinhos, vw_padrao_carrinho_cliente,
--   vw_multiple_items_per_order, view_proporcao_frete_cliente,
--   view_receita_por_categoria, vw_distribuicao_valor_compra
-- Validado: 112.650 linhas, sem nulos em price/freight_value após alteração

-- ===== DROP das views dependentes (ordem identificada via erro do Postgres) =====
DROP VIEW silver.v_outliers_order_items;
DROP VIEW silver.vw_padrao_dos_carrinhos;
DROP VIEW silver.vw_padrao_carrinho_cliente;
DROP VIEW silver.vw_multiple_items_per_order;
DROP VIEW silver.view_proporcao_frete_cliente;
DROP VIEW silver.view_receita_por_categoria;
DROP VIEW silver.vw_distribuicao_valor_compra;

-- ===== ALTER da tabela base =====
ALTER TABLE silver.order_items
  ALTER COLUMN order_item_id TYPE float,
  ALTER COLUMN price TYPE float,
  ALTER COLUMN freight_value TYPE float;

-- ===== CREATE das 7 views (definições originais, preservadas) =====

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

CREATE VIEW silver.vw_padrao_dos_carrinhos AS
WITH carrinho_itens AS (
  SELECT i.order_id,
    count(i.order_item_id) AS total_itens_no_pedido,
    count(DISTINCT p.product_category_name) AS total_categorias_no_pedido
  FROM silver.order_items i
    JOIN silver.products_silver_tratada p ON i.product_id = p.product_id
  GROUP BY i.order_id
), carrinho_financeiro AS (
  SELECT order_payments_silver_tratada.order_id,
    sum(order_payments_silver_tratada.payment_value) AS valor_pago_pedido
  FROM silver.order_payments_silver_tratada
  GROUP BY order_payments_silver_tratada.order_id
), visao_cliente AS (
  SELECT c.customer_unique_id,
    count(DISTINCT o.order_id) AS total_pedidos_validos,
    sum(i.total_itens_no_pedido) AS total_itens_comprados,
    sum(i.total_categorias_no_pedido) AS total_categorias_exploradas,
    sum(f.valor_pago_pedido) AS gasto_total
  FROM silver.order_customers c
    JOIN silver.orders_dataset_silver o ON c.customer_id::text = o.customer_id
    JOIN carrinho_itens i ON o.order_id = i.order_id
    JOIN carrinho_financeiro f ON o.order_id = f.order_id
  WHERE o.status_pedido <> ALL (ARRAY['canceled'::text, 'unavailable'::text])
  GROUP BY c.customer_unique_id
)
SELECT customer_unique_id,
  total_pedidos_validos AS total_pedidos,
  total_itens_comprados,
  total_categorias_exploradas,
  round(100.0 * (total_itens_comprados * 1.0 / total_pedidos_validos::numeric)) / 100.0 AS media_itens_por_pedido,
  round(100.0::double precision * (gasto_total * 1.0::double precision / total_pedidos_validos::double precision)) / 100.0::double precision AS ticket_medio_cliente,
  CASE
    WHEN (total_itens_comprados * 1.0 / total_pedidos_validos::numeric) = 1.0 THEN '1. Carrinho Unitário (1 Item)'::text
    WHEN (total_itens_comprados * 1.0 / total_pedidos_validos::numeric) > 1.0 AND (total_itens_comprados * 1.0 / total_pedidos_validos::numeric) <= 3.0 THEN '2. Carrinho Múltiplo (2 a 3 Itens)'::text
    ELSE '3. Carrinho Volumoso (+3 Itens)'::text
  END AS padrao_comportamental_carrinho
FROM visao_cliente;

CREATE VIEW silver.vw_padrao_carrinho_cliente AS
WITH carrinho_cliente AS (
  SELECT c.customer_unique_id,
    count(DISTINCT o.order_id) AS total_pedidos,
    count(i.order_item_id) AS total_itens,
    sum(i.price) AS valor_total
  FROM silver.order_customers c
    JOIN silver.orders_dataset_silver o ON c.customer_id::text = o.customer_id
    JOIN silver.order_items i ON o.order_id = i.order_id
  GROUP BY c.customer_unique_id
)
SELECT customer_unique_id,
  total_pedidos,
  total_itens,
  round(total_itens::numeric / total_pedidos::numeric, 2) AS media_itens_por_pedido,
  round(valor_total::numeric / total_pedidos::numeric, 2) AS ticket_medio
FROM carrinho_cliente;

CREATE VIEW silver.vw_multiple_items_per_order AS
WITH items_aggregated AS (
  SELECT oi.order_id,
    count(oi.order_item_id) AS total_items,
    count(DISTINCT oi.product_id) AS unique_products,
    sum(oi.price) AS total_produtos,
    sum(oi.freight_value) AS total_frete
  FROM silver.order_items oi
    JOIN silver.products_silver_tratada pr ON oi.product_id = pr.product_id
  GROUP BY oi.order_id
), payments_aggregated AS (
  SELECT order_payments_silver_tratada.order_id,
    sum(order_payments_silver_tratada.payment_value) AS valor_total_gasto,
    max(order_payments_silver_tratada.payment_installments) AS max_installments
  FROM silver.order_payments_silver_tratada
  GROUP BY order_payments_silver_tratada.order_id
)
SELECT o.order_id,
  o.customer_id,
  c.customer_unique_id,
  o.status_pedido,
  o.data_compra,
  COALESCE(i.total_items, 0::bigint) AS total_items,
  COALESCE(i.unique_products, 0::bigint) AS unique_products,
  COALESCE(i.total_produtos, 0::double precision) AS total_produtos,
  COALESCE(i.total_frete, 0::double precision) AS total_frete,
  COALESCE(p.valor_total_gasto, 0::double precision) AS valor_total_gasto,
  CASE
    WHEN COALESCE(i.total_items, 0::bigint) > 1 THEN true
    ELSE false
  END AS has_multiple_items
FROM silver.orders_dataset_silver o
  JOIN silver.order_customers c ON o.customer_id = c.customer_id::text
  JOIN items_aggregated i ON o.order_id = i.order_id
  JOIN payments_aggregated p ON o.order_id = p.order_id;

CREATE VIEW silver.view_proporcao_frete_cliente AS
SELECT order_id,
  count(order_item_id) AS total_itens_pedido,
  sum(price) AS total_produtos,
  sum(freight_value) AS total_frete,
  sum(price + freight_value) AS valor_total_pedido,
  round((sum(freight_value) / NULLIF(sum(price + freight_value), 0::double precision) * 100::double precision)::numeric, 2) AS percentual_frete_proporcional
FROM silver.order_items
GROUP BY order_id
ORDER BY (round((sum(freight_value) / NULLIF(sum(price + freight_value), 0::double precision) * 100::double precision)::numeric, 2)) DESC;

CREATE VIEW silver.view_receita_por_categoria AS
SELECT p.product_category_name AS categoria_produto,
  count(DISTINCT i.order_id) AS quantidade_vendas,
  sum(i.price) AS receita_total_produtos,
  round(avg(i.price)::numeric, 2) AS preco_medio_produto
FROM silver.order_items i
  JOIN silver.products_silver_tratada p ON i.product_id = p.product_id
  JOIN silver.orders_dataset_silver o ON i.order_id = o.order_id
WHERE o.status_pedido = 'delivered'::text
GROUP BY p.product_category_name
ORDER BY (sum(i.price)) DESC;

CREATE VIEW silver.vw_distribuicao_valor_compra AS
SELECT avg(preco) AS media,
  percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY preco) AS mediana,
  percentile_cont(0.25::double precision) WITHIN GROUP (ORDER BY preco) AS q1,
  percentile_cont(0.75::double precision) WITHIN GROUP (ORDER BY preco) AS q3,
  min(preco) AS minimo,
  max(preco) AS maximo
FROM ( SELECT oi.product_id,
    avg(oi.price) AS preco
  FROM silver.order_items oi
  GROUP BY oi.product_id) base;
