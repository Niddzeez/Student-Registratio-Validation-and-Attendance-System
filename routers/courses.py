"""routers/courses.py"""
from fastapi import APIRouter, Depends
from db import query_many
from auth_utils import get_current_user

router = APIRouter()


@router.get("/")
def list_courses(user: dict = Depends(get_current_user)):
    return query_many(
        """SELECT c.course_id, c.course_code, c.course_name, c.credits,
                  c.course_type, c.has_lab, c.lecture_hours, c.tutorial_hours,
                  c.practical_hours, d.dept_name
             FROM courses c
             JOIN departments d ON c.dept_id = d.dept_id
            WHERE c.is_active = 'Y'
            ORDER BY c.course_code""",
        {},
    )