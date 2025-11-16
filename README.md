📊 E-Commerce Revenue, Marketing & Business Intelligence Pipeline
End-to-End SQL ETL, Data Warehousing & Power BI Analytics Project

This project is a complete, production-style Business Intelligence pipeline built to demonstrate real-world data engineering, analytics, and reporting skills. It reproduces the full lifecycle of a BI system:

Data Ingestion → Cleaning & Transformation → Dimensional Modeling → Aggregations → Quality Checks → Marketing Enrichment → Business Dashboards

The system ingests e-commerce transaction data and marketing ad spend, builds a star-schema warehouse using PostgreSQL, and visualizes insights using Power BI. Everything runs inside Docker for reproducibility.

🚀 Project Highlights
✔ Fully Automated ETL Pipeline

Python ingestion (load_raw.py)

SQL-based staging, cleansing, and transformations

Automatic dimensional modeling (dim_date, dim_customer, dim_product)

Fact table generation (orders, order_items)

Daily revenue aggregation table for reporting (agg_daily_revenue)

Marketing ad spend enrichment (ad_spend)

Cohort analysis output

Data quality checks built directly in SQL

✔ Modern Data Architecture Patterns

Raw → Staging → Warehouse (DIM/FACT) → Marts

Star schema optimized for BI tools

Daily aggregates for cost-efficient analytics

Incremental-load–friendly structure (partition-ready)

✔ Robust SQL Skills

Window functions

CTE pipelines

Surrogate key generation

Deduplication

Date normalization & time intelligence

Data quality detection logic

Cohort modeling

✔ Business Value

This project answers real BI questions:

Which marketing channels drive the highest ROAS?

How does ad spend relate to daily revenue?

Which products and countries contribute most to sales?

How are new vs returning customers trending?

What does customer retention look like?

Are there data quality issues affecting reporting accuracy?

🛠 Tech Stack
Languages

Python

SQL (PostgreSQL dialect)

Tools

Docker (multi-container environment)

PostgreSQL 17

Power BI Desktop

Pandas / psycopg2

DAX

Data Modeling

Kimball-style dimensional modeling

Star schemas, fact & dimension tables

Aggregates + cohorts

📁 Repository Structure
.
├── data/
│   ├── raw_sales_data.csv
│   ├── ad_spend.csv
│
├── pipeline/
│   ├── load_raw.py                 # Load raw CSVs into Postgres
│   ├── backfill.py (optional)
│   ├── monitor.py  (optional)
│
├── sql/
│   ├── staging_cleaning.sql        # Staging transforms & cleaning
│   ├── dims_facts.sql              # Dimension + fact models
│   ├── aggregates_daily.sql        # Daily revenue aggregates
│   ├── cohorts.sql                 # Cohort creation
│   ├── quality_checks.sql          # Data validation tests
│
├── docker/
│   ├── Dockerfile.etl              # Python ETL image
│   ├── Dockerfile.db (optional)
│
├── docker-compose.yml
│
└── powerbi/
    ├── Ecommerce Revenue & Marketing Performance.pbix
    └── (Exported screenshots)

🏗 How the Pipeline Works
1️⃣ Raw Layer (Landing Zone)

Python loads CSV files into Postgres:

raw_sales – e-commerce transactions

raw_ad_spend – daily marketing spend by channel

Each raw table mirrors the structure of the input source with minimal changes.

2️⃣ Staging Layer (Data Standardization)

staging_cleaning.sql cleans and normalizes both datasets:

Sales:

Fix encoding issues

Clean descriptions / remove Nulls

Convert text timestamps to real timestamps

Remove negative/zero quantities

Remove cancelled/refunded invoices

Map inconsistent country names

Deduplicate rows

Ad Spend:

Normalize channels

Validate date ranges

Deduplicate

Convert strings → numeric

Constrain to valid sales-date window

Each table ends with a clean, consistent schema ready for modeling.

3️⃣ Dimensional Modeling (Warehouse Layer)

dims_facts.sql builds the star schema:

Dimensions

dim_date — full calendar table

dim_customer — customer master info

dim_product — SKU-level product dimension

Facts

fct_orders — invoice-level orders

fct_order_items — item-level transactional granularity

All surrogate keys are generated for BI compatibility.

4️⃣ Daily Revenue Aggregation (Data Mart)

aggregates_daily.sql produces mart.agg_daily_revenue, containing:

Revenue

Orders

AOV

Active customers

New vs returning customers

Revenue by country

Date keys for Power BI filtering

This table powers modern BI dashboards efficiently.

5️⃣ Cohort Modeling

cohorts.sql generates:

Monthly acquisition cohorts

Months-since-first-purchase

Retention counts

Retention rates

Perfect for a retention heatmap in Power BI.

6️⃣ Data Quality Checks

quality_checks.sql includes automated tests:

Orphaned fact records

Null keys in dimensions/facts

Negative revenue / invalid quantities

Unexpected date gaps

Ad spend without matching dates

Overlapping or duplicate records

Revenue outlier detection

Results log into a dedicated quality_check_results table to monitor data freshness & validity.

📊 Business Intelligence (Power BI)

The Power BI file contains 4 pages:

Page 1 – Executive Performance Overview

Total revenue, spend, orders, ROAS

Trend lines

ROAS over time

Slicers (date, channel, country)

Page 2 – Channel Performance

Spend by channel

ROAS by channel

Spend over time

Scatter: Spend vs ROAS

Channel contribution to total spend

Page 3 – Product & Customer Insights

Top products by revenue

Revenue by country

Customer mix

AOV trend

Page 4 – Cohort Retention Analysis

Cohort heatmap

Month-over-month retention trends

Customer lifetime behavior insights

🎯 Key Skills Demonstrated
Business Intelligence / Analytics

ROAS, MER, LTV, AOV

Customer segmentation & retention analysis

Channel performance evaluation

Revenue forecasting foundations

KPI storytelling with dashboards

Data Engineering & Modeling

ETL automation

Clean staging pipelines

Fact/dimensional modeling

Incremental & partition-ready design

Data quality frameworks

Power BI & DAX

Calculated measures

Calendar/date-intelligence

Visual selections, filters, slicers

KPI cards, trends, scatter, matrix visuals

Relationship modeling

🧪 How to Run Locally
1. Start PostgreSQL + ETL containers
docker compose up -d
docker compose run --rm etl    # loads raw → builds all tables

2. Connect Power BI

Use:

Server: localhost:5433

Database: analytics

Authentication: Database

User: postgres

Password: postgres

3. Refresh visuals

Open the .pbix file → Refresh.

📦 Data Sources
Online Retail Dataset (UCI Machine Learning Repository)

Modified, cleaned, and restructured for this warehouse.

Synthetic Ad Spend Dataset

Realistic ad spend values generated to support ROAS analysis.

📝 Future Enhancements

Airflow DAG for orchestrated ETL

Incremental backfills with partition logic

dbt refactoring

Real anomaly detection on revenue and spend

Forecasting models (Prophet / ARIMA)

CI/CD for warehouse tests (SQLFluff, Great Expectations)

🎉 Final Notes

This project demonstrates the full workflow of a modern BI/Data Analyst:

Working with raw messy data

Designing a warehouse

Writing high-quality SQL

Implementing automated pipelines

Building insightful dashboards

Communicating business impact

If you're a recruiter or reviewer:
This project represents real, job-ready business intelligence capability.