"""routers/attendance.py

BUGS FIXED vs previous version:
1. t_total / l_total calculation was joining class_schedule THROUGH the
   attendance table (LEFT JOIN attendance ON ... LEFT JOIN class_schedule ON
   a.schedule_id). This meant sessions with zero attendance rows contributed
   0 to the total instead of 1 — artificially inflating percentages toward
   100 % when few rows existed.

   Fix: join class_schedule directly on section_id (as the master) and
   LEFT JOIN attendance on (registration_id, schedule_id), exactly matching
   the pattern used in reports.py and the Oracle views.
"""
from fastapi import APIRouter, Depends
from db import query_many
from auth_utils import get_current_user

router = APIRouter()


@router.get("/section/{section_id}/summary")
def section_attendance_summary(section_id: int, user: dict = Depends(get_current_user)):
    return query_many(
        """WITH att_calc AS (
               SELECT
                   r.registration_id,
                   r.student_id,
                   -- TOTAL: count from class_schedule directly (not via attendance)
                   SUM(CASE WHEN cs.class_type = 'THEORY' AND cs.is_cancelled = 'N'
                            THEN 1 ELSE 0 END) AS t_total,
                   SUM(CASE WHEN cs.class_type = 'LAB'    AND cs.is_cancelled = 'N'
                            THEN 1 ELSE 0 END) AS l_total,
                   -- ATTENDED: only where an attendance row with a present-status exists
                   COUNT(CASE WHEN cs.class_type = 'THEORY'
                               AND a.status IN ('P','L','E','OD') THEN 1 END) AS t_att,
                   COUNT(CASE WHEN cs.class_type = 'LAB'
                               AND a.status IN ('P','L','E','OD') THEN 1 END) AS l_att
                 FROM registrations r
                 -- master: every scheduled (non-cancelled) class for the section
                 LEFT JOIN class_schedule cs ON cs.section_id = r.section_id
                 -- left: attendance rows for this registration + class
                 LEFT JOIN attendance a
                        ON a.registration_id = r.registration_id
                       AND a.schedule_id     = cs.schedule_id
                WHERE r.section_id          = :sid
                  AND r.registration_status IN ('REGISTERED','APPROVED')
                GROUP BY r.registration_id, r.student_id
           )
           SELECT
               s.student_id,
               s.roll_number,
               s.first_name || ' ' || NVL(s.last_name, '') AS student_name,
               ac.t_att,
               ac.t_total,
               ac.l_att,
               ac.l_total,
               ROUND(NVL(ac.t_att, 0) * 100.0 / NULLIF(ac.t_total, 0), 2) AS theory_pct,
               ROUND(NVL(ac.l_att, 0) * 100.0 / NULLIF(ac.l_total, 0), 2) AS lab_pct,
               ROUND(
                   NVL(NVL(ac.t_att, 0) * 100.0 / NULLIF(ac.t_total, 0), 0) * 0.6
                   + NVL(NVL(ac.l_att, 0) * 100.0 / NULLIF(ac.l_total, 0), 0) * 0.4
               , 2) AS overall_pct
             FROM att_calc ac
             JOIN students s ON ac.student_id = s.student_id
            ORDER BY s.roll_number""",
        {"sid": section_id},
    )