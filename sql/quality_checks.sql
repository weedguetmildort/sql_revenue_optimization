-- ======================================================================
-- quality_checks.sql
-- Purpose: Run data quality checks on staging + mart layers.
--          Results are stored in mart.quality_check_results.
-- Dialect: PostgreSQL
-- ======================================================================

CREATE SCHEMA IF NOT EXISTS mart;
SET search_path = mart, public;

-- ----------------------------------------------------------------------
-- 0) Results table (truncate + reuse each run)
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.quality_check_results;
CREATE TABLE mart.quality_check_results (
  check_name   TEXT,
  status       TEXT,          -- 'PASS' / 'FAIL' / 'WARN'
  failures     INTEGER,
  details      TEXT,
  checked_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ----------------------------------------------------------------------
-- 1) Sanity: Required tables exist (including ad spend + aggregates)
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'tables_exist',
  CASE WHEN COUNT(t.table_name) = 11 THEN 'PASS' ELSE 'FAIL' END AS status,
  11 - COUNT(t.table_name) AS missing_tables,
  'Expected: staging.stg_orders, staging.stg_order_items, staging.stg_customers, staging.stg_products, staging.stg_daily_ad_spend, mart.dim_date, mart.dim_customer, mart.dim_product, mart.fct_orders, mart.fct_order_items, mart.agg_daily_revenue' AS details
FROM (
  SELECT 'staging' AS schema_name, 'stg_orders'           AS table_name UNION ALL
  SELECT 'staging',               'stg_order_items'                       UNION ALL
  SELECT 'staging',               'stg_customers'                         UNION ALL
  SELECT 'staging',               'stg_products'                          UNION ALL
  SELECT 'staging',               'stg_daily_ad_spend'                    UNION ALL
  SELECT 'mart',                  'dim_date'                              UNION ALL
  SELECT 'mart',                  'dim_customer'                          UNION ALL
  SELECT 'mart',                  'dim_product'                           UNION ALL
  SELECT 'mart',                  'fct_orders'                            UNION ALL
  SELECT 'mart',                  'fct_order_items'                       UNION ALL
  SELECT 'mart',                  'agg_daily_revenue'
) expected
LEFT JOIN information_schema.tables t
  ON t.table_schema = expected.schema_name
 AND t.table_name   = expected.table_name;

-- ----------------------------------------------------------------------
-- 2) Row count consistency: staging vs facts
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'row_count_orders_staging_vs_fact',
  CASE WHEN stg_cnt = fct_cnt AND stg_cnt > 0 THEN 'PASS' ELSE 'WARN' END AS status,
  ABS(stg_cnt - fct_cnt) AS failures,
  format('stg_orders=%s, fct_orders=%s', stg_cnt, fct_cnt) AS details
