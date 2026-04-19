-- ============================================================================
-- 01_tables_3nf.sql
-- 3NF Analysis & Fixes:
--
-- VIOLATIONS FOUND & FIXED:
--
-- 1. attendance table: attendance_date, slot_id, class_type are fully
--    determined by schedule_id (transitive dependency via class_schedule).
--    → Removed attendance_date, slot_id, class_type from attendance;
--      these are always derived by joining class_schedule.
--
-- 2. attendance table: section_id is determined by schedule_id → section_id
--    is already on class_schedule, creating a transitive path
--    registration_id → section_id AND schedule_id → section_id.
--    → Removed section_id from attendance; derive via JOIN.
--
-- 3. registrations table: theory_classes_attended & lab_classes_attended
--    are aggregates derivable from attendance rows; storing them creates
--    update anomalies (the triggers / procedures must keep them in sync).
--    → Removed cached counters; attendance % is always computed from
--      the attendance table (as the view and package already do).
--
-- 4. sections table: total_theory_classes_conducted &
--    total_lab_classes_conducted are counts derivable from class_schedule
--    (COUNT where is_cancelled='N').  Caching them violates 3NF and
--    requires triggers to stay consistent.
--    → Removed these two columns; counts are computed on demand.
--    (total_*_classes_planned is a planning figure set by faculty,
--     not derivable, so it is retained.)
--
-- 5. waitlist_history: position is derivable from the order of
--    joined_waitlist_at per (section_id, term_id); storing it creates
--    update anomalies when re-ordering.
--    → Removed position column; waitlist rank is always computed with
--      ROW_NUMBER() OVER (ORDER BY joined_waitlist_at).
--
-- 6. students: current_semester is functionally determined by
--    (batch_id, current academic_term), not an independent attribute
--    for a normalised design.  However, since semester progression is
--    managed explicitly (not auto-derived from the term table) and is a
--    mutable administrative field, we retain it but document the
--    dependency.  (Removing it would require an additional mapping table
--    which is out of scope for the current schema.)
--
-- 7. courses table: added max_sections column.
--    3NF justification: max_sections is a planning/policy attribute
--    that belongs to a course (course_id → max_sections). It is NOT
--    derivable from any other column — it is an administrative cap set
--    by the admin when creating a course, not a count of existing
--    sections. The actual count of sections is always derived on-demand
--    via COUNT(*) on the sections table. No transitive dependency is
--    introduced because max_sections depends solely on course_id.
--
-- All other tables are already in 3NF.
-- ============================================================================

DROP TABLE departments          CASCADE CONSTRAINTS;
DROP TABLE programs             CASCADE CONSTRAINTS;
DROP TABLE faculty              CASCADE CONSTRAINTS;
DROP TABLE batches              CASCADE CONSTRAINTS;
DROP TABLE students             CASCADE CONSTRAINTS;
DROP TABLE courses              CASCADE CONSTRAINTS;
DROP TABLE course_prerequisites CASCADE CONSTRAINTS;
DROP TABLE course_eligibility   CASCADE CONSTRAINTS;
DROP TABLE slots                CASCADE CONSTRAINTS;
DROP TABLE slot_timings         CASCADE CONSTRAINTS;
DROP TABLE academic_terms       CASCADE CONSTRAINTS;
DROP TABLE course_offerings     CASCADE CONSTRAINTS;
DROP TABLE sections             CASCADE CONSTRAINTS;
DROP TABLE registrations        CASCADE CONSTRAINTS;
DROP TABLE class_schedule       CASCADE CONSTRAINTS;
DROP TABLE attendance           CASCADE CONSTRAINTS;
DROP TABLE waitlist_history     CASCADE CONSTRAINTS;

DROP SEQUENCE dept_seq;
DROP SEQUENCE program_seq;
DROP SEQUENCE faculty_seq;
DROP SEQUENCE batch_seq;
DROP SEQUENCE student_seq;
DROP SEQUENCE course_seq;
DROP SEQUENCE eligibility_seq;
DROP SEQUENCE offering_seq;
DROP SEQUENCE section_seq;
DROP SEQUENCE registration_seq;
DROP SEQUENCE schedule_seq;
DROP SEQUENCE attendance_seq;
DROP SEQUENCE waitlist_seq;
DROP SEQUENCE term_seq;


