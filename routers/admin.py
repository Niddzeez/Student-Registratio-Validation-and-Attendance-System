"""
routers/admin.py — Admin-facing endpoints.

Admin capabilities:
  POST /api/admin/login                        — admin JWT login
  POST /api/admin/courses                      — create a new course (with max_sections)
  PATCH /api/admin/courses/{id}/max-sections   — update max_sections cap on an existing course
  POST /api/admin/faculty                      — register a new faculty member
  POST /api/admin/students                     — register a new student
  POST /api/admin/terms                        — create a new academic term
  PATCH /api/admin/terms/{id}/current          — set a term as current
  POST /api/admin/offerings                    — float a course offering for a term
  GET  /api/admin/students                     — list all students (with details)
  GET  /api/admin/students/{id}                — single student full profile
  GET  /api/admin/faculty                      — list all faculty (with details)
  GET  /api/admin/faculty/{id}                 — single faculty full profile
  PATCH /api/admin/students/{id}/status        — activate / deactivate
  PATCH /api/admin/faculty/{id}/status         — activate / deactivate
  GET  /api/admin/terms                        — list all terms
  GET  /api/admin/departments                  — lookup list
  GET  /api/admin/batches                      — lookup list
  GET  /api/admin/courses                      — lookup list (includes max_sections)
  GET  /api/admin/slots                        — lookup list

All mutable operations call admin_manager package procedures, following the
exact same anonymous-PL/SQL-block pattern used by students.py and faculty.py
(Oracle BOOLEAN OUT → NUMBER 1/0).
"""

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from typing import Optional
from db import query_many, query_one, get_connection
from auth_utils import create_token
import oracledb

router = APIRouter()


# ─────────────────────────────────────────────────────────────────────────────
# Auth dependency (mirrors require_student / require_faculty pattern)
# ─────────────────────────────────────────────────────────────────────────────

from fastapi import Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from auth_utils import decode_token

_bearer = HTTPBearer()


def require_admin(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer),
) -> dict:
    payload = decode_token(credentials.credentials)
    if payload.get("role") != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to administrators",
        )
    return payload


# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────

class AdminLoginRequest(BaseModel):
    username: str
    password: str


