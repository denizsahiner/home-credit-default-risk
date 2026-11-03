-- Credit card branch: raw.credit_card_balance -> stg.credit_card_summary (sk_id_prev level).
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.credit_card_summary;

CREATE TABLE stg.credit_card_summary AS
WITH with_max_limit AS (
  SELECT
    *,
    MAX(AMT_CREDIT_LIMIT_ACTUAL) OVER (PARTITION BY SK_ID_PREV) AS max_limit
  FROM raw.credit_card_balance
)
SELECT
  SK_ID_PREV,

  COUNT(*)                                                              AS cc_month_count,

  -- Limit utilization (uses the loan's highest limit instead of that month's limit)
  AVG(AMT_BALANCE / NULLIF(max_limit, 0))                               AS cc_avg_utilization,
  MAX(AMT_BALANCE / NULLIF(max_limit, 0))                               AS cc_max_utilization,

  -- Did this loan ever have a month with limit = 0
  MAX(CASE WHEN AMT_CREDIT_LIMIT_ACTUAL = 0 THEN 1 ELSE 0 END)          AS cc_had_zero_limit_month,

  -- Behavior: cash withdrawal frequency and amount
  SUM(AMT_DRAWINGS_ATM_CURRENT)                                         AS cc_total_atm_drawings,
  SUM(CNT_DRAWINGS_ATM_CURRENT)                                         AS cc_atm_drawing_count,

  -- Payment discipline: is only the minimum being paid
  AVG(AMT_PAYMENT_CURRENT / NULLIF(AMT_INST_MIN_REGULARITY, 0))         AS cc_avg_payment_to_min_ratio,
  SUM(CASE WHEN AMT_PAYMENT_CURRENT < AMT_INST_MIN_REGULARITY THEN 1 ELSE 0 END) AS cc_below_min_payment_count,

  -- Delinquency
  MAX(SK_DPD)                                                           AS cc_max_dpd,
  AVG(SK_DPD)                                                           AS cc_avg_dpd,
  SUM(CASE WHEN SK_DPD > 0 THEN 1 ELSE 0 END)                           AS cc_overdue_month_count,

  -- Status categories
  MAX(CASE WHEN NAME_CONTRACT_STATUS IN ('Active','Completed') 
           THEN 1 ELSE 0 END)                                          AS cc_ever_active,
  MAX(CASE WHEN NAME_CONTRACT_STATUS = 'Demand' 
           THEN 1 ELSE 0 END)                                          AS cc_ever_bad_status,
  MAX(CASE WHEN NAME_CONTRACT_STATUS IN ('Signed','Sent proposal','Approved','Refused') 
           THEN 1 ELSE 0 END)                                          AS cc_never_activated

FROM with_max_limit
GROUP BY SK_ID_PREV;

COMMIT;
