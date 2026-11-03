-- Bureau time windows: stg.bureau_enriched -> stg.bureau_window_summary (sk_id_curr level).
-- Windows are relative to the application date: 6m = 180 days, 12m = 365 days, 24m = 730 days.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.bureau_window_summary;

CREATE TABLE stg.bureau_window_summary AS
SELECT
    sk_id_curr,
    COUNT(*) FILTER (WHERE days_credit >= -180) AS fe_bureau_loan_count_6m,
    SUM(amt_credit_sum) FILTER (WHERE days_credit >= -180) AS fe_bureau_credit_sum_6m,
    SUM(amt_credit_sum_debt) FILTER (WHERE days_credit >= -180 AND credit_active = 'Active') AS fe_bureau_active_debt_6m,
    SUM(bb_overdue_months_6m) AS fe_bureau_overdue_months_6m,
    MAX(bb_worst_status_6m) AS fe_bureau_worst_status_6m,
    COUNT(*) FILTER (WHERE days_credit >= -365) AS fe_bureau_loan_count_12m,
    SUM(amt_credit_sum) FILTER (WHERE days_credit >= -365) AS fe_bureau_credit_sum_12m,
    SUM(amt_credit_sum_debt) FILTER (WHERE days_credit >= -365 AND credit_active = 'Active') AS fe_bureau_active_debt_12m,
    SUM(bb_overdue_months_12m) AS fe_bureau_overdue_months_12m,
    MAX(bb_worst_status_12m) AS fe_bureau_worst_status_12m,
    COUNT(*) FILTER (WHERE days_credit >= -730) AS fe_bureau_loan_count_24m,
    SUM(amt_credit_sum) FILTER (WHERE days_credit >= -730) AS fe_bureau_credit_sum_24m,
    SUM(amt_credit_sum_debt) FILTER (WHERE days_credit >= -730 AND credit_active = 'Active') AS fe_bureau_active_debt_24m,
    SUM(bb_overdue_months_24m) AS fe_bureau_overdue_months_24m,
    MAX(bb_worst_status_24m) AS fe_bureau_worst_status_24m,
    SUM(amt_credit_sum_debt) FILTER (WHERE credit_active = 'Active')
        / NULLIF(SUM(amt_credit_sum) FILTER (WHERE credit_active = 'Active'), 0) AS fe_bureau_active_debt_credit_ratio,
    MAX(days_credit) AS fe_bureau_days_since_last_credit,
    MAX(days_credit_enddate) FILTER (WHERE credit_active = 'Active') AS fe_bureau_latest_active_enddate,
    SUM(amt_credit_sum_overdue) FILTER (WHERE credit_active = 'Active') AS fe_bureau_active_overdue_amount,
    COUNT(*) FILTER (WHERE credit_active = 'Bad debt') AS fe_bureau_bad_debt_count
FROM stg.bureau_enriched
GROUP BY sk_id_curr;

COMMIT;
