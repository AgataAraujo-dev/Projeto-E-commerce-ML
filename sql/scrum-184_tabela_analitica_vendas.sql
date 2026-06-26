-- SCRUM-184 + pedido extra da Veronica
-- tabela_analitica_vendas (tabela física criada por engano) → vw_tabela_analitica_vendas (view)
-- Executado em: Junho 2026
-- Correção adicional: a tabela original (e a view vw_analise_vendas equivalente)
-- usava a camada bronze. Esta view aponta para o silver já tratado.
-- Validado: 98.665 linhas (diferença de 776 em relação ao total de pedidos
-- explicada por pedidos sem item/pagamento associado — ver decisoes_tecnicas.md)

CREATE VIEW silver.vw_tabela_analitica_vendas AS
SELECT
  o.order_id AS id_pedido,
  o.customer_id AS id_cliente_pedido,
  c.customer_unique_id AS id_unico_cliente,
  c.customer_state AS uf_cliente,
  c.customer_city AS cidade_cliente,
  o.status_pedido AS status_pedido,
  o.data_compra AS data_compra,
  o.data_aprovacao_pagamento AS data_aprovacao_pagamento,
  o.data_envio_transportadora AS data_envio_transportadora,
  o.data_entrega_cliente AS data_entrega_cliente,
  o.prazo_estimado_entrega AS prazo_estimado_entrega,
  EXTRACT(day FROM o.data_entrega_cliente - o.data_compra)::integer AS dias_entrega_real,
  GREATEST(0, EXTRACT(day FROM o.data_entrega_cliente - o.prazo_estimado_entrega)::integer) AS dias_atraso,
  COUNT(oi.order_item_id)::integer AS total_itens_comprados,
  SUM(oi.price)::float AS faturamento_produtos,
  SUM(oi.freight_value)::float AS custo_frete,
  (SUM(oi.price) + SUM(oi.freight_value))::float AS valor_total_pedido_calculado,
  SUM(op.payment_value)::float AS valor_efetivamente_pago,
  string_agg(DISTINCT op.payment_type, ', ') AS formas_pagamento,
  MAX(op.payment_installments)::integer AS numero_max_parcelas
FROM silver.orders_dataset_silver o
  JOIN silver.order_customers c ON o.customer_id = c.customer_id
  JOIN silver.order_items oi ON o.order_id = oi.order_id
  JOIN silver.order_payments_silver_tratada op ON o.order_id = op.order_id
GROUP BY
  o.order_id, o.customer_id, c.customer_unique_id, c.customer_state, c.customer_city,
  o.status_pedido, o.data_compra, o.data_aprovacao_pagamento,
  o.data_envio_transportadora, o.data_entrega_cliente, o.prazo_estimado_entrega;
