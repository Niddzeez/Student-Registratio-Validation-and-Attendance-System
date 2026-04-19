-- ============================================================================
-- 04_triggers_3nf.sql  (Bug-fixed version)
--
-- BUG FIXED: trg_update_enrollment previously BOTH set :NEW.registration_status
-- AND issued UPDATE sections SET current_enrollment/waitlist + 1. Meanwhile,
-- register_student() in the package body ALSO issued the same UPDATE before
-- INSERT, causing double-counting.
--
-- Resolution:  The package body's manual counter UPDATEs are removed (see
-- 02_RegValandProcessing_3nf.sql). This trigger is the SOLE place that
-- increments current_enrollment / current_waitlist. It uses the capacity
-- values it reads under the FOR UPDATE lock that the package already holds,
-- so it is consistent.
--
-- trg_class_conducted is intentionally absent — columns removed in 3NF.
-- ============================================================================

CREATE OR REPLACE TRIGGER trg_update_enrollment
BEFORE INSERT ON registrations
FOR EACH ROW
DECLARE
    v_capacity NUMBER;
    v_enrolled NUMBER;
BEGIN
    -- Read current state (section row is already locked by the calling package)
    SELECT max_capacity, current_enrollment
      INTO v_capacity, v_enrolled
      FROM sections
     WHERE section_id = :NEW.section_id;

    -- Override whatever status was passed in based on real capacity
    IF v_enrolled < v_capacity THEN
        :NEW.registration_status := 'REGISTERED';
        UPDATE sections
           SET current_enrollment = current_enrollment + 1
         WHERE section_id = :NEW.section_id;
    ELSE
        :NEW.registration_status := 'WAITLISTED';
        UPDATE sections
           SET current_waitlist = current_waitlist + 1
         WHERE section_id = :NEW.section_id;
    END IF;
END;
/