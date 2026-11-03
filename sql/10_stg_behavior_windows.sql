-- Behavioral time windows (sk_id_curr level): previous applications, installments, POS and credit card.
-- Windows are relative to the application date: 6m = 180 days / 6 months, 12m = 365 days / 12 months, 24m = 730 days / 24 months.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.prev_window_summary;

CREATE TABLE stg.prev_window_summary AS
SELECT
    sk_id_curr,
    COUNT(*) FILTER (WHERE days_decision >= -180) AS fe_prev_app_count_6m,
    COUNT(*) FILTER (WHERE days_decision >= -180 AND name_contract_status = 'Refused') AS fe_prev_refused_count_6m,
    SUM(amt_credit) FILTER (WHERE days_decision >= -180 AND name_contract_status = 'Approved') AS fe_prev_approved_credit_6m,
    COUNT(*) FILTER (WHERE days_decision >= -365) AS fe_prev_app_count_12m,
    COUNT(*) FILTER (WHERE days_decision >= -365 AND name_contract_status = 'Refused') AS fe_prev_refused_count_12m,
    SUM(amt_credit) FILTER (WHERE days_decision >= -365 AND name_contract_status = 'Approved') AS fe_prev_approved_credit_12m,
    COUNT(*) FILTER (WHERE days_decision >= -730) AS fe_prev_app_count_24m,
    COUNT(*) FILTER (WHERE days_decision >= -730 AND name_contract_status = 'Refused') AS fe_prev_refused_count_24m,
    SUM(amt_credit) FILTER (WHERE days_decision >= -730 AND name_contract_status = 'Approved') AS fe_prev_approved_credit_24m,
    MAX(days_decision) AS fe_prev_days_since_last_decision,
    MAX(days_decision) FILTER (WHERE name_contract_status = 'Refused') AS fe_prev_days_since_last_refusal
FROM stg.previous_application_enriched
GROUP BY sk_id_curr;

DROP TABLE IF EXISTS stg.installments_window_summary;

CREATE TABLE stg.installments_window_summary AS
WITH per_row AS (
    SELECT *, days_entry_payment - days_instalment AS days_diff
    FROM raw.installments_payments
)
SELECT
    sk_id_curr,
    COUNT(*) FILTER (WHERE days_instalment >= -180) AS fe_inst_count_6m,
    COUNT(*) FILTER (WHERE days_instalment >= -180 AND days_diff > 0) AS fe_inst_late_count_6m,
    AVG(GREATEST(days_diff, 0)) FILTER (WHERE days_instalment >= -180) AS fe_inst_avg_days_late_6m,
    COUNT(*) FILTER (WHERE days_instalment >= -180 AND amt_payment < 0.99 * amt_instalment) AS fe_inst_underpaid_count_6m,
    SUM(amt_payment) FILTER (WHERE days_instalment >= -180)
        / NULLIF(SUM(amt_instalment) FILTER (WHERE days_instalment >= -180), 0) AS fe_inst_payment_ratio_6m,
    COUNT(*) FILTER (WHERE days_instalment >= -365) AS fe_inst_count_12m,
    COUNT(*) FILTER (WHERE days_instalment >= -365 AND days_diff > 0) AS fe_inst_late_count_12m,
    AVG(GREATEST(days_diff, 0)) FILTER (WHERE days_instalment >= -365) AS fe_inst_avg_days_late_12m,
    COUNT(*) FILTER (WHERE days_instalment >= -365 AND amt_payment < 0.99 * amt_instalment) AS fe_inst_underpaid_count_12m,
    SUM(amt_payment) FILTER (WHERE days_instalment >= -365)
        / NULLIF(SUM(amt_instalment) FILTER (WHERE days_instalment >= -365), 0) AS fe_inst_payment_ratio_12m,
    COUNT(*) FILTER (WHERE days_instalment >= -730) AS fe_inst_count_24m,
    COUNT(*) FILTER (WHERE days_instalment >= -730 AND days_diff > 0) AS fe_inst_late_count_24m,
    AVG(GREATEST(days_diff, 0)) FILTER (WHERE days_instalment >= -730) AS fe_inst_avg_days_late_24m,
    COUNT(*) FILTER (WHERE days_instalment >= -730 AND amt_payment < 0.99 * amt_instalment) AS fe_inst_underpaid_count_24m,
    SUM(amt_payment) FILTER (WHERE days_instalment >= -730)
        / NULLIF(SUM(amt_instalment) FILTER (WHERE days_instalment >= -730), 0) AS fe_inst_payment_ratio_24m
FROM per_row
GROUP BY sk_id_curr;

DROP TABLE IF EXISTS stg.pos_window_summary;

CREATE TABLE stg.pos_window_summary AS
SELECT
    sk_id_curr,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -6) AS fe_pos_max_dpd_6m,
    COUNT(*) FILTER (WHERE months_balance >= -6 AND sk_dpd > 0) AS fe_pos_overdue_months_6m,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -12) AS fe_pos_max_dpd_12m,
    COUNT(*) FILTER (WHERE months_balance >= -12 AND sk_dpd > 0) AS fe_pos_overdue_months_12m,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -24) AS fe_pos_max_dpd_24m,
    COUNT(*) FILTER (WHERE months_balance >= -24 AND sk_dpd > 0) AS fe_pos_overdue_months_24m
FROM raw.pos_cash_balance
GROUP BY sk_id_curr;

DROP TABLE IF EXISTS stg.cc_window_summary;

CREATE TABLE stg.cc_window_summary AS
SELECT
    sk_id_curr,
    AVG(amt_balance / NULLIF(amt_credit_limit_actual, 0)) FILTER (WHERE months_balance >= -6) AS fe_cc_avg_utilization_6m,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -6) AS fe_cc_max_dpd_6m,
    COUNT(*) FILTER (WHERE months_balance >= -6 AND amt_payment_current < amt_inst_min_regularity) AS fe_cc_below_min_count_6m,
    SUM(amt_drawings_atm_current) FILTER (WHERE months_balance >= -6) AS fe_cc_atm_drawings_6m,
    AVG(amt_balance / NULLIF(amt_credit_limit_actual, 0)) FILTER (WHERE months_balance >= -12) AS fe_cc_avg_utilization_12m,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -12) AS fe_cc_max_dpd_12m,
    COUNT(*) FILTER (WHERE months_balance >= -12 AND amt_payment_current < amt_inst_min_regularity) AS fe_cc_below_min_count_12m,
    SUM(amt_drawings_atm_current) FILTER (WHERE months_balance >= -12) AS fe_cc_atm_drawings_12m,
    AVG(amt_balance / NULLIF(amt_credit_limit_actual, 0)) FILTER (WHERE months_balance >= -24) AS fe_cc_avg_utilization_24m,
    MAX(sk_dpd) FILTER (WHERE months_balance >= -24) AS fe_cc_max_dpd_24m,
    COUNT(*) FILTER (WHERE months_balance >= -24 AND amt_payment_current < amt_inst_min_regularity) AS fe_cc_below_min_count_24m,
    SUM(amt_drawings_atm_current) FILTER (WHERE months_balance >= -24) AS fe_cc_atm_drawings_24m
FROM raw.credit_card_balance
GROUP BY sk_id_curr;

COMMIT;
