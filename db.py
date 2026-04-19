"""
db.py — Oracle DB connection pool using python-oracledb (thin mode).
Set environment variables:
  DB_USER, DB_PASSWORD, DB_DSN  (e.g. "localhost:1521/XEPDB1")
"""
import os
import oracledb
from contextlib import contextmanager

_pool: oracledb.ConnectionPool | None = None


def init_pool():
    global _pool
    _pool = oracledb.create_pool(
        user="nidhi",
        password="nidhi123",
        dsn= "localhost:1521/XEPDB1",
        min=2,
        max=10,
        increment=1,
    )


def get_pool() -> oracledb.ConnectionPool:
    global _pool
    if _pool is None:
        init_pool()
    return _pool


@contextmanager
def get_connection():
    pool = get_pool()
    conn = pool.acquire()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.release(conn)


def call_procedure(proc_name: str, params: dict) -> dict:
    """
    Call an Oracle stored procedure.
    params: dict with keys matching bind variable names.
    OUT params must have value set to the oracledb type or None.
    Returns the params dict updated with OUT values.
    """
    with get_connection() as conn:
        cursor = conn.cursor()
        bind_vars = {}
        for k, v in params.items():
            bind_vars[k] = v
        cursor.callproc(proc_name, keywordParameters=bind_vars)
        return bind_vars


def query_one(sql: str, params: dict = None) -> dict | None:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, params or {})
        columns = [col[0].lower() for col in cursor.description]
        row = cursor.fetchone()
        if row is None:
            return None
        return dict(zip(columns, row))


def query_many(sql: str, params: dict = None) -> list[dict]:
    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, params or {})
        columns = [col[0].lower() for col in cursor.description]
        rows = cursor.fetchall()
        return [dict(zip(columns, row)) for row in rows]
