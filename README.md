# Walmart Data Platform

A batch data platform on Databricks that models Walmart retail operations end to end. An
operational Postgres database feeds the lakehouse hourly through change data capture, a
low-velocity feed is attached directly from S3, and dbt transforms both into a star schema with
slowly changing dimensions. Airflow runs the schedule as a separate, containerised deployment.

---

## Source database: ghost.build

The operational Postgres instance is provisioned with **ghost.build**, an agentic database
service, with a SQL chatbot on top for natural-language querying.

Standing up a realistic source system is normally the tedious part of a data project, so most
skip it and start from a CSV — which quietly removes any chance of doing real incremental work,
because a file has no change history. ghost.build removes that friction: the schema, the
relationships and the seeded data are described rather than assembled, and the database comes
back live and connectable.

That mattered here in three ways:

- **A real write-ahead log**, which is what makes CDC a genuine design choice rather than a label
  on a full reload.
- **A proper relational schema** — customers, employees, orders, order items, products and stores
  as related tables — so the dimensional model is derived from real keys.
- **Mutable records**, which give the snapshot-based dimensions something to actually capture.

---

## Two ingestion paths, and why

Not all source data changes at the same rate, and treating it as though it does burns compute for
nothing.

**Transactional data, via CDC.** Customers, employees, orders, order items, products and stores
change continuously, so they follow the change stream. Each run moves only the rows that changed.

**Customer reviews, via an S3 external location.** Reviews do not need an hourly refresh. Running
them through the same pipeline would mean repeatedly re-processing data that had not meaningfully
changed. Instead they sit in an S3 bucket registered in Databricks as an external location, read
in place.

That means no copy step, no ingestion job to monitor, no duplicate copy to drift out of sync, no
AWS credentials in pipeline code, and a refresh cadence fully decoupled from the hourly schedule.
New files in the bucket are queryable without any pipeline run at all.

This is the decision the architecture is built around: match the ingestion mechanism to how often
the data actually changes.

---

## Transformation layers

**`source/`** — `sources.yml` declares every upstream object, both the CDC-landed tables and the
S3 external table, so lineage is complete from the first hop.

**`silver_t/`** — one typed model per entity. Casting, renaming, deduplication and null handling
only; no cross-entity joins. Tests and docs live in `properties.yml`.

**`silver_b/`** — `obt_b.sql` joins the entities into one wide table. This is the conformed view:
one definition per business concept, and one meaningful place to validate.

**`gold/`** — `eph_*` models carve the wide table back into per-entity shapes. Materialized as
ephemeral, they compile into CTEs rather than physical tables, so the logic is reusable without
adding warehouse objects. `fact_orders.sql` is the central fact table, on the order grain.

**`snapshots/`** — `dim_customers`, `dim_employees`, `dim_orders`, `dim_products` and `dim_stores`
are dbt snapshots. When a customer relocates or a product is repriced, the old row is retained
with validity timestamps instead of overwritten — Type 2 SCD, and what makes point-in-time joins
correct.

**`macros/custom_schema.sql`** overrides dbt's schema naming so the medallion layout in the
project is reflected in the warehouse.

---

## Orchestration

Airflow runs as its own containerised deployment with its own dependencies and lifecycle, not as
a wrapper around the lakehouse. `dags/orchestrate.py` defines the pipeline.

It owns scheduling, dependency ordering and retries, and holds no business logic — that stays in
dbt, where it can be developed and tested without the scheduler in the loop.

---

## Technology stack

| Layer | Technology |
|-------|-----------|
| Source database | Postgres via ghost.build |
| Interactive access | SQL chatbot |
| Change capture | CDC |
| Object storage | AWS S3, read in place |
| Storage integration | Databricks external location |
| Lakehouse | Databricks, Delta Lake |
| Transformation | dbt (`dbt-core`, `dbt-databricks`) |
| Orchestration | Apache Airflow 3.x on Docker Compose |
| Tooling | Python 3.11, `uv` |

---

## Data quality

Checks run at the One Big Table, upstream of the gold layer, so a failure stops bad data before
it reaches anything a consumer queries:

- Uniqueness and not-null on primary and join keys
- Referential integrity between fact and dimensions
- Accepted values on categorical columns
- `test_obt.sql`, a singular test asserting a condition that only holds once entities are joined

---

## Design decisions

**Ingestion matched to change rate.** Hourly CDC for transactional tables; an external location
for review data that does not change hourly.

**Raw data untouched.** The landing layer is append-only, so fixing business logic means a re-run,
not a re-extraction.

**One Big Table before dimensional modelling.** One definition per concept and one validation
point, so the star schema is built on data that already passed its checks.

**Ephemeral in gold.** The `eph_*` models exist for reuse, not for querying, so they compile away
rather than becoming objects to store and govern.

**Snapshots for dimensions.** Overwriting destroys history; snapshots keep it with validity
windows.

---

## Limitations and next steps

Development-scale data, no CI, and default Airflow alerting. Next: CI running the full build and
test suite on pull requests, source freshness monitoring, broader incremental coverage in gold,
and a BI layer on the fact and dimension models.

---

Nandesh Kanagaraju — [github.com/nandeshkanagaraju](https://github.com/nandeshkanagaraju)
