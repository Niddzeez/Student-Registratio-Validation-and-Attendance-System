"""
routers/students.py — Student-facing endpoints.

BUGS FIXED (this version):
1. drop_course / register_student: Oracle PL/SQL BOOLEAN cannot be bound
   through the OCI/oracledb Python driver. callproc() with
   p_success OUT BOOLEAN raised DatabaseError at runtime.
   Fix: replaced with anonymous PL/SQL blocks that convert BOOLEAN → NUMBER.

2. register_student: p_status is VARCHAR2 OUT — that was fine with callproc,
   but the anonymous-block rewrite keeps it consistent and correct.

Previous fixes retained:
3. /available-sections: filters by registration window, eligibility,
   already-registered courses, and active sections/offerings.
4. /drop: single connection for ownership check + procedure call.
5. /attendance/{id}/history: explicit join via section_id to avoid
   Cartesian product.
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import query_many, query_one, get_connection
from auth_utils import require_student
import oracledb

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Course Registration
# ─────────────────────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    section_id: int
    term_id: int


@router.post("/register")
def register_course(req: RegisterRequest, user: dict = Depends(require_student)):
    with get_connection() as conn:
        cursor = conn.cursor()
        p_reg_id = cursor.var(oracledb.NUMBER)
        p_status = cursor.var(oracledb.STRING)
        p_msg    = cursor.var(oracledb.STRING)
        # register_student uses VARCHAR2 OUT for p_status — no BOOLEAN here,
        # but use anonymous block for consistency and to avoid potential issues
        # with keyword-parameter binding across Oracle client versions.
        cursor.execute(
            """
            BEGIN
                registration_manager.register_student(
                    p_student_id      => :p_student_id,
                    p_section_id      => :p_section_id,
                    p_term_id         => :p_term_id,
                    p_registration_id => :p_registration_id,
                    p_status          => :p_status,
                    p_message         => :p_message
                );
            END;
            """,
            {
                "p_student_id":      user["id"],
                "p_section_id":      req.section_id,
                "p_term_id":         req.term_id,
                "p_registration_id": p_reg_id,
                "p_status":          p_status,
                "p_message":         p_msg,
            },
        )
        conn.commit()
        status_val = p_status.getvalue()
        if status_val in ("ERROR", "FAILED"):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {
            "registration_id": int(p_reg_id.getvalue() or 0),
            "status":          status_val,
            "message":         p_msg.getvalue(),
        }


class DropRequest(BaseModel):
    registration_id: int
    reason: str = ""


@router.post("/drop")
def drop_course(req: DropRequest, user: dict = Depends(require_student)):
    """Single connection for ownership check AND procedure call."""
    with get_connection() as conn:
        cursor = conn.cursor()

        # Ownership check on the same connection
        cursor.execute(
            "SELECT student_id FROM registrations WHERE registration_id = :r",
            {"r": req.registration_id},
        )
        row = cursor.fetchone()
        if not row or row[0] != user["id"]:
            raise HTTPException(status_code=403, detail="Not your registration")

        p_success = cursor.var(oracledb.NUMBER)
        p_msg     = cursor.var(oracledb.STRING)
        # Bug fix: drop_course has p_success OUT BOOLEAN → anonymous block
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                registration_manager.drop_course(
                    p_registration_id => :p_registration_id,
                    p_reason          => :p_reason,
                    p_success         => v_success,
                    p_message         => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_registration_id": req.registration_id,
                "p_reason":          req.reason,
                "p_success":         p_success,
                "p_message":         p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {"message": p_msg.getvalue()}


# ─────────────────────────────────────────────────────────────────────────────
# Enrolled Courses & Registration Status
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/enrollments")
def get_enrollments(user: dict = Depends(require_student)):
    return query_many(
        """SELECT r.registration_id, r.registration_status, r.waitlist_position,
                  c.course_id, c.course_code, c.course_name, c.credits,
                  sec.section_id, sec.section_code,
                  t.term_id, t.term_name, t.academic_year,
                  t.is_current,
                  f.first_name || ' ' || NVL(f.last_name, '') AS instructor
             FROM registrations r
             JOIN sections sec        ON r.section_id    = sec.section_id
             JOIN course_offerings co ON sec.offering_id = co.offering_id
             JOIN courses c           ON co.course_id    = c.course_id
             JOIN academic_terms t    ON r.term_id       = t.term_id
             JOIN faculty f           ON sec.instructor_id = f.faculty_id
            WHERE r.student_id = :sid
            ORDER BY t.is_current DESC, t.term_id DESC, c.course_name""",
        {"sid": user["id"]},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Timetable
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/timetable")
def get_timetable(user: dict = Depends(require_student)):
    return query_many(
        """SELECT c.course_code, c.course_name,
                  sec.section_code, sec.theory_room, sec.lab_room,
                  sl.slot_code  AS theory_slot,
                  ls.slot_code  AS lab_slot,
                  st.day_of_week, st.start_time, st.end_time,
                  t.term_name
             FROM registrations r
             JOIN sections sec        ON r.section_id      = sec.section_id
             JOIN course_offerings co ON sec.offering_id   = co.offering_id
             JOIN courses c           ON co.course_id      = c.course_id
             JOIN academic_terms t    ON r.term_id         = t.term_id
             JOIN slots sl            ON co.theory_slot_id = sl.slot_id
             LEFT JOIN slots ls       ON co.lab_slot_id    = ls.slot_id
             LEFT JOIN slot_timings st ON sl.slot_id       = st.slot_id
            WHERE r.student_id          = :sid
              AND r.registration_status IN ('REGISTERED', 'APPROVED')
              AND t.is_current          = 'Y'
            ORDER BY st.day_of_week, st.start_time""",
        {"sid": user["id"]},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Attendance
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/attendance")
def get_attendance_summary(user: dict = Depends(require_student)):
    return query_many(
        """
        SELECT sco.student_id, sco.roll_number, sco.student_name,
               sco.registration_id, sco.registration_status,
               sco.course_code, sco.course_name, sco.credits,
               sco.section_code, sco.term_name, sco.academic_year,
               sco.theory_attendance, sco.lab_attendance, sco.overall_attendance
        FROM student_course_overview sco
        JOIN registrations r  ON sco.registration_id = r.registration_id
        JOIN academic_terms t ON r.term_id = t.term_id
        WHERE sco.student_id = :sid
          AND t.start_date <= SYSDATE
          AND r.registration_status IN ('REGISTERED','APPROVED','COMPLETED')
        ORDER BY t.start_date DESC, sco.course_name
        """,
        {"sid": user["id"]},
    )


@router.get("/attendance/{registration_id}/history")
def get_attendance_history(registration_id: int, user: dict = Depends(require_student)):
    reg = query_one(
        "SELECT student_id FROM registrations WHERE registration_id = :r",
        {"r": registration_id},
    )
    if not reg or reg["student_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Access denied")

    return query_many(
        """
        SELECT cs.class_date, cs.class_type, sl.slot_code,
               cs.topic, cs.room_number,
               NVL(a.status, 'NOT_MARKED') AS status,
               a.remarks,
               f.first_name || ' ' || NVL(f.last_name, '') AS marked_by
        FROM registrations r
        JOIN class_schedule cs  ON cs.section_id = r.section_id
        JOIN slots sl           ON cs.slot_id    = sl.slot_id
        LEFT JOIN attendance a  ON a.registration_id = r.registration_id
                               AND a.schedule_id    = cs.schedule_id
        LEFT JOIN faculty f     ON a.marked_by = f.faculty_id
        WHERE r.registration_id = :rid
          AND cs.is_cancelled   = 'N'
          AND cs.class_date <= SYSDATE
        ORDER BY cs.class_date DESC, cs.class_type
        """,
        {"rid": registration_id},
    )

# ─────────────────────────────────────────────────────────────────────────────
# Available Sections
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/available-sections")
def get_available_sections(user: dict = Depends(require_student)):
    return query_many(
        """
        WITH student_info AS (
            SELECT s.student_id,
                   p.dept_id          AS student_dept,
                   b.program_id       AS student_program,
                   s.current_semester AS student_semester
              FROM students s
              JOIN batches  b ON s.batch_id   = b.batch_id
              JOIN programs p ON b.program_id = p.program_id
             WHERE s.student_id = :sid
        ),
        already_registered AS (
            SELECT co.course_id
              FROM registrations r
              JOIN sections s          ON r.section_id  = s.section_id
              JOIN course_offerings co ON s.offering_id = co.offering_id
             WHERE r.student_id          = :sid
               AND r.registration_status IN ('REGISTERED','WAITLISTED','APPROVED')
        )
        SELECT
            sec.section_id,
            sec.section_code,
            c.course_code,
            c.course_name,
            c.credits,
            c.has_lab,
            c.course_type,
            t.term_id,
            t.term_name,
            t.academic_year,
            t.registration_start_date,
            t.registration_end_date,
            sec.max_capacity,
            sec.current_enrollment,
            sec.current_waitlist,
            GREATEST(sec.max_capacity - sec.current_enrollment, 0) AS seats_available,
            ROUND(sec.current_enrollment * 100.0 / NULLIF(sec.max_capacity, 0), 1)
                AS fill_percentage,
            CASE
                WHEN sec.current_enrollment >= sec.max_capacity AND sec.current_waitlist > 0
                     THEN 'HIGH_DEMAND'
                WHEN sec.current_enrollment >= sec.max_capacity
                     THEN 'FULL'
                WHEN sec.current_enrollment >= 0.75 * sec.max_capacity
                     THEN 'FILLING_FAST'
                ELSE 'AVAILABLE'
            END AS demand_status,
            f.first_name || ' ' || NVL(f.last_name, '') AS instructor,
            sl.slot_code  AS theory_slot,
            ls.slot_code  AS lab_slot,
            CASE
                WHEN NOT EXISTS (
                    SELECT 1 FROM course_prerequisites cp
                     WHERE cp.course_id = c.course_id AND cp.is_mandatory = 'Y'
                       AND NOT EXISTS (
                           SELECT 1 FROM registrations r2
                             JOIN sections s2          ON r2.section_id  = s2.section_id
                             JOIN course_offerings co2 ON s2.offering_id = co2.offering_id
                            WHERE r2.student_id = :sid
                              AND co2.course_id = cp.prerequisite_course_id
                              AND r2.registration_status = 'COMPLETED'
                       )
                ) THEN 'Y' ELSE 'N'
            END AS prerequisites_met
        FROM student_info si
        JOIN course_eligibility ce  ON (
            (ce.dept_id    IS NULL OR ce.dept_id    = si.student_dept)
            AND (ce.program_id IS NULL OR ce.program_id = si.student_program)
            AND (ce.min_semester IS NULL OR si.student_semester >= ce.min_semester)
            AND (ce.max_semester IS NULL OR si.student_semester <= ce.max_semester)
        )
        JOIN courses c              ON ce.course_id    = c.course_id
        JOIN course_offerings co    ON co.course_id    = c.course_id
        JOIN academic_terms t       ON co.term_id      = t.term_id
        JOIN sections sec           ON sec.offering_id = co.offering_id
        JOIN faculty f              ON sec.instructor_id = f.faculty_id
        JOIN slots sl               ON co.theory_slot_id = sl.slot_id
        LEFT JOIN slots ls          ON co.lab_slot_id    = ls.slot_id
        WHERE
            t.registration_start_date IS NOT NULL
            AND t.registration_end_date IS NOT NULL
            AND TRUNC(SYSDATE) BETWEEN TRUNC(t.registration_start_date)
                                   AND TRUNC(t.registration_end_date)
            AND sec.is_active = 'Y'
            AND co.is_active  = 'Y'
            AND c.is_active   = 'Y'
            AND c.course_id NOT IN (SELECT course_id FROM already_registered)
        ORDER BY c.course_name, sec.section_code
        """,
        {"sid": user["id"]},
    )