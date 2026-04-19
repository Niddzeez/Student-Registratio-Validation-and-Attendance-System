"""
routers/faculty.py — Faculty-facing endpoints.

CHANGES for two-term scenario:
- Added GET /terms — returns both terms with metadata so frontend can show
  context (current vs upcoming) correctly.
- Added POST /float-section — faculty can create a new section for the upcoming
  (ODD 2026-27) term, choosing offering, capacity, rooms. This is the "float
  course for registration" workflow.
  ADDED: max_sections enforcement — the number of active sections for a course
  offering in a given term must not exceed courses.max_sections. If the limit
  is reached the request is rejected with a clear message.
- Added GET /upcoming-offerings — lists course offerings in the upcoming term
  that belong to this faculty's department so they know what to float.
- GET /sections now explicitly returns term_type and is_current so the frontend
  can group active-term sections (for attendance/scheduling) vs upcoming-term
  sections (for registration management).

Existing fixes retained:
- Oracle BOOLEAN OUT via anonymous PL/SQL blocks (BOOLEAN → NUMBER 1/0)
- p_class_date passed via TO_DATE(:p_class_date,'YYYY-MM-DD') in anon block
- Section ownership verification before every mutable operation
"""
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import query_many, query_one, get_connection
from auth_utils import require_faculty
import oracledb

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────

def _verify_section_owner(section_id: int, faculty_id: int):
    row = query_one(
        "SELECT instructor_id FROM sections WHERE section_id = :s",
        {"s": section_id},
    )
    if not row or row["instructor_id"] != faculty_id:
        raise HTTPException(status_code=403, detail="Not your section")


