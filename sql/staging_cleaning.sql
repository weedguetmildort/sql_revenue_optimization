-- ======================================================================
-- staging_cleaning.sql
-- Purpose: Clean raw_online_retail into staging tables for analytics.
-- Dialect: PostgreSQL
-- ======================================================================

-- ----------------------------------------------------------------------
-- 0) Schemas
-- ----------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS mart;

SET search_path = staging, public;

-- ----------------------------------------------------------------------
-- 1) Sanity: raw table exists?
-- ----------------------------------------------------------------------
-- This will fail loudly if you forgot to load the CSV.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name   = 'raw_sales'
  ) THEN
    RAISE EXCEPTION 'Table public.raw_sales does not exist. Load raw data first.';
  END IF;
END$$;

-- ----------------------------------------------------------------------
-- 2) Customers (stg_customers)
--     - One row per customer_id
--     - First order timestamp as signup surrogate
--     - Country inferred from latest non-null country
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS staging.stg_customers;
CREATE TABLE staging.stg_customers AS
WITH base AS (
  SELECT
    customer_id,
    country,
    invoice_ts
  FROM public.raw_sales
  WHERE customer_id IS NOT NULL
),
first_order AS (
  SELECT
    customer_id,
    MIN(invoice_ts) AS first_order_ts
  FROM base
  GROUP BY customer_id
),
latest_country AS (
  SELECT DISTINCT ON (customer_id)
    customer_id,
    country
  FROM base
  WHERE country IS NOT NULL
  ORDER BY customer_id, invoice_ts DESC
)
SELECT
  f.customer_id,
  f.first_order_ts AS signup_ts,
  lc.country
FROM first_order f
LEFT JOIN latest_country lc USING (customer_id);

CREATE INDEX IF NOT EXISTS ix_stg_customers_id ON staging.stg_customers(customer_id);

-- ----------------------------------------------------------------------
-- 3) Products (stg_products)
--     - One row per stock_code (product_id)
--     - Latest non-null description
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS staging.stg_products;
CREATE TABLE staging.stg_products AS
WITH ranked AS (
  SELECT
    stock_code     AS product_id,
    NULLIF(TRIM(description), '') AS description,
    ROW_NUMBER() OVER (
      PARTITION BY stock_code
      ORDER BY invoice_ts DESC
    ) AS rn
  FROM public.raw_sales
  WHERE stock_code IS NOT NULL
)
SELECT
  product_id,
  description
FROM ranked
WHERE rn = 1;

CREATE INDEX IF NOT EXISTS ix_stg_products_id ON staging.stg_products(product_id);

-- ----------------------------------------------------------------------
-- 4) Orders (stg_orders)
--     - One row per invoice_no
--     - Aggregate line-item revenue
--     - Use GBP as currency (Online Retail is UK-based)
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS staging.stg_orders;
CREATE TABLE staging.stg_orders AS
WITH cleaned AS (
  SELECT
    invoice_no        AS order_id,
    customer_id,
    invoice_ts,
    quantity,
    unit_price,
    country
  FROM public.raw_sales
  WHERE invoice_no IS NOT NULL
    AND invoice_ts IS NOT NULL
),
agg AS (
  SELECT
    order_id,
    MIN(invoice_ts) AS order_ts,
    DATE(MIN(invoice_ts)) AS order_day,
    MIN(customer_id) AS customer_id,
    MIN(country)     AS country,
    SUM(GREATEST(quantity,0) * GREATEST(unit_price,0))::numeric(12,2) AS total_amount_gbp
  FROM cleaned
  GROUP BY order_id
)
SELECT
  order_id,
  customer_id,
  order_ts,
  order_day,
  'paid'::text AS status,
  'GBP'::text  AS currency,
  total_amount_gbp AS total_amount,
  total_amount_gbp AS total_amount_usd
FROM agg;

CREATE INDEX IF NOT EXISTS ix_stg_orders_id       ON staging.stg_orders(order_id);
CREATE INDEX IF NOT EXISTS ix_stg_orders_customer ON staging.stg_orders(customer_id);
CREATE INDEX IF NOT EXISTS ix_stg_orders_day      ON staging.stg_orders(order_day);

-- ----------------------------------------------------------------------
-- 5) Order Items (stg_order_items)
--     - Line level, cleaned
--     - Non-negative qty/price
--     - Net sales per line
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS staging.stg_order_items;
CREATE TABLE staging.stg_order_items AS
WITH cleaned AS (
  SELECT
    invoice_no   AS order_id,
    stock_code   AS product_id,
    GREATEST(quantity, 0)   AS qty,
    GREATEST(unit_price, 0) AS unit_price,
    invoice_ts
  FROM public.raw_sales
  WHERE invoice_no IS NOT NULL
    AND stock_code IS NOT NULL
)
SELECT
  order_id,
  product_id,
  qty,
  unit_price,
  (qty * unit_price)::numeric(12,2) AS net_sales,
  invoice_ts,
  DATE(invoice_ts) AS order_day
FROM cleaned;

