"""routers/auth.py — Login for students and faculty."""
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from db import query_one
from auth_utils import create_token

router = APIRouter()


class LoginRequest(BaseModel):
    username: str   # roll_number for students, employee_id for faculty
    password: str   # for demo: plain text compared; use hashed in prod
    role: str       # "student" | "faculty"


@router.post("/login")
def login(req: LoginRequest):
    if req.role == "student":
        row = query_one(
            """SELECT student_id, roll_number, first_name, last_name, email,
                      current_semester, is_active
                 FROM students
                WHERE roll_number = :u AND is_active = 'Y'""",
            {"u": req.username},
        )
        if not row:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        # Demo: password == roll_number (replace with bcrypt in prod)
        if req.password != req.username:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        token = create_token({
            "role": "student",
            "id": row["student_id"],
            "roll_number": row["roll_number"],
            "name": f"{row['first_name']} {row['last_name'] or ''}".strip(),
        })
        return {
            "access_token": token,
            "token_type": "bearer",
            "role": "student",
            "name": f"{row['first_name']} {row['last_name'] or ''}".strip(),
            "id": row["student_id"],
        }

    elif req.role == "faculty":
        row = query_one(
            """SELECT faculty_id, employee_id, first_name, last_name, email, is_active
                 FROM faculty
                WHERE employee_id = :u AND is_active = 'Y'""",
            {"u": req.username},
        )
        if not row:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        # Demo: password == employee_id
        if req.password != req.username:
            raise HTTPException(status_code=401, detail="Invalid credentials")
        token = create_token({
            "role": "faculty",
            "id": row["faculty_id"],
            "employee_id": row["employee_id"],
            "name": f"{row['first_name']} {row['last_name'] or ''}".strip(),
        })
        return {
            "access_token": token,
            "token_type": "bearer",
            "role": "faculty",
            "name": f"{row['first_name']} {row['last_name'] or ''}".strip(),
            "id": row["faculty_id"],
        }

    raise HTTPException(status_code=400, detail="role must be 'student' or 'faculty'")