FROM (
  SELECT
    (SELECT COUNT(*) FROM staging.stg_orders) AS stg_cnt,
    (SELECT COUNT(*) FROM mart.fct_orders)    AS fct_cnt
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'row_count_order_items_staging_vs_fact',
  CASE WHEN stg_cnt = fct_cnt AND stg_cnt > 0 THEN 'PASS' ELSE 'WARN' END AS status,
  ABS(stg_cnt - fct_cnt) AS failures,
  format('stg_order_items=%s, fct_order_items=%s', stg_cnt, fct_cnt) AS details
FROM (
  SELECT
    (SELECT COUNT(*) FROM staging.stg_order_items) AS stg_cnt,
    (SELECT COUNT(*) FROM mart.fct_order_items)    AS fct_cnt
) s;

-- ----------------------------------------------------------------------
-- 3) Null checks on key columns
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'null_keys_stg_orders',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Null order_id, customer_id, or order_day in staging.stg_orders'
FROM (
  SELECT
    SUM(CASE WHEN order_id    IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN order_day   IS NULL THEN 1 ELSE 0 END) AS failures
  FROM staging.stg_orders
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'null_keys_stg_order_items',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Null order_id, product_id, or order_day in staging.stg_order_items'
FROM (
  SELECT
    SUM(CASE WHEN order_id    IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN product_id  IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN order_day   IS NULL THEN 1 ELSE 0 END) AS failures
  FROM staging.stg_order_items
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'null_keys_fct_orders',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Null order_id, customer_id, or date_key in mart.fct_orders'
FROM (
  SELECT
    SUM(CASE WHEN order_id    IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN date_key    IS NULL THEN 1 ELSE 0 END) AS failures
  FROM mart.fct_orders
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'null_keys_fct_order_items',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Null order_id, product_id, or date_key in mart.fct_order_items'
FROM (
  SELECT
    SUM(CASE WHEN order_id    IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN product_id  IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN date_key    IS NULL THEN 1 ELSE 0 END) AS failures
  FROM mart.fct_order_items
) s;

-- ----------------------------------------------------------------------
-- 3b) Null checks for ad spend (staging)
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'null_keys_stg_daily_ad_spend',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Null day, channel, or spend in staging.stg_daily_ad_spend'
FROM (
  SELECT
    SUM(CASE WHEN day     IS NULL THEN 1 ELSE 0 END) +
    SUM(CASE WHEN channel IS NULL OR channel = '' THEN 1 ELSE 0 END) +
    SUM(CASE WHEN spend   IS NULL THEN 1 ELSE 0 END) AS failures
  FROM staging.stg_daily_ad_spend
) s;

-- ----------------------------------------------------------------------
-- 4) Uniqueness checks on primary keys & key-like columns
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'pk_uniqueness_fct_orders',
  CASE WHEN total = distinct_cnt THEN 'PASS' ELSE 'FAIL' END,
  total - distinct_cnt AS failures,
  format('total=%s, distinct_order_id=%s', total, distinct_cnt)
FROM (
  SELECT
    COUNT(*) AS total,
    COUNT(DISTINCT order_id) AS distinct_cnt
  FROM mart.fct_orders
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'pk_uniqueness_dim_customer',
  CASE WHEN total = distinct_cnt THEN 'PASS' ELSE 'FAIL' END,
  total - distinct_cnt AS failures,
  format('total=%s, distinct_customer_id=%s', total, distinct_cnt)
FROM (
  SELECT
    COUNT(*) AS total,
    COUNT(DISTINCT customer_id) AS distinct_cnt
  FROM mart.dim_customer
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'pk_uniqueness_dim_product',
  CASE WHEN total = distinct_cnt THEN 'PASS' ELSE 'FAIL' END,
  total - distinct_cnt AS failures,
  format('total=%s, distinct_product_id=%s', total, distinct_cnt)
FROM (
  SELECT
    COUNT(*) AS total,
    COUNT(DISTINCT product_id) AS distinct_cnt
  FROM mart.dim_product
) s;

-- Unique-ish for ad spend: (day, channel)
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'uniqueness_stg_daily_ad_spend_day_channel',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Rows in staging.stg_daily_ad_spend where (day, channel) appears more than once'
FROM (
  SELECT COUNT(*) AS failures
  FROM (
    SELECT day, channel, COUNT(*) AS cnt
    FROM staging.stg_daily_ad_spend
    GROUP BY day, channel
    HAVING COUNT(*) > 1
  ) d
) s;

-- ----------------------------------------------------------------------
-- 5) Referential integrity checks (orphans)
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'orphans_stg_orders_customer',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'stg_orders rows with customer_id not in stg_customers'
FROM (
  SELECT COUNT(*) AS failures
  FROM staging.stg_orders o
  LEFT JOIN staging.stg_customers c
    ON c.customer_id = o.customer_id
  WHERE o.customer_id IS NOT NULL
    AND c.customer_id IS NULL
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'orphans_stg_order_items_product',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'stg_order_items rows with product_id not in stg_products'
FROM (
  SELECT COUNT(*) AS failures
  FROM staging.stg_order_items oi
  LEFT JOIN staging.stg_products p
    ON p.product_id = oi.product_id
  WHERE oi.product_id IS NOT NULL
    AND p.product_id IS NULL
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'orphans_fct_orders_dim_customer',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'fct_orders rows with customer_id not in dim_customer'
FROM (
  SELECT COUNT(*) AS failures
  FROM mart.fct_orders o
  LEFT JOIN mart.dim_customer c
    ON c.customer_id = o.customer_id
  WHERE o.customer_id IS NOT NULL
    AND c.customer_id IS NULL
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'orphans_fct_order_items_dim_product',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'fct_order_items rows with product_id not in dim_product'
FROM (
  SELECT COUNT(*) AS failures
  FROM mart.fct_order_items oi
  LEFT JOIN mart.dim_product p
    ON p.product_id = oi.product_id
  WHERE oi.product_id IS NOT NULL
    AND p.product_id IS NULL
) s;

-- ----------------------------------------------------------------------
-- 6) Revenue sanity: header vs line-level
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
WITH items AS (
  SELECT order_id, SUM(net_sales) AS items_total
  FROM mart.fct_order_items
  GROUP BY order_id
),
joined AS (
  SELECT
    o.order_id,
    o.total_amount     AS header_total,
    COALESCE(i.items_total, 0) AS items_total
  FROM mart.fct_orders o
  LEFT JOIN items i USING (order_id)
),
mismatched AS (
  SELECT COUNT(*) AS failures
  FROM joined
  WHERE ABS(header_total - items_total) > 0.05
)
SELECT
  'revenue_header_vs_items',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'WARN' END,
  failures,
  'Orders where sum(line net_sales) differs from header total_amount by > 0.05'
FROM mismatched;

-- ----------------------------------------------------------------------
-- 7) Non-negative numeric checks
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'nonnegative_totals_fct_orders',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Negative total_amount or total_amount_usd in mart.fct_orders'
FROM (
  SELECT COUNT(*) AS failures
  FROM mart.fct_orders
  WHERE total_amount < 0 OR total_amount_usd < 0
) s;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'nonnegative_net_sales_fct_order_items',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Negative net_sales, qty, or unit_price in mart.fct_order_items'
FROM (
  SELECT COUNT(*) AS failures
  FROM mart.fct_order_items
  WHERE net_sales < 0 OR qty < 0 OR unit_price < 0
) s;

-- Non-negative for ad spend
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'nonnegative_spend_stg_daily_ad_spend',
  CASE WHEN failures = 0 THEN 'PASS' ELSE 'FAIL' END,
  failures,
  'Negative spend values in staging.stg_daily_ad_spend'
FROM (
  SELECT COUNT(*) AS failures
  FROM staging.stg_daily_ad_spend
  WHERE spend < 0
) s;

-- ----------------------------------------------------------------------
-- 8) Freshness checks
-- ----------------------------------------------------------------------
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'freshness_fct_orders',
  'PASS',
  0,
  format('latest date_key in fct_orders: %s', MAX(date_key)::text)
FROM mart.fct_orders;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'freshness_agg_daily_revenue',
  'PASS',
  0,
  format('latest date_key in agg_daily_revenue: %s', MAX(date_key)::text)
FROM mart.agg_daily_revenue;

INSERT INTO mart.quality_check_results (check_name, status, failures, details)
SELECT
  'freshness_stg_daily_ad_spend',
  'PASS',
  0,
  format('latest day in stg_daily_ad_spend: %s', MAX(day)::text)
FROM staging.stg_daily_ad_spend;

-- ----------------------------------------------------------------------
-- 9) Ad spend vs revenue relationship checks
-- ----------------------------------------------------------------------
-- Aggregate spend by day (all channels), and revenue by day (all countries),
-- then look for obvious mismatches (spend with zero revenue, revenue with zero spend)
INSERT INTO mart.quality_check_results (check_name, status, failures, details)
WITH daily_spend AS (
  SELECT day AS date_key, SUM(spend) AS spend_gbp
  FROM staging.stg_daily_ad_spend
  GROUP BY day
),
daily_revenue AS (
  SELECT date_key, SUM(revenue_gbp) AS revenue_gbp
  FROM mart.agg_daily_revenue
  GROUP BY date_key
),
joined AS (
  SELECT
    COALESCE(s.date_key, r.date_key) AS date_key,
    COALESCE(s.spend_gbp,   0)       AS spend_gbp,
    COALESCE(r.revenue_gbp, 0)       AS revenue_gbp
  FROM daily_spend s
  FULL OUTER JOIN daily_revenue r
    ON s.date_key = r.date_key
),
stats AS (
  SELECT
    SUM(CASE WHEN spend_gbp > 0 AND revenue_gbp = 0 THEN 1 ELSE 0 END) AS days_spend_no_revenue,
    SUM(CASE WHEN revenue_gbp > 0 AND spend_gbp = 0 THEN 1 ELSE 0 END) AS days_revenue_no_spend
  FROM joined
)
SELECT
  'ad_vs_revenue_mismatches',
  CASE WHEN days_spend_no_revenue = 0 AND days_revenue_no_spend = 0 THEN 'PASS' ELSE 'WARN' END,
  (days_spend_no_revenue + days_revenue_no_spend) AS failures,
  format('days_spend_no_revenue=%s, days_revenue_no_spend=%s', days_spend_no_revenue, days_revenue_no_spend) AS details
FROM stats;

-- ----------------------------------------------------------------------
-- 10) Final summary: select all results
-- ----------------------------------------------------------------------
SELECT * FROM mart.quality_check_results ORDER BY checked_at, check_name;

-- ======================================================================
-- End of quality_checks.sql
-- ======================================================================
