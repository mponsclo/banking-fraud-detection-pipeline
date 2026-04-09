-- Monthly expense aggregation per client, used for Task 4 (expense forecasting)
select
    client_id,
    DATE_TRUNC(transaction_date, MONTH) as expense_month,
    SUM(case when amount < 0 then ABS(amount) else 0 end) as total_expenses,
    COUNT(case when amount < 0 then 1 end) as num_expense_transactions,
    AVG(case when amount < 0 then ABS(amount) end) as avg_expense_amount,
    MAX(case when amount < 0 then ABS(amount) end) as max_expense_amount,
    SUM(case when amount > 0 then amount else 0 end) as total_earnings,
    COUNT(case when amount > 0 then 1 end) as num_earning_transactions,
    COUNT(*) as total_transactions
from {{ ref('int_transactions_enriched') }}
group by client_id, DATE_TRUNC(transaction_date, MONTH)
order by client_id, expense_month