@router.post("/login")
def admin_login(req: AdminLoginRequest):
    """Authenticate admin via admin_manager.admin_login package function."""
    with get_connection() as conn:
        cursor = conn.cursor()
        p_result    = cursor.var(oracledb.NUMBER)
        p_admin_id  = cursor.var(oracledb.NUMBER)
        p_full_name = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                :p_result := admin_manager.admin_login(
                    p_username  => :p_username,
                    p_password  => :p_password,
                    p_admin_id  => :p_admin_id,
                    p_full_name => :p_full_name
                );
            END;
            """,
            {
                "p_username":  req.username,
                "p_password":  req.password,
                "p_admin_id":  p_admin_id,
                "p_full_name": p_full_name,
                "p_result":    p_result,
            },
        )
        conn.commit()

    if int(p_result.getvalue() or 0) != 1:
        raise HTTPException(status_code=401, detail="Invalid admin credentials")

    token = create_token({
        "role":      "admin",
        "id":        int(p_admin_id.getvalue()),
        "full_name": p_full_name.getvalue(),
    })
    return {
        "access_token": token,
        "token_type":   "bearer",
        "role":         "admin",
        "name":         p_full_name.getvalue(),
        "id":           int(p_admin_id.getvalue()),
    }


# ─────────────────────────────────────────────────────────────────────────────
# CREATE COURSE
# Admin creates a brand-new course with all metadata including max_sections.
# max_sections is the cap on how many sections faculty may float per term.
# ─────────────────────────────────────────────────────────────────────────────

class EligibilityRule(BaseModel):
    """
    One eligibility rule for a course.

    All filter fields are optional — NULL means "any".
    Examples:
      {"dept_id": 1, "min_semester": 3, "max_semester": 8}
        → CSE students from sem 3 onwards
      {"program_type": "UG"}
        → only UG students, any dept/semester
      {}
        → no restriction (equivalent to not providing eligibility at all)

    If no eligibility rules are supplied the course is open to everyone
    (check_eligibility returns TRUE when the table has zero rows for that course).
    """
    dept_id:      Optional[int] = None
    program_id:   Optional[int] = None
    program_type: Optional[str] = None   # "UG" or "PG" — resolved to program_ids at insert time
    min_semester: Optional[int] = None   # 1–8
    max_semester: Optional[int] = None   # 1–8; must be >= min_semester
    priority:     int           = 99     # 1 (highest) – 100 (lowest)


class PrerequisiteEntry(BaseModel):
    """A single prerequisite course link for a new course."""
    prerequisite_course_id: int
    is_mandatory: str = "Y"   # "Y" = hard prerequisite; "N" = recommended only


class CreateCourseRequest(BaseModel):
    course_code:      str
    course_name:      str
    dept_id:          int
    course_type:      str              # DC | DE | OC | HM | BS | ES | AU
    credits:          float
    lecture_hours:    int  = 0
    tutorial_hours:   int  = 0
    practical_hours:  int  = 0
    has_lab:          str  = "N"       # "Y" or "N"
    typical_semester: Optional[int] = None
    max_sections:     int  = 5         # admin-set cap on sections per term
    description:      Optional[str] = None
    # One or more eligibility rules.
    # Leave empty / omit → course is open to all students.
    eligibility_rules: list[EligibilityRule] = []
    # Zero or more prerequisite courses.
    # Leave empty / omit → course has no prerequisites.
    prerequisites: list[PrerequisiteEntry] = []


@router.post("/courses", status_code=201)
def create_course(req: CreateCourseRequest, user: dict = Depends(require_admin)):
    """
    Create a new course via admin_manager.create_course, then insert any
    eligibility rules and prerequisites.

    Eligibility rules live in course_eligibility (3NF-compliant separate entity).
    Prerequisites live in course_prerequisites (course_id → prerequisite_course_id).
    Neither is stored on the courses row itself, preserving 3NF.

    max_sections sets how many sections faculty may float per term.
    The actual count is always derived on-demand (no counter cached).
    """
    # ── basic field-level validation before hitting the DB ──────────────────
    for i, rule in enumerate(req.eligibility_rules):
        if rule.min_semester is not None and rule.max_semester is not None:
            if rule.min_semester > rule.max_semester:
                raise HTTPException(
                    status_code=400,
                    detail=f"eligibility_rules[{i}]: min_semester must be <= max_semester",
                )
        for sem_val, sem_name in [
            (rule.min_semester, "min_semester"),
            (rule.max_semester, "max_semester"),
        ]:
            if sem_val is not None and not (1 <= sem_val <= 8):
                raise HTTPException(
                    status_code=400,
                    detail=f"eligibility_rules[{i}]: {sem_name} must be between 1 and 8",
                )
        if not (1 <= rule.priority <= 100):
            raise HTTPException(
                status_code=400,
                detail=f"eligibility_rules[{i}]: priority must be between 1 and 100",
            )
        if rule.program_type is not None and rule.program_type not in ("UG", "PG"):
            raise HTTPException(
                status_code=400,
                detail=f"eligibility_rules[{i}]: program_type must be 'UG' or 'PG'",
            )

    for i, prereq in enumerate(req.prerequisites):
        if prereq.is_mandatory not in ("Y", "N"):
            raise HTTPException(
                status_code=400,
                detail=f"prerequisites[{i}]: is_mandatory must be 'Y' or 'N'",
            )

    with get_connection() as conn:
        cursor = conn.cursor()

        # ── Step 1: create the course ────────────────────────────────────────
        p_course_id = cursor.var(oracledb.NUMBER)
        p_success   = cursor.var(oracledb.NUMBER)
        p_message   = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.create_course(
                    p_course_code      => :p_course_code,
                    p_course_name      => :p_course_name,
                    p_dept_id          => :p_dept_id,
                    p_course_type      => :p_course_type,
                    p_credits          => :p_credits,
                    p_lecture_hours    => :p_lecture_hours,
                    p_tutorial_hours   => :p_tutorial_hours,
                    p_practical_hours  => :p_practical_hours,
                    p_has_lab          => :p_has_lab,
                    p_typical_semester => :p_typical_semester,
                    p_max_sections     => :p_max_sections,
                    p_description      => :p_description,
                    p_course_id        => :p_course_id,
                    p_success          => :p_success,
                    p_message          => :p_message
                );
            END;
            """,
            {
                "p_course_code":      req.course_code,
                "p_course_name":      req.course_name,
                "p_dept_id":          req.dept_id,
                "p_course_type":      req.course_type,
                "p_credits":          req.credits,
                "p_lecture_hours":    req.lecture_hours,
                "p_tutorial_hours":   req.tutorial_hours,
                "p_practical_hours":  req.practical_hours,
                "p_has_lab":          req.has_lab,
                "p_typical_semester": req.typical_semester,
                "p_max_sections":     req.max_sections,
                "p_description":      req.description,
                "p_course_id":        p_course_id,
                "p_success":          p_success,
                "p_message":          p_message,
            },
        )

        if int(p_success.getvalue() or 0) != 1:
            conn.rollback()
            raise HTTPException(status_code=400, detail=p_message.getvalue())

        new_course_id = int(p_course_id.getvalue())

        # ── Step 2: insert eligibility rules (if any) ────────────────────────
        # If program_type is supplied instead of program_id, resolve all matching
        # program_ids from the programs table and create one rule per program.
        inserted_rules: list[dict] = []
        for rule in req.eligibility_rules:
            # Resolve program_type → list of program_ids (or [None] if no type filter)
            if rule.program_type:
                rows = cursor.execute(
                    "SELECT program_id FROM programs WHERE program_type = :pt",
                    {"pt": rule.program_type},
                ).fetchall()
                prog_ids = [r[0] for r in rows] if rows else [None]
            else:
                prog_ids = [rule.program_id]  # may be None → any program

            for prog_id in prog_ids:
                er_success = cursor.var(oracledb.NUMBER)
                er_message = cursor.var(oracledb.STRING)
                cursor.execute(
                    """
                    BEGIN
                        admin_manager.add_course_eligibility_rule(
                            p_course_id    => :p_course_id,
                            p_dept_id      => :p_dept_id,
                            p_program_id   => :p_program_id,
                            p_min_semester => :p_min_semester,
                            p_max_semester => :p_max_semester,
                            p_priority     => :p_priority,
                            p_success      => :p_success,
                            p_message      => :p_message
                        );
                    END;
                    """,
                    {
                        "p_course_id":    new_course_id,
                        "p_dept_id":      rule.dept_id,
                        "p_program_id":   prog_id,
                        "p_min_semester": rule.min_semester,
                        "p_max_semester": rule.max_semester,
                        "p_priority":     rule.priority,
                        "p_success":      er_success,
                        "p_message":      er_message,
                    },
                )
                if int(er_success.getvalue() or 0) != 1:
                    conn.rollback()
                    raise HTTPException(
                        status_code=400,
                        detail=f"Eligibility rule error: {er_message.getvalue()}",
                    )
                inserted_rules.append({
                    "dept_id":      rule.dept_id,
                    "program_id":   prog_id,
                    "program_type": rule.program_type,
                    "min_semester": rule.min_semester,
                    "max_semester": rule.max_semester,
                    "priority":     rule.priority,
                })

        # ── Step 3: insert prerequisites (if any) ────────────────────────────
        inserted_prereqs: list[dict] = []
        for prereq in req.prerequisites:
            # Guard: cannot link the new course as its own prerequisite
            if prereq.prerequisite_course_id == new_course_id:
                conn.rollback()
                raise HTTPException(
                    status_code=400,
                    detail="A course cannot be its own prerequisite.",
                )
            cursor.execute(
                """
                INSERT INTO course_prerequisites
                    (course_id, prerequisite_course_id, is_mandatory)
                VALUES (:cid, :pid, :mand)
                """,
                {
                    "cid":  new_course_id,
                    "pid":  prereq.prerequisite_course_id,
                    "mand": prereq.is_mandatory,
                },
            )
            inserted_prereqs.append({
                "prerequisite_course_id": prereq.prerequisite_course_id,
                "is_mandatory":           prereq.is_mandatory,
            })

        conn.commit()

    return {
        "course_id":         new_course_id,
        "max_sections":      req.max_sections,
        "eligibility_rules": inserted_rules,
        "open_to_all":       len(inserted_rules) == 0,
        "prerequisites":     inserted_prereqs,
        "message":           p_message.getvalue(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# UPDATE max_sections ON AN EXISTING COURSE
# ─────────────────────────────────────────────────────────────────────────────

class UpdateMaxSectionsRequest(BaseModel):
    max_sections: int


@router.patch("/courses/{course_id}/max-sections")
def update_max_sections(
    course_id: int,
    req: UpdateMaxSectionsRequest,
    user: dict = Depends(require_admin),
):
    """
    Update the max_sections cap on an existing course.
    Cannot be lowered below the highest active section count in any term
    (the procedure enforces this).
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.update_course_max_sections(
                    p_course_id    => :p_course_id,
                    p_max_sections => :p_max_sections,
                    p_success      => :p_success,
                    p_message      => :p_message
                );
            END;
            """,
            {
                "p_course_id":    course_id,
                "p_max_sections": req.max_sections,
                "p_success":      p_success,
                "p_message":      p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}


# ─────────────────────────────────────────────────────────────────────────────
# COURSE ELIGIBILITY MANAGEMENT
# Eligibility rules live in the course_eligibility table (separate 3NF entity).
# course_id is NOT stored redundantly on the courses row.
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/courses/{course_id}/eligibility")
def get_course_eligibility(course_id: int, user: dict = Depends(require_admin)):
    """
    Return all eligibility rules for a course.
    An empty list means the course is open to all students.
    """
    rows = query_many(
        """SELECT ce.eligibility_id, ce.course_id,
                  ce.dept_id,    d.dept_code,    d.dept_name,
                  ce.program_id, p.program_code, p.program_name,
                  ce.min_semester, ce.max_semester, ce.priority,
                  ce.created_at
             FROM course_eligibility ce
             LEFT JOIN departments d ON ce.dept_id    = d.dept_id
             LEFT JOIN programs    p ON ce.program_id = p.program_id
            WHERE ce.course_id = :cid
            ORDER BY ce.priority, ce.eligibility_id""",
        {"cid": course_id},
    )
    return {
        "course_id":        course_id,
        "open_to_all":      len(rows) == 0,
        "eligibility_rules": rows,
    }


@router.post("/courses/{course_id}/eligibility", status_code=201)
def add_course_eligibility(
    course_id: int,
    rule: EligibilityRule,
    user: dict = Depends(require_admin),
):
    """
    Append a single eligibility rule to an existing course.
    Use this to restrict who can register — by dept, program, and/or semester range.
    """
    if rule.min_semester is not None and rule.max_semester is not None:
        if rule.min_semester > rule.max_semester:
            raise HTTPException(
                status_code=400,
                detail="min_semester must be <= max_semester",
            )
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.add_course_eligibility_rule(
                    p_course_id    => :p_course_id,
                    p_dept_id      => :p_dept_id,
                    p_program_id   => :p_program_id,
                    p_min_semester => :p_min_semester,
                    p_max_semester => :p_max_semester,
                    p_priority     => :p_priority,
                    p_success      => :p_success,
                    p_message      => :p_message
                );
            END;
            """,
            {
                "p_course_id":    course_id,
                "p_dept_id":      rule.dept_id,
                "p_program_id":   rule.program_id,
                "p_min_semester": rule.min_semester,
                "p_max_semester": rule.max_semester,
                "p_priority":     rule.priority,
                "p_success":      p_success,
                "p_message":      p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}


@router.delete("/courses/{course_id}/eligibility/{eligibility_id}")
def delete_course_eligibility(
    course_id:      int,
    eligibility_id: int,
    user: dict = Depends(require_admin),
):
    """
    Remove a single eligibility rule.
    If this was the last rule the course becomes open to all students.
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.delete_course_eligibility_rule(
                    p_eligibility_id => :p_eligibility_id,
                    p_course_id      => :p_course_id,
                    p_success        => :p_success,
                    p_message        => :p_message
                );
            END;
            """,
            {
                "p_eligibility_id": eligibility_id,
                "p_course_id":      course_id,
                "p_success":        p_success,
                "p_message":        p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}



# ─────────────────────────────────────────────────────────────────────────────
# COURSE PREREQUISITES MANAGEMENT
# Prerequisites live in course_prerequisites (course_id, prerequisite_course_id,
# is_mandatory).  They are a separate 3NF entity — not stored on courses row.
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/courses/{course_id}/prerequisites")
def get_course_prerequisites(course_id: int, user: dict = Depends(require_admin)):
    """
    Return all prerequisites for a course.
    An empty list means the course has no entry requirements.
    """
    rows = query_many(
        """SELECT cp.prerequisite_course_id,
                  c.course_code, c.course_name, c.credits,
                  cp.is_mandatory, cp.created_at
             FROM course_prerequisites cp
             JOIN courses c ON cp.prerequisite_course_id = c.course_id
            WHERE cp.course_id = :cid
            ORDER BY c.course_code""",
        {"cid": course_id},
    )
    return {
        "course_id":     course_id,
        "prerequisites": rows,
    }


@router.post("/courses/{course_id}/prerequisites", status_code=201)
def add_course_prerequisite(
    course_id: int,
    prereq: PrerequisiteEntry,
    user: dict = Depends(require_admin),
):
    """
    Link a prerequisite to an existing course.
    is_mandatory='Y' → student must have passed it; 'N' → recommended only.
    """
    if prereq.prerequisite_course_id == course_id:
        raise HTTPException(status_code=400, detail="A course cannot be its own prerequisite.")
    if prereq.is_mandatory not in ("Y", "N"):
        raise HTTPException(status_code=400, detail="is_mandatory must be 'Y' or 'N'.")
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(
                """INSERT INTO course_prerequisites
                       (course_id, prerequisite_course_id, is_mandatory)
                   VALUES (:cid, :pid, :mand)""",
                {"cid": course_id, "pid": prereq.prerequisite_course_id, "mand": prereq.is_mandatory},
            )
            conn.commit()
        except Exception as exc:
            conn.rollback()
            raise HTTPException(status_code=400, detail=str(exc))
    return {"message": "Prerequisite added.", "prerequisite_course_id": prereq.prerequisite_course_id}


@router.delete("/courses/{course_id}/prerequisites/{prereq_course_id}")
def delete_course_prerequisite(
    course_id:       int,
    prereq_course_id: int,
    user: dict = Depends(require_admin),
):
    """Remove a prerequisite link from a course."""
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(
            """DELETE FROM course_prerequisites
                WHERE course_id = :cid AND prerequisite_course_id = :pid""",
            {"cid": course_id, "pid": prereq_course_id},
        )
        if cursor.rowcount == 0:
            conn.rollback()
            raise HTTPException(status_code=404, detail="Prerequisite not found.")
        conn.commit()
    return {"message": "Prerequisite removed."}


# ─────────────────────────────────────────────────────────────────────────────
# REGISTER FACULTY
# ─────────────────────────────────────────────────────────────────────────────

class RegisterFacultyRequest(BaseModel):
    employee_id:    str
    first_name:     str
    last_name:      Optional[str] = None
    email:          str
    phone:          Optional[str] = None
    dept_id:        int
    designation:    Optional[str] = None
    specialization: Optional[str] = None


@router.post("/faculty", status_code=201)
def register_faculty(req: RegisterFacultyRequest, user: dict = Depends(require_admin)):
    """Register a new faculty member via admin_manager.register_faculty."""
    with get_connection() as conn:
        cursor = conn.cursor()
        p_faculty_id = cursor.var(oracledb.NUMBER)
        p_success    = cursor.var(oracledb.NUMBER)
        p_message    = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.register_faculty(
                    p_employee_id    => :p_employee_id,
                    p_first_name     => :p_first_name,
                    p_last_name      => :p_last_name,
                    p_email          => :p_email,
                    p_phone          => :p_phone,
                    p_dept_id        => :p_dept_id,
                    p_designation    => :p_designation,
                    p_specialization => :p_specialization,
                    p_faculty_id     => :p_faculty_id,
                    p_success        => :p_success,
                    p_message        => :p_message
                );
            END;
            """,
            {
                "p_employee_id":    req.employee_id,
                "p_first_name":     req.first_name,
                "p_last_name":      req.last_name,
                "p_email":          req.email,
                "p_phone":          req.phone,
                "p_dept_id":        req.dept_id,
                "p_designation":    req.designation,
                "p_specialization": req.specialization,
                "p_faculty_id":     p_faculty_id,
                "p_success":        p_success,
                "p_message":        p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())

    return {
        "faculty_id": int(p_faculty_id.getvalue()),
        "message":    p_message.getvalue(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# REGISTER STUDENT
# ─────────────────────────────────────────────────────────────────────────────

class RegisterStudentRequest(BaseModel):
    roll_number:      str
    first_name:       str
    last_name:        Optional[str] = None
    email:            str
    phone:            Optional[str] = None
    batch_id:         int
    current_semester: int = 1
    date_of_birth:    Optional[str] = None   # "YYYY-MM-DD"


@router.post("/students", status_code=201)
def register_student(req: RegisterStudentRequest, user: dict = Depends(require_admin)):
    """Register a new student via admin_manager.register_student."""
    from datetime import date as dt_date
    dob = None
    if req.date_of_birth:
        try:
            dob = dt_date.fromisoformat(req.date_of_birth)
        except ValueError:
            raise HTTPException(status_code=400, detail="date_of_birth must be YYYY-MM-DD")

    with get_connection() as conn:
        cursor = conn.cursor()
        p_student_id = cursor.var(oracledb.NUMBER)
        p_success    = cursor.var(oracledb.NUMBER)
        p_message    = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.register_student(
                    p_roll_number      => :p_roll_number,
                    p_first_name       => :p_first_name,
                    p_last_name        => :p_last_name,
                    p_email            => :p_email,
                    p_phone            => :p_phone,
                    p_batch_id         => :p_batch_id,
                    p_current_semester => :p_current_semester,
                    p_date_of_birth    => TO_DATE(:p_dob, 'YYYY-MM-DD'),
                    p_student_id       => :p_student_id,
                    p_success          => :p_success,
                    p_message          => :p_message
                );
            END;
            """,
            {
                "p_roll_number":      req.roll_number,
                "p_first_name":       req.first_name,
                "p_last_name":        req.last_name,
                "p_email":            req.email,
                "p_phone":            req.phone,
                "p_batch_id":         req.batch_id,
                "p_current_semester": req.current_semester,
                "p_dob":              req.date_of_birth,
                "p_student_id":       p_student_id,
                "p_success":          p_success,
                "p_message":          p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())

    return {
        "student_id": int(p_student_id.getvalue()),
        "message":    p_message.getvalue(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# FLOAT COURSE OFFERING
# ─────────────────────────────────────────────────────────────────────────────

class FloatOfferingRequest(BaseModel):
    course_id:      int
    term_id:        int
    theory_slot_id: int
    lab_slot_id:    Optional[int] = None


@router.post("/offerings", status_code=201)
def float_offering(req: FloatOfferingRequest, user: dict = Depends(require_admin)):
    """Float a course offering for an upcoming term via admin_manager.float_course_offering."""
    with get_connection() as conn:
        cursor = conn.cursor()
        p_offering_id = cursor.var(oracledb.NUMBER)
        p_success     = cursor.var(oracledb.NUMBER)
        p_message     = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.float_course_offering(
                    p_course_id      => :p_course_id,
                    p_term_id        => :p_term_id,
                    p_theory_slot_id => :p_theory_slot_id,
                    p_lab_slot_id    => :p_lab_slot_id,
                    p_offering_id    => :p_offering_id,
                    p_success        => :p_success,
                    p_message        => :p_message
                );
            END;
            """,
            {
                "p_course_id":      req.course_id,
                "p_term_id":        req.term_id,
                "p_theory_slot_id": req.theory_slot_id,
                "p_lab_slot_id":    req.lab_slot_id,
                "p_offering_id":    p_offering_id,
                "p_success":        p_success,
                "p_message":        p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())

    return {
        "offering_id": int(p_offering_id.getvalue()),
        "message":     p_message.getvalue(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# ACADEMIC TERM MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────

class CreateTermRequest(BaseModel):
    term_code:               str
    term_name:               str
    academic_year:           str
    term_type:               str          # ODD | EVEN | SUMMER
    start_date:              str          # YYYY-MM-DD
    end_date:                str
    registration_start_date: str
    registration_end_date:   str


@router.post("/terms", status_code=201)
def create_term(req: CreateTermRequest, user: dict = Depends(require_admin)):
    """Create a new academic term via admin_manager.create_academic_term."""
    with get_connection() as conn:
        cursor = conn.cursor()
        p_term_id = cursor.var(oracledb.NUMBER)
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.create_academic_term(
                    p_term_code               => :p_term_code,
                    p_term_name               => :p_term_name,
                    p_academic_year           => :p_academic_year,
                    p_term_type               => :p_term_type,
                    p_start_date              => TO_DATE(:p_start_date, 'YYYY-MM-DD'),
                    p_end_date                => TO_DATE(:p_end_date, 'YYYY-MM-DD'),
                    p_registration_start_date => TO_DATE(:p_reg_start, 'YYYY-MM-DD'),
                    p_registration_end_date   => TO_DATE(:p_reg_end,   'YYYY-MM-DD'),
                    p_term_id                 => :p_term_id,
                    p_success                 => :p_success,
                    p_message                 => :p_message
                );
            END;
            """,
            {
                "p_term_code":    req.term_code,
                "p_term_name":    req.term_name,
                "p_academic_year":req.academic_year,
                "p_term_type":    req.term_type,
                "p_start_date":   req.start_date,
                "p_end_date":     req.end_date,
                "p_reg_start":    req.registration_start_date,
                "p_reg_end":      req.registration_end_date,
                "p_term_id":      p_term_id,
                "p_success":      p_success,
                "p_message":      p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())

    return {
        "term_id": int(p_term_id.getvalue()),
        "message": p_message.getvalue(),
    }


@router.patch("/terms/{term_id}/current")
def set_current_term(term_id: int, user: dict = Depends(require_admin)):
    """Mark a term as the current term via admin_manager.set_current_term."""
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.set_current_term(
                    p_term_id => :p_term_id,
                    p_success => :p_success,
                    p_message => :p_message
                );
            END;
            """,
            {
                "p_term_id": term_id,
                "p_success": p_success,
                "p_message": p_message,
            },
        )
        conn.commit()

    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}


@router.get("/terms")
def list_terms(user: dict = Depends(require_admin)):
    return query_many(
        """SELECT term_id, term_code, term_name, academic_year, term_type,
                  start_date, end_date,
                  registration_start_date, registration_end_date,
                  is_current,
                  CASE
                      WHEN is_current = 'Y'                                              THEN 'ACTIVE'
                      WHEN TRUNC(SYSDATE) < TRUNC(start_date)
                       AND TRUNC(SYSDATE) BETWEEN TRUNC(registration_start_date)
                                              AND TRUNC(registration_end_date)           THEN 'REG_OPEN'
                      WHEN TRUNC(SYSDATE) < TRUNC(start_date)                            THEN 'UPCOMING'
                      ELSE 'PAST'
                  END AS term_status
             FROM academic_terms
            ORDER BY term_id DESC""",
        {},
    )


# ─────────────────────────────────────────────────────────────────────────────
# VIEW ALL STUDENTS  (full detail)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/students")
def list_students(user: dict = Depends(require_admin)):
    return query_many(
        """SELECT s.student_id, s.roll_number,
                  s.first_name, s.last_name,
                  s.first_name || ' ' || NVL(s.last_name,'') AS full_name,
                  s.email, s.phone, s.current_semester,
                  s.date_of_birth, s.enrollment_date, s.is_active,
                  s.created_at,
                  b.batch_id, b.batch_code, b.year_of_admission,
                  p.program_id, p.program_code, p.program_name, p.program_type,
                  d.dept_id, d.dept_code, d.dept_name,
                  -- Active enrollments count (derived, not cached — 3NF)
                  (SELECT COUNT(*) FROM registrations r
                    WHERE r.student_id = s.student_id
                      AND r.registration_status IN ('REGISTERED','APPROVED')) AS active_enrollments
             FROM students s
             JOIN batches b    ON s.batch_id   = b.batch_id
             JOIN programs p   ON b.program_id = p.program_id
             JOIN departments d ON p.dept_id   = d.dept_id
            ORDER BY s.roll_number""",
        {},
    )


@router.get("/students/{student_id}")
def get_student(student_id: int, user: dict = Depends(require_admin)):
    row = query_one(
        """SELECT s.student_id, s.roll_number,
                  s.first_name, s.last_name,
                  s.first_name || ' ' || NVL(s.last_name,'') AS full_name,
                  s.email, s.phone, s.current_semester,
                  s.date_of_birth, s.enrollment_date, s.is_active, s.created_at,
                  b.batch_id, b.batch_code, b.year_of_admission,
                  p.program_id, p.program_code, p.program_name, p.program_type,
                  d.dept_id, d.dept_code, d.dept_name
             FROM students s
             JOIN batches b    ON s.batch_id   = b.batch_id
             JOIN programs p   ON b.program_id = p.program_id
             JOIN departments d ON p.dept_id   = d.dept_id
            WHERE s.student_id = :sid""",
        {"sid": student_id},
    )
    if not row:
        raise HTTPException(status_code=404, detail="Student not found")

    history = query_many(
        """SELECT r.registration_id, r.registration_status,
                  r.registration_date, r.approved_date, r.waitlist_position,
                  c.course_code, c.course_name, c.credits,
                  sec.section_code,
                  t.term_name, t.academic_year,
                  f.first_name || ' ' || NVL(f.last_name,'') AS instructor
             FROM registrations r
             JOIN sections sec        ON r.section_id    = sec.section_id
             JOIN course_offerings co ON sec.offering_id = co.offering_id
             JOIN courses c           ON co.course_id    = c.course_id
             JOIN academic_terms t    ON r.term_id       = t.term_id
             JOIN faculty f           ON sec.instructor_id = f.faculty_id
            WHERE r.student_id = :sid
            ORDER BY t.term_id DESC, c.course_name""",
        {"sid": student_id},
    )
    row["registration_history"] = history
    return row


@router.patch("/students/{student_id}/status")
def update_student_status(
    student_id: int,
    payload: dict,
    user: dict = Depends(require_admin),
):
    is_active = payload.get("is_active", "Y")
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.update_student_status(
                    p_student_id => :p_student_id,
                    p_is_active  => :p_is_active,
                    p_success    => :p_success,
                    p_message    => :p_message
                );
            END;
            """,
            {
                "p_student_id": student_id,
                "p_is_active":  is_active,
                "p_success":    p_success,
                "p_message":    p_message,
            },
        )
        conn.commit()
    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}


# ─────────────────────────────────────────────────────────────────────────────
# VIEW ALL FACULTY  (full detail)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/faculty")
def list_faculty(user: dict = Depends(require_admin)):
    return query_many(
        """SELECT f.faculty_id, f.employee_id,
                  f.first_name, f.last_name,
                  f.first_name || ' ' || NVL(f.last_name,'') AS full_name,
                  f.email, f.phone, f.designation, f.specialization,
                  f.is_active, f.created_at,
                  d.dept_id, d.dept_code, d.dept_name,
                  -- Current active sections count (derived — 3NF)
                  (SELECT COUNT(*) FROM sections sec
                     JOIN course_offerings co ON sec.offering_id = co.offering_id
                     JOIN academic_terms t    ON co.term_id      = t.term_id
                    WHERE sec.instructor_id = f.faculty_id
                      AND sec.is_active = 'Y'
                      AND (t.is_current = 'Y' OR t.start_date > SYSDATE)) AS active_sections
             FROM faculty f
             JOIN departments d ON f.dept_id = d.dept_id
            ORDER BY f.employee_id""",
        {},
    )


@router.get("/faculty/{faculty_id}")
def get_faculty(faculty_id: int, user: dict = Depends(require_admin)):
    row = query_one(
        """SELECT f.faculty_id, f.employee_id,
                  f.first_name, f.last_name,
                  f.first_name || ' ' || NVL(f.last_name,'') AS full_name,
                  f.email, f.phone, f.designation, f.specialization,
                  f.is_active, f.created_at,
                  d.dept_id, d.dept_code, d.dept_name
             FROM faculty f
             JOIN departments d ON f.dept_id = d.dept_id
            WHERE f.faculty_id = :fid""",
        {"fid": faculty_id},
    )
    if not row:
        raise HTTPException(status_code=404, detail="Faculty not found")

    sections = query_many(
        """SELECT sec.section_id, sec.section_code,
                  sec.max_capacity, sec.current_enrollment,
                  c.course_code, c.course_name, c.max_sections,
                  t.term_name, t.academic_year, t.is_current,
                  -- How many sections exist for this offering
                  (SELECT COUNT(*) FROM sections s2
                    WHERE s2.offering_id = sec.offering_id AND s2.is_active='Y'
                  ) AS offering_section_count
             FROM sections sec
             JOIN course_offerings co ON sec.offering_id = co.offering_id
             JOIN courses c           ON co.course_id    = c.course_id
             JOIN academic_terms t    ON co.term_id      = t.term_id
            WHERE sec.instructor_id = :fid AND sec.is_active = 'Y'
            ORDER BY t.term_id DESC, c.course_name""",
        {"fid": faculty_id},
    )
    row["sections"] = sections
    return row


@router.patch("/faculty/{faculty_id}/status")
def update_faculty_status(
    faculty_id: int,
    payload: dict,
    user: dict = Depends(require_admin),
):
    is_active = payload.get("is_active", "Y")
    with get_connection() as conn:
        cursor = conn.cursor()
        p_success = cursor.var(oracledb.NUMBER)
        p_message = cursor.var(oracledb.STRING)
        cursor.execute(
            """
            BEGIN
                admin_manager.update_faculty_status(
                    p_faculty_id => :p_faculty_id,
                    p_is_active  => :p_is_active,
                    p_success    => :p_success,
                    p_message    => :p_message
                );
            END;
            """,
            {
                "p_faculty_id": faculty_id,
                "p_is_active":  is_active,
                "p_success":    p_success,
                "p_message":    p_message,
            },
        )
        conn.commit()
    if int(p_success.getvalue() or 0) != 1:
        raise HTTPException(status_code=400, detail=p_message.getvalue())
    return {"message": p_message.getvalue()}


# ─────────────────────────────────────────────────────────────────────────────
# LOOKUP ENDPOINTS  (for form dropdowns in the admin UI)
# ─────────────────────────────────────────────────────────────────────────────

@router.get("/departments")
def list_departments(user: dict = Depends(require_admin)):
    return query_many(
        "SELECT dept_id, dept_code, dept_name, total_semesters FROM departments ORDER BY dept_code",
        {},
    )


@router.get("/programs")
def list_programs(user: dict = Depends(require_admin)):
    """Lookup list for eligibility rule program dropdowns."""
    return query_many(
        """SELECT p.program_id, p.program_code, p.program_name, p.program_type,
                  d.dept_id, d.dept_code, d.dept_name
             FROM programs p
             JOIN departments d ON p.dept_id = d.dept_id
            ORDER BY p.program_code""",
        {},
    )


@router.get("/batches")
def list_batches(user: dict = Depends(require_admin)):
    return query_many(
        """SELECT b.batch_id, b.batch_code, b.year_of_admission, b.is_active,
                  p.program_name, p.program_type,
                  d.dept_name
             FROM batches b
             JOIN programs p   ON b.program_id = p.program_id
             JOIN departments d ON p.dept_id   = d.dept_id
            ORDER BY b.batch_id""",
        {},
    )


@router.get("/courses")
def list_courses(user: dict = Depends(require_admin)):
    """
    List all courses with max_sections and a derived current_section_count
    so the admin can see headroom per course at a glance.
    current_section_count is computed on-demand across all active terms (3NF).
    """
    return query_many(
        """SELECT c.course_id, c.course_code, c.course_name, c.credits,
                  c.course_type, c.has_lab, c.typical_semester, c.is_active,
                  c.max_sections,
                  c.lecture_hours, c.tutorial_hours, c.practical_hours,
                  d.dept_id, d.dept_code, d.dept_name,
                  -- Max active sections in any single term (derived — 3NF)
                  NVL((
                      SELECT MAX(term_cnt)
                        FROM (
                            SELECT co2.term_id, COUNT(*) AS term_cnt
                              FROM sections s2
                              JOIN course_offerings co2 ON s2.offering_id = co2.offering_id
                             WHERE co2.course_id = c.course_id
                               AND s2.is_active  = 'Y'
                             GROUP BY co2.term_id
                        )
                  ), 0) AS max_active_sections_in_any_term
             FROM courses c
             JOIN departments d ON c.dept_id = d.dept_id
            ORDER BY c.course_code""",
        {},
    )


@router.get("/slots")
def list_slots(user: dict = Depends(require_admin)):
    return query_many(
        "SELECT slot_id, slot_code, slot_type, is_active FROM slots WHERE is_active='Y' ORDER BY slot_code",
        {},
    )


@router.get("/offerings")
def list_offerings(user: dict = Depends(require_admin)):
    """All current + upcoming term offerings for admin overview, including section cap info."""
    return query_many(
        """SELECT co.offering_id, co.is_active,
                  c.course_id, c.course_code, c.course_name, c.credits,
                  c.max_sections,
                  t.term_id, t.term_name, t.academic_year, t.is_current,
                  sl.slot_code  AS theory_slot,
                  ls.slot_code  AS lab_slot,
                  -- Derived counts (3NF — no cached counters)
                  (SELECT COUNT(*) FROM sections sec
                    WHERE sec.offering_id = co.offering_id AND sec.is_active='Y') AS section_count,
                  GREATEST(c.max_sections - (
                      SELECT COUNT(*) FROM sections sec
                       WHERE sec.offering_id = co.offering_id AND sec.is_active='Y'
                  ), 0) AS sections_remaining,
                  (SELECT NVL(SUM(sec.current_enrollment),0) FROM sections sec
                    WHERE sec.offering_id = co.offering_id AND sec.is_active='Y') AS total_enrolled
             FROM course_offerings co
             JOIN courses c       ON co.course_id = c.course_id
             JOIN academic_terms t ON co.term_id  = t.term_id
             JOIN slots sl        ON co.theory_slot_id = sl.slot_id
             LEFT JOIN slots ls   ON co.lab_slot_id    = ls.slot_id
            WHERE t.is_current = 'Y' OR t.start_date > SYSDATE
            ORDER BY t.term_id DESC, c.course_code""",
        {},
    )