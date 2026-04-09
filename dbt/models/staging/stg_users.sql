with source as (
    select *
    from {{ ref('users_data') }}
)

select
    id as client_id,
    current_age,
    retirement_age,
    birth_year,
    birth_month,
    gender,
    address,
    latitude,
    longitude,
    CAST(per_capita_income AS FLOAT64) as per_capita_income,
    CAST(yearly_income AS FLOAT64) as yearly_income,
    CAST(total_debt AS FLOAT64) as total_debt,
    credit_score,
    num_credit_cards
from source
