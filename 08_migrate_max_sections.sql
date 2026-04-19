-- ============================================================================
-- 08_migrate_max_sections.sql
--
-- MIGRATION SCRIPT — run this ONLY on an existing database that was created
-- with the old 01_tables_3nf.sql (without max_sections on courses).
--
-- If you are doing a fresh setup, skip this file — 01_tables_3nf.sql already
-- includes max_sections in the CREATE TABLE statement.
--
-- What this script does:
--   1. Adds max_sections column to the existing courses table.
--   2. Sets a sensible default (5) for all pre-existing courses so the
--      faculty float-section check is immediately enforced.
--   3. Adds the CHECK constraint to keep data valid.
--
-- 3NF justification (same as in 01_tables_3nf.sql):
--   max_sections depends solely on course_id — it is an admin-set planning
--   cap, not derivable from any other stored column.  No new transitive
--   dependency is introduced.
-- ============================================================================

-- Step 1: Add column with a nullable default so existing rows are not
--         immediately violated (Oracle requires NOT NULL columns added to
--         non-empty tables to have a DEFAULT or be nullable initially).
ALTER TABLE courses
    ADD max_sections NUMBER DEFAULT 3
        CHECK (max_sections > 0 AND max_sections <= 50);

-- Step 2: Backfill all existing courses with the default of 5 sections.
--         Admins can update individual courses afterward via the API.
UPDATE courses
   SET max_sections = 3
 WHERE max_sections IS NULL;

-- Step 3: Now that all rows have a value, add NOT NULL constraint.
--         (Oracle allows this as a separate ALTER once nulls are gone.)
ALTER TABLE courses
    MODIFY max_sections NUMBER NOT NULL;

COMMIT;

-- ============================================================================
-- Verification query — should return 0 rows if migration succeeded.
-- ============================================================================
SELECT course_id, course_code
  FROM courses
 WHERE max_sections IS NULL OR max_sections <= 0;