CREATE INDEX IF NOT EXISTS ix_stg_order_items_order   ON staging.stg_order_items(order_id);
CREATE INDEX IF NOT EXISTS ix_stg_order_items_product ON staging.stg_order_items(product_id);

-- ----------------------------------------------------------------------
-- 6) Ad Spend (stg_daily_ad_spend)
--     - Source: public.raw_ad_spend (date, channel, spend)
--     - One row per (day, channel)
--     - Cleans channel names and enforces non-negative spend
-- ----------------------------------------------------------------------

DROP TABLE IF EXISTS staging.stg_daily_ad_spend;
CREATE TABLE staging.stg_daily_ad_spend AS
WITH base AS (
  SELECT
    -- Make sure date is valid and cast correctly
    DATE("date") AS day,
    LOWER(NULLIF(TRIM(channel), '')) AS channel_raw,
    COALESCE(spend, 0)::numeric AS spend_raw
  FROM public.raw_ad_spend
  WHERE "date" IS NOT NULL
),
ranked AS (
  -- If there are duplicates for (day, channel), keep the last one
  SELECT
    day,
    channel_raw,
    spend_raw,
    ROW_NUMBER() OVER (
      PARTITION BY day, channel_raw
      ORDER BY day DESC
    ) AS rn
  FROM base
)
SELECT
  day,
  -- Normalize channel names to a small, controlled vocabulary
  CASE
    WHEN channel_raw IN ('search', 'paid_search', 'sem') THEN 'search'
    WHEN channel_raw IN ('display', 'programmatic')       THEN 'display'
    WHEN channel_raw IN ('social', 'facebook', 'instagram', 'twitter') THEN 'social'
    WHEN channel_raw IN ('email', 'newsletter')           THEN 'email'
    WHEN channel_raw IS NULL OR channel_raw = ''          THEN 'unknown'
    ELSE channel_raw
  END AS channel,
  GREATEST(spend_raw, 0)::numeric(12,2) AS spend
FROM ranked
WHERE rn = 1;

CREATE INDEX IF NOT EXISTS ix_stg_daily_ad_spend_day_channel
  ON staging.stg_daily_ad_spend(day, channel);

-- ----------------------------------------------------------------------
-- 7) Basic Data Quality Checks (for logs / monitoring)
-- ----------------------------------------------------------------------

-- 7.1 Orphan orders: order with missing customer
WITH missing_customer AS (
  SELECT o.order_id
  FROM staging.stg_orders o
  LEFT JOIN staging.stg_customers c ON c.customer_id = o.customer_id
  WHERE o.customer_id IS NOT NULL
    AND c.customer_id IS NULL
)
SELECT 'DQ:orders_missing_customer' AS check_name, COUNT(*) AS failures
FROM missing_customer;

-- 7.2 Orphan order_items: item with missing product
WITH missing_product AS (
  SELECT oi.order_id, oi.product_id
  FROM staging.stg_order_items oi
  LEFT JOIN staging.stg_products p ON p.product_id = oi.product_id
  WHERE p.product_id IS NULL
)
SELECT 'DQ:order_items_missing_product' AS check_name, COUNT(*) AS failures
FROM missing_product;

-- 7.3 Revenue sanity: sum of items vs order header (by order)
WITH items AS (
  SELECT order_id, SUM(net_sales) AS items_total
  FROM staging.stg_order_items
  GROUP BY order_id
),
joined AS (
  SELECT
    o.order_id,
    o.total_amount,
    COALESCE(i.items_total, 0) AS items_total
  FROM staging.stg_orders o
  LEFT JOIN items i USING (order_id)
),
diffs AS (
  SELECT
    COUNT(*) AS mismatched
  FROM joined
  WHERE ABS(total_amount - items_total) > 0.05
)
SELECT 'DQ:order_header_items_mismatch' AS check_name, mismatched AS failures
FROM diffs;

-- 7.4 Freshness: latest order_day
SELECT 'DQ:freshness_latest_order_day' AS check_name,
       MAX(order_day)                  AS latest_day
FROM staging.stg_orders;

-- 7.5 Ad spend sanity checks

-- Nulls in stg_daily_ad_spend
SELECT 'DQ:ad_spend_nulls' AS check_name,
       SUM(CASE WHEN day IS NULL THEN 1 ELSE 0 END)    AS null_day,
       SUM(CASE WHEN channel IS NULL OR channel = '' THEN 1 ELSE 0 END) AS null_channel,
       SUM(CASE WHEN spend IS NULL THEN 1 ELSE 0 END)  AS null_spend
FROM staging.stg_daily_ad_spend;

-- Negative or obviously huge spend values
SELECT 'DQ:ad_spend_non_negative_and_reasonable' AS check_name,
       SUM(CASE WHEN spend < 0 THEN 1 ELSE 0 END) AS negative_spend_rows,
       MIN(spend) AS min_spend,
       MAX(spend) AS max_spend,
       SUM(spend) AS total_spend
FROM staging.stg_daily_ad_spend;

-- ======================================================================
-- End of staging_cleaning.sql
-- ======================================================================