# ─────────────────────────────────────────────────────────────────────────────
# Terms — return both terms so frontend knows what's current vs upcoming
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/terms")
def get_terms(user: dict = Depends(require_faculty)):
    """Return all relevant terms with registration window status."""
    return query_many(
        """SELECT term_id, term_code, term_name, academic_year, term_type,
                  start_date, end_date,
                  registration_start_date, registration_end_date,
                  is_current,
                  CASE
                      WHEN is_current = 'Y'                                    THEN 'ACTIVE'
                      WHEN TRUNC(SYSDATE) < TRUNC(start_date)
                       AND TRUNC(SYSDATE) BETWEEN TRUNC(registration_start_date)
                                              AND TRUNC(registration_end_date) THEN 'REG_OPEN'
                      WHEN TRUNC(SYSDATE) < TRUNC(start_date)                  THEN 'UPCOMING'
                      ELSE 'PAST'
                  END AS term_status
             FROM academic_terms
            WHERE term_id > 0
            ORDER BY term_id DESC""",
        {},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Sections — all sections assigned to this faculty across all active terms
# Returns term_type and is_current for frontend grouping
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/sections")
def get_my_sections(user: dict = Depends(require_faculty)):
    return query_many(
        """SELECT sec.section_id, sec.section_code,
                  sec.theory_room, sec.lab_room,
                  sec.max_capacity, sec.current_enrollment, sec.current_waitlist,
                  sec.total_theory_classes_planned,
                  sec.total_lab_classes_planned,
                  c.course_code, c.course_name, c.credits, c.has_lab,
                  c.max_sections,
                  t.term_id, t.term_name, t.academic_year,
                  t.term_type, t.is_current,
                  t.start_date, t.end_date,
                  t.registration_start_date, t.registration_end_date,
                  -- Term status: ACTIVE (running) or REG_OPEN (upcoming, reg window open)
                  CASE
                      WHEN t.is_current = 'Y' THEN 'ACTIVE'
                      WHEN TRUNC(SYSDATE) BETWEEN TRUNC(t.registration_start_date)
                                              AND TRUNC(t.registration_end_date)
                       AND TRUNC(SYSDATE) < TRUNC(t.start_date)              THEN 'REG_OPEN'
                      WHEN TRUNC(SYSDATE) < TRUNC(t.start_date)              THEN 'UPCOMING'
                      ELSE 'PAST'
                  END AS term_status,
                  sl.slot_id    AS theory_slot_id,
                  sl.slot_code  AS theory_slot,
                  ls.slot_id    AS lab_slot_id,
                  ls.slot_code  AS lab_slot,
                  -- Conducted counts (3NF: from class_schedule)
                  (SELECT COUNT(*) FROM class_schedule cs
                    WHERE cs.section_id = sec.section_id
                      AND cs.class_type = 'THEORY' AND cs.is_cancelled = 'N') AS theory_conducted,
                  (SELECT COUNT(*) FROM class_schedule cs
                    WHERE cs.section_id = sec.section_id
                      AND cs.class_type = 'LAB'    AND cs.is_cancelled = 'N') AS lab_conducted,
                  -- Current section count for this offering (for display)
                  (SELECT COUNT(*) FROM sections s2
                    WHERE s2.offering_id = sec.offering_id
                      AND s2.is_active   = 'Y') AS current_section_count
             FROM sections sec
             JOIN course_offerings co ON sec.offering_id  = co.offering_id
             JOIN courses c           ON co.course_id     = c.course_id
             JOIN academic_terms t    ON co.term_id       = t.term_id
             JOIN slots sl            ON co.theory_slot_id = sl.slot_id
             LEFT JOIN slots ls       ON co.lab_slot_id    = ls.slot_id
            WHERE sec.instructor_id = :fid
              AND sec.is_active     = 'Y'
              AND (t.is_current = 'Y' OR t.start_date > SYSDATE)
            ORDER BY t.is_current DESC, t.term_id DESC, c.course_name""",
        {"fid": user["id"]},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Upcoming term offerings — for "float section" workflow
# Shows course offerings in the upcoming term (registration window open)
# that this faculty could be assigned to teach
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/upcoming-offerings")
def get_upcoming_offerings(user: dict = Depends(require_faculty)):
    """
    Returns course offerings in terms whose registration window is open but
    whose semester hasn't started yet. Faculty use this list to float sections.
    Filters to courses in the faculty member's department.
    Includes max_sections and existing_sections so the UI can show the cap.
    """
    return query_many(
        """SELECT co.offering_id,
                  c.course_id, c.course_code, c.course_name, c.credits,
                  c.has_lab, c.lecture_hours, c.tutorial_hours, c.practical_hours,
                  c.max_sections,
                  t.term_id, t.term_name, t.academic_year,
                  t.registration_start_date, t.registration_end_date,
                  sl.slot_id   AS theory_slot_id,
                  sl.slot_code AS theory_slot,
                  ls.slot_id   AS lab_slot_id,
                  ls.slot_code AS lab_slot,
                  -- Count of sections already floated for this offering
                  (SELECT COUNT(*) FROM sections s2
                    WHERE s2.offering_id = co.offering_id
                      AND s2.is_active   = 'Y') AS existing_sections,
                  -- Remaining slots available
                  GREATEST(c.max_sections - (
                      SELECT COUNT(*) FROM sections s2
                       WHERE s2.offering_id = co.offering_id
                         AND s2.is_active   = 'Y'
                  ), 0) AS sections_remaining
             FROM course_offerings co
             JOIN courses c       ON co.course_id = c.course_id
             JOIN academic_terms t ON co.term_id  = t.term_id
             JOIN slots sl        ON co.theory_slot_id = sl.slot_id
             LEFT JOIN slots ls   ON co.lab_slot_id    = ls.slot_id
             JOIN faculty f       ON f.faculty_id = :fid
            WHERE co.is_active = 'Y'
              AND c.is_active  = 'Y'
              AND c.dept_id    = f.dept_id
              -- upcoming term: reg window open, semester not started yet
              AND TRUNC(SYSDATE) BETWEEN TRUNC(t.registration_start_date)
                                     AND TRUNC(t.registration_end_date)
              AND TRUNC(SYSDATE) < TRUNC(t.start_date)
            ORDER BY c.course_name""",
        {"fid": user["id"]},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Float Section — faculty creates a new section for an upcoming term offering
# ─────────────────────────────────────────────────────────────────────────────
class FloatSectionRequest(BaseModel):
    offering_id:                  int
    section_code:                 str
    max_capacity:                 int
    waitlist_capacity:            int = 10
    theory_room:                  Optional[str] = None
    lab_room:                     Optional[str] = None
    total_theory_classes_planned: int = 42
    total_lab_classes_planned:    int = 0


@router.post("/float-section")
def float_section(req: FloatSectionRequest, user: dict = Depends(require_faculty)):
    """
    Faculty floats a section for a course offering in the upcoming term.

    Enforces:
      1. Offering must be active, in-window, and in faculty's department.
      2. max_sections cap — total active sections for this offering must be
         strictly less than courses.max_sections. Returns a clear error if
         the limit is already reached.
      3. One faculty per course section — each instructor may hold at most
         one section per offering.
      4. Section code uniqueness within the offering.
      5. Theory and lab room/slot collision checks.
    """
    # 1. Fetch offering, term, and course details (including max_sections)
    offering = query_one(
        """SELECT co.offering_id, co.term_id, co.theory_slot_id, co.lab_slot_id,
                  c.dept_id, c.course_code, c.max_sections,
                  t.registration_start_date, t.registration_end_date, t.start_date
             FROM course_offerings co
             JOIN courses c       ON co.course_id = c.course_id
             JOIN academic_terms t ON co.term_id   = t.term_id
             JOIN faculty f       ON f.faculty_id  = :fid
            WHERE co.offering_id = :oid
              AND co.is_active   = 'Y'
              AND c.dept_id      = f.dept_id
              AND TRUNC(SYSDATE) BETWEEN TRUNC(t.registration_start_date)
                                     AND TRUNC(t.registration_end_date)
              AND TRUNC(SYSDATE) < TRUNC(t.start_date)""",
        {"fid": user["id"], "oid": req.offering_id},
    )
    if not offering:
        raise HTTPException(
            status_code=400,
            detail="Invalid offering, or term registration window is not open, "
                   "or course is not in your department.",
        )

    # 2. max_sections cap check
    #    Count active sections for this offering and compare to the course cap.
    #    This is computed on-demand from the sections table — no cached counter
    #    is read, preserving 3NF (max_sections is on courses; the live count
    #    is derived via COUNT(*)).
    section_count_row = query_one(
        """SELECT COUNT(*) AS cnt
             FROM sections
            WHERE offering_id = :oid AND is_active = 'Y'""",
        {"oid": req.offering_id},
    )
    current_count = section_count_row["cnt"] if section_count_row else 0
    max_allowed   = offering["max_sections"]

    if current_count >= max_allowed:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Max sections exceeded: '{offering['course_code']}' allows at most "
                f"{max_allowed} section(s) per term. "
                f"{current_count} section(s) have already been floated."
            ),
        )

    # 3. One faculty per course section limit
    personal_limit = query_one(
        """SELECT COUNT(*) AS cnt FROM sections
            WHERE offering_id = :oid AND instructor_id = :fid AND is_active = 'Y'""",
        {"oid": req.offering_id, "fid": user["id"]},
    )
    if personal_limit and personal_limit["cnt"] > 0:
        raise HTTPException(
            status_code=400,
            detail="Limit Exceeded: You have already floated a section for this course.",
        )

    # 4. Section code uniqueness within the offering
    existing_code = query_one(
        """SELECT COUNT(*) AS cnt FROM sections
            WHERE offering_id = :oid AND section_code = :sc AND is_active = 'Y'""",
        {"oid": req.offering_id, "sc": req.section_code.strip().upper()},
    )
    if existing_code and existing_code["cnt"] > 0:
        raise HTTPException(
            status_code=400,
            detail=f"Section '{req.section_code.upper()}' already exists for this course.",
        )

    # 5. Unified room-slot collision check (Theory AND Lab)
    with get_connection() as conn:
        cursor = conn.cursor()

        # Theory room collision
        if req.theory_room:
            theory_collision = query_one(
                """SELECT c.course_code, s.section_code
                     FROM sections s
                     JOIN course_offerings co ON s.offering_id = co.offering_id
                     JOIN courses c           ON co.course_id = c.course_id
                    WHERE co.term_id = :tid AND co.theory_slot_id = :slot
                      AND s.theory_room = :room AND s.is_active = 'Y'""",
                {
                    "tid":  offering["term_id"],
                    "slot": offering["theory_slot_id"],
                    "room": req.theory_room.strip(),
                },
            )
            if theory_collision:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Theory Collision: Room {req.theory_room} is occupied by "
                        f"{theory_collision['course_code']} "
                        f"({theory_collision['section_code']})."
                    ),
                )

        # Lab room collision
        if req.lab_room and offering["lab_slot_id"]:
            lab_collision = query_one(
                """SELECT c.course_code, s.section_code
                     FROM sections s
                     JOIN course_offerings co ON s.offering_id = co.offering_id
                     JOIN courses c           ON co.course_id = c.course_id
                    WHERE co.term_id = :tid AND co.lab_slot_id = :slot
                      AND s.lab_room = :room AND s.is_active = 'Y'""",
                {
                    "tid":  offering["term_id"],
                    "slot": offering["lab_slot_id"],
                    "room": req.lab_room.strip(),
                },
            )
            if lab_collision:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        f"Lab Collision: Room {req.lab_room} is already booked for "
                        f"{lab_collision['course_code']} during its lab slot."
                    ),
                )

        # 6. Insert the section — all checks passed
        cursor.execute("SELECT section_seq.NEXTVAL FROM dual")
        new_section_id_val = cursor.fetchone()[0]

        cursor.execute(
            """INSERT INTO sections (
                   section_id, offering_id, section_code,
                   instructor_id, section_coordinator_id,
                   max_capacity, current_enrollment, waitlist_capacity, current_waitlist,
                   theory_room, lab_room,
                   total_theory_classes_planned, total_lab_classes_planned,
                   is_active, created_at
               ) VALUES (
                   :sid, :oid, :sc,
                   :fid, :fid,
                   :maxcap, 0, :waitcap, 0,
                   :troom, :lroom,
                   :tplan, :lplan,
                   'Y', SYSTIMESTAMP
               )""",
            {
                "sid":    new_section_id_val,
                "oid":    req.offering_id,
                "sc":     req.section_code.strip().upper(),
                "fid":    user["id"],
                "maxcap": req.max_capacity,
                "waitcap": req.waitlist_capacity,
                "troom":  req.theory_room,
                "lroom":  req.lab_room,
                "tplan":  req.total_theory_classes_planned,
                "lplan":  req.total_lab_classes_planned,
            },
        )
        conn.commit()

        return {
            "section_id":        int(new_section_id_val),
            "section_code":      req.section_code.strip().upper(),
            "sections_floated":  current_count + 1,
            "max_sections":      max_allowed,
            "message": (
                f"Section '{req.section_code.upper()}' floated successfully. "
                f"({current_count + 1}/{max_allowed} sections used for this course)."
            ),
        }


