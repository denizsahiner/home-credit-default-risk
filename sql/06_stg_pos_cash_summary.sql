-- POS branch: raw.pos_cash_balance -> stg.pos_cash_summary (sk_id_prev level).
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.pos_cash_summary;

CREATE TABLE stg.pos_cash_summary AS
SELECT
  SK_ID_PREV,
  COUNT(*)                                                              AS pos_month_count,
  MAX(SK_DPD)                                                           AS pos_max_dpd,
  AVG(SK_DPD)                                                           AS pos_avg_dpd,
  SUM(CASE WHEN SK_DPD > 0 THEN 1 ELSE 0 END)                           AS pos_overdue_month_count,
  MAX(CASE WHEN NAME_CONTRACT_STATUS IN ('Active','Completed') 
           THEN 1 ELSE 0 END)                                          AS pos_ever_active,
  MAX(CASE WHEN NAME_CONTRACT_STATUS IN ('Demand','Amortized debt') 
           THEN 1 ELSE 0 END)                                          AS pos_ever_bad_status,
  MAX(CASE WHEN NAME_CONTRACT_STATUS IN ('Signed','Approved','Returned to the store','Canceled') 
           THEN 1 ELSE 0 END)                                          AS pos_never_activated,
  COUNT(DISTINCT CNT_INSTALMENT)                                        AS pos_term_change_count,
  MAX(CASE WHEN NAME_CONTRACT_STATUS = 'Completed' THEN 1 ELSE 0 END)   AS pos_reached_completed
FROM raw.pos_cash_balance
GROUP BY SK_ID_PREV;

COMMIT;
