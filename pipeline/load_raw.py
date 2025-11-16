# pipeline/load_raw.py
import psycopg2
import pandas as pd
import os
from io import StringIO

# ----------------------------------------------------------------------
# Database connection
# ----------------------------------------------------------------------
conn = psycopg2.connect(
    dbname=os.getenv("PGDATABASE"),
    user=os.getenv("PGUSER"),
    password=os.getenv("PGPASSWORD"),
    host=os.getenv("PGHOST"),
    port=os.getenv("PGPORT", "5432"),
)
cur = conn.cursor()

# ----------------------------------------------------------------------
# 1) Load raw_sales_data.csv → raw_sales
# ----------------------------------------------------------------------
sales_csv_path = "data/raw_sales_data.csv"

print("[load_raw] Loading raw_sales_data.csv → raw_sales")

cur.execute("DROP TABLE IF EXISTS raw_sales;")
cur.execute("""
    CREATE TABLE raw_sales (
        invoice_no   TEXT,
        stock_code   TEXT,
        description  TEXT,
        quantity     INTEGER,
        invoice_ts   TIMESTAMP,
        unit_price   NUMERIC,
        customer_id  TEXT,
        country      TEXT
    );
""")

sales_copy_sql = """
COPY raw_sales (invoice_no, stock_code, description, quantity, invoice_ts, unit_price, customer_id, country)
FROM STDIN WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', QUOTE '"');
"""

with open(sales_csv_path, "r", encoding="cp1252", newline="") as f:
    cur.copy_expert(sales_copy_sql, f)

print("[load_raw] raw_sales loaded.")

# ----------------------------------------------------------------------
# 2) Load ad_spend.csv → raw_ad_spend
# ----------------------------------------------------------------------
ad_csv_path = "data/ad_spend.csv"

print("[load_raw] Loading ad_spend.csv → raw_ad_spend")

cur.execute("DROP TABLE IF EXISTS raw_ad_spend;")
cur.execute("""
    CREATE TABLE raw_ad_spend (
        date    DATE,
        channel TEXT,
        spend   NUMERIC
    );
""")

ad_df = pd.read_csv(ad_csv_path)

# Convert DF → text buffer for COPY
buffer = StringIO()
ad_df.to_csv(buffer, index=False, header=False)
buffer.seek(0)

cur.copy_from(buffer, "raw_ad_spend", sep=",")

print("[load_raw] raw_ad_spend loaded.")

# ----------------------------------------------------------------------
# Finalize
# ----------------------------------------------------------------------
conn.commit()
cur.close()
conn.close()

print("[load_raw] Completed loading all raw sources.")
