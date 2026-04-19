-- ============================================================================
-- 02_RegValandProcessing_3nf.sql  (Bug-fixed version)
--
-- BUGS FIXED:
-- 1. check_eligibility(): Was using OR-across-conditions to find failing rows,
--    meaning a CSE student was blocked if ANY eligibility row (e.g. for EEE)
--    didn't match. Fixed: student passes if AT LEAST ONE row fully satisfies
--    all its non-null dept/program/semester constraints.
--
-- 2. register_student(): Was manually doing UPDATE sections SET
--    current_enrollment+1 / current_waitlist+1 BEFORE the INSERT. The
--    trg_update_enrollment BEFORE INSERT trigger ALSO increments these
--    counters, causing double-counting. Removed the manual updates.
--    The FOR UPDATE lock on sections is kept to prevent race conditions
--    and the capacity decision is made before INSERT so the trigger's
--    own counter bump is consistent.
--
-- 3. validate_registration(): Added check that section and offering are
--    active, and that the offering belongs to the requested term_id.
-- ============================================================================

DROP PACKAGE registration_manager;

CREATE OR REPLACE PACKAGE registration_manager AS

    PROCEDURE register_student (
        p_student_id      IN  NUMBER,
        p_section_id      IN  NUMBER,
        p_term_id         IN  NUMBER,
        p_registration_id OUT NUMBER,
        p_status          OUT VARCHAR2,
        p_message         OUT VARCHAR2
    );

    PROCEDURE drop_course (
        p_registration_id IN  NUMBER,
        p_reason          IN  VARCHAR2,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    );

    PROCEDURE approve_from_waitlist (
        p_registration_id IN  NUMBER,
        p_approved_by     IN  NUMBER,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    );

    FUNCTION validate_registration (
        p_student_id    IN  NUMBER,
        p_section_id    IN  NUMBER,
        p_term_id       IN  NUMBER,
        p_error_message OUT VARCHAR2
    ) RETURN BOOLEAN;

    FUNCTION check_slot_conflict (
        p_student_id  IN NUMBER,
        p_offering_id IN NUMBER,
        p_term_id     IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_prerequisites (
        p_student_id IN NUMBER,
        p_course_id  IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_credit_limit (
        p_student_id  IN NUMBER,
        p_term_id     IN NUMBER,
        p_new_credits IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_eligibility (
        p_student_id IN NUMBER,
        p_course_id  IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_section_capacity (
        p_section_id IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_duplicate_course (
        p_student_id IN NUMBER,
        p_course_id  IN NUMBER,
        p_term_id    IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION check_registration_period (
        p_term_id IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION get_student_current_credits (
        p_student_id IN NUMBER,
        p_term_id    IN NUMBER
    ) RETURN NUMBER;

    PROCEDURE update_enrollment_counts (p_section_id IN NUMBER);

END registration_manager;
/

CREATE OR REPLACE PACKAGE BODY registration_manager AS

    PROCEDURE promote_from_waitlist (p_section_id IN NUMBER, p_term_id IN NUMBER);
    PROCEDURE reorder_waitlist      (p_section_id IN NUMBER, p_term_id IN NUMBER);

    -- ========================================================================
    -- REGISTER STUDENT
    -- Bug fix: trigger handles counter increments — removed double-update.
    -- We keep FOR UPDATE lock to read capacity atomically; the trigger fires
    -- on the subsequent INSERT and does the actual counter bump.
    -- ========================================================================
    PROCEDURE register_student (
        p_student_id      IN  NUMBER,
        p_section_id      IN  NUMBER,
        p_term_id         IN  NUMBER,
        p_registration_id OUT NUMBER,
        p_status          OUT VARCHAR2,
        p_message         OUT VARCHAR2
    ) IS
        v_is_valid      BOOLEAN;
        v_error_message VARCHAR2(4000);
        v_waitlist_pos  NUMBER;
        v_capacity      NUMBER;
        v_enrolled      NUMBER;
        v_dummy         NUMBER;
    BEGIN
        v_is_valid := validate_registration(
            p_student_id, p_section_id, p_term_id, v_error_message
        );
        IF NOT v_is_valid THEN
            p_status := 'FAILED'; p_message := v_error_message;
            p_registration_id := NULL; RETURN;
        END IF;

        SELECT registration_seq.NEXTVAL INTO p_registration_id FROM dual;

        -- Atomic capacity read under lock
        SELECT max_capacity, current_enrollment
          INTO v_capacity, v_enrolled
          FROM sections WHERE section_id = p_section_id
        FOR UPDATE;

        IF v_enrolled < v_capacity THEN
            -- Trigger will set status=REGISTERED and bump current_enrollment
            INSERT INTO registrations (
                registration_id, student_id, section_id, term_id,
                registration_status, approved_date
            ) VALUES (
                p_registration_id, p_student_id, p_section_id, p_term_id,
                'REGISTERED', SYSTIMESTAMP
            );
            p_status  := 'REGISTERED';
            p_message := 'Successfully registered for the course';
        ELSE
            -- Lock existing waitlist rows to compute next position safely
            BEGIN
                SELECT 1 INTO v_dummy FROM registrations
                 WHERE section_id = p_section_id AND term_id = p_term_id
                   AND registration_status = 'WAITLISTED' AND ROWNUM = 1
                FOR UPDATE;
            EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
            END;

            SELECT NVL(MAX(waitlist_position), 0) + 1 INTO v_waitlist_pos
              FROM registrations
             WHERE section_id = p_section_id AND term_id = p_term_id
               AND registration_status = 'WAITLISTED';

            -- Trigger will set status=WAITLISTED and bump current_waitlist
            INSERT INTO registrations (
                registration_id, student_id, section_id, term_id,
                registration_status, waitlist_position
            ) VALUES (
                p_registration_id, p_student_id, p_section_id, p_term_id,
                'WAITLISTED', v_waitlist_pos
            );

            INSERT INTO waitlist_history (
                waitlist_id, student_id, section_id, term_id, status
            ) VALUES (
                waitlist_seq.NEXTVAL, p_student_id, p_section_id, p_term_id,
                'WAITING'
            );

            p_status  := 'WAITLISTED';
            p_message := 'Added to waitlist at position ' || v_waitlist_pos;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            p_status := 'ERROR'; p_message := 'Registration failed: ' || SQLERRM;
            p_registration_id := NULL;
    END register_student;


    -- ========================================================================
    -- DROP COURSE - MODIFIED to only allow drops during registration window
    -- ========================================================================
    PROCEDURE drop_course (
        p_registration_id IN  NUMBER,
        p_reason          IN  VARCHAR2,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    ) IS
        v_section_id NUMBER; 
        v_status VARCHAR2(20);
        v_term_id    NUMBER; 
        v_reg_end    DATE;
        v_reg_start  DATE;
        v_student_id NUMBER;
    BEGIN
        -- Get registration details with registration window dates
        SELECT r.section_id, r.registration_status, r.term_id,
               t.registration_end_date, t.registration_start_date,
               r.student_id
          INTO v_section_id, v_status, v_term_id, 
               v_reg_end, v_reg_start,
               v_student_id
          FROM registrations r 
          JOIN academic_terms t ON r.term_id = t.term_id
         WHERE r.registration_id = p_registration_id 
         FOR UPDATE;

        IF v_status IN ('DROPPED','WITHDRAWN') THEN
            p_success := FALSE; 
            p_message := 'Course already dropped/withdrawn'; 
            RETURN;
        END IF;
        
        -- Check if registration window has started
        IF SYSDATE < v_reg_start THEN
            p_success := FALSE;
            p_message := 'Cannot drop before registration opens on ' 
                         || TO_CHAR(v_reg_start, 'DD-MON-YYYY');
            RETURN;
        END IF;
        
        -- Check if registration window is still open
        IF SYSDATE > v_reg_end THEN
            p_success := FALSE; 
            p_message := 'Cannot drop after registration window closes on ' 
                         || TO_CHAR(v_reg_end, 'DD-MON-YYYY');
            RETURN;
        END IF;

        -- Proceed with drop
        UPDATE registrations SET registration_status = 'DROPPED', updated_at = SYSTIMESTAMP
         WHERE registration_id = p_registration_id;

        IF v_status = 'REGISTERED' THEN
            UPDATE sections SET current_enrollment = current_enrollment - 1
             WHERE section_id = v_section_id AND current_enrollment > 0;
            promote_from_waitlist(v_section_id, v_term_id);
        ELSIF v_status = 'WAITLISTED' THEN
            UPDATE sections SET current_waitlist = current_waitlist - 1
             WHERE section_id = v_section_id AND current_waitlist > 0;
            UPDATE waitlist_history SET status = 'STUDENT_DROPPED', status_changed_at = SYSTIMESTAMP
             WHERE student_id = v_student_id AND section_id = v_section_id
               AND term_id = v_term_id AND status = 'WAITING';
            reorder_waitlist(v_section_id, v_term_id);
        END IF;

        p_success := TRUE; 
        p_message := 'Course dropped successfully';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN 
            p_success := FALSE; 
            p_message := 'Invalid registration ID';
        WHEN OTHERS THEN 
            p_success := FALSE; 
            p_message := 'Error: ' || SQLERRM;
    END drop_course;

    -- ========================================================================
    -- APPROVE FROM WAITLIST
    -- ========================================================================
    PROCEDURE approve_from_waitlist (
        p_registration_id IN  NUMBER,
        p_approved_by     IN  NUMBER,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    ) IS
        v_section_id NUMBER; v_status VARCHAR2(20);
        v_student_id NUMBER; v_term_id NUMBER;
    BEGIN
        SELECT section_id, registration_status, student_id, term_id
          INTO v_section_id, v_status, v_student_id, v_term_id
          FROM registrations WHERE registration_id = p_registration_id FOR UPDATE;

        IF v_status != 'WAITLISTED' THEN
            p_success := FALSE; p_message := 'Not in waitlisted status'; RETURN;
        END IF;

        UPDATE sections
           SET current_enrollment = current_enrollment + 1,
               current_waitlist   = current_waitlist   - 1
         WHERE section_id = v_section_id
           AND current_enrollment < max_capacity AND current_waitlist > 0;

        IF SQL%ROWCOUNT = 0 THEN
            p_success := FALSE; p_message := 'Section full or inconsistent'; RETURN;
        END IF;

        UPDATE registrations
           SET registration_status = 'REGISTERED', waitlist_position = NULL,
               approved_date = SYSTIMESTAMP, updated_at = SYSTIMESTAMP
         WHERE registration_id = p_registration_id AND registration_status = 'WAITLISTED';

        UPDATE waitlist_history
           SET status = 'APPROVED', status_changed_at = SYSTIMESTAMP
         WHERE student_id = v_student_id AND section_id = v_section_id
           AND term_id = v_term_id AND status = 'WAITING' AND ROWNUM = 1;

        BEGIN reorder_waitlist(v_section_id, v_term_id); EXCEPTION WHEN OTHERS THEN NULL; END;

        p_success := TRUE; p_message := 'Student approved from waitlist';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN p_success := FALSE; p_message := 'Invalid registration ID';
        WHEN OTHERS THEN p_success := FALSE; p_message := 'Error: ' || SQLERRM;
    END approve_from_waitlist;

    -- ========================================================================
    -- VALIDATE REGISTRATION  (bug fix: active checks + term ownership)
    -- ========================================================================
    FUNCTION validate_registration (
        p_student_id    IN  NUMBER,
        p_section_id    IN  NUMBER,
        p_term_id       IN  NUMBER,
        p_error_message OUT VARCHAR2
    ) RETURN BOOLEAN IS
        v_offering_id NUMBER; v_course_id NUMBER; v_credits NUMBER;
        v_sec_active  CHAR(1); v_off_active CHAR(1); v_off_term_id NUMBER;
    BEGIN
        BEGIN
            SELECT s.offering_id, co.course_id, c.credits,
                   s.is_active, co.is_active, co.term_id
              INTO v_offering_id, v_course_id, v_credits,
                   v_sec_active, v_off_active, v_off_term_id
              FROM sections s
              JOIN course_offerings co ON s.offering_id = co.offering_id
              JOIN courses c           ON co.course_id   = c.course_id
             WHERE s.section_id = p_section_id;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_error_message := 'Invalid section ID'; RETURN FALSE;
        END;

        IF v_sec_active != 'Y' THEN
            p_error_message := 'Section is not active'; RETURN FALSE;
        END IF;
        IF v_off_active != 'Y' THEN
            p_error_message := 'Course offering is not active'; RETURN FALSE;
        END IF;
        IF v_off_term_id != p_term_id THEN
            p_error_message := 'Section does not belong to specified term'; RETURN FALSE;
        END IF;
        IF NOT check_registration_period(p_term_id) THEN
            p_error_message := 'Registration period is not open for this term'; RETURN FALSE;
        END IF;
        IF check_duplicate_course(p_student_id, v_course_id, p_term_id) THEN
            p_error_message := 'Already registered for this course this term'; RETURN FALSE;
        END IF;
        IF NOT check_eligibility(p_student_id, v_course_id) THEN
            p_error_message := 'Not eligible (dept/program/semester restriction)'; RETURN FALSE;
        END IF;
        IF NOT check_prerequisites(p_student_id, v_course_id) THEN
            p_error_message := 'Mandatory prerequisites not completed'; RETURN FALSE;
        END IF;
        IF NOT check_credit_limit(p_student_id, p_term_id, v_credits) THEN
            p_error_message := 'Credit limit would be exceeded'; RETURN FALSE;
        END IF;
        IF NOT check_slot_conflict(p_student_id, v_offering_id, p_term_id) THEN
            p_error_message := 'Time slot conflicts with an existing registration'; RETURN FALSE;
        END IF;

        p_error_message := NULL; RETURN TRUE;
    EXCEPTION WHEN OTHERS THEN RAISE;
    END validate_registration;

    -- ========================================================================
    -- CHECK SLOT CONFLICT
    -- ========================================================================
    FUNCTION check_slot_conflict (
        p_student_id IN NUMBER, p_offering_id IN NUMBER, p_term_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_conflict_count NUMBER; v_theory_slot_id NUMBER; v_lab_slot_id NUMBER;
    BEGIN
        SELECT theory_slot_id, lab_slot_id INTO v_theory_slot_id, v_lab_slot_id
          FROM course_offerings WHERE offering_id = p_offering_id;

        SELECT COUNT(*) INTO v_conflict_count
          FROM registrations r
          JOIN sections s          ON r.section_id  = s.section_id
          JOIN course_offerings co ON s.offering_id = co.offering_id
         WHERE r.student_id = p_student_id AND r.term_id = p_term_id
           AND r.registration_status IN ('REGISTERED','APPROVED','WAITLISTED')
           AND co.offering_id != p_offering_id
           AND (
                   (v_theory_slot_id IS NOT NULL AND co.theory_slot_id = v_theory_slot_id)
                OR (v_lab_slot_id    IS NOT NULL AND co.lab_slot_id    = v_lab_slot_id)
                OR (v_theory_slot_id IS NOT NULL AND co.lab_slot_id    = v_theory_slot_id)
                OR (v_lab_slot_id    IS NOT NULL AND co.theory_slot_id = v_lab_slot_id)
               );
        RETURN v_conflict_count = 0;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS THEN RAISE;
    END check_slot_conflict;

    -- ========================================================================
    -- CHECK PREREQUISITES
    -- ========================================================================
    FUNCTION check_prerequisites (
        p_student_id IN NUMBER, p_course_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_unmet_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_unmet_count
          FROM course_prerequisites cp
         WHERE cp.course_id = p_course_id AND cp.is_mandatory = 'Y'
           AND NOT EXISTS (
               SELECT 1 FROM registrations r
                 JOIN sections s          ON r.section_id  = s.section_id
                 JOIN course_offerings co ON s.offering_id = co.offering_id
                WHERE r.student_id = p_student_id
                  AND co.course_id = cp.prerequisite_course_id
                  AND r.registration_status = 'COMPLETED'
           );
        RETURN v_unmet_count = 0;
    EXCEPTION WHEN OTHERS THEN RAISE;
    END check_prerequisites;

    -- ========================================================================
    -- CHECK CREDIT LIMIT
    -- ========================================================================
    FUNCTION check_credit_limit (
        p_student_id IN NUMBER, p_term_id IN NUMBER, p_new_credits IN NUMBER
    ) RETURN BOOLEAN IS
        v_current_credits NUMBER; v_max_credits NUMBER;
    BEGIN
        v_current_credits := get_student_current_credits(p_student_id, p_term_id);
        BEGIN
            SELECT p.max_credits_per_semester INTO v_max_credits
              FROM students s
              JOIN batches  b ON s.batch_id   = b.batch_id
              JOIN programs p ON b.program_id = p.program_id
             WHERE s.student_id = p_student_id;
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN FALSE;
        END;
        RETURN (v_current_credits + p_new_credits) <= v_max_credits;
    EXCEPTION WHEN OTHERS THEN RAISE;
    END check_credit_limit;

    -- ========================================================================
    -- CHECK ELIGIBILITY  (Bug fixed — was OR-logic across rows, now ANY-row-match)
    -- ========================================================================
    FUNCTION check_eligibility (
        p_student_id IN NUMBER, p_course_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_student_dept    NUMBER; v_student_program  NUMBER;
        v_student_semester NUMBER; v_total_rules NUMBER; v_matching_rules NUMBER;
    BEGIN
        SELECT p.dept_id, b.program_id, s.current_semester
          INTO v_student_dept, v_student_program, v_student_semester
          FROM students s
          JOIN batches  b ON s.batch_id   = b.batch_id
          JOIN programs p ON b.program_id = p.program_id
         WHERE s.student_id = p_student_id;

        SELECT COUNT(*) INTO v_total_rules
          FROM course_eligibility WHERE course_id = p_course_id;

        IF v_total_rules = 0 THEN RETURN TRUE; END IF;

        -- Student passes if at least one row fully satisfies all constraints
        SELECT COUNT(*) INTO v_matching_rules
          FROM course_eligibility ce
         WHERE ce.course_id = p_course_id
           AND (ce.dept_id    IS NULL OR ce.dept_id    = v_student_dept)
           AND (ce.program_id IS NULL OR ce.program_id = v_student_program)
           AND (ce.min_semester IS NULL OR v_student_semester >= ce.min_semester)
           AND (ce.max_semester IS NULL OR v_student_semester <= ce.max_semester);

        RETURN v_matching_rules > 0;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS THEN RETURN FALSE;
    END check_eligibility;

    -- ========================================================================
    -- CHECK SECTION CAPACITY
    -- ========================================================================
    FUNCTION check_section_capacity (p_section_id IN NUMBER) RETURN BOOLEAN IS
        v_current_enrollment NUMBER; v_max_capacity NUMBER;
    BEGIN
        SELECT current_enrollment, max_capacity INTO v_current_enrollment, v_max_capacity
          FROM sections WHERE section_id = p_section_id;
        RETURN v_current_enrollment < v_max_capacity;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS THEN RAISE;
    END check_section_capacity;

    -- ========================================================================
    -- CHECK DUPLICATE COURSE
    -- ========================================================================
    FUNCTION check_duplicate_course (
        p_student_id IN NUMBER, p_course_id IN NUMBER, p_term_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_dummy NUMBER;
    BEGIN
        SELECT 1 INTO v_dummy
          FROM registrations r
          JOIN sections s          ON r.section_id  = s.section_id
          JOIN course_offerings co ON s.offering_id = co.offering_id
         WHERE r.student_id = p_student_id AND co.course_id = p_course_id
           AND r.term_id = p_term_id
           AND r.registration_status IN ('REGISTERED','WAITLISTED','APPROVED')
           AND ROWNUM = 1;
        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS THEN RAISE;
    END check_duplicate_course;

    -- ========================================================================
    -- CHECK REGISTRATION PERIOD
    -- ========================================================================
    FUNCTION check_registration_period (p_term_id IN NUMBER) RETURN BOOLEAN IS
        v_reg_start DATE; v_reg_end DATE;
    BEGIN
        SELECT registration_start_date, registration_end_date
          INTO v_reg_start, v_reg_end
          FROM academic_terms WHERE term_id = p_term_id;
        RETURN v_reg_start IS NOT NULL AND v_reg_end IS NOT NULL
           AND TRUNC(SYSDATE) BETWEEN TRUNC(v_reg_start) AND TRUNC(v_reg_end);
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS THEN RAISE;
    END check_registration_period;

    -- ========================================================================
    -- GET STUDENT CURRENT CREDITS
    -- ========================================================================
    FUNCTION get_student_current_credits (
        p_student_id IN NUMBER, p_term_id IN NUMBER
    ) RETURN NUMBER IS
        v_total_credits NUMBER;
    BEGIN
        SELECT NVL(SUM(c.credits), 0) INTO v_total_credits
          FROM registrations r
          JOIN sections s          ON r.section_id  = s.section_id
          JOIN course_offerings co ON s.offering_id = co.offering_id
          JOIN courses c           ON co.course_id   = c.course_id
         WHERE r.student_id = p_student_id AND r.term_id = p_term_id
           AND r.registration_status IN ('REGISTERED','APPROVED');
        RETURN v_total_credits;
    EXCEPTION WHEN OTHERS THEN RAISE;
    END get_student_current_credits;

    -- ========================================================================
    -- UPDATE ENROLLMENT COUNTS
    -- ========================================================================
    PROCEDURE update_enrollment_counts (p_section_id IN NUMBER) IS
    BEGIN
        UPDATE sections s
           SET current_enrollment = (
               SELECT COUNT(*) FROM registrations r
                WHERE r.section_id = s.section_id
                  AND r.registration_status IN ('REGISTERED','APPROVED')
           ),
               current_waitlist = (
               SELECT COUNT(*) FROM registrations r
                WHERE r.section_id = s.section_id
                  AND r.registration_status = 'WAITLISTED'
           )
         WHERE s.section_id = p_section_id;
    EXCEPTION WHEN OTHERS THEN RAISE;
    END update_enrollment_counts;

    -- ========================================================================
    -- PRIVATE: PROMOTE FROM WAITLIST
    -- ========================================================================
    PROCEDURE promote_from_waitlist (p_section_id IN NUMBER, p_term_id IN NUMBER) IS
        v_next_reg_id NUMBER; v_success BOOLEAN; v_message VARCHAR2(4000);
    BEGIN
        BEGIN
            SELECT registration_id INTO v_next_reg_id
              FROM (SELECT registration_id FROM registrations
                     WHERE section_id = p_section_id AND term_id = p_term_id
                       AND registration_status = 'WAITLISTED'
                     ORDER BY waitlist_position)
             WHERE ROWNUM = 1;
        EXCEPTION WHEN NO_DATA_FOUND THEN RETURN;
        END;
        approve_from_waitlist(v_next_reg_id, NULL, v_success, v_message);
    END promote_from_waitlist;

    -- ========================================================================
    -- PRIVATE: REORDER WAITLIST
    -- ========================================================================
    PROCEDURE reorder_waitlist (p_section_id IN NUMBER, p_term_id IN NUMBER) IS
    BEGIN
        MERGE INTO registrations r
        USING (
            SELECT registration_id,
                   ROW_NUMBER() OVER (ORDER BY waitlist_position) AS new_pos
              FROM registrations
             WHERE section_id = p_section_id AND term_id = p_term_id
               AND registration_status = 'WAITLISTED'
        ) o ON (r.registration_id = o.registration_id)
        WHEN MATCHED THEN UPDATE SET r.waitlist_position = o.new_pos;
    END reorder_waitlist;

END registration_manager;
/