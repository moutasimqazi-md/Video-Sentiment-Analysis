"""Accounts, plans and monthly usage for the mobile app.

People sign up with an email and password and each device they sign in on gets its own session token (only hashes of passwords
and tokens are stored, and a session can be revoked). Everything a user creates on the
server (Instagram sessions, child monitors, scans, alerts) lives under their own prefix `u<id>-`, so one user can never see or
touch another's. Plan limits (analyses per month, child profiles) are enforced here, on the server, not in the app.

Payments are in demo mode: choosing a plan switches it on without charging anyone. A real provider (Stripe, Play Billing)
would replace `subscribe()` in accounts_api.py; nothing else changes."""

import hashlib
import hmac
import re
import secrets
import shutil
import threading
import time

from neurolens import browser, logstore, monitorstore

PLANS = {
    "free": {
        "id": "free", "name": "Starter", "monthly": 0, "yearly": 0, "quota": 5, "history": 10, "children": 0, "weekly": False, "seats": 1,
        "blurb": "Analyze your own Reels and images.",
        "features": ["5 analyses / month", "Paste links or upload videos and images", "Emotion timeline and wellbeing signal", "Feed check for your own account", "Last 10 analyses saved"],
        "off": ["Child profiles and monitoring", "Weekly summary reports"],
    },
    "pro": {
        "id": "pro", "name": "Creator & Family", "monthly": 12, "yearly": 9, "quota": 100, "history": 200, "children": 3, "weekly": True, "seats": 1, "featured": True,
        "blurb": "For creators and parents who want ongoing insight.",
        "features": ["100 analyses / month", "3 child profiles with automatic monitoring", "Concern alerts", "Weekly summary reports", "Full history (200 analyses)", "Priority queue"],
        "off": [],
    },
    "studio": {
        "id": "studio", "name": "Studio", "monthly": 39, "yearly": 29, "quota": 500, "history": 1000, "children": 10, "weekly": True, "seats": 5,
        "blurb": "For agencies, schools and brand teams.",
        "features": ["500 analyses / month", "Everything in Creator & Family", "10 child profiles", "5 team seats", "API access"],
        "off": [],
    },
}

_lock = threading.Lock()
_regs = {}  # ip -> [timestamps], to slow down mass sign-ups
REG_LIMIT, REG_WINDOW = 10, 24 * 3600
UID = re.compile(r"^u([0-9a-f]{8})-")


