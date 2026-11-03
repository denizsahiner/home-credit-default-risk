-- Previous application branch: raw.previous_application + installment/POS/card summaries
-- -> stg.previous_application_enriched -> stg.previous_application_summary.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

-- 1) Application (sk_id_prev) level
DROP TABLE IF EXISTS stg.previous_application_enriched;

CREATE TABLE stg.previous_application_enriched AS
SELECT
    pa.*,
    i.installment_count,
    i.avg_days_diff,
    i.worst_days_diff,
    i.days_diff_volatility,
    i.late_payment_count,
    i.missed_installment_count,
    i.avg_payment_ratio,
    i.worst_payment_ratio,
    i.underpaid_installment_count,
    i.version_change_increase_count,
    i.version_change_decrease_count,
    p.pos_month_count,
    p.pos_max_dpd,
    p.pos_avg_dpd,
    p.pos_overdue_month_count,
    p.pos_ever_active,
    p.pos_ever_bad_status,
    p.pos_never_activated,
    p.pos_term_change_count,
    p.pos_reached_completed,
    c.cc_month_count,
    c.cc_avg_utilization,
    c.cc_max_utilization,
    c.cc_had_zero_limit_month,
    c.cc_total_atm_drawings,
    c.cc_atm_drawing_count,
    c.cc_avg_payment_to_min_ratio,
    c.cc_below_min_payment_count,
    c.cc_max_dpd,
    c.cc_avg_dpd,
    c.cc_overdue_month_count,
    c.cc_ever_active,
    c.cc_ever_bad_status,
    c.cc_never_activated,
    -- only meaningful for approved applications: elsewhere amt_credit is not an actual loan
    CASE WHEN pa.name_contract_status = 'Approved'
         THEN pa.amt_credit / NULLIF(pa.amt_application, 0) END   AS credit_to_application_ratio,
    CASE WHEN pa.code_reject_reason IN ('HC','LIMIT','SCO','SCOFR')
         THEN 1 ELSE 0 END                                        AS is_credit_related_rejection
FROM raw.previous_application pa
LEFT JOIN stg.installments_summary i ON pa.sk_id_prev = i.sk_id_prev
LEFT JOIN stg.pos_cash_summary p     ON pa.sk_id_prev = p.sk_id_prev
LEFT JOIN stg.credit_card_summary c  ON pa.sk_id_prev = c.sk_id_prev;

-- 365243 date placeholder -> NULL
UPDATE stg.previous_application_enriched SET days_first_drawing = NULL WHERE days_first_drawing = 365243;
UPDATE stg.previous_application_enriched SET days_first_due = NULL WHERE days_first_due = 365243;
UPDATE stg.previous_application_enriched SET days_last_due_1st_version = NULL WHERE days_last_due_1st_version = 365243;
UPDATE stg.previous_application_enriched SET days_last_due = NULL WHERE days_last_due = 365243;
UPDATE stg.previous_application_enriched SET days_termination = NULL WHERE days_termination = 365243;

-- 2) Customer (sk_id_curr) level summary
DROP TABLE IF EXISTS stg.previous_application_summary;

CREATE TABLE stg.previous_application_summary AS
SELECT
    sk_id_curr,
    COUNT(*)                                                      AS prev_app_count,
    COUNT(*) FILTER (WHERE name_contract_status = 'Approved')     AS prev_approved_count,
    COUNT(*) FILTER (WHERE name_contract_status = 'Refused')      AS prev_refused_count,
    COUNT(*) FILTER (WHERE name_contract_status = 'Canceled')     AS prev_canceled_count,
    COUNT(*) FILTER (WHERE name_contract_status = 'Unused offer') AS prev_unused_offer_count,
    COUNT(*) FILTER (WHERE is_credit_related_rejection = 1)       AS prev_credit_related_rejection_count,
    AVG(credit_to_application_ratio)                              AS prev_avg_credit_to_application_ratio,
    MIN(credit_to_application_ratio)                              AS prev_min_credit_to_application_ratio,
    MAX(CASE WHEN name_client_type = 'Repeater' THEN 1 ELSE 0 END) AS prev_ever_repeater,
    AVG(avg_days_diff)                                            AS prev_avg_days_diff,
    MAX(worst_days_diff)                                          AS prev_worst_days_diff,
    SUM(late_payment_count)                                       AS prev_total_late_payments,
    SUM(missed_installment_count)                                 AS prev_total_missed_installments,
    AVG(avg_payment_ratio)                                        AS prev_avg_payment_ratio,
    SUM(version_change_decrease_count)                            AS prev_total_version_decrease,
    MAX(pos_max_dpd)                                              AS prev_pos_max_dpd,
    SUM(pos_overdue_month_count)                                  AS prev_pos_total_overdue_months,
    MAX(pos_ever_bad_status)                                      AS prev_pos_ever_bad_status,
    AVG(cc_avg_utilization)                                       AS prev_cc_avg_utilization,
    MAX(cc_max_utilization)                                       AS prev_cc_max_utilization,
    SUM(cc_below_min_payment_count)                               AS prev_cc_total_below_min_payments,
    MAX(cc_ever_bad_status)                                       AS prev_cc_ever_bad_status
FROM stg.previous_application_enriched
GROUP BY sk_id_curr;

COMMIT;
