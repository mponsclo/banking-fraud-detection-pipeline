with source as (
    select *
    from {{ ref('cards_data') }}
)

select
    id as card_id,
    client_id,
    card_brand,
    card_type,
    card_number,
    expires,
    cvv,
    has_chip = 'YES' as has_chip,
    num_cards_issued,
    CAST(credit_limit AS FLOAT64) as credit_limit,
    acct_open_date,
    year_pin_last_changed,
    card_on_dark_web = 'Yes' as card_on_dark_web,
    -- derived: parse expiry date (MM/YYYY format)
    DATE(
        CAST(SPLIT(expires, '/')[SAFE_OFFSET(1)] AS INT64),
        CAST(SPLIT(expires, '/')[SAFE_OFFSET(0)] AS INT64),
        1
    ) as expiry_date
from source
