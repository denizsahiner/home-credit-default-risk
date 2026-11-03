-- Model feature tables: stg.application + bureau + previous_application summaries + fe_* features.
-- mart.features_application is the training data, mart.features_application_test the application test data; columns match (except target).
-- Customers without records get 0 in count columns; the *_has_record flags keep that distinction.
-- fe_ prefixed columns come from feature engineering; the baseline notebook excludes them.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

CREATE TEMP TABLE features ON COMMIT DROP AS
SELECT
  a.*,                                   -- cleaned application, including days_employed_anom and dataset

  -- BUREAU
  COALESCE(b.bureau_loan_count, 0)                AS bureau_loan_count,
  COALESCE(b.bureau_active_loan_count, 0)         AS bureau_active_loan_count,
  COALESCE(b.bureau_total_debt, 0)                AS bureau_total_debt,
  b.bureau_max_overdue_amount,
  COALESCE(b.bureau_total_prolong_count, 0)       AS bureau_total_prolong_count,
  COALESCE(b.bureau_loans_with_history_count, 0)  AS bureau_loans_with_history_count,
  b.bureau_any_loan_ever_overdue,
  b.bureau_any_ever_written_off,
  b.bureau_total_serious_overdue_months,
  b.bureau_worst_status_level,
  b.bureau_avg_status_level,
  (b.sk_id_curr IS NOT NULL)::int                 AS bureau_has_record,

  -- PREVIOUS APPLICATION
  COALESCE(p.prev_app_count, 0)                   AS prev_app_count,
  COALESCE(p.prev_approved_count, 0)              AS prev_approved_count,
  COALESCE(p.prev_refused_count, 0)               AS prev_refused_count,
  COALESCE(p.prev_canceled_count, 0)              AS prev_canceled_count,
  COALESCE(p.prev_unused_offer_count, 0)          AS prev_unused_offer_count,
  COALESCE(p.prev_credit_related_rejection_count, 0) AS prev_credit_related_rejection_count,
  p.prev_avg_credit_to_application_ratio,
  p.prev_min_credit_to_application_ratio,
  p.prev_ever_repeater,
  p.prev_avg_days_diff,
  p.prev_worst_days_diff,
  p.prev_total_late_payments,
  p.prev_total_missed_installments,
  p.prev_avg_payment_ratio,
  p.prev_total_version_decrease,
  p.prev_pos_max_dpd,
  p.prev_pos_total_overdue_months,
  p.prev_pos_ever_bad_status,
  p.prev_cc_avg_utilization,
  p.prev_cc_max_utilization,
  p.prev_cc_total_below_min_payments,
  p.prev_cc_ever_bad_status,
  (p.sk_id_curr IS NOT NULL)::int                 AS prev_has_record,

  -- RATIOS
  a.amt_credit / NULLIF(a.amt_income_total, 0)      AS fe_credit_income_ratio,
  a.amt_annuity / NULLIF(a.amt_income_total, 0)     AS fe_annuity_income_ratio,
  a.amt_credit / NULLIF(a.amt_annuity, 0)           AS fe_credit_annuity_ratio,
  a.amt_goods_price / NULLIF(a.amt_credit, 0)       AS fe_goods_credit_ratio,
  a.amt_income_total / NULLIF(a.cnt_fam_members, 0) AS fe_income_per_person,
  a.days_employed::float / NULLIF(a.days_birth, 0)  AS fe_employed_birth_ratio,
  b.bureau_total_debt / NULLIF(a.amt_income_total, 0) AS fe_bureau_debt_income_ratio,

  -- EXT_SOURCE COMBINATIONS
  ext.ext_mean                                      AS fe_ext_source_mean,
  ext.ext_std                                       AS fe_ext_source_std,
  LEAST(a.ext_source_1, a.ext_source_2, a.ext_source_3)    AS fe_ext_source_min,
  GREATEST(a.ext_source_1, a.ext_source_2, a.ext_source_3) AS fe_ext_source_max,
  a.ext_source_1 * a.ext_source_2 * a.ext_source_3  AS fe_ext_source_prod,
  3 - ext.ext_count                                 AS fe_ext_source_null_count,

  -- TIME WINDOWS
  bw.fe_bureau_loan_count_6m,
  bw.fe_bureau_credit_sum_6m,
  bw.fe_bureau_active_debt_6m,
  bw.fe_bureau_overdue_months_6m,
  bw.fe_bureau_worst_status_6m,
  bw.fe_bureau_loan_count_12m,
  bw.fe_bureau_credit_sum_12m,
  bw.fe_bureau_active_debt_12m,
  bw.fe_bureau_overdue_months_12m,
  bw.fe_bureau_worst_status_12m,
  bw.fe_bureau_loan_count_24m,
  bw.fe_bureau_credit_sum_24m,
  bw.fe_bureau_active_debt_24m,
  bw.fe_bureau_overdue_months_24m,
  bw.fe_bureau_worst_status_24m,
  bw.fe_bureau_active_debt_credit_ratio,
  bw.fe_bureau_days_since_last_credit,
  bw.fe_bureau_latest_active_enddate,
  bw.fe_bureau_active_overdue_amount,
  bw.fe_bureau_bad_debt_count,
  pw.fe_prev_app_count_6m,
  pw.fe_prev_refused_count_6m,
  pw.fe_prev_approved_credit_6m,
  pw.fe_prev_app_count_12m,
  pw.fe_prev_refused_count_12m,
  pw.fe_prev_approved_credit_12m,
  pw.fe_prev_app_count_24m,
  pw.fe_prev_refused_count_24m,
  pw.fe_prev_approved_credit_24m,
  pw.fe_prev_days_since_last_decision,
  pw.fe_prev_days_since_last_refusal,
  iw.fe_inst_count_6m,
  iw.fe_inst_late_count_6m,
  iw.fe_inst_avg_days_late_6m,
  iw.fe_inst_underpaid_count_6m,
  iw.fe_inst_payment_ratio_6m,
  iw.fe_inst_count_12m,
  iw.fe_inst_late_count_12m,
  iw.fe_inst_avg_days_late_12m,
  iw.fe_inst_underpaid_count_12m,
  iw.fe_inst_payment_ratio_12m,
  iw.fe_inst_count_24m,
  iw.fe_inst_late_count_24m,
  iw.fe_inst_avg_days_late_24m,
  iw.fe_inst_underpaid_count_24m,
  iw.fe_inst_payment_ratio_24m,
  ow.fe_pos_max_dpd_6m,
  ow.fe_pos_overdue_months_6m,
  ow.fe_pos_max_dpd_12m,
  ow.fe_pos_overdue_months_12m,
  ow.fe_pos_max_dpd_24m,
  ow.fe_pos_overdue_months_24m,
  cw.fe_cc_avg_utilization_6m,
  cw.fe_cc_max_dpd_6m,
  cw.fe_cc_below_min_count_6m,
  cw.fe_cc_atm_drawings_6m,
  cw.fe_cc_avg_utilization_12m,
  cw.fe_cc_max_dpd_12m,
  cw.fe_cc_below_min_count_12m,
  cw.fe_cc_atm_drawings_12m,
  cw.fe_cc_avg_utilization_24m,
  cw.fe_cc_max_dpd_24m,
  cw.fe_cc_below_min_count_24m,
  cw.fe_cc_atm_drawings_24m

