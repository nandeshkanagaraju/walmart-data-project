{{
    config(
        materialized = 'incremental',
        unique_key = 'customer_id',
        schema = 'silver_t',
        database = 'walmart'
    )
}}

SELECT
    *,
    CURRENT_TIMESTAMP() AS processed_at
FROM
    {{ source('walmart_databricks', 'customers') }}

{% if is_incremental()%}
    AND updated_timestamp > (SELECT COALESCE(MAX(updated_timestamp), '1900-01-01') FROM {{this}})
{% endif %} 