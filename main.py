"""
main.py — FastAPI application entry point.
Run:  uvicorn main:app --reload
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import auth, students, faculty, courses, attendance, reports, admin

from fastapi.responses import FileResponse


app = FastAPI(
    title="Academic Management System API",
    version="1.0.0",
    description="REST API for Student, Faculty & Admin academic management",
)


@app.get("/")
def home():
    return FileResponse("index.html")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router,       prefix="/api/auth",       tags=["Auth"])
app.include_router(students.router,   prefix="/api/student",    tags=["Student"])
app.include_router(faculty.router,    prefix="/api/faculty",    tags=["Faculty"])
app.include_router(courses.router,    prefix="/api/courses",    tags=["Courses"])
app.include_router(attendance.router, prefix="/api/attendance", tags=["Attendance"])
app.include_router(reports.router,    prefix="/api/reports",    tags=["Reports"])
app.include_router(admin.router,      prefix="/api/admin",      tags=["Admin"])

@app.get("/api/health")
def health():
    return {"status": "ok"}
