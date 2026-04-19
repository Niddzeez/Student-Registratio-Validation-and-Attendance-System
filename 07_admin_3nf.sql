-- ============================================================================
-- 07_admin_3nf.sql
--
-- ADMIN SUBSYSTEM — 3NF compliant
--
-- New table:  admin_users
--   Stores admin credentials and audit metadata.
--   admin_id → (username, email, is_active, created_at, last_login_at)
--   No transitive dependencies — all non-key columns depend solely on admin_id.
--
-- New package: admin_manager
--   All UI operations go through this package (mirrors the pattern of
--   registration_manager and attendance_manager).
--
--   Procedures:
--     create_course         — creates a new course with all attributes
--                             including max_sections (the admin-set cap on
--                             how many sections faculty may float per term)
--     register_faculty      — creates a faculty record
--     register_student      — creates a student record
--     float_course_offering — creates a course_offering + optional first section
--                             for an upcoming term (admin "floats" the course)
--     update_student_status — activate / deactivate a student
--     update_faculty_status — activate / deactivate a faculty member
--     update_term_status    — flip is_current flag safely (only one term current)
--     create_academic_term  — create a new term
--     update_course_max_sections — change the max_sections cap on a course
--
--   Functions:
--     admin_login           — returns 1 if credentials match, 0 otherwise
--     student_exists        — guard against duplicate roll numbers
--     faculty_exists        — guard against duplicate employee IDs
--     course_exists         — guard against duplicate course codes
-- ============================================================================

-- ============================================================================
-- TABLE: admin_users
-- 3NF:  admin_id (PK) → all columns.  No partial or transitive dependencies.
-- ============================================================================

DROP TABLE admin_users CASCADE CONSTRAINTS;
DROP SEQUENCE admin_seq;

