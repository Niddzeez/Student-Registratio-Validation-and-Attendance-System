-- ============================================================================
-- 06_sample_data_vnit_2026.sql
-- VNIT Nagpur — Complete demo data for AcadMS (Two-Term Scenario)
--
-- SET DEFINE OFF prevents SQLPlus/SQLcl from treating '&' as a substitution
-- variable prompt. Without this, numeric ranges like 1001..1012 are parsed
-- as &1001 by the scanner and Oracle asks for user input.
--
-- TODAY = 16-APR-2026
--
-- TERM 1 — EVEN 2025-26  (CURRENT, is_current='Y')
--   • Started:  06-FEB-2026  (≈ 2 months ago)
--   • Ends:     31-MAY-2026  (≈ 1.5 months from now)
--   • Reg window: CLOSED (was 10-JAN-2026 → 05-FEB-2026)
--   • Students already registered; many attendance classes conducted
--   • Faculty: mark attendance, schedule classes, view reports
--
-- TERM 2 — ODD 2026-27  (UPCOMING, is_current='N')
--   • Starts:   01-JUL-2026  (≈ 2.5 months from now)
--   • Ends:     30-NOV-2026
--   • Reg window: OPEN NOW (10-APR-2026 → 10-MAY-2026)
--   • Faculty can float sections; students can register for eligible courses
--   • No classes scheduled yet (term hasn't started)
-- ============================================================================

SET DEFINE OFF;
SET BLANKLINES ON;

-- ── Wipe all tables in dependency order ─────────────────────────────────────
TRUNCATE TABLE attendance;
TRUNCATE TABLE waitlist_history;
TRUNCATE TABLE registrations;
TRUNCATE TABLE class_schedule;
TRUNCATE TABLE sections;
TRUNCATE TABLE course_offerings;
TRUNCATE TABLE course_eligibility;
TRUNCATE TABLE course_prerequisites;
TRUNCATE TABLE courses;
TRUNCATE TABLE academic_terms;
TRUNCATE TABLE slot_timings;
TRUNCATE TABLE slots;
TRUNCATE TABLE students;
TRUNCATE TABLE batches;
TRUNCATE TABLE faculty;
TRUNCATE TABLE programs;
TRUNCATE TABLE departments;
COMMIT;

-- ============================================================================
-- 1. DEPARTMENTS
-- ============================================================================
INSERT INTO departments VALUES (1,'CSE',  'Computer Science & Engineering',          8,SYSTIMESTAMP);
INSERT INTO departments VALUES (2,'EEE',  'Electrical & Electronics Engineering',    8,SYSTIMESTAMP);
INSERT INTO departments VALUES (3,'MECH', 'Mechanical Engineering',                  8,SYSTIMESTAMP);
INSERT INTO departments VALUES (4,'CIVIL','Civil Engineering',                       8,SYSTIMESTAMP);
INSERT INTO departments VALUES (5,'ECE',  'Electronics & Communication Engineering', 8,SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 2. PROGRAMS
-- ============================================================================
INSERT INTO programs VALUES (1,'BTECH-CSE', 'B.Tech Computer Science & Engineering',         1,'UG',4,170,28,SYSTIMESTAMP);
INSERT INTO programs VALUES (2,'BTECH-EEE', 'B.Tech Electrical & Electronics Engineering',   2,'UG',4,170,28,SYSTIMESTAMP);
INSERT INTO programs VALUES (3,'BTECH-MECH','B.Tech Mechanical Engineering',                  3,'UG',4,170,28,SYSTIMESTAMP);
INSERT INTO programs VALUES (4,'MTECH-CSE', 'M.Tech Computer Science & Engineering',          1,'PG',2, 60,24,SYSTIMESTAMP);
INSERT INTO programs VALUES (5,'BTECH-ECE', 'B.Tech Electronics & Communication Engineering', 5,'UG',4,170,28,SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 3. FACULTY  (login: employee_id / employee_id)
-- ============================================================================
INSERT INTO faculty VALUES (1,'F001','Rajesh',  'Kumar',    'rajesh.kumar@vnit.ac.in',  '9876543210',1,'Professor',          'Algorithms, Data Structures',           'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (2,'F002','Priya',   'Sharma',   'priya.sharma@vnit.ac.in',  '9876543211',1,'Associate Professor','Database Systems, Cloud Computing',     'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (3,'F003','Amit',    'Verma',    'amit.verma@vnit.ac.in',    '9876543212',1,'Assistant Professor','Operating Systems, Systems Programming', 'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (4,'F004','Sunita',  'Patel',    'sunita.patel@vnit.ac.in',  '9876543213',1,'Professor',          'Computer Networks, Security',           'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (5,'F005','Vikram',  'Singh',    'vikram.singh@vnit.ac.in',  '9876543214',2,'Professor',          'Control Systems, Power Electronics',    'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (6,'F006','Anjali',  'Deshmukh', 'anjali.d@vnit.ac.in',      '9876543215',1,'Assistant Professor','Machine Learning, AI',                  'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (7,'F007','Suresh',  'Bhadauria','suresh.b@vnit.ac.in',      '9876543216',1,'Associate Professor','Compiler Design, Formal Languages',     'Y',SYSTIMESTAMP);
INSERT INTO faculty VALUES (8,'F008','Kavita',  'Jha',      'kavita.jha@vnit.ac.in',    '9876543217',5,'Assistant Professor','VLSI Design, Embedded Systems',         'Y',SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 4. BATCHES
-- (2022 batch → Sem 6 in EVEN 2025-26; Sem 7 in ODD 2026-27)
-- (2023 batch → Sem 4 in EVEN 2025-26; Sem 5 in ODD 2026-27)
-- ============================================================================
INSERT INTO batches VALUES (1,'2022-BTECH-CSE', 1,2022,1,'Y',SYSTIMESTAMP);
INSERT INTO batches VALUES (2,'2023-BTECH-CSE', 1,2023,2,'Y',SYSTIMESTAMP);
INSERT INTO batches VALUES (3,'2024-BTECH-CSE', 1,2024,2,'Y',SYSTIMESTAMP);
INSERT INTO batches VALUES (4,'2023-BTECH-EEE', 2,2022,5,'Y',SYSTIMESTAMP);
INSERT INTO batches VALUES (5,'2022-MTECH-CSE', 4,2023,6,'Y',SYSTIMESTAMP);
INSERT INTO batches VALUES (6,'2023-BTECH-ECE', 5,2023,8,'Y',SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 5. STUDENTS  (login: roll_number / roll_number)
--    2022 CSE batch  → current_semester = 6 (Even 2025-26)
--    2023 CSE batch  → current_semester = 4 (Even 2025-26)
--    EEE 2022        → current_semester = 6 (different dept)
-- ============================================================================

-- 2022 CSE — Sem 6
INSERT INTO students VALUES (1001,'2023BCS001','Aarav',    'Gupta',   'aarav.gupta@students.vnit.ac.in',   '8765432101',2,6,DATE'2004-05-15',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1002,'2023BCS002','Diya',     'Mehta',   'diya.mehta@students.vnit.ac.in',    '8765432102',2,6,DATE'2004-03-22',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1003,'2023BCS003','Arjun',    'Reddy',   'arjun.reddy@students.vnit.ac.in',   '8765432103',2,6,DATE'2004-07-10',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1004,'2023BCS004','Ananya',   'Iyer',    'ananya.iyer@students.vnit.ac.in',   '8765432104',2,6,DATE'2004-01-18',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1005,'2023BCS005','Kabir',    'Shah',    'kabir.shah@students.vnit.ac.in',    '8765432105',2,6,DATE'2004-09-25',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1006,'2023BCS006','Ishita',   'Joshi',   'ishita.joshi@students.vnit.ac.in',  '8765432106',2,6,DATE'2004-11-03',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1007,'2023BCS007','Rohan',    'Kulkarni','rohan.k@students.vnit.ac.in',       '8765432107',2,6,DATE'2004-04-12',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1008,'2023BCS008','Nisha',    'Agarwal', 'nisha.a@students.vnit.ac.in',       '8765432108',2,6,DATE'2004-06-30',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1009,'2023BCS009','Siddharth','Mishra',  's.mishra@students.vnit.ac.in',      '8765432109',2,6,DATE'2004-02-14',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1010,'2023BCS010','Prisha',   'Nair',    'prisha.n@students.vnit.ac.in',      '8765432110',2,6,DATE'2004-08-21',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1011,'2023BCS011','Dev',      'Tiwari',  'dev.tiwari@students.vnit.ac.in',    '8765432111',2,6,DATE'2004-12-05',DATE'2023-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (1012,'2023BCS012','Riya',     'Saxena',  'riya.saxena@students.vnit.ac.in',   '8765432112',2,6,DATE'2004-10-17',DATE'2023-08-01','Y',SYSTIMESTAMP);

-- 2023 CSE — Sem 4 (should NOT see Sem-6/7 restricted courses in ODD 2026-27)
INSERT INTO students VALUES (2001,'2024BCS001','Tanvi',    'Bhatt',   'tanvi.bhatt@students.vnit.ac.in',   '8765432201',3,4,DATE'2005-06-10',DATE'2024-08-01','Y',SYSTIMESTAMP);
INSERT INTO students VALUES (2002,'2024BCS002','Harsh',    'Pandey',  'harsh.pandey@students.vnit.ac.in',  '8765432202',3,4,DATE'2005-04-22',DATE'2024-08-01','Y',SYSTIMESTAMP);

-- EEE 2022 — Sem 6 (different dept, can only see open electives)
INSERT INTO students VALUES (3001,'2023BEE001','Vivaan',   'Modi',    'vivaan.modi@students.vnit.ac.in',   '8765432301',4,6,DATE'2004-03-08',DATE'2023-08-01','Y',SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 6. SLOTS
-- ============================================================================
INSERT INTO slots VALUES (1, 'A', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (2, 'B', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (3, 'C', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (4, 'D', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (5, 'E', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (6, 'F', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (7, 'G', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (8, 'H', 'THEORY','Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (11,'L1','LAB',   'Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (12,'L2','LAB',   'Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (13,'L3','LAB',   'Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (14,'L4','LAB',   'Y',SYSTIMESTAMP);
INSERT INTO slots VALUES (15,'L5','LAB',   'Y',SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 7. SLOT TIMINGS (VNIT-style)
-- ============================================================================
-- Slot A: MON/WED/FRI 08:00–09:30
INSERT INTO slot_timings VALUES (1, 1,'MON',TO_DATE('08:00','HH24:MI'),TO_DATE('09:30','HH24:MI'));
INSERT INTO slot_timings VALUES (2, 1,'WED',TO_DATE('08:00','HH24:MI'),TO_DATE('09:30','HH24:MI'));
INSERT INTO slot_timings VALUES (3, 1,'FRI',TO_DATE('08:00','HH24:MI'),TO_DATE('09:30','HH24:MI'));
-- Slot B: MON/WED/FRI 10:00–11:30
INSERT INTO slot_timings VALUES (4, 2,'MON',TO_DATE('10:00','HH24:MI'),TO_DATE('11:30','HH24:MI'));
INSERT INTO slot_timings VALUES (5, 2,'WED',TO_DATE('10:00','HH24:MI'),TO_DATE('11:30','HH24:MI'));
INSERT INTO slot_timings VALUES (6, 2,'FRI',TO_DATE('10:00','HH24:MI'),TO_DATE('11:30','HH24:MI'));
-- Slot C: TUE/THU 08:00–09:30
INSERT INTO slot_timings VALUES (7, 3,'TUE',TO_DATE('08:00','HH24:MI'),TO_DATE('09:30','HH24:MI'));
INSERT INTO slot_timings VALUES (8, 3,'THU',TO_DATE('08:00','HH24:MI'),TO_DATE('09:30','HH24:MI'));
-- Slot D: TUE/THU 10:00–11:30
INSERT INTO slot_timings VALUES (9, 4,'TUE',TO_DATE('10:00','HH24:MI'),TO_DATE('11:30','HH24:MI'));
INSERT INTO slot_timings VALUES (10,4,'THU',TO_DATE('10:00','HH24:MI'),TO_DATE('11:30','HH24:MI'));
-- Slot E: MON/WED/FRI 12:00–13:00
INSERT INTO slot_timings VALUES (11,5,'MON',TO_DATE('12:00','HH24:MI'),TO_DATE('13:00','HH24:MI'));
INSERT INTO slot_timings VALUES (12,5,'WED',TO_DATE('12:00','HH24:MI'),TO_DATE('13:00','HH24:MI'));
INSERT INTO slot_timings VALUES (13,5,'FRI',TO_DATE('12:00','HH24:MI'),TO_DATE('13:00','HH24:MI'));
-- Slot F: TUE/THU 12:00–13:30
INSERT INTO slot_timings VALUES (14,6,'TUE',TO_DATE('12:00','HH24:MI'),TO_DATE('13:30','HH24:MI'));
INSERT INTO slot_timings VALUES (15,6,'THU',TO_DATE('12:00','HH24:MI'),TO_DATE('13:30','HH24:MI'));
-- Slot G: TUE/THU 14:00–15:30
INSERT INTO slot_timings VALUES (16,7,'TUE',TO_DATE('14:00','HH24:MI'),TO_DATE('15:30','HH24:MI'));
INSERT INTO slot_timings VALUES (17,7,'THU',TO_DATE('14:00','HH24:MI'),TO_DATE('15:30','HH24:MI'));
-- Slot H: MON/WED 14:00–15:30
INSERT INTO slot_timings VALUES (18,8,'MON',TO_DATE('14:00','HH24:MI'),TO_DATE('15:30','HH24:MI'));
INSERT INTO slot_timings VALUES (19,8,'WED',TO_DATE('14:00','HH24:MI'),TO_DATE('15:30','HH24:MI'));
-- Lab slots (3-hour afternoon)
INSERT INTO slot_timings VALUES (21,11,'MON',TO_DATE('14:00','HH24:MI'),TO_DATE('17:00','HH24:MI'));
INSERT INTO slot_timings VALUES (22,12,'TUE',TO_DATE('14:00','HH24:MI'),TO_DATE('17:00','HH24:MI'));
INSERT INTO slot_timings VALUES (23,13,'WED',TO_DATE('14:00','HH24:MI'),TO_DATE('17:00','HH24:MI'));
INSERT INTO slot_timings VALUES (24,14,'THU',TO_DATE('14:00','HH24:MI'),TO_DATE('17:00','HH24:MI'));
INSERT INTO slot_timings VALUES (25,15,'FRI',TO_DATE('14:00','HH24:MI'),TO_DATE('17:00','HH24:MI'));
COMMIT;

-- ============================================================================
-- 8. ACADEMIC TERMS
-- ============================================================================

-- TERM 1: EVEN 2025-26 — CURRENTLY RUNNING (is_current = 'Y')
-- Started 2 months ago, ends ~1.5 months from now
-- Registration window CLOSED (was Jan-Feb 2026)
INSERT INTO academic_terms VALUES (
    1, 'EVEN-2025-26', 'Even Semester 2025-26', '2025-26', 'EVEN',
    DATE '2026-02-06',           -- start (≈2 months ago)
    DATE '2026-05-31',           -- end   (≈1.5 months from now)
    DATE '2026-01-10',           -- reg start (closed)
    DATE '2026-02-05',           -- reg end   (closed, day before sem started)
    'Y',                         -- IS_CURRENT = Y
    SYSTIMESTAMP
);

-- TERM 2: ODD 2026-27 — UPCOMING (is_current = 'N')
-- Starts ~2.5 months from now; registration window OPEN NOW
INSERT INTO academic_terms VALUES (
    2, 'ODD-2026-27', 'Odd Semester 2026-27', '2026-27', 'ODD',
    DATE '2026-07-01',           -- start (≈2.5 months from now)
    DATE '2026-11-30',           -- end
    DATE '2026-04-10',           -- reg start (6 days ago — window OPEN)
    DATE '2026-05-10',           -- reg end   (24 days from now — still OPEN)
    'N',                         -- IS_CURRENT = N (not started yet)
    SYSTIMESTAMP
);
COMMIT;

-- ============================================================================
-- 9. COURSES
--
-- Column order (matches 01_tables_3nf.sql CREATE TABLE):
--   course_id, course_code, course_name,
--   dept_id, course_type,
--   lecture_hours, tutorial_hours, practical_hours,
--   credits, typical_semester,
--   has_lab,
--   max_sections,    ← NEW: admin-set cap on sections per term
--   description,
--   is_active, created_at
--
-- max_sections values chosen to reflect course size/demand:
--   2  — niche / small-enrollment courses (HML, foundational theory-only)
--   3  — standard courses with 1–2 expected sections
--   4  — larger demand courses (Compiler, AI, DBMS, Networks, ML)
--   5  — open electives (any dept, high demand)
-- ============================================================================

-- ── Prerequisite / foundation courses (completed in earlier sems) ────────────
--                    id   code       name                                dept type  lec tut lab crd sem lab? maxsec  description                                    active  created
INSERT INTO courses VALUES (101,'MAL101','Mathematics I',                          1,'BS', 3,1,0,4,1,'N', 3,'Calculus and Linear Algebra',                    'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (102,'CSL101','Programming and Problem Solving',        1,'DC', 3,0,2,4,1,'Y', 3,'C programming fundamentals',                     'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (103,'CSL201','Data Structures',                        1,'DC', 3,1,2,5,3,'Y', 3,'Fundamental data structures',                    'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (104,'CSL202','Discrete Mathematics',                   1,'DC', 3,1,0,4,3,'N', 3,'Logic and combinatorics',                         'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (105,'CSL203','Computer Organization & Architecture',   1,'DC', 3,0,0,3,3,'N', 3,'CPU design and memory systems',                   'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (106,'CSL301','Design and Analysis of Algorithms',      1,'DC', 3,1,0,4,5,'N', 3,'Sorting, graphs, DP, NP completeness',            'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (107,'CSL303','Theory of Computation',                  1,'DC', 3,1,0,4,5,'N', 3,'Automata, formal languages, Turing machines',    'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (108,'CSL305','Operating Systems',                      1,'DC', 3,0,2,4,5,'Y', 3,'Process management, memory, file systems',        'Y',SYSTIMESTAMP);

-- ── EVEN 2025-26 running courses (Term 1, Sem 6 for 2022 batch) ─────────────
INSERT INTO courses VALUES (601,'CSL401','Compiler Design',                        1,'DC', 3,1,2,5,6,'Y', 2,'Lexing, parsing, code generation',                'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (602,'CSL403','Artificial Intelligence',                1,'DC', 3,0,2,4,6,'Y', 2,'Search, knowledge repr, ML basics',               'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (603,'CSL405','Computer Graphics',                      1,'DC', 3,0,2,4,6,'Y', 2,'2D/3D rendering, OpenGL',                         'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (604,'CSL407','Software Engineering',                   1,'DC', 3,1,0,4,6,'N', 2,'SDLC, Agile, testing, design patterns',           'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (605,'CSL409','Database Management Systems',            1,'DC', 3,0,2,4,6,'Y', 2,'ER model, SQL, transactions, normalization',       'Y',SYSTIMESTAMP);

-- ── ODD 2026-27 upcoming courses (Term 2, Sem 7 for 2022 batch) ─────────────
INSERT INTO courses VALUES (701,'CSL501','Computer Networks',                      1,'DC', 3,0,2,4,7,'Y', 3,'TCP/IP, routing, network security',               'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (702,'CSL503','Machine Learning',                       1,'DC', 3,0,2,4,7,'Y', 3,'Supervised/Unsupervised, Neural Networks',         'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (703,'CSL505','Cloud Computing',                        1,'DC', 3,1,2,4,7,'Y', 3,'Virtualization, AWS, Docker, Kubernetes',          'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (704,'CSL507','Information Security',                   1,'DC', 3,0,0,3,7,'N', 2,'Cryptography, PKI, network security',              'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (705,'CSL509','Distributed Systems',                    1,'DC', 3,1,0,4,7,'N', 2,'Consensus, fault tolerance, CAP theorem',          'Y',SYSTIMESTAMP);
INSERT INTO courses VALUES (706,'HML501','Technical Writing & Communication',      1,'HM', 2,0,0,2,7,'N', 2,'Reports, presentations, academic writing',         'Y',SYSTIMESTAMP);
-- Open elective — no eligibility rows → visible to ALL depts sem 5+
-- Higher max_sections (5) because demand spans all departments
INSERT INTO courses VALUES (707,'OEL501','Introduction to Data Science',           1,'OC', 3,0,2,4,5,'Y', 5,'Data wrangling, visualization, ML basics',        'Y',SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 10. COURSE PREREQUISITES
-- ============================================================================

-- EVEN 2025-26 courses require Sem-5 foundations
INSERT INTO course_prerequisites VALUES (601, 103, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (601, 107, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (602, 106, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (603, 105, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (605, 103, 'Y', SYSTIMESTAMP);

-- ODD 2026-27 courses require Sem-6 (Even 2025-26) courses
INSERT INTO course_prerequisites VALUES (701, 108, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (702, 602, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (703, 605, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (704, 701, 'Y', SYSTIMESTAMP);
INSERT INTO course_prerequisites VALUES (705, 601, 'Y', SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 11. COURSE ELIGIBILITY
-- ============================================================================

-- EVEN 2025-26 Sem-6 courses: CSE program only
INSERT INTO course_eligibility VALUES (1, 601, 1, 1, 6, 7, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (2, 602, 1, 1, 6, 7, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (3, 603, 1, 1, 6, 7, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (4, 604, 1, 1, 6, 7, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (5, 605, 1, 1, 6, 7, 1, SYSTIMESTAMP);

-- ODD 2026-27 Sem-7 courses: CSE program only, semesters 7-8
INSERT INTO course_eligibility VALUES (6,  701, 1, 1, 7, 8, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (7,  702, 1, 1, 7, 8, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (8,  703, 1, 1, 7, 8, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (9,  704, 1, 1, 7, 8, 1, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (10, 705, 1, 1, 7, 8, 1, SYSTIMESTAMP);

-- HML501: all UG programs Sem 5+
INSERT INTO course_eligibility VALUES (11, 706, NULL, 1, 5, 8, 2, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (12, 706, NULL, 2, 5, 8, 2, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (13, 706, NULL, 3, 5, 8, 2, SYSTIMESTAMP);
INSERT INTO course_eligibility VALUES (14, 706, NULL, 5, 5, 8, 2, SYSTIMESTAMP);

-- OEL501: NO eligibility rows → open to all departments and semesters

COMMIT;

-- ============================================================================
-- 12. COURSE OFFERINGS
-- ============================================================================

-- ── TERM 1 (EVEN 2025-26, term_id=1) — CURRENTLY RUNNING ──────────────────
INSERT INTO course_offerings VALUES (1, 601, 1, 3,  13,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (2, 602, 1, 1,  11,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (3, 603, 1, 4,  14,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (4, 604, 1, 6,  NULL,'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (5, 605, 1, 5,  12,  'Y', SYSTIMESTAMP);

-- ── TERM 2 (ODD 2026-27, term_id=2) — UPCOMING (faculty floating sections) ─
INSERT INTO course_offerings VALUES (6, 701, 2, 3,  13,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (7, 702, 2, 1,  11,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (8, 703, 2, 4,  14,  'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (9, 704, 2, 6,  NULL,'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (10,705, 2, 5,  NULL,'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (11,706, 2, 2,  NULL,'Y', SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (12,707, 2, 7,  15,  'Y', SYSTIMESTAMP);
COMMIT;

-- ============================================================================
-- 13. SECTIONS
-- ── TERM 1 — Active sections (students enrolled, classes happening) ─────────
-- ── TERM 2 — Pre-floated sections (reg window open, no classes yet) ─────────
-- ============================================================================

-- TERM 1: Compiler Design (max_sections=2) — already has 2 sections floated,
--         which equals the cap. This demonstrates the limit in action.
-- Section A (Prof Kumar): 10 students, near full
INSERT INTO sections VALUES (1,  1,'A', 1, 1, 12, 0,10,0,'SB-301','LAB-101',42,14,'Y',SYSTIMESTAMP);
-- Section B (Dr Sharma):  smaller, 6 capacity → waitlist demo
INSERT INTO sections VALUES (2,  1,'B', 2, 2,  6, 0,10,0,'SB-302','LAB-103',42,14,'Y',SYSTIMESTAMP);

-- TERM 1: AI (Dr Deshmukh) — max_sections=2, 1 floated
INSERT INTO sections VALUES (3,  2,'A', 6, 6, 40, 0,10,0,'SB-501','LAB-201',42,14,'Y',SYSTIMESTAMP);

-- TERM 1: Computer Graphics (Dr Verma) — max_sections=2, 1 floated
INSERT INTO sections VALUES (4,  3,'A', 3, 3, 40, 0,10,0,'SB-201','LAB-102',42,14,'Y',SYSTIMESTAMP);

-- TERM 1: Software Engineering (Prof Kumar) — max_sections=2, 1 floated
INSERT INTO sections VALUES (5,  4,'A', 1, 1, 60, 0,10,0,'SB-301', NULL,    44, 0,'Y',SYSTIMESTAMP);

-- TERM 1: DBMS (Dr Sharma) — max_sections=2, 1 floated
INSERT INTO sections VALUES (6,  5,'A', 2, 2, 60, 0,10,0,'SB-303','LAB-103',42,14,'Y',SYSTIMESTAMP);

-- TERM 2: Networks (Dr Patel) — max_sections=3, 1 floated
INSERT INTO sections VALUES (7,  6,'A', 4, 4, 50, 0,10,0,'SB-202','LAB-102',44,15,'Y',SYSTIMESTAMP);

-- TERM 2: ML (Dr Deshmukh) — max_sections=3, small cap → FILLING_FAST demo
INSERT INTO sections VALUES (8,  7,'A', 6, 6, 30, 0,10,0,'SB-501','LAB-201',44,15,'Y',SYSTIMESTAMP);

-- TERM 2: Cloud Computing (Dr Verma) — max_sections=3, 1 floated
INSERT INTO sections VALUES (9,  8,'A', 3, 3, 50, 0,10,0,'SB-201','LAB-102',44,15,'Y',SYSTIMESTAMP);

-- TERM 2: InfoSec (Dr Patel) — max_sections=2, 1 floated
INSERT INTO sections VALUES (10, 9,'A', 4, 4, 50, 0,10,0,'SB-202', NULL,    44, 0,'Y',SYSTIMESTAMP);

-- TERM 2: Distributed Systems (Prof Kumar) — max_sections=2, 1 floated
INSERT INTO sections VALUES (11,10,'A', 1, 1, 60, 0,10,0,'SB-301', NULL,    44, 0,'Y',SYSTIMESTAMP);

-- TERM 2: HML (Dr Jha) — max_sections=2, 1 floated
INSERT INTO sections VALUES (12,11,'A', 8, 8, 80, 0,10,0,'SB-601', NULL,    44, 0,'Y',SYSTIMESTAMP);

-- TERM 2: Data Science Open Elective (Dr Deshmukh) — max_sections=5, 1 floated
INSERT INTO sections VALUES (13,12,'A', 6, 6, 40, 0,10,0,'SB-502','LAB-202',44,15,'Y',SYSTIMESTAMP);

COMMIT;

-- ============================================================================
-- 14. COMPLETED REGISTRATIONS FROM EARLIER SEMESTERS
--     2022 CSE students need these COMPLETED so Term-1 & Term-2 prereqs pass
-- ============================================================================

-- Historical term for Sem 1-5 records
INSERT INTO academic_terms VALUES (
    0,'HIST-2022-25','Historical 2022-25','2022-25','ODD',
    DATE'2022-08-01',DATE'2025-12-31',
    DATE'2022-07-01',DATE'2022-08-05',
    'N',SYSTIMESTAMP
);

-- Historical offerings & sections (capacity 999, is_active Y so trigger works)
INSERT INTO course_offerings VALUES (80,101,0,8, NULL,'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (81,102,0,7, 15,  'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (82,103,0,6, 11,  'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (83,104,0,5, NULL,'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (84,105,0,4, NULL,'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (85,106,0,3, NULL,'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (86,107,0,1, NULL,'Y',SYSTIMESTAMP);
INSERT INTO course_offerings VALUES (87,108,0,2, 13,  'Y',SYSTIMESTAMP);

INSERT INTO sections VALUES (80,80,'A',1,1,999,0,0,0,'HIST',NULL,  30, 0,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (81,81,'A',2,2,999,0,0,0,'HIST','L',   30,10,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (82,82,'A',1,1,999,0,0,0,'HIST','L',   30,10,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (83,83,'A',7,7,999,0,0,0,'HIST',NULL,  30, 0,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (84,84,'A',3,3,999,0,0,0,'HIST',NULL,  30, 0,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (85,85,'A',1,1,999,0,0,0,'HIST',NULL,  30, 0,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (86,86,'A',7,7,999,0,0,0,'HIST',NULL,  30, 0,'Y',SYSTIMESTAMP);
INSERT INTO sections VALUES (87,87,'A',3,3,999,0,0,0,'HIST','L',   30,10,'Y',SYSTIMESTAMP);

COMMIT;

-- Insert completed registrations (trigger sets REGISTERED; we UPDATE to COMPLETED)
DECLARE
    v_id NUMBER := 9000;
    PROCEDURE add_completed(p_sid NUMBER, p_sec NUMBER, p_term NUMBER) IS
    BEGIN
        v_id := v_id + 1;
        INSERT INTO registrations(
            registration_id, student_id, section_id, term_id,
            registration_status, approved_date, created_at, updated_at
        ) VALUES (
            v_id, p_sid, p_sec, p_term,
            'REGISTERED', SYSTIMESTAMP - 400, SYSTIMESTAMP - 400, SYSTIMESTAMP - 400
        );
        UPDATE registrations SET registration_status = 'COMPLETED'
         WHERE registration_id = v_id AND term_id = 0;
    END;
BEGIN
    -- Explicit calls per student — avoids FOR sid IN 1001..1012 which
    -- SQLPlus mis-parses as a substitution variable (&1001) and prompts
    -- for user input. Oracle numeric FOR loops only safely handle small
    -- integer literals; large start values trigger this scanner bug.
    add_completed(1001, 80, 0); add_completed(1001, 81, 0);
    add_completed(1001, 82, 0); add_completed(1001, 83, 0);
    add_completed(1001, 84, 0); add_completed(1001, 85, 0);
    add_completed(1001, 86, 0); add_completed(1001, 87, 0);

    add_completed(1002, 80, 0); add_completed(1002, 81, 0);
    add_completed(1002, 82, 0); add_completed(1002, 83, 0);
    add_completed(1002, 84, 0); add_completed(1002, 85, 0);
    add_completed(1002, 86, 0); add_completed(1002, 87, 0);

    add_completed(1003, 80, 0); add_completed(1003, 81, 0);
    add_completed(1003, 82, 0); add_completed(1003, 83, 0);
    add_completed(1003, 84, 0); add_completed(1003, 85, 0);
    add_completed(1003, 86, 0); add_completed(1003, 87, 0);

    add_completed(1004, 80, 0); add_completed(1004, 81, 0);
    add_completed(1004, 82, 0); add_completed(1004, 83, 0);
    add_completed(1004, 84, 0); add_completed(1004, 85, 0);
    add_completed(1004, 86, 0); add_completed(1004, 87, 0);

    add_completed(1005, 80, 0); add_completed(1005, 81, 0);
    add_completed(1005, 82, 0); add_completed(1005, 83, 0);
    add_completed(1005, 84, 0); add_completed(1005, 85, 0);
    add_completed(1005, 86, 0); add_completed(1005, 87, 0);

    add_completed(1006, 80, 0); add_completed(1006, 81, 0);
    add_completed(1006, 82, 0); add_completed(1006, 83, 0);
    add_completed(1006, 84, 0); add_completed(1006, 85, 0);
    add_completed(1006, 86, 0); add_completed(1006, 87, 0);

    add_completed(1007, 80, 0); add_completed(1007, 81, 0);
    add_completed(1007, 82, 0); add_completed(1007, 83, 0);
    add_completed(1007, 84, 0); add_completed(1007, 85, 0);
    add_completed(1007, 86, 0); add_completed(1007, 87, 0);

    add_completed(1008, 80, 0); add_completed(1008, 81, 0);
    add_completed(1008, 82, 0); add_completed(1008, 83, 0);
    add_completed(1008, 84, 0); add_completed(1008, 85, 0);
    add_completed(1008, 86, 0); add_completed(1008, 87, 0);

    add_completed(1009, 80, 0); add_completed(1009, 81, 0);
    add_completed(1009, 82, 0); add_completed(1009, 83, 0);
    add_completed(1009, 84, 0); add_completed(1009, 85, 0);
    add_completed(1009, 86, 0); add_completed(1009, 87, 0);

    add_completed(1010, 80, 0); add_completed(1010, 81, 0);
    add_completed(1010, 82, 0); add_completed(1010, 83, 0);
    add_completed(1010, 84, 0); add_completed(1010, 85, 0);
    add_completed(1010, 86, 0); add_completed(1010, 87, 0);

    add_completed(1011, 80, 0); add_completed(1011, 81, 0);
    add_completed(1011, 82, 0); add_completed(1011, 83, 0);
    add_completed(1011, 84, 0); add_completed(1011, 85, 0);
    add_completed(1011, 86, 0); add_completed(1011, 87, 0);

    add_completed(1012, 80, 0); add_completed(1012, 81, 0);
    add_completed(1012, 82, 0); add_completed(1012, 83, 0);
    add_completed(1012, 84, 0); add_completed(1012, 85, 0);
    add_completed(1012, 86, 0); add_completed(1012, 87, 0);

    COMMIT;
END;
/

-- ============================================================================
-- 15. TERM-1 REGISTRATIONS  (Even 2025-26 — currently running)
--     Trigger fires on INSERT → sets REGISTERED and bumps counters
-- ============================================================================

-- Compiler Design Section A (sec=1): students 1001–1010
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1001,1001,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1002,1002,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1003,1003,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1004,1004,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1005,1005,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1006,1006,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1007,1007,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1008,1008,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1009,1009,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1010,1010,1,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');

-- Compiler Design Section B (sec=2, cap=6): students 1011,1012 + simulate 4 more
-- Section B cap=6, we put 2 real students and bump enrollment to 5 to demo waitlist
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1051,1011,2,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(1052,1012,2,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
-- Bump sec 2 enrollment to 5 (leaving 1 seat) to show FILLING_FAST
UPDATE sections SET current_enrollment = 5 WHERE section_id = 2;

-- AI Section A (sec=3): students 1001–1006
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2001,1001,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2002,1002,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2003,1003,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2004,1004,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2005,1005,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(2006,1006,3,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');

-- Computer Graphics (sec=4): students 1001–1005
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(3001,1001,4,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(3002,1002,4,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(3003,1003,4,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(3004,1004,4,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(3005,1005,4,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');

-- DBMS (sec=6): students 1001–1007
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4001,1001,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4002,1002,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4003,1003,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4004,1004,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4005,1005,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4006,1006,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(4007,1007,6,1,'REGISTERED',DATE'2026-02-01',DATE'2026-02-01',DATE'2026-02-01');

COMMIT;

-- Reconcile enrollment counts for Term-1 sections
BEGIN
    registration_manager.update_enrollment_counts(1);
    registration_manager.update_enrollment_counts(3);
    registration_manager.update_enrollment_counts(4);
    registration_manager.update_enrollment_counts(5);
    registration_manager.update_enrollment_counts(6);
    COMMIT;
END;
/

-- ============================================================================
-- 16. CLASS SCHEDULE — TERM 1 (EVEN 2025-26)
--     Classes started 06-FEB-2026; today is 16-APR-2026
--     ~10 weeks of classes conducted = ~18 theory, ~8 lab sessions
-- ============================================================================

-- ── Compiler Design Section A (section_id=1, slot C=TUE/THU 08:00-09:30) ──
INSERT INTO class_schedule VALUES(101,1,DATE'2026-02-10',3,'THEORY',1, 'Introduction to Compilers & Phases',  1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-65,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(102,1,DATE'2026-02-12',3,'THEORY',2, 'Lexical Analysis & Regular Expressions',1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-63,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(103,1,DATE'2026-02-17',3,'THEORY',3, 'DFA/NFA & Regex to DFA',              1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-58,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(104,1,DATE'2026-02-19',3,'THEORY',4, 'Context-Free Grammars',               1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-56,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(105,1,DATE'2026-02-24',3,'THEORY',5, 'Top-Down Parsing',                    1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-51,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(106,1,DATE'2026-02-26',3,'THEORY',6, 'LL(1) Parsers',                       1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-49,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(107,1,DATE'2026-03-04',3,'THEORY',7, 'Bottom-Up Parsing — LR(0)',           1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-42,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(108,1,DATE'2026-03-06',3,'THEORY',8, 'SLR and LALR Parsers',               1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-40,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(109,1,DATE'2026-03-11',3,'THEORY',9, 'Semantic Analysis & Symbol Tables',  1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-35,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(110,1,DATE'2026-03-13',3,'THEORY',10,'Type Checking',                      1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-33,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(111,1,DATE'2026-03-18',3,'THEORY',11,'Intermediate Code Generation',       1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-28,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(112,1,DATE'2026-03-20',3,'THEORY',12,'Three Address Code',                 1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-26,SYSTIMESTAMP);
-- Mid-semester break week (25 Mar–01 Apr)
INSERT INTO class_schedule VALUES(113,1,DATE'2026-04-01',3,'THEORY',13,'Code Optimization Basics',           1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-15,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(114,1,DATE'2026-04-03',3,'THEORY',14,'Loop Optimization',                  1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-13,SYSTIMESTAMP);
-- Cancelled class
INSERT INTO class_schedule VALUES(115,1,DATE'2026-04-08',3,'THEORY',15,'Register Allocation',                1,'SB-301','Y','Faculty at Conference','N',NULL,SYSTIMESTAMP-8,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(116,1,DATE'2026-04-10',3,'THEORY',16,'Code Generation',                    1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-6,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(117,1,DATE'2026-04-15',3,'THEORY',17,'Run-time Environment',               1,'SB-301','N',NULL,'Y',1,SYSTIMESTAMP-1,SYSTIMESTAMP);

-- Compiler Design Lab sessions (slot L3=WED 14:00-17:00)
INSERT INTO class_schedule VALUES(151,1,DATE'2026-02-12',13,'LAB',1,'Flex Lexer Basics',                     1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-63,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(152,1,DATE'2026-02-19',13,'LAB',2,'NFA to DFA Conversion Tool',            1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-56,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(153,1,DATE'2026-02-26',13,'LAB',3,'YACC/Bison Parser',                     1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-49,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(154,1,DATE'2026-03-05',13,'LAB',4,'Symbol Table Implementation',           1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-42,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(155,1,DATE'2026-03-12',13,'LAB',5,'Semantic Analysis Lab',                 1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-35,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(156,1,DATE'2026-04-02',13,'LAB',6,'Three-Address Code Generation',         1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-14,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(157,1,DATE'2026-04-09',13,'LAB',7,'Mini Compiler Project',                 1,'LAB-101','N',NULL,'Y',1,SYSTIMESTAMP-7,SYSTIMESTAMP);

-- ── AI Section A (section_id=3, slot A=MON/WED/FRI 08:00-09:30) ────────────
INSERT INTO class_schedule VALUES(201,3,DATE'2026-02-09',1,'THEORY',1, 'Introduction to AI & Search',        6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-66,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(202,3,DATE'2026-02-11',1,'THEORY',2, 'BFS and DFS in AI',                  6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-64,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(203,3,DATE'2026-02-13',1,'THEORY',3, 'Heuristic Search — A*',              6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-62,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(204,3,DATE'2026-02-16',1,'THEORY',4, 'Adversarial Search — Minimax',       6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-59,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(205,3,DATE'2026-02-18',1,'THEORY',5, 'Knowledge Representation',           6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-57,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(206,3,DATE'2026-02-20',1,'THEORY',6, 'Propositional Logic',                6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-55,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(207,3,DATE'2026-02-23',1,'THEORY',7, 'First-Order Logic',                  6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-52,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(208,3,DATE'2026-02-25',1,'THEORY',8, 'Bayesian Networks',                  6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-50,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(209,3,DATE'2026-02-27',1,'THEORY',9, 'Naive Bayes Classifier',             6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-48,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(210,3,DATE'2026-03-02',1,'THEORY',10,'Decision Trees',                     6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-45,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(211,3,DATE'2026-03-04',1,'THEORY',11,'Support Vector Machines',            6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-43,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(212,3,DATE'2026-03-06',1,'THEORY',12,'Neural Networks Intro',              6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-41,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(213,3,DATE'2026-04-01',1,'THEORY',13,'Backpropagation',                    6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-15,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(214,3,DATE'2026-04-03',1,'THEORY',14,'CNNs Introduction',                  6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-13,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(215,3,DATE'2026-04-08',1,'THEORY',15,'NLP Basics',                         6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-8, SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(216,3,DATE'2026-04-13',1,'THEORY',16,'Reinforcement Learning',             6,'SB-501','N',NULL,'Y',6,SYSTIMESTAMP-3, SYSTIMESTAMP);

-- AI Lab (slot L1=MON 14:00-17:00)
INSERT INTO class_schedule VALUES(251,3,DATE'2026-02-09',11,'LAB',1,'Python for AI Setup',                   6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-66,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(252,3,DATE'2026-02-16',11,'LAB',2,'A* Search Implementation',              6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-59,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(253,3,DATE'2026-02-23',11,'LAB',3,'Naive Bayes Classifier Lab',            6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-52,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(254,3,DATE'2026-03-02',11,'LAB',4,'Decision Tree Implementation',          6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-45,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(255,3,DATE'2026-03-09',11,'LAB',5,'SVM with Scikit-learn',                 6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-38,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(256,3,DATE'2026-04-06',11,'LAB',6,'Neural Network from Scratch',           6,'LAB-201','N',NULL,'Y',6,SYSTIMESTAMP-10,SYSTIMESTAMP);

-- ── DBMS Section A (section_id=6, slot E=MON/WED/FRI 12:00-13:00) ─────────
INSERT INTO class_schedule VALUES(301,6,DATE'2026-02-09',5,'THEORY',1, 'ER Modelling & Relational Model',    2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-66,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(302,6,DATE'2026-02-11',5,'THEORY',2, 'Relational Algebra',                 2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-64,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(303,6,DATE'2026-02-13',5,'THEORY',3, 'SQL — DDL and DML',                  2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-62,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(304,6,DATE'2026-02-16',5,'THEORY',4, 'SQL — Joins, Subqueries',            2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-59,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(305,6,DATE'2026-02-18',5,'THEORY',5, 'Functional Dependencies',            2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-57,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(306,6,DATE'2026-02-20',5,'THEORY',6, '1NF, 2NF, 3NF, BCNF',              2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-55,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(307,6,DATE'2026-02-23',5,'THEORY',7, 'Transactions & ACID',                2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-52,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(308,6,DATE'2026-02-25',5,'THEORY',8, 'Concurrency Control',                2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-50,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(309,6,DATE'2026-02-27',5,'THEORY',9, 'Recovery Techniques',                2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-48,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(310,6,DATE'2026-03-02',5,'THEORY',10,'Indexing — B+ Trees',               2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-45,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(311,6,DATE'2026-03-04',5,'THEORY',11,'Query Processing',                   2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-43,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(312,6,DATE'2026-04-01',5,'THEORY',12,'Query Optimization',                 2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-15,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(313,6,DATE'2026-04-06',5,'THEORY',13,'NoSQL Databases',                    2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-10,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(314,6,DATE'2026-04-13',5,'THEORY',14,'Distributed Databases',              2,'SB-303','N',NULL,'Y',2,SYSTIMESTAMP-3, SYSTIMESTAMP);

-- DBMS Lab (slot L2=TUE 14:00-17:00)
INSERT INTO class_schedule VALUES(351,6,DATE'2026-02-11',12,'LAB',1,'SQL DDL Practice',                      2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-64,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(352,6,DATE'2026-02-18',12,'LAB',2,'Complex SQL Queries',                   2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-57,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(353,6,DATE'2026-02-25',12,'LAB',3,'PL/SQL Procedures',                     2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-50,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(354,6,DATE'2026-03-04',12,'LAB',4,'Triggers and Views',                    2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-43,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(355,6,DATE'2026-04-01',12,'LAB',5,'Indexing and Performance',              2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-15,SYSTIMESTAMP);
INSERT INTO class_schedule VALUES(356,6,DATE'2026-04-08',12,'LAB',6,'NoSQL with MongoDB',                    2,'LAB-103','N',NULL,'Y',2,SYSTIMESTAMP-8, SYSTIMESTAMP);

COMMIT;

-- ============================================================================
-- 17. ATTENDANCE DATA
--     Realistic distribution for demo:
--     1001 Aarav    : 95%+ (star student)
--     1002 Diya     : 88%  (good)
--     1003 Arjun    : 82%  (above threshold)
--     1004 Ananya   : 76%  (borderline)
--     1005 Kabir    : 70%  (DEFAULTER — below 75%)
--     1006 Ishita   : 65%  (DEFAULTER)
--     1007 Rohan    : 55%  (DEFAULTER — worst)
--     Others vary
-- ============================================================================

DECLARE
    PROCEDURE mark(p_reg NUMBER, p_sched NUMBER, p_status VARCHAR2, p_fac NUMBER) IS
    BEGIN
        INSERT INTO attendance(attendance_id,registration_id,schedule_id,status,marked_by,marked_at,created_at)
        VALUES(attendance_seq.NEXTVAL, p_reg, p_sched, p_status, p_fac, SYSTIMESTAMP, SYSTIMESTAMP);
    EXCEPTION WHEN DUP_VAL_ON_INDEX THEN NULL;
    END;
BEGIN

    -- ── COMPILER DESIGN SECTION A (sec=1, regs 1001-1010) ──────────────────
    -- Theory schedules: 101-117 (115 cancelled; 116,117 most recent)
    -- 16 non-cancelled theory + 7 lab = 23 sessions

    -- Student 1001 (reg=1001): PERFECT theory, all labs
    FOR s IN (SELECT schedule_id FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(1001,s.schedule_id,'P',1);
    END LOOP;

    -- Student 1002 (reg=1002): 88% — misses 2 theory, 1 lab
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1002,s.schedule_id,CASE WHEN s.rn IN(5,12) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1002,s.schedule_id,CASE WHEN s.rn=2 THEN 'A' ELSE 'P' END,1); END IF;
    END LOOP;

    -- Student 1003 (reg=1003): 82% — misses 3 theory, 1 lab
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1003,s.schedule_id,CASE WHEN s.rn IN(3,8,14) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1003,s.schedule_id,CASE WHEN s.rn=4 THEN 'A' ELSE 'P' END,1); END IF;
    END LOOP;

    -- Student 1004 (reg=1004): 76% — misses 4 theory (borderline)
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1004,s.schedule_id,CASE WHEN s.rn IN(2,7,11,15) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1004,s.schedule_id,'P',1); END IF;
    END LOOP;

    -- Student 1005 (reg=1005): 70% DEFAULTER — misses 5 theory, 2 lab
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1005,s.schedule_id,CASE WHEN s.rn IN(1,4,8,12,16) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1005,s.schedule_id,CASE WHEN s.rn IN(2,5) THEN 'A' ELSE 'P' END,1); END IF;
    END LOOP;

    -- Student 1006 (reg=1006): 65% DEFAULTER — misses 6 theory, 2 lab
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1006,s.schedule_id,CASE WHEN s.rn IN(2,5,8,11,14,16) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1006,s.schedule_id,CASE WHEN s.rn IN(1,6) THEN 'A' ELSE 'P' END,1); END IF;
    END LOOP;

    -- Student 1007 (reg=1007): 55% DEFAULTER — misses 7 theory, 3 lab
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1007,s.schedule_id,CASE WHEN s.rn IN(1,3,6,9,12,14,16) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1007,s.schedule_id,CASE WHEN s.rn IN(2,4,7) THEN 'A' ELSE 'P' END,1); END IF;
    END LOOP;

    -- Student 1008 (reg=1008): 78%
    FOR s IN (SELECT schedule_id,class_type,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY class_type DESC,schedule_id) LOOP
        IF s.class_type='THEORY' THEN mark(1008,s.schedule_id,CASE WHEN s.rn IN(4,10,15) THEN 'A' ELSE 'P' END,1);
        ELSE mark(1008,s.schedule_id,'P',1); END IF;
    END LOOP;

    -- Student 1009 (reg=1009): 84%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(1009,s.schedule_id,CASE WHEN s.rn IN(7,13) THEN 'A' ELSE 'P' END,1);
    END LOOP;

    -- Student 1010 (reg=1010): 90%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=1 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(1010,s.schedule_id,CASE WHEN s.rn=6 THEN 'A' ELSE 'P' END,1);
    END LOOP;

    -- ── AI Section A (sec=3, regs 2001-2006) ───────────────────────────────

    -- Student 1001 (reg=2001): 100%
    FOR s IN (SELECT schedule_id FROM class_schedule WHERE section_id=3 AND is_cancelled='N') LOOP
        mark(2001,s.schedule_id,'P',6);
    END LOOP;

    -- Student 1002 (reg=2002): 88%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=3 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(2002,s.schedule_id,CASE WHEN s.rn IN(4,10,15) THEN 'A' ELSE 'P' END,6);
    END LOOP;

    -- Student 1003 (reg=2003): 78%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=3 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(2003,s.schedule_id,CASE WHEN s.rn IN(3,7,12,16) THEN 'A' ELSE 'P' END,6);
    END LOOP;

    -- Student 1004 (reg=2004): DEFAULTER 68% — misses ~7/22
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=3 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(2004,s.schedule_id,CASE WHEN s.rn IN(2,5,8,11,14,17,20) THEN 'A' ELSE 'P' END,6);
    END LOOP;

    -- Student 1005 (reg=2005): 82%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=3 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(2005,s.schedule_id,CASE WHEN s.rn IN(6,13,19) THEN 'A' ELSE 'P' END,6);
    END LOOP;

    -- Student 1006 (reg=2006): 91%
    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=3 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(2006,s.schedule_id,CASE WHEN s.rn=9 THEN 'L' ELSE 'P' END,6);
    END LOOP;

    -- ── DBMS Section A (sec=6, regs 4001-4007) ─────────────────────────────

    FOR s IN (SELECT schedule_id FROM class_schedule WHERE section_id=6 AND is_cancelled='N') LOOP
        mark(4001,s.schedule_id,'P',2);  -- 100%
        mark(4002,s.schedule_id,'P',2);  -- 100%
        mark(4006,s.schedule_id,'P',2);  -- 100%
    END LOOP;

    FOR s IN (SELECT schedule_id,ROWNUM rn FROM class_schedule WHERE section_id=6 AND is_cancelled='N' ORDER BY schedule_id) LOOP
        mark(4003,s.schedule_id,CASE WHEN s.rn IN(3,9) THEN 'A' ELSE 'P' END,2);       -- 90%
        mark(4004,s.schedule_id,CASE WHEN s.rn IN(2,6,11,16) THEN 'A' ELSE 'P' END,2); -- 79%
        mark(4005,s.schedule_id,CASE WHEN s.rn IN(1,4,7,10,13,16,19) THEN 'A' ELSE 'P' END,2); -- DEFAULTER 65%
        mark(4007,s.schedule_id,CASE WHEN s.rn IN(5,12) THEN 'A' ELSE 'P' END,2);      -- 88%
    END LOOP;

    COMMIT;
END;
/

-- ============================================================================
-- 19. TERM-2 REGISTRATIONS
--     Some students have already registered during the open window (Apr 10+)
--     Leave others unregistered so you can demo live registration
-- ============================================================================

-- Networks (sec=7): Aarav and Diya already registered
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(5001,1001,7,2,'REGISTERED',DATE'2026-04-11',DATE'2026-04-11',DATE'2026-04-11');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(5002,1002,7,2,'REGISTERED',DATE'2026-04-11',DATE'2026-04-11',DATE'2026-04-11');
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(5003,1003,7,2,'REGISTERED',DATE'2026-04-12',DATE'2026-04-12',DATE'2026-04-12');

-- ML (sec=8, cap=30): 24 already registered → show FILLING_FAST
-- Simulate by bumping enrollment counter
UPDATE sections SET current_enrollment = 24 WHERE section_id = 8;

-- Aarav registered for ML too
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(5010,1001,8,2,'REGISTERED',DATE'2026-04-11',DATE'2026-04-11',DATE'2026-04-11');

-- Arjun registered for Data Science (open elective, also for EEE demo)
INSERT INTO registrations(registration_id,student_id,section_id,term_id,registration_status,approved_date,created_at,updated_at) VALUES(5011,1003,13,2,'REGISTERED',DATE'2026-04-12',DATE'2026-04-12',DATE'2026-04-12');

COMMIT;

-- Reconcile Term-2 section counts
BEGIN
    registration_manager.update_enrollment_counts(7);
    registration_manager.update_enrollment_counts(8);
    registration_manager.update_enrollment_counts(9);
    registration_manager.update_enrollment_counts(10);
    registration_manager.update_enrollment_counts(11);
    registration_manager.update_enrollment_counts(12);
    registration_manager.update_enrollment_counts(13);
    COMMIT;
END;
/

-- ============================================================================
-- 20. SUMMARY
-- ============================================================================
SET SERVEROUTPUT ON;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=================================================');
    DBMS_OUTPUT.PUT_LINE('  VNIT AcadMS — Two-Term Demo Data Loaded');
    DBMS_OUTPUT.PUT_LINE('  Today: 16-APR-2026');
    DBMS_OUTPUT.PUT_LINE('=================================================');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('TERM 1 — EVEN 2025-26 (CURRENT, is_current=Y)');
    DBMS_OUTPUT.PUT_LINE('  Running:      06-FEB-2026 to 31-MAY-2026');
    DBMS_OUTPUT.PUT_LINE('  Reg window:   CLOSED (10-JAN – 05-FEB-2026)');
    DBMS_OUTPUT.PUT_LINE('  Courses:      Compiler, AI, Graphics, SWE, DBMS');
    DBMS_OUTPUT.PUT_LINE('  Attendance:   17 theory + 7 lab classes in Compiler');
    DBMS_OUTPUT.PUT_LINE('                16 theory + 6 lab in AI');
    DBMS_OUTPUT.PUT_LINE('                14 theory + 6 lab in DBMS');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('TERM 2 — ODD 2026-27 (UPCOMING, is_current=N)');
    DBMS_OUTPUT.PUT_LINE('  Starts:       01-JUL-2026');
    DBMS_OUTPUT.PUT_LINE('  Reg window:   OPEN (10-APR – 10-MAY-2026)');
    DBMS_OUTPUT.PUT_LINE('  Courses:      Networks, ML, Cloud, InfoSec,');
    DBMS_OUTPUT.PUT_LINE('                Distributed, HML, Data Science (OE)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('max_sections per course (demo values):');
    DBMS_OUTPUT.PUT_LINE('  Compiler Design     : 2  (both slots used — cap hit demo)');
    DBMS_OUTPUT.PUT_LINE('  AI, Graphics, SWE   : 2  (1 floated, 1 remaining)');
    DBMS_OUTPUT.PUT_LINE('  DBMS                : 2  (1 floated, 1 remaining)');
    DBMS_OUTPUT.PUT_LINE('  Networks, ML, Cloud : 3  (1 floated, 2 remaining)');
    DBMS_OUTPUT.PUT_LINE('  InfoSec, Distributed: 2  (1 floated, 1 remaining)');
    DBMS_OUTPUT.PUT_LINE('  HML                 : 2  (1 floated, 1 remaining)');
    DBMS_OUTPUT.PUT_LINE('  Data Science OE     : 5  (1 floated, 4 remaining)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('FACULTY LOGINS (employee_id / employee_id):');
    DBMS_OUTPUT.PUT_LINE('  F001 Kumar   — Compiler §A, SWE §A, Distributed §A');
    DBMS_OUTPUT.PUT_LINE('  F002 Sharma  — Compiler §B, DBMS §A');
    DBMS_OUTPUT.PUT_LINE('  F003 Verma   — Graphics §A, Cloud §A');
    DBMS_OUTPUT.PUT_LINE('  F004 Patel   — Networks §A, InfoSec §A');
    DBMS_OUTPUT.PUT_LINE('  F006 Deshmukh— AI §A, ML §A, Data Science §A');
    DBMS_OUTPUT.PUT_LINE('  F007 Bhadauria— (no section assigned yet)');
    DBMS_OUTPUT.PUT_LINE('  F008 Jha     — HML §A');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('STUDENT LOGINS (roll_number / roll_number):');
    DBMS_OUTPUT.PUT_LINE('  2022BCS001 Aarav   — 95%+ att; registered Term-2 Networks+ML');
    DBMS_OUTPUT.PUT_LINE('  2022BCS002 Diya    — 88%  att; registered Term-2 Networks');
    DBMS_OUTPUT.PUT_LINE('  2022BCS005 Kabir   — DEFAULTER 70% (Compiler)');
    DBMS_OUTPUT.PUT_LINE('  2022BCS006 Ishita  — DEFAULTER 65% (Compiler)');
    DBMS_OUTPUT.PUT_LINE('  2022BCS007 Rohan   — DEFAULTER 55% (Compiler)');
    DBMS_OUTPUT.PUT_LINE('  2023BCS001 Tanvi   — Sem 4; sees NO Sem-7 courses');
    DBMS_OUTPUT.PUT_LINE('  2022BEE001 Vivaan  — EEE; sees ONLY Data Science OE');
    DBMS_OUTPUT.PUT_LINE('=================================================');
END;
/