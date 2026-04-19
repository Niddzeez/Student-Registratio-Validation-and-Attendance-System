"""routers/reports.py"""
from fastapi import APIRouter, Depends, HTTPException
from db import query_many, query_one
from auth_utils import require_faculty

router = APIRouter()


@router.get("/section/{section_id}/defaulters")
def get_defaulters(
    section_id: int,
    threshold: float = 75,
    user: dict = Depends(require_faculty),
):
    row = query_one(
        "SELECT instructor_id FROM sections WHERE section_id = :s",
        {"s": section_id},
    )
    if not row or row["instructor_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Not your section")

    return query_many(
        """WITH att_calc AS (
               SELECT
                   r.registration_id, r.student_id,
                   SUM(CASE WHEN cs.class_type='THEORY' AND cs.is_cancelled='N' THEN 1 ELSE 0 END) AS t_total,
                   SUM(CASE WHEN cs.class_type='LAB'    AND cs.is_cancelled='N' THEN 1 ELSE 0 END) AS l_total,
                   COUNT(CASE WHEN cs.class_type='THEORY' AND a.status IN ('P','L','E','OD') THEN 1 END) AS t_att,
                   COUNT(CASE WHEN cs.class_type='LAB'    AND a.status IN ('P','L','E','OD') THEN 1 END) AS l_att
                 FROM registrations r
                 LEFT JOIN attendance a       ON a.registration_id = r.registration_id
                 LEFT JOIN class_schedule cs  ON a.schedule_id     = cs.schedule_id
                WHERE r.section_id          = :sid
                  AND r.registration_status IN ('REGISTERED','APPROVED')
                GROUP BY r.registration_id, r.student_id
           )
           SELECT
               s.student_id, s.roll_number, s.email,
               s.first_name || ' ' || NVL(s.last_name,'') AS student_name,
               ROUND(NVL(ac.t_att,0)*100.0/NULLIF(ac.t_total,0),2)  AS theory_pct,
               ROUND(NVL(ac.l_att,0)*100.0/NULLIF(ac.l_total,0),2)  AS lab_pct,
               ROUND(
                   NVL(NVL(ac.t_att,0)*100.0/NULLIF(ac.t_total,0),0)*0.6
                   + NVL(NVL(ac.l_att,0)*100.0/NULLIF(ac.l_total,0),0)*0.4
               ,2) AS overall_pct
             FROM att_calc ac
             JOIN students s ON ac.student_id = s.student_id
            WHERE ROUND(
                      NVL(NVL(ac.t_att,0)*100.0/NULLIF(ac.t_total,0),0)*0.6
                      + NVL(NVL(ac.l_att,0)*100.0/NULLIF(ac.l_total,0),0)*0.4
                  ,2) < :thresh
            ORDER BY overall_pct""",
        {"sid": section_id, "thresh": threshold},
    )


@router.get("/section/{section_id}/full")
def get_full_report(section_id: int, user: dict = Depends(require_faculty)):
    row = query_one(
        "SELECT instructor_id FROM sections WHERE section_id = :s",
        {"s": section_id},
    )
    if not row or row["instructor_id"] != user["id"]:
        raise HTTPException(status_code=403, detail="Not your section")

    return query_many(
        """SELECT sco.student_name, sco.roll_number,
                  sco.theory_attendance, sco.lab_attendance, sco.overall_attendance,
                  sco.registration_status
             FROM student_course_overview sco
            WHERE sco.section_id = :sid
            ORDER BY sco.roll_number""",
        {"sid": section_id},
    )