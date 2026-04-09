select
    CAST(mcc_code AS INT64) as mcc,
    category_name
from {{ ref('mcc_codes') }}