# ─────────────────────────────────────────────────────────────────────────────
# Students in a section
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/sections/{section_id}/students")
def get_section_students(section_id: int, user: dict = Depends(require_faculty)):
    _verify_section_owner(section_id, user["id"])
    return query_many(
        """SELECT s.student_id, s.roll_number,
                  s.first_name || ' ' || NVL(s.last_name, '') AS student_name,
                  s.email, s.current_semester,
                  r.registration_id, r.registration_status, r.waitlist_position,
                  r.attendance_warning_sent, r.attendance_locked
             FROM registrations r
             JOIN students s ON r.student_id = s.student_id
            WHERE r.section_id = :sid
            ORDER BY r.registration_status, s.roll_number""",
        {"sid": section_id},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Class Schedule Management (only for ACTIVE / current-term sections)
# ─────────────────────────────────────────────────────────────────────────────

class CreateSessionRequest(BaseModel):
    section_id:      int
    class_date:      str          # "YYYY-MM-DD"
    slot_id:         int
    class_type:      str          # "THEORY" | "LAB"
    topic:           Optional[str] = None
    room_number:     Optional[str] = None




@router.post("/sessions")
def create_session(req: CreateSessionRequest, user: dict = Depends(require_faculty)):
    _verify_section_owner(req.section_id, user["id"])

    # Only allow scheduling for the active (current) term, not upcoming
    term_check = query_one(
        """SELECT t.is_current FROM sections sec
             JOIN course_offerings co ON sec.offering_id = co.offering_id
             JOIN academic_terms t    ON co.term_id      = t.term_id
            WHERE sec.section_id = :sid""",
        {"sid": req.section_id},
    )
    lecture = query_one(
        """
        SELECT NVL(MAX(lecture_number), 0) + 1 AS next_lecture
        FROM class_schedule
        WHERE section_id = :sid
        AND class_type = :ctype
        AND is_cancelled = 'N'
        """,
        {
            "sid": req.section_id,
            "ctype": req.class_type
        },
    )

    next_lecture = lecture["next_lecture"] if lecture else 1
    if not term_check or term_check["is_current"] != "Y":
        raise HTTPException(
            status_code=400,
            detail="Class sessions can only be scheduled for the current (active) term.",
        )

    with get_connection() as conn:
        cursor = conn.cursor()
        p_schedule_id = cursor.var(oracledb.NUMBER)
        p_success     = cursor.var(oracledb.NUMBER)
        p_msg         = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                attendance_manager.create_class_session(
                    p_section_id     => :p_section_id,
                    p_class_date     => TO_DATE(:p_class_date, 'YYYY-MM-DD'),
                    p_slot_id        => :p_slot_id,
                    p_class_type     => :p_class_type,
                    p_lecture_number => :p_lecture_number,
                    p_topic          => :p_topic,
                    p_conducted_by   => :p_conducted_by,
                    p_room_number    => :p_room_number,
                    p_schedule_id    => :p_schedule_id,
                    p_success        => v_success,
                    p_message        => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_section_id":     req.section_id,
                "p_class_date":     req.class_date,
                "p_slot_id":        req.slot_id,
                "p_class_type":     req.class_type,
                "p_lecture_number": next_lecture,
                "p_topic":          req.topic,
                "p_conducted_by":   user["id"],
                "p_room_number":    req.room_number,
                "p_schedule_id":    p_schedule_id,
                "p_success":        p_success,
                "p_message":        p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {
            "schedule_id": int(p_schedule_id.getvalue() or 0),
            "message":     p_msg.getvalue(),
        }


class CancelSessionRequest(BaseModel):
    schedule_id: int
    reason:      str = ""


@router.post("/sessions/cancel")
def cancel_session(req: CancelSessionRequest, user: dict = Depends(require_faculty)):
    row = query_one(
        """SELECT cs.section_id FROM class_schedule cs
             JOIN sections sec ON cs.section_id = sec.section_id
            WHERE cs.schedule_id = :sch AND sec.instructor_id = :fid""",
        {"sch": req.schedule_id, "fid": user["id"]},
    )
    if not row:
        raise HTTPException(status_code=403, detail="Not your session or invalid ID")

    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_msg     = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                attendance_manager.cancel_class_session(
                    p_schedule_id  => :p_schedule_id,
                    p_reason       => :p_reason,
                    p_cancelled_by => :p_cancelled_by,
                    p_success      => v_success,
                    p_message      => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_schedule_id":  req.schedule_id,
                "p_reason":       req.reason,
                "p_cancelled_by": user["id"],
                "p_success":      p_success,
                "p_message":      p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {"message": p_msg.getvalue()}


@router.get("/sections/{section_id}/schedule")
def get_section_schedule(section_id: int, user: dict = Depends(require_faculty)):
    _verify_section_owner(section_id, user["id"])
    return query_many(
        """SELECT cs.schedule_id, cs.class_date, cs.class_type,
                  cs.lecture_number, cs.topic, cs.room_number,
                  cs.is_cancelled, cs.cancellation_reason,
                  cs.is_attendance_marked,
                  sl.slot_code,
                  sl.slot_id,
                  f.first_name || ' ' || NVL(f.last_name,'') AS conducted_by_name
             FROM class_schedule cs
             JOIN slots sl       ON cs.slot_id     = sl.slot_id
             LEFT JOIN faculty f ON cs.conducted_by = f.faculty_id
            WHERE cs.section_id = :sid
            ORDER BY cs.class_date DESC, cs.lecture_number""",
        {"sid": section_id},
    )


# ─────────────────────────────────────────────────────────────────────────────
# Attendance Management
# ─────────────────────────────────────────────────────────────────────────────

class MarkSingleRequest(BaseModel):
    student_id:  int
    schedule_id: int
    status:      str
    remarks:     Optional[str] = None


@router.post("/attendance/mark")
def mark_attendance(req: MarkSingleRequest, user: dict = Depends(require_faculty)):
    row = query_one(
        """SELECT cs.section_id FROM class_schedule cs
             JOIN sections sec ON cs.section_id = sec.section_id
            WHERE cs.schedule_id = :sch AND sec.instructor_id = :fid""",
        {"sch": req.schedule_id, "fid": user["id"]},
    )
    if not row:
        raise HTTPException(status_code=403, detail="Not your session")

    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_msg     = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                attendance_manager.mark_single_attendance(
                    p_student_id  => :p_student_id,
                    p_schedule_id => :p_schedule_id,
                    p_status      => :p_status,
                    p_marked_by   => :p_marked_by,
                    p_remarks     => :p_remarks,
                    p_success     => v_success,
                    p_message     => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_student_id":  req.student_id,
                "p_schedule_id": req.schedule_id,
                "p_status":      req.status,
                "p_marked_by":   user["id"],
                "p_remarks":     req.remarks,
                "p_success":     p_success,
                "p_message":     p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {"message": p_msg.getvalue()}


class BulkAttendanceRequest(BaseModel):
    schedule_id:     int
    attendance_data: str


@router.post("/attendance/bulk")
def mark_bulk(req: BulkAttendanceRequest, user: dict = Depends(require_faculty)):
    row = query_one(
        """SELECT cs.section_id FROM class_schedule cs
             JOIN sections sec ON cs.section_id = sec.section_id
            WHERE cs.schedule_id = :sch AND sec.instructor_id = :fid""",
        {"sch": req.schedule_id, "fid": user["id"]},
    )
    if not row:
        raise HTTPException(status_code=403, detail="Not your session")

    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_msg     = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                attendance_manager.mark_bulk_attendance(
                    p_schedule_id     => :p_schedule_id,
                    p_attendance_data => :p_attendance_data,
                    p_marked_by       => :p_marked_by,
                    p_success         => v_success,
                    p_message         => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_schedule_id":     req.schedule_id,
                "p_attendance_data": req.attendance_data,
                "p_marked_by":       user["id"],
                "p_success":         p_success,
                "p_message":         p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {"message": p_msg.getvalue()}


class UpdateAttendanceRequest(BaseModel):
    attendance_id: int
    new_status:    str
    remarks:       Optional[str] = None


@router.put("/attendance/update")
def update_attendance(req: UpdateAttendanceRequest, user: dict = Depends(require_faculty)):
    row = query_one(
        """SELECT a.attendance_id FROM attendance a
             JOIN class_schedule cs ON a.schedule_id = cs.schedule_id
             JOIN sections sec      ON cs.section_id = sec.section_id
            WHERE a.attendance_id = :aid AND sec.instructor_id = :fid""",
        {"aid": req.attendance_id, "fid": user["id"]},
    )
    if not row:
        raise HTTPException(status_code=403, detail="Not your attendance record")

    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_msg     = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            DECLARE
                v_success BOOLEAN;
            BEGIN
                attendance_manager.update_attendance(
                    p_attendance_id => :p_attendance_id,
                    p_new_status    => :p_new_status,
                    p_updated_by    => :p_updated_by,
                    p_remarks       => :p_remarks,
                    p_success       => v_success,
                    p_message       => :p_message
                );
                :p_success := CASE WHEN v_success THEN 1 ELSE 0 END;
            END;
            """,
            {
                "p_attendance_id": req.attendance_id,
                "p_new_status":    req.new_status,
                "p_updated_by":    user["id"],
                "p_remarks":       req.remarks,
                "p_success":       p_success,
                "p_message":       p_msg,
            },
        )
        conn.commit()
        if not int(p_success.getvalue() or 0):
            raise HTTPException(status_code=400, detail=p_msg.getvalue())
        return {"message": p_msg.getvalue()}


@router.get("/sections/{section_id}/attendance/{schedule_id}")
def get_schedule_attendance(
    section_id: int, schedule_id: int, user: dict = Depends(require_faculty)
):
    _verify_section_owner(section_id, user["id"])
    return query_many(
        """SELECT s.student_id, s.roll_number,
                  s.first_name || ' ' || NVL(s.last_name, '') AS student_name,
                  r.registration_id,
                  NVL(a.status, 'NOT_MARKED') AS status,
                  a.attendance_id, a.remarks
             FROM registrations r
             JOIN students s    ON r.student_id = s.student_id
             LEFT JOIN attendance a ON a.registration_id = r.registration_id
                                   AND a.schedule_id     = :sch
            WHERE r.section_id          = :sec
              AND r.registration_status IN ('REGISTERED', 'APPROVED')
            ORDER BY s.roll_number""",
        {"sec": section_id, "sch": schedule_id},
    )
