-- Installments branch: raw.installments_payments -> stg.installments_summary (sk_id_prev level).
-- days_diff = actual payment - due date: positive means late, negative means early.
-- payment_ratio is capped at 5: for tiny installments it reaches 194,250 and distorts averages.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.installments_summary;

CREATE TABLE stg.installments_summary AS
WITH ordered AS (
  SELECT
    SK_ID_PREV,
    NUM_INSTALMENT_NUMBER,
    NUM_INSTALMENT_VERSION,
    DAYS_INSTALMENT,
    DAYS_ENTRY_PAYMENT,
    AMT_INSTALMENT,
    AMT_PAYMENT,
    LAG(NUM_INSTALMENT_VERSION) OVER w AS prev_version,
    LAG(AMT_INSTALMENT) OVER w AS prev_amount
  FROM raw.installments_payments
  -- one installment number can have several payment rows; keep the result independent of row order
  WINDOW w AS (
    PARTITION BY SK_ID_PREV
    ORDER BY NUM_INSTALMENT_NUMBER, DAYS_INSTALMENT, DAYS_ENTRY_PAYMENT NULLS LAST,
             NUM_INSTALMENT_VERSION, AMT_INSTALMENT, AMT_PAYMENT
  )
),
per_row AS (
  SELECT
    SK_ID_PREV,
    (DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT) AS days_diff,
    CASE WHEN DAYS_ENTRY_PAYMENT IS NULL THEN 1 ELSE 0 END AS is_missed,
    LEAST(AMT_PAYMENT / NULLIF(AMT_INSTALMENT, 0), 5) AS payment_ratio,
    CASE WHEN AMT_PAYMENT / NULLIF(AMT_INSTALMENT, 0) < 0.99 THEN 1 ELSE 0 END AS is_underpaid,
    CASE WHEN NUM_INSTALMENT_VERSION <> prev_version AND AMT_INSTALMENT > prev_amount THEN 1 ELSE 0 END AS version_change_with_increase,
    CASE WHEN NUM_INSTALMENT_VERSION <> prev_version AND AMT_INSTALMENT < prev_amount THEN 1 ELSE 0 END AS version_change_with_decrease
  FROM ordered
)
SELECT
  SK_ID_PREV,
  COUNT(*)                                       AS installment_count,
  AVG(days_diff)                                 AS avg_days_diff,
  MAX(days_diff)                                 AS worst_days_diff,
  STDDEV(days_diff)                              AS days_diff_volatility,
  SUM(CASE WHEN days_diff > 0 THEN 1 ELSE 0 END) AS late_payment_count,
  SUM(is_missed)                                 AS missed_installment_count,
  AVG(payment_ratio)                             AS avg_payment_ratio,
  MIN(payment_ratio)                             AS worst_payment_ratio,
  SUM(is_underpaid)                              AS underpaid_installment_count,
  SUM(version_change_with_increase)              AS version_change_increase_count,
  SUM(version_change_with_decrease)              AS version_change_decrease_count
FROM per_row
GROUP BY SK_ID_PREV;

COMMIT;
