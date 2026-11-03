-- stg.application: raw.application_train + raw.application_test, before cleaning.
-- The dataset column marks the source; target is NULL for test rows.
-- Cleaning steps are applied by 02_stg_application_cleaning.sql.
-- Idempotent (DROP IF EXISTS + CREATE).
BEGIN;

DROP TABLE IF EXISTS stg.application;

CREATE TABLE stg.application AS
SELECT *, 'train'::text AS dataset
FROM raw.application_train;

-- the two tables have different column orders (target), so insert by name
DO $$
DECLARE
    cols text;
BEGIN
    SELECT string_agg(quote_ident(column_name), ', ' ORDER BY ordinal_position)
    INTO cols
    FROM information_schema.columns
    WHERE table_schema = 'raw' AND table_name = 'application_test';

    EXECUTE format(
        'INSERT INTO stg.application (%1$s, dataset) SELECT %1$s, ''test'' FROM raw.application_test',
        cols
    );
END $$;

COMMIT;
