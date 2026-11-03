-- Bureau branch: raw.bureau + stg.bureau_balance_summary -> stg.bureau_enriched -> stg.bureau_summary.
-- NULL in bb_* columns means "no monthly history"; intentionally not COALESCEd.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

-- 1) Loan (sk_id_bureau) level: bureau + monthly balance summary
DROP TABLE IF EXISTS stg.bureau_enriched;

CREATE TABLE stg.bureau_enriched AS
SELECT
    br.*,
    bbs.bb_month_count,
    bbs.bb_ever_overdue,
    bbs.bb_ever_written_off,
    bbs.bb_serious_overdue_month_count,
    bbs.bb_worst_status_level,
    bbs.bb_avg_status_level,
    bbs.bb_total_status_score,
    bbs.bb_overdue_months_6m,
    bbs.bb_worst_status_6m,
    bbs.bb_overdue_months_12m,
    bbs.bb_worst_status_12m,
    bbs.bb_overdue_months_24m,
    bbs.bb_worst_status_24m
FROM raw.bureau br
LEFT JOIN stg.bureau_balance_summary bbs
    ON br.sk_id_bureau = bbs.sk_id_bureau;

-- Impossible dates (beyond ±50 years, updates in the future) -> NULL
UPDATE stg.bureau_enriched SET days_credit_enddate = NULL
WHERE ABS(days_credit_enddate) > 18250;

UPDATE stg.bureau_enriched SET days_enddate_fact = NULL
WHERE days_enddate_fact < -18250;

UPDATE stg.bureau_enriched SET days_credit_update = NULL
WHERE days_credit_update > 0 OR days_credit_update < -18250;

-- 2) Customer (sk_id_curr) level summary
DROP TABLE IF EXISTS stg.bureau_summary;

CREATE TABLE stg.bureau_summary AS
SELECT
    sk_id_curr,
    -- original columns (identical to the previous definition)
    COUNT(*)                                        AS bureau_loan_count,
    COUNT(*) FILTER (WHERE credit_active = 'Active') AS bureau_active_loan_count,
    SUM(amt_credit_sum_debt)                        AS bureau_total_debt,
    MAX(amt_credit_max_overdue)                     AS bureau_max_overdue_amount,
    SUM(cnt_credit_prolong)                         AS bureau_total_prolong_count,
    -- new columns derived from bureau_balance
    COUNT(bb_month_count)                           AS bureau_loans_with_history_count,
    MAX(bb_ever_overdue)                            AS bureau_any_loan_ever_overdue,
    MAX(bb_ever_written_off)                        AS bureau_any_ever_written_off,
    SUM(bb_serious_overdue_month_count)             AS bureau_total_serious_overdue_months,
    MAX(bb_worst_status_level)                      AS bureau_worst_status_level,
    AVG(bb_avg_status_level)                        AS bureau_avg_status_level
FROM stg.bureau_enriched
GROUP BY sk_id_curr;

COMMIT;
