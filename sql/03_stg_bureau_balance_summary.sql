-- Bureau monthly balance branch: raw.bureau_balance -> stg.bureau_balance_summary (sk_id_bureau level).
-- status: 0-5 delinquency level, C closed, X unknown. C/X are excluded from numeric levels.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.bureau_balance_summary;

CREATE TABLE stg.bureau_balance_summary AS
WITH per_row AS (
  SELECT
    sk_id_bureau,
    status,
    months_balance,
    CASE WHEN status IN ('0','1','2','3','4','5') THEN status::int END AS status_level
  FROM raw.bureau_balance
)
SELECT
  sk_id_bureau,
  COUNT(*)                                                 AS bb_month_count,
  MAX(CASE WHEN status_level >= 1 THEN 1 ELSE 0 END)       AS bb_ever_overdue,
  MAX(CASE WHEN status_level = 5 THEN 1 ELSE 0 END)        AS bb_ever_written_off,
  SUM(CASE WHEN status_level >= 2 THEN 1 ELSE 0 END)       AS bb_serious_overdue_month_count,
  MAX(status_level)                                        AS bb_worst_status_level,
  AVG(status_level)                                        AS bb_avg_status_level,
  SUM(status_level)                                        AS bb_total_status_score,
  MAX(CASE WHEN status_level IS NOT NULL THEN 1 ELSE 0 END) AS bb_has_numeric_status,
  -- delinquency in the last N months
  SUM(CASE WHEN status_level >= 1 AND months_balance >= -6 THEN 1 ELSE 0 END) AS bb_overdue_months_6m,
  MAX(status_level) FILTER (WHERE months_balance >= -6) AS bb_worst_status_6m,
  SUM(CASE WHEN status_level >= 1 AND months_balance >= -12 THEN 1 ELSE 0 END) AS bb_overdue_months_12m,
  MAX(status_level) FILTER (WHERE months_balance >= -12) AS bb_worst_status_12m,
  SUM(CASE WHEN status_level >= 1 AND months_balance >= -24 THEN 1 ELSE 0 END) AS bb_overdue_months_24m,
  MAX(status_level) FILTER (WHERE months_balance >= -24) AS bb_worst_status_24m
FROM per_row
GROUP BY sk_id_bureau;

COMMIT;
