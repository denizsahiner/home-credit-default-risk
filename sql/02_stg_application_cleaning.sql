-- stg.application cleaning.
-- days_employed: 365243 (unemployed/pensioner) -> NULL, the original anomaly is kept in the days_employed_anom flag.
-- code_gender: XNA -> NULL (4 rows).
-- amt_income_total: the single 117,000,000 row is a data error -> NULL; the next highest values are kept.
-- organization_type: XNA is kept on purpose; it is exactly the same customers as the days_employed anomaly.
-- Idempotent: once the flag is set, the NULLs are preserved.
BEGIN;

ALTER TABLE stg.application
    ADD COLUMN IF NOT EXISTS days_employed_anom smallint NOT NULL DEFAULT 0;

UPDATE stg.application
SET days_employed_anom = 1,
    days_employed = NULL
WHERE days_employed = 365243;

UPDATE stg.application
SET code_gender = NULL
WHERE code_gender = 'XNA';

UPDATE stg.application
SET amt_income_total = NULL
WHERE amt_income_total > 100000000;

COMMIT;
