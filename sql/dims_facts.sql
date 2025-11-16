-- ======================================================================
-- dims_facts.sql
-- Purpose: Build dimension (dim_*) and fact (fct_*) tables from staging.
-- Schema: mart
-- ======================================================================

CREATE SCHEMA IF NOT EXISTS mart;
SET search_path = mart, public;

-- ----------------------------------------------------------------------
-- 1) dim_date
--     - One row per calendar day that appears in orders
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.dim_date;
CREATE TABLE mart.dim_date AS
WITH calendar AS (
  SELECT
    MIN(order_day) AS min_day,
    MAX(order_day) AS max_day
  FROM staging.stg_orders
),
series AS (
  SELECT
    GENERATE_SERIES(min_day, max_day, INTERVAL '1 day')::date AS date_key
  FROM calendar
)
SELECT
  date_key,                              -- PK
  EXTRACT(ISODOW FROM date_key)::int AS day_of_week,
  TO_CHAR(date_key, 'Day')       AS day_name,
  EXTRACT(DAY   FROM date_key)::int AS day_of_month,
  EXTRACT(WEEK  FROM date_key)::int AS week_of_year,
  EXTRACT(MONTH FROM date_key)::int AS month,
  TO_CHAR(date_key, 'Mon')      AS month_name,
  EXTRACT(QUARTER FROM date_key)::int AS quarter,
  EXTRACT(YEAR   FROM date_key)::int AS year,
  (EXTRACT(ISODOW FROM date_key) IN (6,7)) AS is_weekend
FROM series
ORDER BY date_key;

ALTER TABLE mart.dim_date
  ADD CONSTRAINT pk_dim_date PRIMARY KEY (date_key);

-- ----------------------------------------------------------------------
-- 2) dim_customer
--     - One row per customer
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.dim_customer;
CREATE TABLE mart.dim_customer AS
SELECT
  c.customer_id,          -- natural key
  c.signup_ts,
  DATE(c.signup_ts) AS signup_day,
  c.country
FROM staging.stg_customers c;

ALTER TABLE mart.dim_customer
  ADD CONSTRAINT pk_dim_customer PRIMARY KEY (customer_id);

CREATE INDEX IF NOT EXISTS ix_dim_customer_country ON mart.dim_customer(country);

-- ----------------------------------------------------------------------
-- 3) dim_product
--     - One row per product
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.dim_product;
CREATE TABLE mart.dim_product AS
SELECT
  p.product_id,                     -- natural key
  p.description AS product_name
FROM staging.stg_products p;

ALTER TABLE mart.dim_product
  ADD CONSTRAINT pk_dim_product PRIMARY KEY (product_id);

-- ----------------------------------------------------------------------
-- 4) fct_orders
--     - One row per order
--     - Joins to date + customer dimensions
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.fct_orders;
CREATE TABLE mart.fct_orders AS
SELECT
  o.order_id,
  o.customer_id,
  o.order_ts,
  o.order_day       AS date_key,         -- FK to dim_date
  o.status,
  o.currency,
  o.total_amount,                        -- in GBP in this project
  o.total_amount_usd,                    -- same as total_amount for now
  d.year,
  d.month,
  d.week_of_year,
  c.country
FROM staging.stg_orders o
LEFT JOIN mart.dim_date     d ON d.date_key    = o.order_day
LEFT JOIN mart.dim_customer c ON c.customer_id = o.customer_id;

ALTER TABLE mart.fct_orders
  ADD CONSTRAINT pk_fct_orders PRIMARY KEY (order_id);

CREATE INDEX IF NOT EXISTS ix_fct_orders_date   ON mart.fct_orders(date_key);
CREATE INDEX IF NOT EXISTS ix_fct_orders_cust   ON mart.fct_orders(customer_id);
CREATE INDEX IF NOT EXISTS ix_fct_orders_status ON mart.fct_orders(status);

-- ----------------------------------------------------------------------
-- 5) fct_order_items
--     - One row per order line (product in an order)
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.fct_order_items;
CREATE TABLE mart.fct_order_items AS
SELECT
  oi.order_id,
  oi.product_id,
  DATE(oi.order_day) AS date_key,    -- FK to dim_date
  oi.qty,
  oi.unit_price,
  oi.net_sales,
  d.year,
  d.month,
  p.product_name
FROM staging.stg_order_items oi
LEFT JOIN mart.dim_date    d ON d.date_key    = oi.order_day
LEFT JOIN mart.dim_product p ON p.product_id  = oi.product_id;

-- No natural PK (could add surrogate). Use composite indexes.
CREATE INDEX IF NOT EXISTS ix_fct_order_items_order  ON mart.fct_order_items(order_id);
CREATE INDEX IF NOT EXISTS ix_fct_order_items_prod   ON mart.fct_order_items(product_id);
CREATE INDEX IF NOT EXISTS ix_fct_order_items_date   ON mart.fct_order_items(date_key);

-- ----------------------------------------------------------------------
-- 6) fct_daily_revenue
--     - Aggregated table for dashboard performance
--     - One row per day (+ country)
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.fct_daily_revenue;
CREATE TABLE mart.fct_daily_revenue AS
SELECT
  o.date_key,
  d.year,
  d.month,
  d.week_of_year,
  o.country,
  COUNT(DISTINCT o.order_id) AS orders,
  SUM(o.total_amount)        AS revenue_gbp,
  AVG(o.total_amount)        AS avg_order_value_gbp
FROM mart.fct_orders o
LEFT JOIN mart.dim_date d ON d.date_key = o.date_key
GROUP BY
  o.date_key,
  d.year,
  d.month,
  d.week_of_year,
  o.country
ORDER BY o.date_key, o.country;

CREATE INDEX IF NOT EXISTS ix_fct_daily_revenue_date
  ON mart.fct_daily_revenue(date_key);

-- ======================================================================
-- End of dims_facts.sql
-- ======================================================================
