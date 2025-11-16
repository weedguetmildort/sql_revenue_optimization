-- ======================================================================
-- aggregates_daily.sql
-- Purpose: Build daily-level aggregate tables for fast dashboards.
-- Schema: mart
-- ======================================================================

CREATE SCHEMA IF NOT EXISTS mart;
SET search_path = mart, public;

-- ----------------------------------------------------------------------
-- 0) Sanity checks: required source tables
-- ----------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'mart' AND table_name = 'fct_orders'
  ) THEN
    RAISE EXCEPTION 'mart.fct_orders does not exist. Run dims_facts.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'mart' AND table_name = 'dim_customer'
  ) THEN
    RAISE EXCEPTION 'mart.dim_customer does not exist. Run dims_facts.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'mart' AND table_name = 'fct_order_items'
  ) THEN
    RAISE EXCEPTION 'mart.fct_order_items does not exist. Run dims_facts.sql first.';
  END IF;
END$$;

-- ----------------------------------------------------------------------
-- 1) agg_daily_revenue
--     - One row per (date, country)
--     - Metrics: orders, revenue, AOV, active / new / returning customers
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.agg_daily_revenue;
CREATE TABLE mart.agg_daily_revenue AS
WITH base AS (
  SELECT
    o.date_key,
    o.country,
    o.order_id,
    o.customer_id,
    o.total_amount        AS revenue_gbp,
    COALESCE(c.signup_day, o.date_key) AS signup_day
  FROM mart.fct_orders o
  LEFT JOIN mart.dim_customer c
    ON c.customer_id = o.customer_id
  -- If you later add cancelled/refunded logic, you can filter here:
  -- WHERE o.status = 'paid'
),
agg AS (
  SELECT
    date_key,
    country,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT customer_id) AS active_customers,
    SUM(revenue_gbp)           AS revenue_gbp,
    AVG(revenue_gbp)           AS avg_order_value_gbp,
    COUNT(DISTINCT CASE WHEN signup_day = date_key THEN customer_id END) AS new_customers,
    COUNT(DISTINCT CASE WHEN signup_day <  date_key THEN customer_id END) AS returning_customers
  FROM base
  GROUP BY date_key, country
)
SELECT
  a.date_key,
  d.year,
  d.month,
  d.week_of_year,
  a.country,
  a.orders,
  a.active_customers,
  a.revenue_gbp,
  a.avg_order_value_gbp,
  a.new_customers,
  a.returning_customers
FROM agg a
LEFT JOIN mart.dim_date d
  ON d.date_key = a.date_key
ORDER BY a.date_key, a.country;

ALTER TABLE mart.agg_daily_revenue
  ADD CONSTRAINT pk_agg_daily_revenue PRIMARY KEY (date_key, country);

CREATE INDEX IF NOT EXISTS ix_agg_daily_revenue_year_month
  ON mart.agg_daily_revenue(year, month);

-- ----------------------------------------------------------------------
-- 2) agg_daily_product_revenue
--     - One row per (date, product)
--     - Use this for "top products over time" views
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.agg_daily_product_revenue;
CREATE TABLE mart.agg_daily_product_revenue AS
SELECT
  oi.date_key,
  d.year,
  d.month,
  oi.product_id,
  p.product_name,
  SUM(oi.qty)       AS units_sold,
  SUM(oi.net_sales) AS revenue_gbp,
  COUNT(DISTINCT oi.order_id) AS orders
FROM mart.fct_order_items oi
LEFT JOIN mart.dim_product p
  ON p.product_id = oi.product_id
LEFT JOIN mart.dim_date d
  ON d.date_key = oi.date_key
GROUP BY
  oi.date_key,
  d.year,
  d.month,
  oi.product_id,
  p.product_name
ORDER BY oi.date_key, revenue_gbp DESC;

CREATE INDEX IF NOT EXISTS ix_agg_daily_product_revenue_date
  ON mart.agg_daily_product_revenue(date_key);

CREATE INDEX IF NOT EXISTS ix_agg_daily_product_revenue_product
  ON mart.agg_daily_product_revenue(product_id);

-- ----------------------------------------------------------------------
-- 3) (Optional) agg_daily_customer_cohort
--     - Cohort-style view: for each customer signup_day, how many orders
--       and how much revenue did they generate on each activity_date.
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.agg_daily_customer_cohort;
CREATE TABLE mart.agg_daily_customer_cohort AS
WITH base AS (
  SELECT
    o.order_id,
    o.customer_id,
    o.date_key      AS activity_date,
    c.signup_day    AS cohort_day,
    o.total_amount  AS revenue_gbp
  FROM mart.fct_orders o
  LEFT JOIN mart.dim_customer c
    ON c.customer_id = o.customer_id
  WHERE c.signup_day IS NOT NULL
),
agg AS (
  SELECT
    cohort_day,
    activity_date,
    COUNT(DISTINCT customer_id) AS active_customers,
    COUNT(DISTINCT order_id)    AS orders,
    SUM(revenue_gbp)            AS revenue_gbp
  FROM base
  GROUP BY cohort_day, activity_date
)
SELECT
  a.cohort_day,
  a.activity_date,
  cd.year  AS cohort_year,
  cd.month AS cohort_month,
  ad.year  AS activity_year,
  ad.month AS activity_month,
  a.active_customers,
  a.orders,
  a.revenue_gbp
FROM agg a
LEFT JOIN mart.dim_date cd ON cd.date_key = a.cohort_day
LEFT JOIN mart.dim_date ad ON ad.date_key = a.activity_date
ORDER BY cohort_day, activity_date;

CREATE INDEX IF NOT EXISTS ix_agg_daily_customer_cohort_cohort
  ON mart.agg_daily_customer_cohort(cohort_day);

CREATE INDEX IF NOT EXISTS ix_agg_daily_customer_cohort_activity
  ON mart.agg_daily_customer_cohort(activity_date);

-- ======================================================================
-- End of aggregates_daily.sql
-- ======================================================================