def init():
    with logstore._lock, logstore._conn() as con:
        con.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                user_id TEXT PRIMARY KEY, email TEXT UNIQUE, password_hash TEXT, created_at REAL, name TEXT,
                plan TEXT DEFAULT 'free', cycle TEXT DEFAULT 'monthly', plan_since REAL, last_seen REAL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY, user_id TEXT, created_at REAL, last_seen REAL, device TEXT
            );
            CREATE INDEX IF NOT EXISTS sessions_user ON sessions(user_id);
            CREATE TABLE IF NOT EXISTS usage (user_id TEXT, month TEXT, count INTEGER DEFAULT 0, PRIMARY KEY (user_id, month));
            """
        )


def _hash(token):
    return hashlib.sha256(token.encode()).hexdigest()


def _month():
    return time.strftime("%Y-%m", time.gmtime())


def _row(sql, args=()):
    with logstore._lock, logstore._conn() as con:
        r = con.execute(sql, args).fetchone()
    return dict(r) if r else None


EMAIL = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,255}\.[^@\s]{2,}$")
MIN_PASSWORD = 8
_fails = {}  # (email, ip) -> [timestamps of wrong passwords]
LOCK_AFTER, LOCK_WINDOW = 5, 15 * 60


class AuthError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.message, self.status = message, status


def rate_ok(ip):
    """False when this address has made too many sign-ups today."""
    now = time.time()
    with _lock:
        hits = [t for t in _regs.get(ip, []) if now - t < REG_WINDOW]
        if len(hits) >= REG_LIMIT:
            _regs[ip] = hits
            return False
        hits.append(now)
        _regs[ip] = hits
        return True


def normalize_email(email):
    e = (email or "").strip().lower()
    if not EMAIL.match(e) or len(e) > 120:
        raise AuthError("Enter a valid email address.")
    return e


def check_password(pw):
    if not isinstance(pw, str) or len(pw) < MIN_PASSWORD:
        raise AuthError(f"Use a password of at least {MIN_PASSWORD} characters.")
    if len(pw) > 200:
        raise AuthError("That password is too long.")
    if pw.lower() in {"password", "12345678", "123456789", "qwertyui", "11111111", "password1"}:
        raise AuthError("That password is too easy to guess. Choose another.")


def hash_password(pw):
    salt = secrets.token_bytes(16)
    h = hashlib.scrypt(pw.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt$16384$8$1${salt.hex()}${h.hex()}"


def verify_password(pw, stored):
    try:
        _, n, r, p, salt, h = stored.split("$")
        got = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p), dklen=32)
        return hmac.compare_digest(got.hex(), h)
    except Exception:
        return False


def new_session(uid, device=None):
    token = secrets.token_urlsafe(32)
    now = time.time()
    with logstore._lock, logstore._conn() as con:
        con.execute("INSERT INTO sessions (token_hash, user_id, created_at, last_seen, device) VALUES (?,?,?,?,?)", (_hash(token), uid, now, now, (device or "")[:60] or None))
    return token


def signup(name, email, password, device=None):
    e = normalize_email(email)
    check_password(password)
    if _row("SELECT 1 AS x FROM users WHERE email=?", (e,)):
        raise AuthError("An account with this email already exists. Sign in instead.", 409)
    uid = secrets.token_hex(4)
    with logstore._lock, logstore._conn() as con:
        con.execute(
            "INSERT INTO users (user_id, email, password_hash, created_at, name, plan, cycle, plan_since, last_seen) VALUES (?,?,?,?,?,?,?,?,?)",
            (uid, e, hash_password(password), time.time(), (name or "").strip()[:40] or None, "free", "monthly", time.time(), time.time()),
        )
    return uid, new_session(uid, device)


def login(email, password, ip="", device=None):
    e = (email or "").strip().lower()
    key = (e, ip)
    now = time.time()
    with _lock:
        recent = [t for t in _fails.get(key, []) if now - t < LOCK_WINDOW]
        _fails[key] = recent
        if len(recent) >= LOCK_AFTER:
            raise AuthError("Too many wrong attempts. Wait 15 minutes and try again.", 429)
    u = _row("SELECT * FROM users WHERE email=?", (e,))
    # always run a hash so a missing account takes as long as a wrong password
    ok = verify_password(password or "", u["password_hash"] if u else "scrypt$16384$8$1$" + "00" * 16 + "$" + "00" * 32)
    if not (u and ok):
        with _lock:
            _fails.setdefault(key, []).append(now)
        raise AuthError("Incorrect email or password.", 401)
    with _lock:
        _fails.pop(key, None)
    return u["user_id"], new_session(u["user_id"], device)


def by_token(token):
    if not token or len(token) > 200:
        return None
    sess = _row("SELECT user_id FROM sessions WHERE token_hash=?", (_hash(token),))
    if not sess:
        return None
    u = _row("SELECT * FROM users WHERE user_id=?", (sess["user_id"],))
    if u:
        with logstore._lock, logstore._conn() as con:
            con.execute("UPDATE sessions SET last_seen=? WHERE token_hash=?", (time.time(), _hash(token)))
    return u


def revoke(token):
    with logstore._lock, logstore._conn() as con:
        con.execute("DELETE FROM sessions WHERE token_hash=?", (_hash(token),))


def revoke_all(uid, except_token=None):
    keep = _hash(except_token) if except_token else ""
    with logstore._lock, logstore._conn() as con:
        con.execute("DELETE FROM sessions WHERE user_id=? AND token_hash != ?", (uid, keep))


def change_password(uid, current, new, keep_token=None):
    u = _row("SELECT password_hash FROM users WHERE user_id=?", (uid,))
    if not u or not verify_password(current or "", u["password_hash"]):
        raise AuthError("Your current password is wrong.", 403)
    check_password(new)
    with logstore._lock, logstore._conn() as con:
        con.execute("UPDATE users SET password_hash=? WHERE user_id=?", (hash_password(new), uid))
    revoke_all(uid, except_token=keep_token)  # every other device has to sign in again


def confirm_password(uid, pw):
    u = _row("SELECT password_hash FROM users WHERE user_id=?", (uid,))
    return bool(u and verify_password(pw or "", u["password_hash"]))


def uid_of(pid):
    m = UID.match(pid or "")
    return m.group(1) if m else None


def plan_of(uid):
    u = _row("SELECT plan FROM users WHERE user_id=?", (uid,))
    return PLANS.get(u["plan"] if u else "free", PLANS["free"])


def used(uid):
    r = _row("SELECT count FROM usage WHERE user_id=? AND month=?", (uid, _month()))
    return r["count"] if r else 0


def remaining(uid):
    return max(0, plan_of(uid)["quota"] - used(uid))


def add_usage(uid, n=1):
    with logstore._lock, logstore._conn() as con:
        con.execute(
            "INSERT INTO usage (user_id, month, count) VALUES (?,?,?) ON CONFLICT(user_id, month) DO UPDATE SET count = count + ?",
            (uid, _month(), n, n),
        )


def children_used(uid):
    prefix = f"u{uid}-"
    return len([m for m in monitorstore.list_monitors() if m["profile_id"].startswith(prefix) and m["profile_id"] != prefix + "me"])


def resets_on():
    t = time.gmtime()
    y, m = (t.tm_year + 1, 1) if t.tm_mon == 12 else (t.tm_year, t.tm_mon + 1)
    return f"{y:04d}-{m:02d}-01"


def status(uid):
    u = _row("SELECT * FROM users WHERE user_id=?", (uid,))
    plan = PLANS.get(u["plan"], PLANS["free"])
    n = used(uid)
    return {
        "userId": uid, "name": u["name"], "email": u["email"], "plan": plan, "cycle": u["cycle"], "since": u["plan_since"],
        "used": n, "quota": plan["quota"], "remaining": max(0, plan["quota"] - n), "resetsOn": resets_on(),
        "childrenUsed": children_used(uid), "childrenAllowed": plan["children"],
    }


def update_profile(uid, name=None):
    with logstore._lock, logstore._conn() as con:
        if name is not None:
            con.execute("UPDATE users SET name=? WHERE user_id=?", (name.strip()[:40] or None, uid))


def set_plan(uid, plan_id, cycle="monthly"):
    if plan_id not in PLANS:
        raise KeyError(plan_id)
    cycle = cycle if cycle in ("monthly", "yearly") else "monthly"
    with logstore._lock, logstore._conn() as con:
        con.execute("UPDATE users SET plan=?, cycle=?, plan_since=? WHERE user_id=?", (plan_id, cycle, time.time(), uid))
    allowed = PLANS[plan_id]["children"]
    prefix = f"u{uid}-"
    kids = [m for m in monitorstore.list_monitors() if m["profile_id"].startswith(prefix) and m["profile_id"] != prefix + "me"]
    for m in kids[allowed:]:  # a downgrade pauses monitoring beyond what the plan allows
        monitorstore.save_monitor(m["profile_id"], enabled=0)


def delete_user(uid):
    """Everything this user has on the server: account, usage, monitors, scans, alerts, remembered items, and Instagram sessions."""
    prefix = f"u{uid}-"
    pids = {m["profile_id"] for m in monitorstore.list_monitors() if m["profile_id"].startswith(prefix)}
    if browser.SESS_DIR.exists():
        pids |= {d.name for d in browser.SESS_DIR.iterdir() if d.name.startswith(prefix)}
    from neurolens import live

    for pid in pids:
        try:
            live.cancel(pid)
            browser.disconnect(pid)
        except Exception:
            shutil.rmtree(browser.SESS_DIR / pid, ignore_errors=True)
    like = prefix + "%"
    with logstore._lock, logstore._conn() as con:
        for t in ("monitors", "scans", "alerts", "seen_items"):
            con.execute(f"DELETE FROM {t} WHERE profile_id LIKE ?", (like,))
        con.execute("DELETE FROM usage WHERE user_id=?", (uid,))
        con.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
        con.execute("DELETE FROM push_subs WHERE user_id=?", (uid,))
        con.execute("DELETE FROM users WHERE user_id=?", (uid,))
