-- ============================================================================
-- 05_views_3nf.sql
-- 3NF Updates:
--   - student_course_overview: attendance aggregation now JOINs
--     class_schedule to obtain class_type.
--   - course_enrollment_summary: added DATE VALIDATION to demand_status
--     so 'AVAILABLE' only shows if the registration period is open.
-- ============================================================================

SET DEFINE OFF;
SET BLANKLINES ON;

-- ============================================================================
-- VIEW: student_course_overview
-- ============================================================================
CREATE OR REPLACE VIEW student_course_overview AS
WITH section_conducted AS (
    SELECT
        section_id,
        COUNT(CASE WHEN class_type = 'THEORY' AND is_cancelled = 'N' THEN 1 END) AS theory_conducted,
        COUNT(CASE WHEN class_type = 'LAB'    AND is_cancelled = 'N' THEN 1 END) AS lab_conducted
      FROM class_schedule
     GROUP BY section_id
),
attendance_agg AS (
    SELECT
        a.registration_id,
        COUNT(DISTINCT CASE
            WHEN cs.class_type = 'THEORY' AND a.status IN ('P','L','E','OD')
            THEN a.schedule_id
        END) AS theory_attended,
        COUNT(DISTINCT CASE
            WHEN cs.class_type = 'LAB' AND a.status IN ('P','L','E','OD')
            THEN a.schedule_id
        END) AS lab_attended
      FROM attendance a
      JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
     GROUP BY a.registration_id
)
SELECT
    s.student_id,
    s.roll_number,
    s.first_name || ' ' || s.last_name AS student_name,
    r.registration_id,
    r.registration_status,
    t.term_id,
    t.term_name,
    t.academic_year,
    c.course_id,
    c.course_code,
    c.course_name,
    c.credits,
    sec.section_id,
    sec.section_code,
    ROUND(CASE WHEN NVL(sc.theory_conducted, 0) > 0 THEN (NVL(aa.theory_attended, 0) * 100.0) / sc.theory_conducted ELSE 0 END, 2) AS theory_attendance,
    ROUND(CASE WHEN NVL(sc.lab_conducted, 0) > 0 THEN (NVL(aa.lab_attended, 0) * 100.0) / sc.lab_conducted ELSE 0 END, 2) AS lab_attendance,
    ROUND((CASE WHEN NVL(sc.theory_conducted, 0) > 0 THEN (NVL(aa.theory_attended, 0) * 100.0) / sc.theory_conducted ELSE 0 END) * 0.6 + 
          (CASE WHEN NVL(sc.lab_conducted, 0) > 0 THEN (NVL(aa.lab_attended, 0) * 100.0) / sc.lab_conducted ELSE 0 END) * 0.4, 2) AS overall_attendance
FROM students s
JOIN registrations r     ON s.student_id    = r.student_id
JOIN sections sec        ON r.section_id    = sec.section_id
JOIN course_offerings co ON sec.offering_id = co.offering_id
JOIN courses c           ON co.course_id    = c.course_id
JOIN academic_terms t    ON r.term_id       = t.term_id
LEFT JOIN section_conducted sc ON sec.section_id = sc.section_id
LEFT JOIN attendance_agg aa    ON r.registration_id = aa.registration_id
WHERE r.registration_status IN ('REGISTERED','APPROVED','COMPLETED') AND (t.is_current = 'Y' OR t.term_id = 2);
/

-- ============================================================================
-- VIEW: course_enrollment_summary (With Date Validation)
-- ============================================================================
CREATE OR REPLACE VIEW course_enrollment_summary AS
SELECT
    c.course_id,
    c.course_code,
    c.course_name,
    t.term_id,
    t.term_name,
    t.academic_year,
    t.registration_start_date,
    t.registration_end_date,
    sec.section_id,
    sec.section_code,
    sec.max_capacity,
    sec.current_enrollment,
    sec.current_waitlist,
    GREATEST(sec.max_capacity - sec.current_enrollment, 0) AS seats_available,
    ROUND(CASE WHEN sec.max_capacity > 0 THEN (sec.current_enrollment * 100.0) / sec.max_capacity ELSE 0 END, 2) AS fill_percentage,
    ROUND(sec.current_enrollment / NULLIF(sec.max_capacity, 0), 2) AS load_ratio,
    -- Enhanced Status Logic: Check dates first, then capacity
    CASE
        WHEN CURRENT_DATE < t.registration_start_date           THEN 'UPCOMING'
        WHEN CURRENT_DATE > t.registration_end_date             THEN 'CLOSED'
        WHEN sec.current_enrollment > sec.max_capacity           THEN 'DATA_ERROR'
        WHEN sec.current_enrollment >= sec.max_capacity 
             AND sec.current_waitlist > 0                       THEN 'HIGH_DEMAND'
        WHEN sec.current_enrollment >= sec.max_capacity          THEN 'FULL'
        WHEN sec.current_enrollment >= 0.75 * sec.max_capacity   THEN 'FILLING_FAST'
        ELSE 'AVAILABLE'
    END AS demand_status
FROM courses c
JOIN course_offerings co ON c.course_id    = co.course_id
JOIN sections sec        ON co.offering_id = sec.offering_id
JOIN academic_terms t    ON co.term_id     = t.term_id
WHERE c.is_active   = 'Y'
  AND co.is_active  = 'Y'
  AND sec.is_active = 'Y';
/