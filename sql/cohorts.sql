-- ======================================================================
-- cohorts.sql
-- Purpose: Build cohort analysis tables (daily + monthly) from mart layer.
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
    WHERE table_schema = 'mart' AND table_name = 'dim_customer'
  ) THEN
    RAISE EXCEPTION 'mart.dim_customer does not exist. Run dims_facts.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'mart' AND table_name = 'fct_orders'
  ) THEN
    RAISE EXCEPTION 'mart.fct_orders does not exist. Run dims_facts.sql first.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'mart' AND table_name = 'dim_date'
  ) THEN
    RAISE EXCEPTION 'mart.dim_date does not exist. Run dims_facts.sql first.';
  END IF;
END$$;

-- ----------------------------------------------------------------------
-- 1) cohort_daily_activity
--     - Grain: one row per (cohort_day, activity_day)
--     - Metrics: active_customers, orders, revenue
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.cohort_daily_activity;
CREATE TABLE mart.cohort_daily_activity AS
WITH base AS (
  SELECT
    o.order_id,
    o.customer_id,
    o.date_key      AS activity_day,
    c.signup_day    AS cohort_day,
    o.total_amount  AS revenue_gbp
  FROM mart.fct_orders o
  JOIN mart.dim_customer c
    ON c.customer_id = o.customer_id
  WHERE c.signup_day IS NOT NULL
),
agg AS (
  SELECT
    cohort_day,
    activity_day,
    COUNT(DISTINCT customer_id) AS active_customers,
    COUNT(DISTINCT order_id)    AS orders,
    SUM(revenue_gbp)            AS revenue_gbp
  FROM base
  GROUP BY cohort_day, activity_day
)
SELECT
  a.cohort_day,
  a.activity_day,
  cd.year  AS cohort_year,
  cd.month AS cohort_month,
  ad.year  AS activity_year,
  ad.month AS activity_month,
  a.active_customers,
  a.orders,
  a.revenue_gbp
FROM agg a
LEFT JOIN mart.dim_date cd ON cd.date_key = a.cohort_day
LEFT JOIN mart.dim_date ad ON ad.date_key = a.activity_day
ORDER BY cohort_day, activity_day;

CREATE INDEX IF NOT EXISTS ix_cohort_daily_activity_cohort
  ON mart.cohort_daily_activity(cohort_day);

CREATE INDEX IF NOT EXISTS ix_cohort_daily_activity_activity
  ON mart.cohort_daily_activity(activity_day);

-- ----------------------------------------------------------------------
-- 2) cohort_monthly_metrics
--     - Grain: one row per (cohort_month, activity_month)
--     - Adds "months_since_cohort" and retention_rate
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.cohort_monthly_metrics;
CREATE TABLE mart.cohort_monthly_metrics AS
WITH base AS (
  SELECT
    c.customer_id,
    DATE_TRUNC('month', c.signup_day)::date AS cohort_month,
    DATE_TRUNC('month', o.date_key)::date   AS activity_month,
    o.order_id,
    o.total_amount AS revenue_gbp
  FROM mart.dim_customer c
  JOIN mart.fct_orders o
    ON o.customer_id = c.customer_id
  WHERE c.signup_day IS NOT NULL
),
cohort_sizes AS (
  -- One row per cohort_month with number of customers in that cohort
  SELECT
    DATE_TRUNC('month', signup_day)::date AS cohort_month,
    COUNT(DISTINCT customer_id)           AS cohort_size
  FROM mart.dim_customer
  WHERE signup_day IS NOT NULL
  GROUP BY DATE_TRUNC('month', signup_day)::date
),
agg AS (
  SELECT
    cohort_month,
    activity_month,
    COUNT(DISTINCT customer_id) AS active_customers,
    COUNT(DISTINCT order_id)    AS orders,
    SUM(revenue_gbp)            AS revenue_gbp
  FROM base
  GROUP BY cohort_month, activity_month
),
joined AS (
  SELECT
    a.cohort_month,
    a.activity_month,
    cs.cohort_size,
    a.active_customers,
    a.orders,
    a.revenue_gbp
  FROM agg a
  LEFT JOIN cohort_sizes cs
    ON cs.cohort_month = a.cohort_month
),
final AS (
  SELECT
    j.cohort_month,
    j.activity_month,
    cd.year  AS cohort_year,
    cd.month AS cohort_month_num,
    ad.year  AS activity_year,
    ad.month AS activity_month_num,
    -- months_since_cohort = number of months between cohort_month and activity_month
    ((EXTRACT(YEAR  FROM j.activity_month)::int * 12 +
      EXTRACT(MONTH FROM j.activity_month)::int)
     -
     (EXTRACT(YEAR  FROM j.cohort_month)::int * 12 +
      EXTRACT(MONTH FROM j.cohort_month)::int)
    ) AS months_since_cohort,
    j.cohort_size,
    j.active_customers,
    j.orders,
    j.revenue_gbp,
    CASE
      WHEN j.cohort_size > 0
      THEN ROUND(j.active_customers::numeric / j.cohort_size::numeric, 4)
      ELSE NULL
    END AS retention_rate
  FROM joined j
  LEFT JOIN mart.dim_date cd ON cd.date_key = j.cohort_month
  LEFT JOIN mart.dim_date ad ON ad.date_key = j.activity_month
)
SELECT *
FROM final
ORDER BY cohort_month, activity_month;
;

CREATE INDEX IF NOT EXISTS ix_cohort_monthly_metrics_cohort
  ON mart.cohort_monthly_metrics(cohort_month);

CREATE INDEX IF NOT EXISTS ix_cohort_monthly_metrics_months_since
  ON mart.cohort_monthly_metrics(months_since_cohort);

-- ----------------------------------------------------------------------
-- 3) cohort_retention_curve
--     - Grain: one row per (cohort_month, months_since_cohort)
--     - Aggregates across all activity_months for each offset
--       (handy for heatmaps in dashboards)
-- ----------------------------------------------------------------------
DROP TABLE IF EXISTS mart.cohort_retention_curve;
CREATE TABLE mart.cohort_retention_curve AS
SELECT
  cohort_month,
  cohort_year,
  cohort_month_num,
  months_since_cohort,
  cohort_size,
  active_customers,
  orders,
  revenue_gbp,
  retention_rate
FROM mart.cohort_monthly_metrics
ORDER BY cohort_month, months_since_cohort;

CREATE INDEX IF NOT EXISTS ix_cohort_retention_curve_cohort_offset
  ON mart.cohort_retention_curve(cohort_month, months_since_cohort);

-- ======================================================================
-- End of cohorts.sql
-- ======================================================================