FROM stg.application a
LEFT JOIN stg.bureau_summary b               ON a.sk_id_curr = b.sk_id_curr
LEFT JOIN stg.previous_application_summary p ON a.sk_id_curr = p.sk_id_curr
LEFT JOIN stg.bureau_window_summary bw       ON a.sk_id_curr = bw.sk_id_curr
LEFT JOIN stg.prev_window_summary pw         ON a.sk_id_curr = pw.sk_id_curr
LEFT JOIN stg.installments_window_summary iw ON a.sk_id_curr = iw.sk_id_curr
LEFT JOIN stg.pos_window_summary ow          ON a.sk_id_curr = ow.sk_id_curr
LEFT JOIN stg.cc_window_summary cw           ON a.sk_id_curr = cw.sk_id_curr
CROSS JOIN LATERAL (
  SELECT AVG(v) AS ext_mean, STDDEV_POP(v) AS ext_std, COUNT(v) AS ext_count
  FROM unnest(ARRAY[a.ext_source_1, a.ext_source_2, a.ext_source_3]) AS v
) ext;

DROP TABLE IF EXISTS mart.features_application;

CREATE TABLE mart.features_application AS
SELECT * FROM features WHERE dataset = 'train';

ALTER TABLE mart.features_application DROP COLUMN dataset;

DROP TABLE IF EXISTS mart.features_application_test;

CREATE TABLE mart.features_application_test AS
SELECT * FROM features WHERE dataset = 'test';

ALTER TABLE mart.features_application_test DROP COLUMN dataset, DROP COLUMN target;

COMMIT;
