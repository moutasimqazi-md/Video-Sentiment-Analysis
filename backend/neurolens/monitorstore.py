"""SQLite tables for live feed checks: monitors (per profile settings and consent), scans, seen items, alerts, push subscriptions.
Shares the analysis database file and its lock."""

import json
import time
import uuid

from neurolens import logstore

_lock, _conn = logstore._lock, logstore._conn


def init():
    with _lock, _conn() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS monitors (
                profile_id TEXT PRIMARY KEY, name TEXT, enabled INTEGER DEFAULT 0, interval_min INTEGER DEFAULT 120,
                consent_at REAL, last_scan REAL, next_scan REAL, status TEXT, status_at REAL, connected_at REAL
            );
            CREATE TABLE IF NOT EXISTS scans (
                scan_id TEXT PRIMARY KEY, profile_id TEXT, kind TEXT, created_at REAL, finished_at REAL,
                status TEXT, stage TEXT, progress REAL, items_json TEXT, summary_json TEXT, error TEXT, params_json TEXT
            );
            CREATE INDEX IF NOT EXISTS scans_profile ON scans(profile_id, created_at);
            CREATE TABLE IF NOT EXISTS seen_items (profile_id TEXT, url_key TEXT, first_seen REAL, PRIMARY KEY (profile_id, url_key));
            CREATE TABLE IF NOT EXISTS alerts (
                alert_id TEXT PRIMARY KEY, profile_id TEXT, created_at REAL, level TEXT, kind TEXT,
                title TEXT, body TEXT, link TEXT, job_id TEXT, scan_id TEXT, seen INTEGER DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS alerts_time ON alerts(created_at);
            CREATE TABLE IF NOT EXISTS push_subs (endpoint TEXT PRIMARY KEY, sub_json TEXT, created_at REAL);
            """
        )


def _rows(sql, args=()):
    with _lock, _conn() as con:
        return [dict(r) for r in con.execute(sql, args).fetchall()]


# ---------------- monitors ----------------
def get_monitor(pid):
    r = _rows("SELECT * FROM monitors WHERE profile_id=?", (pid,))
    return r[0] if r else None


def save_monitor(pid, **fields):
    cur = get_monitor(pid) or {"profile_id": pid, "enabled": 0, "interval_min": 120}
    cur.update({k: v for k, v in fields.items()})
    cols = ["profile_id", "name", "enabled", "interval_min", "consent_at", "last_scan", "next_scan", "status", "status_at", "connected_at"]
    with _lock, _conn() as con:
        con.execute(f"INSERT OR REPLACE INTO monitors ({','.join(cols)}) VALUES ({','.join('?' * len(cols))})", [cur.get(c) for c in cols])
    return get_monitor(pid)


def list_monitors():
    return _rows("SELECT * FROM monitors ORDER BY profile_id")


def due_monitors(now=None):
    return _rows(
        "SELECT * FROM monitors WHERE enabled=1 AND consent_at IS NOT NULL AND connected_at IS NOT NULL AND (next_scan IS NULL OR next_scan<=?)",
        (now or time.time(),),
    )


# ---------------- scans ----------------
def new_scan(pid, kind, params):
    sid = uuid.uuid4().hex
    with _lock, _conn() as con:
        con.execute(
            "INSERT INTO scans (scan_id, profile_id, kind, created_at, status, stage, progress, items_json, params_json) VALUES (?,?,?,?,?,?,?,?,?)",
            (sid, pid, kind, time.time(), "running", "Starting", 0.0, "[]", json.dumps(params)),
        )
    return sid


def update_scan(sid, **f):
    if not f:
        return
    for k in ("items", "summary"):
        if k in f:
            f[k + "_json"] = json.dumps(f.pop(k))
    with _lock, _conn() as con:
        con.execute(f"UPDATE scans SET {', '.join(k + '=?' for k in f)} WHERE scan_id=?", [*f.values(), sid])


def _scan_out(r):
    return {
        "id": r["scan_id"], "profile": r["profile_id"], "kind": r["kind"], "createdAt": r["created_at"], "finishedAt": r["finished_at"],
        "status": r["status"], "stage": r["stage"], "progress": r["progress"], "error": r["error"],
        "items": json.loads(r["items_json"] or "[]"), "summary": json.loads(r["summary_json"]) if r["summary_json"] else None,
    }


def get_scan(sid):
    r = _rows("SELECT * FROM scans WHERE scan_id=?", (sid,))
    return _scan_out(r[0]) if r else None


def list_scans(pid=None, limit=20):
    rows = _rows("SELECT * FROM scans WHERE (?1 IS NULL OR profile_id=?1) ORDER BY created_at DESC LIMIT ?2", (pid, limit))
    out = []
    for r in rows:
        s = _scan_out(r)
        s["items"] = len(s["items"])  # the list view only needs the count
        out.append(s)
    return out


def abort_stale_scans():
    """A restart mid-scan leaves rows saying 'running'; mark them so the UI doesn't wait forever."""
    with _lock, _conn() as con:
        con.execute("UPDATE scans SET status='error', error='The server restarted during this scan.', finished_at=? WHERE status='running'", (time.time(),))


# ---------------- seen items ----------------
def unseen(pid, keys):
    have = {r["url_key"] for r in _rows("SELECT url_key FROM seen_items WHERE profile_id=?", (pid,))}
    return [k for k in keys if k not in have]


def mark_seen(pid, key):
    with _lock, _conn() as con:
        con.execute("INSERT OR IGNORE INTO seen_items (profile_id, url_key, first_seen) VALUES (?,?,?)", (pid, key, time.time()))


# ---------------- alerts ----------------
def add_alert(pid, level, kind, title, body, link=None, job_id=None, scan_id=None):
    aid = uuid.uuid4().hex
    with _lock, _conn() as con:
        con.execute(
            "INSERT INTO alerts (alert_id, profile_id, created_at, level, kind, title, body, link, job_id, scan_id) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (aid, pid, time.time(), level, kind, title, body, link, job_id, scan_id),
        )
    return aid


def list_alerts(pid=None, since=0, limit=50):
    rows = _rows("SELECT * FROM alerts WHERE (?1 IS NULL OR profile_id=?1) AND created_at>? ORDER BY created_at DESC LIMIT ?", (pid, since, limit))
    unread = _rows("SELECT COUNT(*) AS n FROM alerts WHERE seen=0 AND (?1 IS NULL OR profile_id=?1)", (pid,))[0]["n"]
    return {"alerts": [{"id": r["alert_id"], "profile": r["profile_id"], "createdAt": r["created_at"], "level": r["level"], "kind": r["kind"], "title": r["title"],
                        "body": r["body"], "link": r["link"], "jobId": r["job_id"], "scanId": r["scan_id"], "seen": bool(r["seen"])} for r in rows], "unread": unread}


def mark_read(ids=None):
    with _lock, _conn() as con:
        if ids:
            con.executemany("UPDATE alerts SET seen=1 WHERE alert_id=?", [(i,) for i in ids])
        else:
            con.execute("UPDATE alerts SET seen=1")


# ---------------- push ----------------
def save_sub(sub):
    with _lock, _conn() as con:
        con.execute("INSERT OR REPLACE INTO push_subs (endpoint, sub_json, created_at) VALUES (?,?,?)", (sub["endpoint"], json.dumps(sub), time.time()))


def drop_sub(endpoint):
    with _lock, _conn() as con:
        con.execute("DELETE FROM push_subs WHERE endpoint=?", (endpoint,))


def subs():
    return [json.loads(r["sub_json"]) for r in _rows("SELECT sub_json FROM push_subs")]
