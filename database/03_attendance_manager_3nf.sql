-- ============================================================================
-- 03_attendance_manager_3nf.sql
-- Updated for 3NF schema:
--   - attendance table no longer has attendance_date, slot_id, class_type,
--     section_id — these are derived by JOIN with class_schedule
--   - registrations no longer has theory_classes_attended / lab_classes_attended
--     — attendance counts are always queried from attendance table directly
--   - sections no longer has total_theory_classes_conducted /
--     total_lab_classes_conducted — these are computed from class_schedule
-- ============================================================================

DROP PACKAGE attendance_manager;

-- ============================================================================
-- PACKAGE SPECIFICATION
-- ============================================================================

CREATE OR REPLACE PACKAGE attendance_manager AS

    exc_invalid_student           EXCEPTION;
    exc_invalid_schedule          EXCEPTION;
    exc_duplicate_attendance      EXCEPTION;
    exc_attendance_already_marked EXCEPTION;
    exc_invalid_date              EXCEPTION;
    exc_student_not_registered    EXCEPTION;

    PROCEDURE mark_single_attendance (
        p_student_id  IN  NUMBER,
        p_schedule_id IN  NUMBER,
        p_status      IN  VARCHAR2,
        p_marked_by   IN  NUMBER,
        p_remarks     IN  VARCHAR2 DEFAULT NULL,
        p_success     OUT BOOLEAN,
        p_message     OUT VARCHAR2
    );

    PROCEDURE mark_bulk_attendance (
        p_schedule_id     IN  NUMBER,
        p_attendance_data IN  VARCHAR2,
        p_marked_by       IN  NUMBER,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    );

    PROCEDURE mark_section_attendance (
        p_section_id     IN  NUMBER,
        p_class_date     IN  DATE,
        p_class_type     IN  VARCHAR2,
        p_slot_id        IN  NUMBER,
        p_lecture_number IN  NUMBER,
        p_default_status IN  VARCHAR2,
        p_marked_by      IN  NUMBER,
        p_topic          IN  VARCHAR2 DEFAULT NULL,
        p_success        OUT BOOLEAN,
        p_message        OUT VARCHAR2
    );

    PROCEDURE update_attendance (
        p_attendance_id IN  NUMBER,
        p_new_status    IN  VARCHAR2,
        p_updated_by    IN  NUMBER,
        p_remarks       IN  VARCHAR2 DEFAULT NULL,
        p_success       OUT BOOLEAN,
        p_message       OUT VARCHAR2
    );

    PROCEDURE calculate_student_attendance (
        p_registration_id IN  NUMBER,
        p_theory_percent  OUT NUMBER,
        p_lab_percent     OUT NUMBER,
        p_overall_percent OUT NUMBER
    );

    PROCEDURE recalculate_all_attendance (
        p_section_id IN NUMBER
    );

    PROCEDURE check_attendance_warnings (
        p_term_id           IN NUMBER,
        p_warning_threshold IN NUMBER DEFAULT 75
    );

    PROCEDURE generate_attendance_report (
        p_section_id  IN  NUMBER,
        p_report_type IN  VARCHAR2,
        p_cursor      OUT SYS_REFCURSOR
    );

    PROCEDURE lock_low_attendance_students (
        p_term_id   IN NUMBER,
        p_threshold IN NUMBER DEFAULT 75
    );

    PROCEDURE create_class_session (
        p_section_id     IN  NUMBER,
        p_class_date     IN  DATE,
        p_slot_id        IN  NUMBER,
        p_class_type     IN  VARCHAR2,
        p_lecture_number IN  NUMBER DEFAULT 1,
        p_topic          IN  VARCHAR2 DEFAULT NULL,
        p_conducted_by   IN  NUMBER,
        p_room_number    IN  VARCHAR2 DEFAULT NULL,
        p_schedule_id    OUT NUMBER,
        p_success        OUT BOOLEAN,
        p_message        OUT VARCHAR2
    );

    PROCEDURE cancel_class_session (
        p_schedule_id  IN  NUMBER,
        p_reason       IN  VARCHAR2,
        p_cancelled_by IN  NUMBER,
        p_success      OUT BOOLEAN,
        p_message      OUT VARCHAR2
    );

    FUNCTION validate_attendance_marking (
        p_student_id  IN NUMBER,
        p_schedule_id IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION is_attendance_marked (
        p_schedule_id IN NUMBER
    ) RETURN BOOLEAN;

    FUNCTION get_attendance_percentage (
        p_registration_id IN NUMBER,
        p_class_type      IN VARCHAR2
    ) RETURN NUMBER;

    FUNCTION get_total_classes_conducted (
        p_section_id IN NUMBER,
        p_class_type IN VARCHAR2
    ) RETURN NUMBER;

    FUNCTION get_student_classes_attended (
        p_registration_id IN NUMBER,
        p_class_type      IN VARCHAR2
    ) RETURN NUMBER;

END attendance_manager;
/

-- ============================================================================
-- PACKAGE BODY
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY attendance_manager AS

    -- ========================================================================
    -- MARK SINGLE ATTENDANCE
    -- 3NF update: INSERT only (registration_id, schedule_id, status,
    --   marked_by, remarks). attendance_date / slot_id / class_type /
    --   section_id removed from attendance table.
    -- Cached counter updates in registrations removed (columns dropped).
    -- ========================================================================

    PROCEDURE mark_single_attendance (
        p_student_id  IN  NUMBER,
        p_schedule_id IN  NUMBER,
        p_status      IN  VARCHAR2,
        p_marked_by   IN  NUMBER,
        p_remarks     IN  VARCHAR2 DEFAULT NULL,
        p_success     OUT BOOLEAN,
        p_message     OUT VARCHAR2
    ) IS
        v_registration_id NUMBER;
        v_section_id      NUMBER;
        v_is_cancelled    CHAR(1);
    BEGIN
        -- Get schedule details (only what we still need)
        SELECT section_id, is_cancelled
          INTO v_section_id, v_is_cancelled
          FROM class_schedule
         WHERE schedule_id = p_schedule_id;

        IF v_is_cancelled = 'Y' THEN
            p_success := FALSE;
            p_message := 'Cannot mark attendance for cancelled class';
            RETURN;
        END IF;

        -- Get registration (lock row)
        BEGIN
            SELECT registration_id
              INTO v_registration_id
              FROM registrations
             WHERE student_id          = p_student_id
               AND section_id          = v_section_id
               AND registration_status IN ('REGISTERED','APPROVED')
            FOR UPDATE;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_success := FALSE;
                p_message := 'Student not registered for this section';
                RETURN;
        END;

        -- Insert attendance (3NF: only non-derivable columns)
        BEGIN
            INSERT INTO attendance (
                attendance_id, registration_id, schedule_id,
                status, marked_by, remarks
            ) VALUES (
                attendance_seq.NEXTVAL, v_registration_id, p_schedule_id,
                p_status, p_marked_by, p_remarks
            );
        EXCEPTION
            WHEN DUP_VAL_ON_INDEX THEN
                p_success := FALSE;
                p_message := 'Attendance already marked';
                RETURN;
        END;

        -- Mark schedule as attendance-marked
        UPDATE class_schedule
           SET is_attendance_marked = 'Y',
               attendance_marked_by = p_marked_by,
               attendance_marked_at = SYSTIMESTAMP
         WHERE schedule_id = p_schedule_id;

        p_success := TRUE;
        p_message := 'Attendance marked successfully';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := FALSE;
            p_message := 'Invalid schedule ID';
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error marking attendance: ' || SQLERRM;
    END mark_single_attendance;

    -- ========================================================================
    -- MARK SECTION ATTENDANCE
    -- Creates class session then marks all registered students.
    -- ========================================================================

    PROCEDURE mark_section_attendance (
        p_section_id     IN  NUMBER,
        p_class_date     IN  DATE,
        p_class_type     IN  VARCHAR2,
        p_slot_id        IN  NUMBER,
        p_lecture_number IN  NUMBER,
        p_default_status IN  VARCHAR2,
        p_marked_by      IN  NUMBER,
        p_topic          IN  VARCHAR2 DEFAULT NULL,
        p_success        OUT BOOLEAN,
        p_message        OUT VARCHAR2
    ) IS
        v_schedule_id NUMBER;
        v_bool        BOOLEAN;
        v_msg         VARCHAR2(4000);
    BEGIN
        -- Create class session first
        create_class_session(
            p_section_id, p_class_date, p_slot_id, p_class_type,
            p_lecture_number, p_topic, p_marked_by, NULL,
            v_schedule_id, v_bool, v_msg
        );

        IF NOT v_bool THEN
            -- Session may already exist; try to find it
            BEGIN
                SELECT schedule_id INTO v_schedule_id
                  FROM class_schedule
                 WHERE section_id     = p_section_id
                   AND class_date     = p_class_date
                   AND slot_id        = p_slot_id
                   AND class_type     = p_class_type
                   AND lecture_number = p_lecture_number;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    p_success := FALSE;
                    p_message := 'Could not create/find class session: ' || v_msg;
                    RETURN;
            END;
        END IF;

        -- Mark all registered students with default status
        FOR rec IN (
            SELECT student_id, registration_id
              FROM registrations
             WHERE section_id          = p_section_id
               AND registration_status IN ('REGISTERED','APPROVED')
        ) LOOP
            BEGIN
                INSERT INTO attendance (
                    attendance_id, registration_id, schedule_id,
                    status, marked_by
                ) VALUES (
                    attendance_seq.NEXTVAL, rec.registration_id, v_schedule_id,
                    p_default_status, p_marked_by
                );
            EXCEPTION
                WHEN DUP_VAL_ON_INDEX THEN NULL; -- skip if already marked
            END;
        END LOOP;

        UPDATE class_schedule
           SET is_attendance_marked = 'Y',
               attendance_marked_by = p_marked_by,
               attendance_marked_at = SYSTIMESTAMP
         WHERE schedule_id = v_schedule_id;

        p_success := TRUE;
        p_message := 'Section attendance marked successfully';

    EXCEPTION
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error marking section attendance: ' || SQLERRM;
    END mark_section_attendance;

    -- ========================================================================
    -- MARK BULK ATTENDANCE
    -- p_attendance_data format: "student_id:status,student_id:status,..."
    -- ========================================================================

    PROCEDURE mark_bulk_attendance (
        p_schedule_id     IN  NUMBER,
        p_attendance_data IN  VARCHAR2,
        p_marked_by       IN  NUMBER,
        p_success         OUT BOOLEAN,
        p_message         OUT VARCHAR2
    ) IS
        v_section_id   NUMBER;
        v_is_cancelled CHAR(1);
        v_token        VARCHAR2(50);
        v_student_id   NUMBER;
        v_status       VARCHAR2(10);
        v_reg_id       NUMBER;
        v_data         VARCHAR2(32767) := p_attendance_data;
        v_pair         VARCHAR2(100);
        v_pos          NUMBER;
        v_colon        NUMBER;
        v_count        NUMBER := 0;
    BEGIN
        SELECT section_id, is_cancelled
          INTO v_section_id, v_is_cancelled
          FROM class_schedule
         WHERE schedule_id = p_schedule_id;

        IF v_is_cancelled = 'Y' THEN
            p_success := FALSE;
            p_message := 'Cannot mark attendance for cancelled class';
            RETURN;
        END IF;

        -- Parse "sid:status,sid:status,..."
        LOOP
            v_pos := INSTR(v_data, ',');
            IF v_pos > 0 THEN
                v_pair := TRIM(SUBSTR(v_data, 1, v_pos - 1));
                v_data := SUBSTR(v_data, v_pos + 1);
            ELSE
                v_pair := TRIM(v_data);
                v_data := NULL;
            END IF;

            EXIT WHEN v_pair IS NULL OR LENGTH(v_pair) = 0;

            v_colon     := INSTR(v_pair, ':');
            v_student_id := TO_NUMBER(TRIM(SUBSTR(v_pair, 1, v_colon - 1)));
            v_status    := TRIM(SUBSTR(v_pair, v_colon + 1));

            BEGIN
                SELECT registration_id INTO v_reg_id
                  FROM registrations
                 WHERE student_id          = v_student_id
                   AND section_id          = v_section_id
                   AND registration_status IN ('REGISTERED','APPROVED');

                INSERT INTO attendance (
                    attendance_id, registration_id, schedule_id,
                    status, marked_by
                ) VALUES (
                    attendance_seq.NEXTVAL, v_reg_id, p_schedule_id,
                    v_status, p_marked_by
                );
                v_count := v_count + 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN NULL;
                WHEN DUP_VAL_ON_INDEX THEN
                    -- Update existing
                    UPDATE attendance
                       SET status    = v_status,
                           marked_by = p_marked_by,
                           marked_at = SYSTIMESTAMP
                     WHERE registration_id = v_reg_id
                       AND schedule_id     = p_schedule_id;
            END;

            EXIT WHEN v_data IS NULL;
        END LOOP;

        UPDATE class_schedule
           SET is_attendance_marked = 'Y',
               attendance_marked_by = p_marked_by,
               attendance_marked_at = SYSTIMESTAMP
         WHERE schedule_id = p_schedule_id;

        p_success := TRUE;
        p_message := 'Bulk attendance processed for ' || v_count || ' students';

    EXCEPTION
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error in bulk attendance: ' || SQLERRM;
    END mark_bulk_attendance;

    -- ========================================================================
    -- UPDATE ATTENDANCE
    -- ========================================================================

    PROCEDURE update_attendance (
        p_attendance_id IN  NUMBER,
        p_new_status    IN  VARCHAR2,
        p_updated_by    IN  NUMBER,
        p_remarks       IN  VARCHAR2 DEFAULT NULL,
        p_success       OUT BOOLEAN,
        p_message       OUT VARCHAR2
    ) IS
        v_old_status      VARCHAR2(10);
        v_registration_id NUMBER;
    BEGIN
        SELECT status, registration_id
          INTO v_old_status, v_registration_id
          FROM attendance
         WHERE attendance_id = p_attendance_id
        FOR UPDATE;

        UPDATE attendance
           SET status    = p_new_status,
               marked_by = p_updated_by,
               marked_at = SYSTIMESTAMP,
               remarks   = NVL(p_remarks, remarks)
         WHERE attendance_id = p_attendance_id;

        p_success := TRUE;
        p_message := 'Attendance updated from ' || v_old_status || ' to ' || p_new_status;

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := FALSE;
            p_message := 'Invalid attendance ID';
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error updating attendance: ' || SQLERRM;
    END update_attendance;

    -- ========================================================================
    -- CALCULATE STUDENT ATTENDANCE
    -- 3NF: All counts are now computed from attendance + class_schedule JOINs.
    --      No cached columns used.
    -- ========================================================================

    PROCEDURE calculate_student_attendance (
        p_registration_id IN  NUMBER,
        p_theory_percent  OUT NUMBER,
        p_lab_percent     OUT NUMBER,
        p_overall_percent OUT NUMBER
    ) IS
        v_section_id       NUMBER;
        v_theory_conducted NUMBER;
        v_lab_conducted    NUMBER;
        v_theory_attended  NUMBER;
        v_lab_attended     NUMBER;
        v_has_lab          CHAR(1);
    BEGIN
        -- Get section and course info
        SELECT r.section_id, c.has_lab
          INTO v_section_id, v_has_lab
          FROM registrations r
          JOIN sections s          ON r.section_id  = s.section_id
          JOIN course_offerings co ON s.offering_id = co.offering_id
          JOIN courses c           ON co.course_id   = c.course_id
         WHERE r.registration_id = p_registration_id;

        -- Compute conducted counts from class_schedule (3NF: no cached counters)
        SELECT COUNT(CASE WHEN class_type = 'THEORY' THEN 1 END),
               COUNT(CASE WHEN class_type = 'LAB'    THEN 1 END)
          INTO v_theory_conducted, v_lab_conducted
          FROM class_schedule
         WHERE section_id   = v_section_id
           AND is_cancelled = 'N';

        -- Compute attended counts from attendance table
        SELECT COUNT(CASE WHEN cs.class_type = 'THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END),
               COUNT(CASE WHEN cs.class_type = 'LAB'    AND a.status IN ('P','L','E','OD') THEN 1 END)
          INTO v_theory_attended, v_lab_attended
          FROM attendance a
          JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
         WHERE a.registration_id = p_registration_id;

        p_theory_percent :=
            CASE WHEN v_theory_conducted > 0
                 THEN ROUND((v_theory_attended / v_theory_conducted) * 100, 2)
                 ELSE 0
            END;

        p_lab_percent :=
            CASE WHEN v_has_lab = 'Y' AND v_lab_conducted > 0
                 THEN ROUND((v_lab_attended / v_lab_conducted) * 100, 2)
                 ELSE 0
            END;

        p_overall_percent := ROUND(p_theory_percent * 0.6 + p_lab_percent * 0.4, 2);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_theory_percent  := 0;
            p_lab_percent     := 0;
            p_overall_percent := 0;
    END calculate_student_attendance;

    -- ========================================================================
    -- RECALCULATE ALL ATTENDANCE (no-op for cached fields — they're removed)
    -- Kept for API compatibility; warnings are recalculated live.
    -- ========================================================================

    PROCEDURE recalculate_all_attendance (
        p_section_id IN NUMBER
    ) IS
    BEGIN
        -- No cached counters to update in 3NF schema.
        -- Attendance percentages are computed on demand via queries.
        -- Update attendance warnings for students below threshold.
        UPDATE registrations r
           SET attendance_warning_sent = 'Y'
         WHERE r.section_id          = p_section_id
           AND r.registration_status IN ('REGISTERED','APPROVED')
           AND (
               SELECT ROUND(
                   (COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END) * 100.0)
                   / NULLIF(COUNT(DISTINCT CASE WHEN cs.class_type='THEORY' AND cs.is_cancelled='N' THEN cs.schedule_id END), 0)
               , 2)
                 FROM attendance a
                 JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
                WHERE a.registration_id = r.registration_id
           ) < 75;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END recalculate_all_attendance;

    -- ========================================================================
    -- CHECK ATTENDANCE WARNINGS
    -- ========================================================================

    PROCEDURE check_attendance_warnings (
        p_term_id           IN NUMBER,
        p_warning_threshold IN NUMBER DEFAULT 75
    ) IS
    BEGIN
        -- Mark warning flag for students whose computed overall % < threshold
        UPDATE registrations r
           SET attendance_warning_sent = 'Y'
         WHERE r.term_id              = p_term_id
           AND r.registration_status IN ('REGISTERED','APPROVED')
           AND r.attendance_warning_sent = 'N'
           AND (
               SELECT ROUND(
                   (COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END) * 60.0
                    / NULLIF(COUNT(DISTINCT CASE WHEN cs.class_type='THEORY' AND cs.is_cancelled='N' THEN cs.schedule_id END), 0))
                   +
                   (COUNT(CASE WHEN cs.class_type='LAB' AND a.status IN ('P','L','E','OD') THEN 1 END) * 40.0
                    / NULLIF(COUNT(DISTINCT CASE WHEN cs.class_type='LAB' AND cs.is_cancelled='N' THEN cs.schedule_id END), 0))
               , 2)
                 FROM attendance a
                 JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
                WHERE a.registration_id = r.registration_id
           ) < p_warning_threshold;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END check_attendance_warnings;

    -- ========================================================================
    -- GENERATE ATTENDANCE REPORT
    -- ========================================================================

    PROCEDURE generate_attendance_report (
        p_section_id  IN  NUMBER,
        p_report_type IN  VARCHAR2,
        p_cursor      OUT SYS_REFCURSOR
    ) IS
    BEGIN
        IF p_report_type = 'SUMMARY' THEN
            OPEN p_cursor FOR
                SELECT
                    s.student_id,
                    s.roll_number,
                    s.first_name || ' ' || s.last_name AS student_name,
                    r.registration_id,
                    -- Theory: computed from class_schedule + attendance
                    (SELECT COUNT(*) FROM class_schedule cs
                      WHERE cs.section_id = p_section_id
                        AND cs.class_type = 'THEORY' AND cs.is_cancelled = 'N')
                        AS theory_total,
                    (SELECT COUNT(*) FROM attendance a
                       JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
                      WHERE a.registration_id = r.registration_id
                        AND cs.class_type = 'THEORY'
                        AND a.status IN ('P','L','E','OD'))
                        AS theory_attended,
                    (SELECT COUNT(*) FROM class_schedule cs
                      WHERE cs.section_id = p_section_id
                        AND cs.class_type = 'LAB' AND cs.is_cancelled = 'N')
                        AS lab_total,
                    (SELECT COUNT(*) FROM attendance a
                       JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
                      WHERE a.registration_id = r.registration_id
                        AND cs.class_type = 'LAB'
                        AND a.status IN ('P','L','E','OD'))
                        AS lab_attended
                  FROM registrations r
                  JOIN students s ON r.student_id = s.student_id
                 WHERE r.section_id          = p_section_id
                   AND r.registration_status IN ('REGISTERED','APPROVED')
                 ORDER BY s.roll_number;

        ELSIF p_report_type = 'DEFAULTERS' THEN
            OPEN p_cursor FOR
                WITH att_calc AS (
                    SELECT
                        r.registration_id,
                        r.student_id,
                        ROUND(
                            (COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END) * 100.0)
                            / NULLIF(SUM(CASE WHEN cs.class_type='THEORY' AND cs.is_cancelled='N' THEN 1 ELSE 0 END), 0)
                        , 2) AS theory_pct,
                        ROUND(
                            (COUNT(CASE WHEN cs.class_type='LAB' AND a.status IN ('P','L','E','OD') THEN 1 END) * 100.0)
                            / NULLIF(SUM(CASE WHEN cs.class_type='LAB' AND cs.is_cancelled='N' THEN 1 ELSE 0 END), 0)
                        , 2) AS lab_pct
                      FROM registrations r
                      LEFT JOIN attendance a    ON a.registration_id = r.registration_id
                      LEFT JOIN class_schedule cs ON a.schedule_id  = cs.schedule_id
                     WHERE r.section_id          = p_section_id
                       AND r.registration_status IN ('REGISTERED','APPROVED')
                     GROUP BY r.registration_id, r.student_id
                )
                SELECT
                    s.student_id,
                    s.roll_number,
                    s.first_name || ' ' || s.last_name AS student_name,
                    ac.theory_pct,
                    ac.lab_pct,
                    ROUND(NVL(ac.theory_pct, 0) * 0.6 + NVL(ac.lab_pct, 0) * 0.4, 2) AS overall_pct
                  FROM att_calc ac
                  JOIN students s ON ac.student_id = s.student_id
                 WHERE NVL(ac.theory_pct, 0) * 0.6 + NVL(ac.lab_pct, 0) * 0.4 < 75
                 ORDER BY overall_pct;

        ELSE -- DETAILED
            OPEN p_cursor FOR
                SELECT
                    s.student_id,
                    s.roll_number,
                    s.first_name || ' ' || s.last_name AS student_name,
                    cs.class_date,
                    cs.class_type,
                    sl.slot_code,
                    NVL(a.status, 'NOT_MARKED') AS status,
                    a.remarks
                  FROM registrations r
                  JOIN students s             ON r.student_id  = s.student_id
                  JOIN class_schedule cs      ON cs.section_id = r.section_id
                  JOIN slots sl               ON cs.slot_id    = sl.slot_id
                  LEFT JOIN attendance a      ON a.registration_id = r.registration_id
                                             AND a.schedule_id    = cs.schedule_id
                 WHERE r.section_id          = p_section_id
                   AND r.registration_status IN ('REGISTERED','APPROVED')
                   AND cs.is_cancelled       = 'N'
                 ORDER BY s.roll_number, cs.class_date;
        END IF;
    END generate_attendance_report;

    -- ========================================================================
    -- LOCK LOW ATTENDANCE STUDENTS
    -- ========================================================================

    PROCEDURE lock_low_attendance_students (
        p_term_id   IN NUMBER,
        p_threshold IN NUMBER DEFAULT 75
    ) IS
    BEGIN
        UPDATE registrations r
           SET attendance_locked = 'Y'
         WHERE r.term_id              = p_term_id
           AND r.registration_status IN ('REGISTERED','APPROVED')
           AND r.attendance_locked   = 'N'
           AND (
               SELECT ROUND(
                   NVL(
                       (COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END) * 100.0)
                       / NULLIF(SUM(CASE WHEN cs.class_type='THEORY' AND cs.is_cancelled='N' THEN 1 ELSE 0 END), 0)
                   , 0) * 0.6
                   + NVL(
                       (COUNT(CASE WHEN cs.class_type='LAB' AND a.status IN ('P','L','E','OD') THEN 1 END) * 100.0)
                       / NULLIF(SUM(CASE WHEN cs.class_type='LAB' AND cs.is_cancelled='N' THEN 1 ELSE 0 END), 0)
                   , 0) * 0.4
               , 2)
                 FROM attendance a
                 JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
                WHERE a.registration_id = r.registration_id
           ) < p_threshold;
    EXCEPTION
        WHEN OTHERS THEN NULL;
    END lock_low_attendance_students;

    -- ========================================================================
    -- CREATE CLASS SESSION
    -- ========================================================================

    PROCEDURE create_class_session (
        p_section_id     IN  NUMBER,
        p_class_date     IN  DATE,
        p_slot_id        IN  NUMBER,
        p_class_type     IN  VARCHAR2,
        p_lecture_number IN  NUMBER DEFAULT 1,
        p_topic          IN  VARCHAR2 DEFAULT NULL,
        p_conducted_by   IN  NUMBER,
        p_room_number    IN  VARCHAR2 DEFAULT NULL,
        p_schedule_id    OUT NUMBER,
        p_success        OUT BOOLEAN,
        p_message        OUT VARCHAR2
    ) IS
        v_section_active CHAR(1);
    BEGIN
        -- Validate section
        SELECT is_active INTO v_section_active
          FROM sections WHERE section_id = p_section_id;

        IF v_section_active != 'Y' THEN
            p_success := FALSE;
            p_message := 'Section is not active';
            RETURN;
        END IF;

        SELECT schedule_seq.NEXTVAL INTO p_schedule_id FROM dual;

        INSERT INTO class_schedule (
            schedule_id, section_id, class_date, slot_id, class_type,
            lecture_number, topic, conducted_by, room_number
        ) VALUES (
            p_schedule_id, p_section_id, p_class_date, p_slot_id, p_class_type,
            p_lecture_number, p_topic, p_conducted_by, p_room_number
        );

        p_success := TRUE;
        p_message := 'Class session created successfully';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := FALSE;
            p_message := 'Invalid section ID';
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := FALSE;
            p_message := 'A class session already exists for this slot/date';
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error creating class session: ' || SQLERRM;
    END create_class_session;

    -- ========================================================================
    -- CANCEL CLASS SESSION
    -- 3NF update: no conducted-counter decrement (columns removed from sections)
    -- ========================================================================

    PROCEDURE cancel_class_session (
        p_schedule_id  IN  NUMBER,
        p_reason       IN  VARCHAR2,
        p_cancelled_by IN  NUMBER,
        p_success      OUT BOOLEAN,
        p_message      OUT VARCHAR2
    ) IS
        v_is_marked    CHAR(1);
        v_is_cancelled CHAR(1);
    BEGIN
        SELECT is_attendance_marked, is_cancelled
          INTO v_is_marked, v_is_cancelled
          FROM class_schedule
         WHERE schedule_id = p_schedule_id
        FOR UPDATE;

        IF v_is_cancelled = 'Y' THEN
            p_success := FALSE;
            p_message := 'Class already cancelled';
            RETURN;
        END IF;

        IF v_is_marked = 'Y' THEN
            p_success := FALSE;
            p_message := 'Cannot cancel class - attendance already marked';
            RETURN;
        END IF;

        UPDATE class_schedule
           SET is_cancelled        = 'Y',
               cancellation_reason = p_reason
         WHERE schedule_id  = p_schedule_id
           AND is_cancelled  = 'N';

        IF SQL%ROWCOUNT = 0 THEN
            p_success := FALSE;
            p_message := 'Cancellation failed due to concurrent update';
            RETURN;
        END IF;

        -- No counter to decrement in 3NF schema — count is derived on demand
        p_success := TRUE;
        p_message := 'Class session cancelled successfully';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := FALSE;
            p_message := 'Invalid schedule ID';
        WHEN OTHERS THEN
            p_success := FALSE;
            p_message := 'Error cancelling class: ' || SQLERRM;
    END cancel_class_session;

    -- ========================================================================
    -- VALIDATE ATTENDANCE MARKING
    -- ========================================================================

    FUNCTION validate_attendance_marking (
        p_student_id  IN NUMBER,
        p_schedule_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_dummy NUMBER;
    BEGIN
        SELECT 1 INTO v_dummy
          FROM class_schedule cs
          JOIN registrations r ON r.section_id  = cs.section_id
          JOIN students s      ON s.student_id   = r.student_id
         WHERE cs.schedule_id          = p_schedule_id
           AND cs.is_cancelled         = 'N'
           AND r.student_id            = p_student_id
           AND r.registration_status  IN ('REGISTERED','APPROVED')
           AND s.is_active             = 'Y';

        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN FALSE;
        WHEN OTHERS        THEN RAISE;
    END validate_attendance_marking;

    -- ========================================================================
    -- IS ATTENDANCE MARKED
    -- ========================================================================

    FUNCTION is_attendance_marked (
        p_schedule_id IN NUMBER
    ) RETURN BOOLEAN IS
        v_is_marked CHAR(1);
    BEGIN
        SELECT is_attendance_marked INTO v_is_marked
          FROM class_schedule WHERE schedule_id = p_schedule_id;

        RETURN v_is_marked = 'Y';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20003, 'Invalid schedule ID');
    END is_attendance_marked;

    -- ========================================================================
    -- GET ATTENDANCE PERCENTAGE
    -- 3NF: computes from class_schedule + attendance joins
    -- ========================================================================

    FUNCTION get_attendance_percentage (
        p_registration_id IN NUMBER,
        p_class_type      IN VARCHAR2
    ) RETURN NUMBER IS
        v_section_id       NUMBER;
        v_theory_conducted NUMBER;
        v_lab_conducted    NUMBER;
        v_theory_attended  NUMBER;
        v_lab_attended     NUMBER;
        v_has_lab          CHAR(1);
    BEGIN
        IF p_class_type NOT IN ('THEORY','LAB','OVERALL') THEN
            RAISE_APPLICATION_ERROR(-20004, 'Invalid class type');
        END IF;

        SELECT r.section_id, c.has_lab
          INTO v_section_id, v_has_lab
          FROM registrations r
          JOIN sections s          ON r.section_id  = s.section_id
          JOIN course_offerings co ON s.offering_id = co.offering_id
          JOIN courses c           ON co.course_id   = c.course_id
         WHERE r.registration_id = p_registration_id;

        -- Conducted: count from class_schedule (no cached counter)
        SELECT COUNT(CASE WHEN class_type='THEORY' THEN 1 END),
               COUNT(CASE WHEN class_type='LAB'    THEN 1 END)
          INTO v_theory_conducted, v_lab_conducted
          FROM class_schedule
         WHERE section_id   = v_section_id
           AND is_cancelled = 'N';

        -- Attended: count from attendance joined with class_schedule
        SELECT COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END),
               COUNT(CASE WHEN cs.class_type='LAB'    AND a.status IN ('P','L','E','OD') THEN 1 END)
          INTO v_theory_attended, v_lab_attended
          FROM attendance a
          JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
         WHERE a.registration_id = p_registration_id;

        IF p_class_type = 'THEORY' THEN
            RETURN CASE WHEN v_theory_conducted > 0
                        THEN ROUND((v_theory_attended / v_theory_conducted) * 100, 2)
                        ELSE 0 END;
        END IF;

        IF p_class_type = 'LAB' THEN
            RETURN CASE WHEN v_has_lab = 'Y' AND v_lab_conducted > 0
                        THEN ROUND((v_lab_attended / v_lab_conducted) * 100, 2)
                        ELSE 0 END;
        END IF;

        RETURN ROUND(
            (CASE WHEN v_theory_conducted > 0
                  THEN (v_theory_attended / v_theory_conducted) * 100
                  ELSE 0 END) * 0.6
            +
            (CASE WHEN v_lab_conducted > 0
                  THEN (v_lab_attended / v_lab_conducted) * 100
                  ELSE 0 END) * 0.4
        , 2);

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20005, 'Invalid registration ID');
    END get_attendance_percentage;

    -- ========================================================================
    -- GET TOTAL CLASSES CONDUCTED
    -- 3NF: computed from class_schedule, not cached column
    -- ========================================================================

    FUNCTION get_total_classes_conducted (
        p_section_id IN NUMBER,
        p_class_type IN VARCHAR2
    ) RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        IF p_class_type NOT IN ('THEORY','LAB') THEN
            RAISE_APPLICATION_ERROR(-20006, 'Invalid class type');
        END IF;

        SELECT COUNT(*)
          INTO v_count
          FROM class_schedule
         WHERE section_id   = p_section_id
           AND class_type   = p_class_type
           AND is_cancelled = 'N';

        RETURN v_count;
    EXCEPTION
        WHEN OTHERS THEN RAISE;
    END get_total_classes_conducted;

    -- ========================================================================
    -- GET STUDENT CLASSES ATTENDED
    -- 3NF: join attendance with class_schedule to get class_type
    -- ========================================================================

    FUNCTION get_student_classes_attended (
        p_registration_id IN NUMBER,
        p_class_type      IN VARCHAR2
    ) RETURN NUMBER IS
        v_count NUMBER;
    BEGIN
        IF p_class_type NOT IN ('THEORY','LAB') THEN
            RAISE_APPLICATION_ERROR(-20008, 'Invalid class type');
        END IF;

        SELECT COUNT(*)
          INTO v_count
          FROM attendance a
          JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
         WHERE a.registration_id = p_registration_id
           AND cs.class_type     = p_class_type
           AND a.status         IN ('P','L','E','OD');

        RETURN v_count;
    EXCEPTION
        WHEN OTHERS THEN RAISE;
    END get_student_classes_attended;

END attendance_manager;
/
