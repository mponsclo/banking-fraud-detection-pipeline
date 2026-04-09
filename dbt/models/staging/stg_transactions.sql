with source as (
    select *
    from {{ source('raw', 'transactions_data') }}
)

select
    id as transaction_id,
    date as transaction_date,
    client_id,
    card_id,
    amount,
    use_chip,
    merchant_id,
    merchant_city,
    merchant_state,
    CAST(zip AS STRING) as zip,
    mcc,
    NULLIF(TRIM(errors), '') as errors,

    -- error flag features (parsed from comma-separated errors field)
    case when LOWER(COALESCE(errors, '')) like '%bad cvv%' then 1 else 0 end as has_bad_cvv,
    case when LOWER(COALESCE(errors, '')) like '%bad expiration%' then 1 else 0 end as has_bad_expiration,
    case when LOWER(COALESCE(errors, '')) like '%bad card number%' then 1 else 0 end as has_bad_card_number,
    case when LOWER(COALESCE(errors, '')) like '%bad pin%' then 1 else 0 end as has_bad_pin,
    case when LOWER(COALESCE(errors, '')) like '%insufficient balance%' then 1 else 0 end as has_insufficient_balance,
    case when LOWER(COALESCE(errors, '')) like '%technical glitch%' then 1 else 0 end as has_technical_glitch,
    case when NULLIF(TRIM(errors), '') is not null then 1 else 0 end as has_any_error,

    -- online flag (strongest single signal: 28x fraud rate vs swipe)
    case when use_chip = 'Online Transaction' then 1 else 0 end as is_online
from source
