FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

ARG APP_USER=appuser
ARG APP_UID=10001
RUN useradd -m -u ${APP_UID} ${APP_USER}

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --upgrade pip && pip install -r /app/requirements.txt

COPY pipeline/ /app/pipeline/
COPY sql/ /app/sql/

RUN printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  ': "${PGHOST:?Set PGHOST}"; : "${PGPORT:=5432}"; : "${PGUSER:?Set PGUSER}"; : "${PGDATABASE:?Set PGDATABASE}";' \
  '' \
  'echo "[1/6] Loading raw data via Python..."' \
  'python /app/pipeline/load_raw.py' \
  '' \
  'echo "[2/6] Running staging_cleaning.sql..."' \
  'psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -f /app/sql/staging_cleaning.sql' \
  '' \
  'echo "[3/6] Running dims_facts.sql..."' \
  'psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -f /app/sql/dims_facts.sql' \
  '' \
  'echo "[4/6] Running aggregates_daily.sql..."' \
  'psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -f /app/sql/aggregates_daily.sql' \
  '' \
  'echo "[5/6] Running cohorts.sql..."' \
  'psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -f /app/sql/cohorts.sql' \
  '' \
  'echo "[6/6] Running quality_checks.sql..."' \
  'psql "host=$PGHOST port=$PGPORT user=$PGUSER dbname=$PGDATABASE" -f /app/sql/quality_checks.sql' \
  '' \
  'echo "ETL completed successfully."' \
  > /usr/local/bin/run_etl.sh && chmod +x /usr/local/bin/run_etl.sh

# Use non-root
USER ${APP_USER}

# Default command: run the end-to-end step (can be overridden)
CMD ["/usr/local/bin/run_etl.sh"]