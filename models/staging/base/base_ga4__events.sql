{% set partitions_to_replace = ['current_date'] %}
{% for i in range(var('static_incremental_days')) %}
    {% set partitions_to_replace = partitions_to_replace.append('date_sub(current_date, interval ' + (i+1)|string + ' day)') %}
{% endfor %}


{% set start_date = var('start_date', none) %}
{% set end_date = var('end_date', none) %}

{{ log("Initial start_date: " ~ start_date, info=True) }}
{{ log("Initial end_date: " ~ end_date, info=True) }}


{% if execute %}
{% if start_date and end_date %}
    {{ log("Running with start_date: " ~ start_date, info=True) }}
    {{ log("Running with end_date: " ~ end_date, info=True) }}

    {% set formatted_start_date = start_date[:4] ~ '-' ~ start_date[4:6] ~ '-' ~ start_date[6:] %}
    {% set formatted_end_date = end_date[:4] ~ '-' ~ end_date[4:6] ~ '-' ~ end_date[6:] %}

    {{ log("Formatted start_date: " ~ formatted_start_date, info=True) }}
    {{ log("Formatted end_date: " ~ formatted_end_date, info=True) }}

    {% set date_array_query %}
    {{ generate_date_array(formatted_start_date, formatted_end_date) }}
    {% endset %}

    {% set results = run_query(date_array_query) %}
    {% set partitions_to_replace = [] %}
    
    {% set partitions_to_replace = results[0]['date_array'] %}

{% endif %}
{% endif %}


{{ log("Partitions to replace: " ~ partitions_to_replace, info=True) }}

{{
    config(
        pre_hook="{{ ga4.combine_property_data() }}" if var('combined_dataset', false) else "",
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        partition_by={
            "field": "event_date_dt",
            "data_type": "date",
        },
        partitions = partitions_to_replace,
        cluster_by=['event_name', 'stream_id']
    )
}}

with source as (
    select
        {{ ga4.base_select_source() }}
    from {{ source('ga4', 'events') }}
    where cast(left(replace(_table_suffix, 'intraday_', ''), 8) as int64) >= {{var('start_date')}}
    {% if var('end_date') is not none %}
        and cast(left(replace(_table_suffix, 'intraday_', ''), 8) as int64) <= {{ var('end_date')}}
    {% endif %}
    {% if is_incremental() and var('end_date') is none %}
        and parse_date('%Y%m%d', left(replace(_table_suffix, 'intraday_', ''), 8)) in ({{ partitions_to_replace | join(',') }})
    {% endif %}
),
renamed as (
    select
        {{ ga4.base_select_renamed() }}
    from source
)

select * from renamed
qualify row_number() over(partition by event_date_dt, stream_id, user_pseudo_id, session_id, event_name, event_timestamp, to_json_string(ARRAY(SELECT params FROM UNNEST(event_params) AS params ORDER BY key))) = 1