CREATE TABLE admin_users (
    admin_id      NUMBER        PRIMARY KEY,
    username      VARCHAR2(50)  UNIQUE NOT NULL,
    password_hash VARCHAR2(200) NOT NULL,        -- store hashed; plain for demo
    full_name     VARCHAR2(100) NOT NULL,
    email         VARCHAR2(100) UNIQUE NOT NULL,
    is_active     CHAR(1)       DEFAULT 'Y'
        CHECK (is_active IN ('Y','N')),
    last_login_at TIMESTAMP,
    created_at    TIMESTAMP     DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE admin_seq START WITH 1 INCREMENT BY 1;

-- Seed a default admin (password = "admin123" stored plain for demo;
-- swap with bcrypt hash in production)
INSERT INTO admin_users (admin_id, username, password_hash, full_name, email)
VALUES (admin_seq.NEXTVAL, 'admin', 'admin123', 'System Administrator', 'admin@vnit.ac.in');
COMMIT;

-- ============================================================================
-- PACKAGE SPECIFICATION: admin_manager
-- ============================================================================

DROP PACKAGE admin_manager;

CREATE OR REPLACE PACKAGE admin_manager AS

    -- ── Authentication ───────────────────────────────────────────────────────
    FUNCTION admin_login (
        p_username      IN  VARCHAR2,
        p_password      IN  VARCHAR2,
        p_admin_id      OUT NUMBER,
        p_full_name     OUT VARCHAR2
    ) RETURN NUMBER;   -- 1 = success, 0 = failure

    -- ── Course Creation ──────────────────────────────────────────────────────
    -- Admin creates a brand-new course with all metadata, including the
    -- max_sections cap.  Faculty may then float sections (up to max_sections
    -- per term) once the admin has floated the course offering.
    PROCEDURE create_course (
        p_course_code      IN  VARCHAR2,
        p_course_name      IN  VARCHAR2,
        p_dept_id          IN  NUMBER,
        p_course_type      IN  VARCHAR2,   -- DC|DE|OC|HM|BS|ES|AU
        p_credits          IN  NUMBER,
        p_lecture_hours    IN  NUMBER,
        p_tutorial_hours   IN  NUMBER,
        p_practical_hours  IN  NUMBER,
        p_has_lab          IN  CHAR,       -- 'Y' or 'N'
        p_typical_semester IN  NUMBER,
        p_max_sections     IN  NUMBER,     -- admin-set cap (e.g. 3 means max 3 sections per term)
        p_description      IN  VARCHAR2,
        p_course_id        OUT NUMBER,
        p_success          OUT NUMBER,
        p_message          OUT VARCHAR2
    );

    -- ── Update max_sections on an existing course ────────────────────────────
    PROCEDURE update_course_max_sections (
        p_course_id    IN  NUMBER,
        p_max_sections IN  NUMBER,
        p_success      OUT NUMBER,
        p_message      OUT VARCHAR2
    );

    -- ── Faculty Registration ─────────────────────────────────────────────────
    PROCEDURE register_faculty (
        p_employee_id     IN  VARCHAR2,
        p_first_name      IN  VARCHAR2,
        p_last_name       IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_dept_id         IN  NUMBER,
        p_designation     IN  VARCHAR2,
        p_specialization  IN  VARCHAR2,
        p_faculty_id      OUT NUMBER,
        p_success         OUT NUMBER,          -- 1/0 (avoids BOOLEAN over OCI)
        p_message         OUT VARCHAR2
    );

    -- ── Student Registration ─────────────────────────────────────────────────
    PROCEDURE register_student (
        p_roll_number     IN  VARCHAR2,
        p_first_name      IN  VARCHAR2,
        p_last_name       IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_batch_id        IN  NUMBER,
        p_current_semester IN NUMBER,
        p_date_of_birth   IN  DATE,
        p_student_id      OUT NUMBER,
        p_success         OUT NUMBER,
        p_message         OUT VARCHAR2
    );

    -- ── Float Course for Upcoming Term ───────────────────────────────────────
    PROCEDURE float_course_offering (
        p_course_id          IN  NUMBER,
        p_term_id            IN  NUMBER,
        p_theory_slot_id     IN  NUMBER,
        p_lab_slot_id        IN  NUMBER,         -- NULL if no lab
        p_offering_id        OUT NUMBER,
        p_success            OUT NUMBER,
        p_message            OUT VARCHAR2
    );

    -- ── Status Management ────────────────────────────────────────────────────
    PROCEDURE update_student_status (
        p_student_id  IN  NUMBER,
        p_is_active   IN  CHAR,
        p_success     OUT NUMBER,
        p_message     OUT VARCHAR2
    );

    PROCEDURE update_faculty_status (
        p_faculty_id  IN  NUMBER,
        p_is_active   IN  CHAR,
        p_success     OUT NUMBER,
        p_message     OUT VARCHAR2
    );

    -- ── Term Management ──────────────────────────────────────────────────────
    PROCEDURE create_academic_term (
        p_term_code               IN  VARCHAR2,
        p_term_name               IN  VARCHAR2,
        p_academic_year           IN  VARCHAR2,
        p_term_type               IN  VARCHAR2,
        p_start_date              IN  DATE,
        p_end_date                IN  DATE,
        p_registration_start_date IN  DATE,
        p_registration_end_date   IN  DATE,
        p_term_id                 OUT NUMBER,
        p_success                 OUT NUMBER,
        p_message                 OUT VARCHAR2
    );

    PROCEDURE set_current_term (
        p_term_id  IN  NUMBER,
        p_success  OUT NUMBER,
        p_message  OUT VARCHAR2
    );

    -- ── Course Eligibility Management ─────────────────────────────────────────
    -- Eligibility rules live in the course_eligibility table (3NF: the table's
    -- PK eligibility_id → course_id, dept_id, program_id, min_semester,
    -- max_semester, priority — no attribute depends on anything but the PK).
    -- The courses row itself never stores eligibility data, preserving 3NF.
    --
    -- If a course has zero rows in course_eligibility it is open to all
    -- students (check_eligibility in registration_manager returns TRUE).
    PROCEDURE add_course_eligibility_rule (
        p_course_id    IN  NUMBER,
        p_dept_id      IN  NUMBER,     -- NULL = any department
        p_program_id   IN  NUMBER,     -- NULL = any program
        p_min_semester IN  NUMBER,     -- NULL = no lower bound
        p_max_semester IN  NUMBER,     -- NULL = no upper bound
        p_priority     IN  NUMBER,     -- 1 (highest) – 100 (lowest), default 99
        p_success      OUT NUMBER,
        p_message      OUT VARCHAR2
    );

    PROCEDURE delete_course_eligibility_rule (
        p_eligibility_id IN  NUMBER,
        p_course_id      IN  NUMBER,   -- guard: must match the stored course_id
        p_success        OUT NUMBER,
        p_message        OUT VARCHAR2
    );

    -- ── Prerequisites ────────────────────────────────────────────────────────
    PROCEDURE add_course_prerequisite (
        p_course_id              IN  NUMBER,
        p_prerequisite_course_id IN  NUMBER,
        p_is_mandatory           IN  CHAR DEFAULT 'Y',  -- 'Y' hard req / 'N' recommended
        p_success                OUT NUMBER,
        p_message                OUT VARCHAR2
    );

    PROCEDURE delete_course_prerequisite (
        p_course_id              IN  NUMBER,
        p_prerequisite_course_id IN  NUMBER,
        p_success                OUT NUMBER,
        p_message                OUT VARCHAR2
    );

    -- ── Guard Functions ──────────────────────────────────────────────────────
    FUNCTION student_exists  (p_roll_number IN VARCHAR2) RETURN NUMBER;
    FUNCTION faculty_exists  (p_employee_id IN VARCHAR2) RETURN NUMBER;
    FUNCTION offering_exists (p_course_id   IN NUMBER, p_term_id IN NUMBER) RETURN NUMBER;
    FUNCTION course_exists   (p_course_code IN VARCHAR2) RETURN NUMBER;

END admin_manager;
/

-- ============================================================================
-- PACKAGE BODY: admin_manager
-- ============================================================================

CREATE OR REPLACE PACKAGE BODY admin_manager AS

    -- ========================================================================
    -- ADMIN LOGIN
    -- Returns 1 on success (also stamps last_login_at), 0 on failure.
    -- ========================================================================
    FUNCTION admin_login (
        p_username  IN  VARCHAR2,
        p_password  IN  VARCHAR2,
        p_admin_id  OUT NUMBER,
        p_full_name OUT VARCHAR2
    ) RETURN NUMBER IS
        v_stored_hash VARCHAR2(200);
        v_is_active   CHAR(1);
    BEGIN
        SELECT admin_id, password_hash, full_name, is_active
          INTO p_admin_id, v_stored_hash, p_full_name, v_is_active
          FROM admin_users
         WHERE username = p_username;

        IF v_is_active != 'Y' THEN
            p_admin_id := NULL; p_full_name := NULL; RETURN 0;
        END IF;

        -- Plain-text comparison for demo; replace with crypto comparison in prod
        IF v_stored_hash != p_password THEN
            p_admin_id := NULL; p_full_name := NULL; RETURN 0;
        END IF;

        UPDATE admin_users SET last_login_at = SYSTIMESTAMP
         WHERE admin_id = p_admin_id;

        RETURN 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_admin_id := NULL; p_full_name := NULL; RETURN 0;
        WHEN OTHERS THEN
            p_admin_id := NULL; p_full_name := NULL; RETURN 0;
    END admin_login;

    -- ========================================================================
    -- CREATE COURSE
    -- Admin-only.  Creates a new course record including the max_sections cap.
    --
    -- 3NF note: max_sections is stored directly on courses because
    --   course_id → max_sections with no intermediate dependency.
    --   The actual count of active sections per term is always derived
    --   via COUNT(*) on sections JOIN course_offerings — it is never cached.
    -- ========================================================================
    PROCEDURE create_course (
        p_course_code      IN  VARCHAR2,
        p_course_name      IN  VARCHAR2,
        p_dept_id          IN  NUMBER,
        p_course_type      IN  VARCHAR2,
        p_credits          IN  NUMBER,
        p_lecture_hours    IN  NUMBER,
        p_tutorial_hours   IN  NUMBER,
        p_practical_hours  IN  NUMBER,
        p_has_lab          IN  CHAR,
        p_typical_semester IN  NUMBER,
        p_max_sections     IN  NUMBER,
        p_description      IN  VARCHAR2,
        p_course_id        OUT NUMBER,
        p_success          OUT NUMBER,
        p_message          OUT VARCHAR2
    ) IS
        v_dept_count NUMBER;
    BEGIN
        -- Validate department
        SELECT COUNT(*) INTO v_dept_count
          FROM departments WHERE dept_id = p_dept_id;
        IF v_dept_count = 0 THEN
            p_success := 0; p_message := 'Invalid department ID'; RETURN;
        END IF;

        -- Validate course_type
        IF p_course_type NOT IN ('DC','DE','OC','HM','BS','ES','AU') THEN
            p_success := 0;
            p_message := 'course_type must be one of: DC, DE, OC, HM, BS, ES, AU';
            RETURN;
        END IF;

        -- Validate credits
        IF p_credits <= 0 OR p_credits > 10 THEN
            p_success := 0; p_message := 'credits must be between 1 and 10'; RETURN;
        END IF;

        -- Validate max_sections
        IF p_max_sections IS NULL OR p_max_sections <= 0 OR p_max_sections > 50 THEN
            p_success := 0;
            p_message := 'max_sections must be between 1 and 50';
            RETURN;
        END IF;

        -- Validate has_lab vs practical_hours consistency
        IF p_has_lab = 'Y' AND NVL(p_practical_hours, 0) = 0 THEN
            p_success := 0;
            p_message := 'practical_hours must be > 0 when has_lab = Y';
            RETURN;
        END IF;
        IF p_has_lab = 'N' AND NVL(p_practical_hours, 0) > 0 THEN
            p_success := 0;
            p_message := 'practical_hours must be 0 when has_lab = N';
            RETURN;
        END IF;

        -- Validate typical_semester
        IF p_typical_semester IS NOT NULL AND
           (p_typical_semester < 1 OR p_typical_semester > 8) THEN
            p_success := 0;
            p_message := 'typical_semester must be between 1 and 8';
            RETURN;
        END IF;

        -- Duplicate course code check
        IF course_exists(p_course_code) = 1 THEN
            p_success := 0;
            p_message := 'Course code ' || UPPER(TRIM(p_course_code)) || ' already exists';
            RETURN;
        END IF;

        SELECT course_seq.NEXTVAL INTO p_course_id FROM dual;

        INSERT INTO courses (
            course_id, course_code, course_name,
            dept_id, course_type,
            lecture_hours, tutorial_hours, practical_hours,
            credits, typical_semester,
            has_lab, max_sections,
            description, is_active, created_at
        ) VALUES (
            p_course_id,
            UPPER(TRIM(p_course_code)),
            TRIM(p_course_name),
            p_dept_id,
            UPPER(TRIM(p_course_type)),
            NVL(p_lecture_hours,   0),
            NVL(p_tutorial_hours,  0),
            NVL(p_practical_hours, 0),
            p_credits,
            p_typical_semester,
            NVL(p_has_lab, 'N'),
            p_max_sections,
            p_description,
            'Y',
            SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Course ' || UPPER(TRIM(p_course_code))
                     || ' created successfully (max_sections=' || p_max_sections || ')';

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0;
            p_message := 'Course code already exists';
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error creating course: ' || SQLERRM;
    END create_course;

    -- ========================================================================
    -- UPDATE COURSE MAX SECTIONS
    -- Allows admin to raise or lower the section cap on an existing course.
    -- Lowering below the current active section count is blocked to preserve
    -- consistency — you cannot retroactively violate already-floated sections.
    -- ========================================================================
    PROCEDURE update_course_max_sections (
        p_course_id    IN  NUMBER,
        p_max_sections IN  NUMBER,
        p_success      OUT NUMBER,
        p_message      OUT VARCHAR2
    ) IS
        v_course_count    NUMBER;
        v_active_sections NUMBER;
    BEGIN
        -- Course must exist
        SELECT COUNT(*) INTO v_course_count
          FROM courses WHERE course_id = p_course_id;
        IF v_course_count = 0 THEN
            p_success := 0; p_message := 'Course not found'; RETURN;
        END IF;

        -- Validate new value
        IF p_max_sections IS NULL OR p_max_sections <= 0 OR p_max_sections > 50 THEN
            p_success := 0;
            p_message := 'max_sections must be between 1 and 50';
            RETURN;
        END IF;

        -- Guard: do not allow lowering below the current maximum active
        -- sections count across all terms for this course.
        -- This prevents the cap from being set to a value that would
        -- retroactively conflict with already-floated sections.
        SELECT NVL(MAX(term_section_count), 0)
          INTO v_active_sections
          FROM (
              SELECT co.term_id, COUNT(*) AS term_section_count
                FROM sections s
                JOIN course_offerings co ON s.offering_id = co.offering_id
               WHERE co.course_id = p_course_id
                 AND s.is_active  = 'Y'
               GROUP BY co.term_id
          );

        IF p_max_sections < v_active_sections THEN
            p_success := 0;
            p_message := 'Cannot set max_sections to ' || p_max_sections
                         || '; a term already has ' || v_active_sections
                         || ' active section(s). Please deactivate sections first.';
            RETURN;
        END IF;

        UPDATE courses
           SET max_sections = p_max_sections
         WHERE course_id = p_course_id;

        p_success := 1;
        p_message := 'max_sections updated to ' || p_max_sections
                     || ' for course_id=' || p_course_id;
    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error: ' || SQLERRM;
    END update_course_max_sections;

    -- ========================================================================
    -- REGISTER FACULTY
    -- ========================================================================
    PROCEDURE register_faculty (
        p_employee_id     IN  VARCHAR2,
        p_first_name      IN  VARCHAR2,
        p_last_name       IN  VARCHAR2,
        p_email           IN  VARCHAR2,
        p_phone           IN  VARCHAR2,
        p_dept_id         IN  NUMBER,
        p_designation     IN  VARCHAR2,
        p_specialization  IN  VARCHAR2,
        p_faculty_id      OUT NUMBER,
        p_success         OUT NUMBER,
        p_message         OUT VARCHAR2
    ) IS
        v_dept_count NUMBER;
    BEGIN
        -- Validate department
        SELECT COUNT(*) INTO v_dept_count
          FROM departments WHERE dept_id = p_dept_id;
        IF v_dept_count = 0 THEN
            p_success := 0; p_message := 'Invalid department ID'; RETURN;
        END IF;

        -- Duplicate employee ID
        IF faculty_exists(p_employee_id) = 1 THEN
            p_success := 0;
            p_message := 'Employee ID ' || p_employee_id || ' already exists';
            RETURN;
        END IF;

        -- Duplicate email
        BEGIN
            DECLARE v_dummy NUMBER;
            BEGIN
                SELECT 1 INTO v_dummy FROM faculty WHERE email = p_email;
                p_success := 0; p_message := 'Email already in use'; RETURN;
            EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
            END;
        END;

        SELECT faculty_seq.NEXTVAL INTO p_faculty_id FROM dual;

        INSERT INTO faculty (
            faculty_id, employee_id, first_name, last_name,
            email, phone, dept_id, designation, specialization,
            is_active, created_at
        ) VALUES (
            p_faculty_id, UPPER(TRIM(p_employee_id)),
            TRIM(p_first_name), TRIM(p_last_name),
            LOWER(TRIM(p_email)), p_phone,
            p_dept_id, p_designation, p_specialization,
            'Y', SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Faculty ' || p_employee_id || ' registered successfully';

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0;
            p_message := 'Duplicate key: employee_id or email already exists';
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error registering faculty: ' || SQLERRM;
    END register_faculty;

    -- ========================================================================
    -- REGISTER STUDENT
    -- ========================================================================
    PROCEDURE register_student (
        p_roll_number      IN  VARCHAR2,
        p_first_name       IN  VARCHAR2,
        p_last_name        IN  VARCHAR2,
        p_email            IN  VARCHAR2,
        p_phone            IN  VARCHAR2,
        p_batch_id         IN  NUMBER,
        p_current_semester IN  NUMBER,
        p_date_of_birth    IN  DATE,
        p_student_id       OUT NUMBER,
        p_success          OUT NUMBER,
        p_message          OUT VARCHAR2
    ) IS
        v_batch_count   NUMBER;
        v_prog_semesters NUMBER;
    BEGIN
        -- Validate batch
        SELECT COUNT(*) INTO v_batch_count
          FROM batches WHERE batch_id = p_batch_id AND is_active = 'Y';
        IF v_batch_count = 0 THEN
            p_success := 0; p_message := 'Invalid or inactive batch ID'; RETURN;
        END IF;

        -- Validate semester against program max
        SELECT d.total_semesters INTO v_prog_semesters
          FROM batches b
          JOIN programs p  ON b.program_id = p.program_id
          JOIN departments d ON p.dept_id  = d.dept_id
         WHERE b.batch_id = p_batch_id;

        IF p_current_semester < 1 OR p_current_semester > v_prog_semesters THEN
            p_success := 0;
            p_message := 'Semester must be between 1 and ' || v_prog_semesters;
            RETURN;
        END IF;

        -- Duplicate roll number
        IF student_exists(p_roll_number) = 1 THEN
            p_success := 0;
            p_message := 'Roll number ' || p_roll_number || ' already exists';
            RETURN;
        END IF;

        -- Duplicate email
        BEGIN
            DECLARE v_dummy NUMBER;
            BEGIN
                SELECT 1 INTO v_dummy FROM students WHERE email = p_email;
                p_success := 0; p_message := 'Email already in use'; RETURN;
            EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
            END;
        END;

        SELECT student_seq.NEXTVAL INTO p_student_id FROM dual;

        INSERT INTO students (
            student_id, roll_number, first_name, last_name,
            email, phone, batch_id, current_semester,
            date_of_birth, enrollment_date, is_active, created_at
        ) VALUES (
            p_student_id, UPPER(TRIM(p_roll_number)),
            TRIM(p_first_name), TRIM(p_last_name),
            LOWER(TRIM(p_email)), p_phone,
            p_batch_id, p_current_semester,
            p_date_of_birth, SYSDATE, 'Y', SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Student ' || p_roll_number || ' registered successfully';

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0;
            p_message := 'Duplicate key: roll_number or email already exists';
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error registering student: ' || SQLERRM;
    END register_student;

    -- ========================================================================
    -- FLOAT COURSE OFFERING (Admin floats a course for an upcoming term)
    -- Creates a course_offering.  Section creation is done separately
    -- by faculty (existing float-section endpoint) or can be admin-initiated.
    -- ========================================================================
    PROCEDURE float_course_offering (
        p_course_id      IN  NUMBER,
        p_term_id        IN  NUMBER,
        p_theory_slot_id IN  NUMBER,
        p_lab_slot_id    IN  NUMBER,
        p_offering_id    OUT NUMBER,
        p_success        OUT NUMBER,
        p_message        OUT VARCHAR2
    ) IS
        v_course_active CHAR(1);
        v_term_start    DATE;
        v_slot_type     VARCHAR2(20);
        v_lab_slot_type VARCHAR2(20);
    BEGIN
        -- Course must be active
        SELECT is_active INTO v_course_active
          FROM courses WHERE course_id = p_course_id;
        IF v_course_active != 'Y' THEN
            p_success := 0; p_message := 'Course is inactive'; RETURN;
        END IF;

        -- Term must be in the future (admin can only float for upcoming terms)
        SELECT start_date INTO v_term_start
          FROM academic_terms WHERE term_id = p_term_id;
        IF TRUNC(v_term_start) <= TRUNC(SYSDATE) THEN
            p_success := 0;
            p_message := 'Can only float offerings for future terms';
            RETURN;
        END IF;

        -- Duplicate offering guard
        IF offering_exists(p_course_id, p_term_id) = 1 THEN
            p_success := 0;
            p_message := 'An offering for this course already exists in that term';
            RETURN;
        END IF;

        -- Theory slot must be THEORY type
        SELECT slot_type INTO v_slot_type
          FROM slots WHERE slot_id = p_theory_slot_id AND is_active = 'Y';
        IF v_slot_type != 'THEORY' THEN
            p_success := 0; p_message := 'theory_slot_id must reference a THEORY slot'; RETURN;
        END IF;

        -- Lab slot validation (if provided)
        IF p_lab_slot_id IS NOT NULL THEN
            BEGIN
                SELECT slot_type INTO v_lab_slot_type
                  FROM slots WHERE slot_id = p_lab_slot_id AND is_active = 'Y';
                IF v_lab_slot_type != 'LAB' THEN
                    p_success := 0; p_message := 'lab_slot_id must reference a LAB slot'; RETURN;
                END IF;
            EXCEPTION WHEN NO_DATA_FOUND THEN
                p_success := 0; p_message := 'Invalid lab slot ID'; RETURN;
            END;
        END IF;

        SELECT offering_seq.NEXTVAL INTO p_offering_id FROM dual;

        INSERT INTO course_offerings (
            offering_id, course_id, term_id,
            theory_slot_id, lab_slot_id, is_active, created_at
        ) VALUES (
            p_offering_id, p_course_id, p_term_id,
            p_theory_slot_id, p_lab_slot_id, 'Y', SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Course offering created successfully (offering_id=' || p_offering_id || ')';

    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            p_success := 0; p_message := 'Invalid course_id, term_id, or slot_id';
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0; p_message := 'Offering already exists for this course/term';
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error floating offering: ' || SQLERRM;
    END float_course_offering;

    -- ========================================================================
    -- UPDATE STUDENT STATUS
    -- ========================================================================
    PROCEDURE update_student_status (
        p_student_id IN  NUMBER,
        p_is_active  IN  CHAR,
        p_success    OUT NUMBER,
        p_message    OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        IF p_is_active NOT IN ('Y','N') THEN
            p_success := 0; p_message := 'is_active must be Y or N'; RETURN;
        END IF;
        SELECT COUNT(*) INTO v_count FROM students WHERE student_id = p_student_id;
        IF v_count = 0 THEN
            p_success := 0; p_message := 'Student not found'; RETURN;
        END IF;
        UPDATE students SET is_active = p_is_active WHERE student_id = p_student_id;
        p_success := 1;
        p_message := 'Student status updated to ' || p_is_active;
    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error: ' || SQLERRM;
    END update_student_status;

    -- ========================================================================
    -- UPDATE FACULTY STATUS
    -- ========================================================================
    PROCEDURE update_faculty_status (
        p_faculty_id IN  NUMBER,
        p_is_active  IN  CHAR,
        p_success    OUT NUMBER,
        p_message    OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        IF p_is_active NOT IN ('Y','N') THEN
            p_success := 0; p_message := 'is_active must be Y or N'; RETURN;
        END IF;
        SELECT COUNT(*) INTO v_count FROM faculty WHERE faculty_id = p_faculty_id;
        IF v_count = 0 THEN
            p_success := 0; p_message := 'Faculty not found'; RETURN;
        END IF;
        UPDATE faculty SET is_active = p_is_active WHERE faculty_id = p_faculty_id;
        p_success := 1;
        p_message := 'Faculty status updated to ' || p_is_active;
    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error: ' || SQLERRM;
    END update_faculty_status;

    -- ========================================================================
    -- CREATE ACADEMIC TERM
    -- ========================================================================
    PROCEDURE create_academic_term (
        p_term_code               IN  VARCHAR2,
        p_term_name               IN  VARCHAR2,
        p_academic_year           IN  VARCHAR2,
        p_term_type               IN  VARCHAR2,
        p_start_date              IN  DATE,
        p_end_date                IN  DATE,
        p_registration_start_date IN  DATE,
        p_registration_end_date   IN  DATE,
        p_term_id                 OUT NUMBER,
        p_success                 OUT NUMBER,
        p_message                 OUT VARCHAR2
    ) IS
    BEGIN
        IF p_end_date <= p_start_date THEN
            p_success := 0; p_message := 'end_date must be after start_date'; RETURN;
        END IF;
        IF p_registration_start_date > p_registration_end_date THEN
            p_success := 0; p_message := 'registration_start_date must be <= registration_end_date'; RETURN;
        END IF;
        IF p_term_type NOT IN ('ODD','EVEN','SUMMER') THEN
            p_success := 0; p_message := 'term_type must be ODD, EVEN, or SUMMER'; RETURN;
        END IF;

        SELECT term_seq.NEXTVAL INTO p_term_id FROM dual;

        INSERT INTO academic_terms (
            term_id, term_code, term_name, academic_year, term_type,
            start_date, end_date,
            registration_start_date, registration_end_date,
            is_current, created_at
        ) VALUES (
            p_term_id, UPPER(TRIM(p_term_code)), TRIM(p_term_name),
            p_academic_year, p_term_type,
            p_start_date, p_end_date,
            p_registration_start_date, p_registration_end_date,
            'N', SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Term created successfully (term_id=' || p_term_id || ')';
    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0; p_message := 'Term code already exists';
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error creating term: ' || SQLERRM;
    END create_academic_term;

    -- ========================================================================
    -- SET CURRENT TERM  (flips is_current safely — only one term = 'Y' at once)
    -- The unique index idx_one_current_term on academic_terms enforces this.
    -- ========================================================================
    PROCEDURE set_current_term (
        p_term_id IN  NUMBER,
        p_success             OUT NUMBER,
        p_message             OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM academic_terms WHERE term_id = p_term_id;
        IF v_count = 0 THEN
            p_success := 0; p_message := 'Term not found'; RETURN;
        END IF;

        -- Clear existing current flag first (unique index allows at most one 'Y')
        UPDATE academic_terms SET is_current = 'N' WHERE is_current = 'Y';

        UPDATE academic_terms SET is_current = 'Y' WHERE term_id = p_term_id;

        p_success := 1;
        p_message := 'Term ' || p_term_id || ' is now the current term';
    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0; p_message := 'Error: ' || SQLERRM;
    END set_current_term;

    -- ========================================================================
    -- ADD COURSE ELIGIBILITY RULE
    --
    -- 3NF note: inserts into the separate course_eligibility table.
    --   PK: eligibility_id (sequence-generated)
    --   eligibility_id → course_id, dept_id, program_id,
    --                    min_semester, max_semester, priority
    --   No transitive dependency — all attributes depend solely on the PK.
    --
    -- NULL for dept_id / program_id / min_semester / max_semester means
    -- "no restriction on that dimension".  The check_eligibility function
    -- in registration_manager treats NULL columns as wildcards.
    -- ========================================================================
    PROCEDURE add_course_eligibility_rule (
        p_course_id    IN  NUMBER,
        p_dept_id      IN  NUMBER,
        p_program_id   IN  NUMBER,
        p_min_semester IN  NUMBER,
        p_max_semester IN  NUMBER,
        p_priority     IN  NUMBER,
        p_success      OUT NUMBER,
        p_message      OUT VARCHAR2
    ) IS
        v_course_count  NUMBER;
        v_dept_count    NUMBER;
        v_prog_count    NUMBER;
        v_eligib_id     NUMBER;
        v_priority      NUMBER := NVL(p_priority, 99);
    BEGIN
        -- Course must exist
        SELECT COUNT(*) INTO v_course_count
          FROM courses WHERE course_id = p_course_id;
        IF v_course_count = 0 THEN
            p_success := 0; p_message := 'Course not found'; RETURN;
        END IF;

        -- dept_id must be valid when supplied
        IF p_dept_id IS NOT NULL THEN
            SELECT COUNT(*) INTO v_dept_count
              FROM departments WHERE dept_id = p_dept_id;
            IF v_dept_count = 0 THEN
                p_success := 0; p_message := 'Invalid dept_id'; RETURN;
            END IF;
        END IF;

        -- program_id must be valid when supplied
        IF p_program_id IS NOT NULL THEN
            SELECT COUNT(*) INTO v_prog_count
              FROM programs WHERE program_id = p_program_id;
            IF v_prog_count = 0 THEN
                p_success := 0; p_message := 'Invalid program_id'; RETURN;
            END IF;
        END IF;

        -- Semester range validation
        IF p_min_semester IS NOT NULL AND (p_min_semester < 1 OR p_min_semester > 8) THEN
            p_success := 0; p_message := 'min_semester must be between 1 and 8'; RETURN;
        END IF;
        IF p_max_semester IS NOT NULL AND (p_max_semester < 1 OR p_max_semester > 8) THEN
            p_success := 0; p_message := 'max_semester must be between 1 and 8'; RETURN;
        END IF;
        IF p_min_semester IS NOT NULL AND p_max_semester IS NOT NULL
           AND p_min_semester > p_max_semester THEN
            p_success := 0; p_message := 'min_semester must be <= max_semester'; RETURN;
        END IF;

        -- Priority range
        IF v_priority < 1 OR v_priority > 100 THEN
            p_success := 0; p_message := 'priority must be between 1 and 100'; RETURN;
        END IF;

        SELECT eligibility_seq.NEXTVAL INTO v_eligib_id FROM dual;

        INSERT INTO course_eligibility (
            eligibility_id, course_id,
            dept_id, program_id,
            min_semester, max_semester,
            priority, created_at
        ) VALUES (
            v_eligib_id, p_course_id,
            p_dept_id, p_program_id,
            p_min_semester, p_max_semester,
            v_priority, SYSTIMESTAMP
        );

        p_success := 1;
        p_message := 'Eligibility rule added (eligibility_id=' || v_eligib_id || ')';

    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error adding eligibility rule: ' || SQLERRM;
    END add_course_eligibility_rule;

    -- ========================================================================
    -- DELETE COURSE ELIGIBILITY RULE
    -- Removes a single row from course_eligibility.
    -- p_course_id is a safety guard — deletion only proceeds if the row
    -- belongs to the stated course, preventing cross-course accidents.
    -- ========================================================================
    PROCEDURE delete_course_eligibility_rule (
        p_eligibility_id IN  NUMBER,
        p_course_id      IN  NUMBER,
        p_success        OUT NUMBER,
        p_message        OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM course_eligibility
         WHERE eligibility_id = p_eligibility_id
           AND course_id      = p_course_id;

        IF v_count = 0 THEN
            p_success := 0;
            p_message := 'Eligibility rule not found for this course';
            RETURN;
        END IF;

        DELETE FROM course_eligibility
         WHERE eligibility_id = p_eligibility_id
           AND course_id      = p_course_id;

        p_success := 1;
        p_message := 'Eligibility rule ' || p_eligibility_id || ' deleted';

    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error deleting eligibility rule: ' || SQLERRM;
    END delete_course_eligibility_rule;

    -- ========================================================================
    -- ADD COURSE PREREQUISITE
    -- Links a prerequisite course to a course.
    -- is_mandatory='Y' → student must have passed it to register.
    -- is_mandatory='N' → recommended only (advisory).
    -- ========================================================================
    PROCEDURE add_course_prerequisite (
        p_course_id              IN  NUMBER,
        p_prerequisite_course_id IN  NUMBER,
        p_is_mandatory           IN  CHAR DEFAULT 'Y',
        p_success                OUT NUMBER,
        p_message                OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        -- Guard: a course cannot be its own prerequisite
        IF p_course_id = p_prerequisite_course_id THEN
            p_success := 0;
            p_message := 'A course cannot be its own prerequisite';
            RETURN;
        END IF;

        -- Guard: prerequisite course must exist and be active
        SELECT COUNT(*) INTO v_count
          FROM courses
         WHERE course_id = p_prerequisite_course_id AND is_active = 'Y';
        IF v_count = 0 THEN
            p_success := 0;
            p_message := 'Prerequisite course ' || p_prerequisite_course_id || ' not found or inactive';
            RETURN;
        END IF;

        -- Guard: parent course must exist
        SELECT COUNT(*) INTO v_count
          FROM courses WHERE course_id = p_course_id;
        IF v_count = 0 THEN
            p_success := 0;
            p_message := 'Course ' || p_course_id || ' not found';
            RETURN;
        END IF;

        INSERT INTO course_prerequisites
            (course_id, prerequisite_course_id, is_mandatory)
        VALUES
            (p_course_id, p_prerequisite_course_id, NVL(p_is_mandatory, 'Y'));

        p_success := 1;
        p_message := 'Prerequisite course ' || p_prerequisite_course_id
                     || ' linked to course ' || p_course_id;

    EXCEPTION
        WHEN DUP_VAL_ON_INDEX THEN
            p_success := 0;
            p_message := 'Prerequisite already exists for this course';
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error adding prerequisite: ' || SQLERRM;
    END add_course_prerequisite;

    -- ========================================================================
    -- DELETE COURSE PREREQUISITE
    -- ========================================================================
    PROCEDURE delete_course_prerequisite (
        p_course_id              IN  NUMBER,
        p_prerequisite_course_id IN  NUMBER,
        p_success                OUT NUMBER,
        p_message                OUT VARCHAR2
    ) IS
        v_count NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_count
          FROM course_prerequisites
         WHERE course_id = p_course_id
           AND prerequisite_course_id = p_prerequisite_course_id;

        IF v_count = 0 THEN
            p_success := 0;
            p_message := 'Prerequisite not found for this course';
            RETURN;
        END IF;

        DELETE FROM course_prerequisites
         WHERE course_id = p_course_id
           AND prerequisite_course_id = p_prerequisite_course_id;

        p_success := 1;
        p_message := 'Prerequisite ' || p_prerequisite_course_id || ' removed from course ' || p_course_id;

    EXCEPTION
        WHEN OTHERS THEN
            p_success := 0;
            p_message := 'Error deleting prerequisite: ' || SQLERRM;
    END delete_course_prerequisite;

    -- ========================================================================
    -- GUARD FUNCTIONS
    -- ========================================================================
    FUNCTION student_exists (p_roll_number IN VARCHAR2) RETURN NUMBER IS
        v_c NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_c FROM students
         WHERE roll_number = UPPER(TRIM(p_roll_number));
        RETURN CASE WHEN v_c > 0 THEN 1 ELSE 0 END;
    END student_exists;

    FUNCTION faculty_exists (p_employee_id IN VARCHAR2) RETURN NUMBER IS
        v_c NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_c FROM faculty
         WHERE employee_id = UPPER(TRIM(p_employee_id));
        RETURN CASE WHEN v_c > 0 THEN 1 ELSE 0 END;
    END faculty_exists;

    FUNCTION offering_exists (p_course_id IN NUMBER, p_term_id IN NUMBER) RETURN NUMBER IS
        v_c NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_c FROM course_offerings
         WHERE course_id = p_course_id AND term_id = p_term_id;
        RETURN CASE WHEN v_c > 0 THEN 1 ELSE 0 END;
    END offering_exists;

    FUNCTION course_exists (p_course_code IN VARCHAR2) RETURN NUMBER IS
        v_c NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v_c FROM courses
         WHERE course_code = UPPER(TRIM(p_course_code));
        RETURN CASE WHEN v_c > 0 THEN 1 ELSE 0 END;
    END course_exists;

END admin_manager;
/