-- ============================================================================
-- DEPARTMENTS
-- ============================================================================
CREATE TABLE departments (
    dept_id        NUMBER PRIMARY KEY,
    dept_code      VARCHAR2(10)  UNIQUE NOT NULL,
    dept_name      VARCHAR2(100) NOT NULL,
    total_semesters NUMBER DEFAULT 8,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE dept_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- PROGRAMS
-- ============================================================================
CREATE TABLE programs (
    program_id               NUMBER PRIMARY KEY,
    program_code             VARCHAR2(20)  UNIQUE NOT NULL,
    program_name             VARCHAR2(100) NOT NULL,
    dept_id                  NUMBER REFERENCES departments(dept_id),
    program_type             VARCHAR2(20)  CHECK (program_type IN ('UG','PG')),
    duration_years           NUMBER        NOT NULL,
    total_credits_required   NUMBER        NOT NULL,
    max_credits_per_semester NUMBER DEFAULT 28,
    created_at               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE program_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- FACULTY
-- ============================================================================
CREATE TABLE faculty (
    faculty_id     NUMBER PRIMARY KEY,
    employee_id    VARCHAR2(20)  UNIQUE NOT NULL,
    first_name     VARCHAR2(50)  NOT NULL,
    last_name      VARCHAR2(50),
    email          VARCHAR2(100) UNIQUE NOT NULL,
    phone          VARCHAR2(15) UNIQUE NOT NULL,
    dept_id        NUMBER REFERENCES departments(dept_id),
    designation    VARCHAR2(50),
    specialization VARCHAR2(200),
    is_active      CHAR(1) DEFAULT 'Y',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 128K NEXT 128K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE faculty_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- BATCHES
-- ============================================================================
CREATE TABLE batches (
    batch_id             NUMBER PRIMARY KEY,
    batch_code           VARCHAR2(20) UNIQUE NOT NULL,
    program_id           NUMBER REFERENCES programs(program_id),
    year_of_admission    NUMBER(4) NOT NULL,
    batch_coordinator_id NUMBER REFERENCES faculty(faculty_id),
    is_active            CHAR(1) DEFAULT 'Y',
    created_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE batch_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- STUDENTS
-- ============================================================================
CREATE TABLE students (
    student_id       NUMBER PRIMARY KEY,
    roll_number      VARCHAR2(20)  UNIQUE NOT NULL,
    first_name       VARCHAR2(50)  NOT NULL,
    last_name        VARCHAR2(50),
    email            VARCHAR2(100) UNIQUE NOT NULL,
    phone            VARCHAR2(15) UNIQUE NOT NULL,
    batch_id         NUMBER REFERENCES batches(batch_id),
    current_semester NUMBER DEFAULT 1
        CHECK (current_semester BETWEEN 1 AND 8),
    date_of_birth    DATE,
    enrollment_date  DATE DEFAULT SYSDATE,
    is_active        CHAR(1) DEFAULT 'Y',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 256K NEXT 256K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE student_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- COURSES
-- 3NF note on max_sections:
--   max_sections is a planning/policy attribute of the course itself.
--   course_id → max_sections holds directly with no transitive path.
--   It is NOT derivable from other columns (actual section count is always
--   computed with COUNT(*) on sections; max_sections is an admin-set cap).
--   Default of 5 is applied to all new courses; existing rows are updated
--   via the migration script 08_migrate_max_sections.sql.
-- ============================================================================
CREATE TABLE courses (
    course_id        NUMBER PRIMARY KEY,
    course_code      VARCHAR2(20)  UNIQUE NOT NULL,
    course_name      VARCHAR2(200) NOT NULL,
    dept_id          NUMBER NOT NULL REFERENCES departments(dept_id),
    course_type      VARCHAR2(10)  NOT NULL
        CHECK (course_type IN ('DC','DE','OC','HM','BS','ES','AU')),
    lecture_hours    NUMBER DEFAULT 0,
    tutorial_hours   NUMBER DEFAULT 0,
    practical_hours  NUMBER DEFAULT 0,
    credits          NUMBER NOT NULL
        CHECK (credits > 0 AND credits <= 10),
    typical_semester NUMBER
        CHECK (typical_semester BETWEEN 1 AND 8),
    has_lab          CHAR(1) DEFAULT 'N',
    -- max_sections: admin-set cap on how many sections can be floated
    -- per term for this course. course_id → max_sections (no transitivity).
    max_sections     NUMBER DEFAULT 3
        CHECK (max_sections > 0 AND max_sections <= 3),
    description      CLOB,
    is_active        CHAR(1) DEFAULT 'Y',
    created_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_lab_consistency CHECK (
        (has_lab = 'Y' AND practical_hours > 0) OR
        (has_lab = 'N' AND practical_hours = 0)
    )
)
STORAGE (INITIAL 256K NEXT 256K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE course_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- COURSE PREREQUISITES
-- ============================================================================
CREATE TABLE course_prerequisites (
    course_id              NUMBER NOT NULL REFERENCES courses(course_id),
    prerequisite_course_id NUMBER NOT NULL REFERENCES courses(course_id),
    is_mandatory           CHAR(1) DEFAULT 'Y'
        CHECK (is_mandatory IN ('Y','N')),
    created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (course_id, prerequisite_course_id),
    CHECK (course_id != prerequisite_course_id)
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);


-- ============================================================================
-- COURSE ELIGIBILITY
-- ============================================================================
CREATE TABLE course_eligibility (
    eligibility_id NUMBER PRIMARY KEY,
    course_id      NUMBER NOT NULL REFERENCES courses(course_id),
    dept_id        NUMBER REFERENCES departments(dept_id),
    program_id     NUMBER REFERENCES programs(program_id),
    min_semester   NUMBER,
    max_semester   NUMBER,
    priority       NUMBER DEFAULT 99
        CHECK (priority BETWEEN 1 AND 100),
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (min_semester <= max_semester),
    CHECK (
        min_semester BETWEEN 1 AND 8 AND
        max_semester BETWEEN 1 AND 8
    ),
    CHECK (dept_id IS NOT NULL OR program_id IS NOT NULL)
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE eligibility_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- SLOTS
-- ============================================================================
CREATE TABLE slots (
    slot_id    NUMBER PRIMARY KEY,
    slot_code  VARCHAR2(10) UNIQUE NOT NULL,
    slot_type  VARCHAR2(20)
        CHECK (slot_type IN ('THEORY','LAB')),
    is_active  CHAR(1) DEFAULT 'Y',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

-- slot_timings: timing_id → (slot_id, day_of_week, start_time, end_time)
-- (slot_id, day_of_week) → (start_time, end_time) — no transitive deps.
CREATE TABLE slot_timings (
    timing_id   NUMBER PRIMARY KEY,
    slot_id     NUMBER NOT NULL REFERENCES slots(slot_id),
    day_of_week VARCHAR2(10)
        CHECK (day_of_week IN ('MON','TUE','WED','THU','FRI','SAT')),
    start_time  DATE NOT NULL,
    end_time    DATE NOT NULL,
    CHECK (end_time > start_time)
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE INDEX idx_slot_timings_slot ON slot_timings(slot_id);


-- ============================================================================
-- ACADEMIC TERMS
-- ============================================================================
CREATE TABLE academic_terms (
    term_id                 NUMBER PRIMARY KEY,
    term_code               VARCHAR2(20) UNIQUE NOT NULL,
    term_name               VARCHAR2(50)  NOT NULL,
    academic_year           VARCHAR2(10)  NOT NULL,
    term_type               VARCHAR2(20)  NOT NULL
        CHECK (term_type IN ('ODD','EVEN','SUMMER')),
    start_date              DATE NOT NULL,
    end_date                DATE NOT NULL,
    registration_start_date DATE,
    registration_end_date   DATE,
    is_current              CHAR(1) DEFAULT 'N',
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CHECK (end_date > start_date),
    CHECK (registration_start_date <= registration_end_date)
)
STORAGE (INITIAL 64K NEXT 64K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE term_seq START WITH 1 INCREMENT BY 1;

CREATE UNIQUE INDEX idx_one_current_term ON academic_terms(
    CASE WHEN is_current = 'Y' THEN 1 ELSE NULL END
);


-- ============================================================================
-- COURSE OFFERINGS
-- ============================================================================
CREATE TABLE course_offerings (
    offering_id    NUMBER PRIMARY KEY,
    course_id      NUMBER NOT NULL REFERENCES courses(course_id),
    term_id        NUMBER NOT NULL REFERENCES academic_terms(term_id),
    theory_slot_id NUMBER NOT NULL REFERENCES slots(slot_id),
    lab_slot_id    NUMBER           REFERENCES slots(slot_id),
    is_active      CHAR(1) DEFAULT 'Y',
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (course_id, term_id)
)
STORAGE (INITIAL 128K NEXT 128K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE INDEX idx_offering_theory_slot ON course_offerings(theory_slot_id);
CREATE INDEX idx_offering_lab_slot    ON course_offerings(lab_slot_id);
CREATE SEQUENCE offering_seq START WITH 1 INCREMENT BY 1;


-- ============================================================================
-- SECTIONS
-- 3NF Fix: Removed total_theory_classes_conducted &
--          total_lab_classes_conducted (derivable from class_schedule via
--          COUNT WHERE is_cancelled='N'; caching violates 3NF).
-- ============================================================================
CREATE TABLE sections (
    section_id                   NUMBER PRIMARY KEY,
    offering_id                  NUMBER NOT NULL REFERENCES course_offerings(offering_id),
    section_code                 VARCHAR2(10) NOT NULL,
    instructor_id                NUMBER NOT NULL REFERENCES faculty(faculty_id),
    section_coordinator_id       NUMBER NOT NULL REFERENCES faculty(faculty_id),
    max_capacity                 NUMBER NOT NULL,
    current_enrollment           NUMBER DEFAULT 0,
    waitlist_capacity            NUMBER DEFAULT 10,
    current_waitlist             NUMBER DEFAULT 0,
    theory_room                  VARCHAR2(20),
    lab_room                     VARCHAR2(20),
    total_theory_classes_planned NUMBER DEFAULT 0,
    total_lab_classes_planned    NUMBER DEFAULT 0,
    is_active                    CHAR(1) DEFAULT 'Y',
    created_at                   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (offering_id, section_code),
    CHECK (is_active IN ('Y','N')),
    CHECK (current_enrollment BETWEEN 0 AND max_capacity),
    CHECK (current_waitlist   BETWEEN 0 AND waitlist_capacity),
    CHECK (
        total_theory_classes_planned >= 0 AND
        total_lab_classes_planned    >= 0
    )
)
STORAGE (INITIAL 256K NEXT 256K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE INDEX idx_sections_offering ON sections(offering_id);
CREATE SEQUENCE section_seq START WITH 5000 INCREMENT BY 1;


-- ============================================================================
-- REGISTRATIONS
-- 3NF Fix: Removed theory_classes_attended & lab_classes_attended.
--   These are aggregate counts derivable from the attendance table
--   (COUNT WHERE status IN ('P','L','E','OD') AND class_type = X).
--   Caching them creates update anomalies and violates 3NF because
--   they are not independently determined by registration_id alone —
--   they depend on the attendance rows, creating a transitive dependency:
--     registration_id → {attendance rows} → attended_count.
-- ============================================================================
CREATE TABLE registrations (
    registration_id     NUMBER PRIMARY KEY,
    student_id          NUMBER NOT NULL REFERENCES students(student_id),
    section_id          NUMBER NOT NULL REFERENCES sections(section_id),
    term_id             NUMBER NOT NULL REFERENCES academic_terms(term_id),
    registration_date   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registration_status VARCHAR2(20) DEFAULT 'REGISTERED'
        CHECK (registration_status IN (
            'PENDING','REGISTERED','WAITLISTED',
            'APPROVED','DROPPED','WITHDRAWN','COMPLETED'
        )),
    waitlist_position   NUMBER,
    approved_date       TIMESTAMP,
    attendance_warning_sent CHAR(1) DEFAULT 'N'
        CHECK (attendance_warning_sent IN ('Y','N')),
    attendance_locked   CHAR(1) DEFAULT 'N'
        CHECK (attendance_locked IN ('Y','N')),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (student_id, section_id, term_id)
)
STORAGE (INITIAL 512K NEXT 512K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE registration_seq START WITH 1 INCREMENT BY 1;

CREATE INDEX idx_reg_student_term ON registrations(student_id, term_id);
CREATE INDEX idx_reg_section      ON registrations(section_id);
CREATE INDEX idx_reg_status       ON registrations(registration_status);


-- ============================================================================
-- CLASS SCHEDULE
-- ============================================================================
CREATE TABLE class_schedule (
    schedule_id           NUMBER PRIMARY KEY,
    section_id            NUMBER REFERENCES sections(section_id),
    class_date            DATE NOT NULL,
    slot_id               NUMBER REFERENCES slots(slot_id),
    class_type            VARCHAR2(20) NOT NULL
        CHECK (class_type IN ('THEORY','LAB')),
    lecture_number        NUMBER DEFAULT 1,
    topic                 VARCHAR2(500),
    conducted_by          NUMBER REFERENCES faculty(faculty_id),
    room_number           VARCHAR2(20),
    is_cancelled          CHAR(1) DEFAULT 'N',
    cancellation_reason   VARCHAR2(500),
    is_attendance_marked  CHAR(1) DEFAULT 'N',
    attendance_marked_by  NUMBER REFERENCES faculty(faculty_id),
    attendance_marked_at  TIMESTAMP,
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (section_id, class_date, slot_id, class_type, lecture_number)
)
STORAGE (INITIAL 512K NEXT 512K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE schedule_seq START WITH 1 INCREMENT BY 1;

CREATE INDEX idx_schedule_section_date ON class_schedule(section_id, class_date);
CREATE INDEX idx_schedule_date         ON class_schedule(class_date);


-- ============================================================================
-- ATTENDANCE
-- 3NF Fix: Removed attendance_date, slot_id, class_type, section_id.
--   All four are determined by schedule_id (via class_schedule), making
--   them transitively dependent on attendance_id through schedule_id.
--   Transitive dependency: attendance_id → schedule_id → {date,slot,type,section}
--   They are obtained by joining class_schedule on schedule_id.
-- ============================================================================
CREATE TABLE attendance (
    attendance_id   NUMBER PRIMARY KEY,
    registration_id NUMBER NOT NULL REFERENCES registrations(registration_id),
    schedule_id     NUMBER NOT NULL REFERENCES class_schedule(schedule_id),
    -- attendance_date, slot_id, class_type, section_id removed (3NF fix)
    -- derive from class_schedule JOIN on schedule_id
    status          VARCHAR2(10) NOT NULL
        CHECK (status IN ('P','A','L','E','OD')),
    -- P=Present, A=Absent, L=Late, E=Excused, OD=On Duty
    marked_by       NUMBER REFERENCES faculty(faculty_id),
    marked_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    remarks         VARCHAR2(500),
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (registration_id, schedule_id)
)
STORAGE (INITIAL 1M NEXT 1M MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE attendance_seq START WITH 1 INCREMENT BY 1;

CREATE INDEX idx_att_reg      ON attendance(registration_id);
CREATE INDEX idx_att_schedule ON attendance(schedule_id);
-- Performance index for view queries
CREATE INDEX idx_att_reg_sched    ON attendance(registration_id, schedule_id);
CREATE INDEX idx_att_full         ON attendance(registration_id, status);
CREATE INDEX idx_reg_student_term2 ON registrations(student_id, term_id, registration_status);


-- ============================================================================
-- WAITLIST HISTORY
-- 3NF Fix: Removed 'position' column.
--   position is derivable as ROW_NUMBER() OVER (ORDER BY joined_waitlist_at)
--   partitioned by (section_id, term_id).  Storing it creates update
--   anomalies every time a student is promoted or drops.
-- ============================================================================
CREATE TABLE waitlist_history (
    waitlist_id        NUMBER PRIMARY KEY,
    student_id         NUMBER REFERENCES students(student_id),
    section_id         NUMBER REFERENCES sections(section_id),
    term_id            NUMBER REFERENCES academic_terms(term_id),
    joined_waitlist_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- position removed (3NF fix): derive with ROW_NUMBER() OVER (ORDER BY joined_waitlist_at)
    status             VARCHAR2(20)
        CHECK (status IN ('WAITING','APPROVED','EXPIRED','STUDENT_DROPPED')),
    status_changed_at  TIMESTAMP,
    created_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
STORAGE (INITIAL 128K NEXT 128K MINEXTENTS 1 MAXEXTENTS UNLIMITED PCTINCREASE 0);

CREATE SEQUENCE waitlist_seq START WITH 1 INCREMENT BY 1;
