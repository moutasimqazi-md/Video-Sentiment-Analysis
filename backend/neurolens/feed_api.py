"""Routes for sign-in, feed checks, child monitoring, alerts and push, for Instagram, YouTube, TikTok and Facebook.

Every route that touches a session takes `platform` ("ig" by default, so callers written before other sites existed keep working).
A person's session on a site is one session key (platforms.py): the profile id for Instagram, `<profile>.<site>` for the others.

Callers are either the owner (this computer or a paired browser: original ids) or a signed-in user (X-User-Token): a user's ids
are stored under their own prefix, and they can only ever see and change their own."""

import asyncio
import importlib.util
import os
import re
import time
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket
from pydantic import BaseModel

from neurolens import accounts, browser, guard, live, logstore, monitorstore, platforms, push, scanner

router = APIRouter(prefix="/api")
owner = Depends(guard.require_owner)
who = Depends(guard.actor)


def _browser_ready():
    """Signing in and scanning drive a real browser (Playwright) and stream it over a WebSocket. A host that has neither, such as
    cPanel's Passenger, says so plainly instead of failing halfway. NL_FEED=0 switches the routes off on purpose."""
    if os.environ.get("NL_FEED") == "0" or importlib.util.find_spec("playwright") is None:
        raise HTTPException(503, "Feed check isn't available on this server.")


browser_ready = Depends(_browser_ready)
PID = re.compile(r"^[a-z0-9_-]{1,40}$")
USER_PID = re.compile(r"^[a-z0-9_-]{1,30}$")
HEX32 = re.compile(r"^[0-9a-f]{32}$")


def _plat(code):
    code = (code or "ig").lower()
    if code not in platforms.PLATFORMS:
        raise HTTPException(400, "Unknown site. Choose Instagram, YouTube, TikTok or Facebook.")
    return code


def _sk(a, pid, code="ig"):
    """The session key for this caller's profile on a site (validates the profile id too)."""
    return platforms.session_key(_ns(a, pid), _plat(code))


def _sks(a, pid, code=None):
    """One site's session key, or (no site given) every site's, for a profile."""
    ns = _ns(a, pid)
    return [platforms.session_key(ns, _plat(code))] if code else [platforms.session_key(ns, c) for c in platforms.CODES]


def _out(a, sk):
    """session key -> (the caller-facing profile id, site code)"""
    base, code = platforms.split_key(sk)
    return a.out(base), code


def _ns(a, pid):
    """Validate a profile id from the caller and return the id as stored (namespaced for users)."""
    if not (USER_PID if a.is_user else PID).match(pid or ""):
        raise HTTPException(400, "Invalid profile")
    return a.ns(pid)


def _only_owner(a):
    if a.is_user:
        raise HTTPException(403, "This is only available to the server owner.")


class RedeemIn(BaseModel):
    code: str


@router.get("/owner/state")
def owner_state(request: Request):
    """Does this browser already have owner access? (True on this computer; elsewhere only after pairing.)"""
    try:
        guard.require_owner(request)
        return {"ok": True, "local": guard.is_local(request)}
    except HTTPException:
        return {"ok": False, "local": False}


@router.post("/owner/pair-link", dependencies=[owner])
def pair_link(request: Request):
    """A single-use link that connects another device (phone, the public address) with one tap. Made on this computer."""
    if not guard.is_local(request):
        raise HTTPException(403, "Create pairing links on the computer running NeuroLens.")
    code = guard.new_code()
    base = guard.public_url()
    return {"code": code, "publicUrl": base, "path": f"pages/feed.html?pair={code}", "expiresInMinutes": guard.CODE_TTL // 60}


@router.post("/owner/redeem")
def redeem(body: RedeemIn):
    t = guard.redeem(body.code)
    if not t:
        raise HTTPException(400, "That link has expired or was already used. Make a new one on the computer running NeuroLens.")
    return {"token": t}


@router.get("/owner/check", dependencies=[owner])
def owner_check():
    return {"ok": True}


# ---------------- session ----------------
@router.get("/platforms")
def platform_list():
    """The sites a feed check can read, and which checks each one has."""
    return [{"id": c, "name": P["name"], "modes": [{"id": m, "label": l} for m, l in P["modes"].items()]} for c, P in platforms.PLATFORMS.items()]


@router.get("/sessions/{pid}")
def session_status(pid: str, platform: str = "ig", a=who):
    sk = _sk(a, pid, platform)
    return {"connected": browser.connected_at(sk), "login": live.status(sk), "platform": _plat(platform)}


def _consent_needed(raw, sk):
    if raw != "me":
        m = monitorstore.get_monitor(sk)
        if not (m and m.get("consent_at")):
            raise HTTPException(400, "Confirm that your child knows before connecting their account.")


@router.post("/sessions/{pid}/login", dependencies=[browser_ready])
def session_login(pid: str, platform: str = "ig", a=who):
    sk = _sk(a, pid, platform)
    _consent_needed(pid, sk)
    lv = live.start(sk)
    return {"state": lv.state}


@router.post("/sessions/{pid}/view-token", dependencies=[browser_ready])
def session_view_token(pid: str, platform: str = "ig", a=who):
    """A single-use, 60-second key for the WebSocket that streams the private browser."""
    sk = _sk(a, pid, platform)
    cur = live.get(sk)
    if not cur or cur.state not in ("starting", "live") or cur.stopping:
        raise HTTPException(400, "The private browser isn't open. Start it again.")
    return {"token": live.view_token(sk)}


@router.post("/sessions/{pid}/login/cancel")
def session_login_cancel(pid: str, platform: str = "ig", a=who):
    live.cancel(_sk(a, pid, platform))
    return {"ok": True}


@router.websocket("/sessions/{pid}/view")
async def session_view(ws: WebSocket, pid: str):
    """Streams the isolated browser (JPEG frames) and takes mouse/keyboard input. Opens only with a fresh view token, which
    already names the (namespaced) profile it was made for; the id in the URL is not trusted."""
    origin = ws.headers.get("origin")
    if (origin and urlparse(origin).netloc != ws.headers.get("host")) or not PID.match(pid):
        await ws.close(code=4401)
        return
    stored_pid = live.consume_view_token(ws.query_params.get("t"))
    if not stored_pid:
        await ws.close(code=4401)
        return
    lv = live.get(stored_pid)
    await ws.accept()
    if not lv:
        await ws.close(code=4404)
        return
    loop = asyncio.get_running_loop()
    q: asyncio.Queue = asyncio.Queue(maxsize=3)

    def deliver(kind, payload):
        if kind == "frame" and q.full():
            try:
                q.get_nowait()  # a slow viewer skips frames instead of falling behind
            except asyncio.QueueEmpty:
                pass
        try:
            q.put_nowait((kind, payload))
        except asyncio.QueueFull:
            pass

    def cb(kind, payload):
        loop.call_soon_threadsafe(deliver, kind, payload)

    lv.subs.append(cb)
    lv.snap_requested = True
    deliver("state", {"state": lv.state, "error": lv.error})
    if lv.last_frame:
        deliver("frame", lv.last_frame)

    async def sender():
        while True:
            kind, payload = await q.get()
            if kind == "frame":
                await ws.send_bytes(payload)
            else:
                await ws.send_json({"type": kind, **payload})
                if kind == "state" and payload.get("state") in ("connected", "closed", "error"):
                    return

    async def receiver():
        while True:
            lv.send(await ws.receive_json())

    tasks = [asyncio.create_task(sender()), asyncio.create_task(receiver())]
    try:
        await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
    except Exception:
        pass
    finally:
        for t in tasks:
            t.cancel()
        if cb in lv.subs:
            lv.subs.remove(cb)
        try:
            await ws.close()
        except Exception:
            pass


@router.post("/sessions/{pid}/connected")
def session_connected(pid: str, platform: str = "ig", a=who):
    """Called once the sign-in window reports done, to stamp the monitor row."""
    sk = _sk(a, pid, platform)
    at = browser.connected_at(sk)
    if at and monitorstore.get_monitor(sk):
        monitorstore.save_monitor(sk, connected_at=at, status="ok", status_at=time.time())
    return {"connected": at}


class ImportIn(BaseModel):
    cookies: list[dict]
    platform: str = "ig"


@router.post("/sessions/{pid}/import", dependencies=[browser_ready])
def session_import(pid: str, body: ImportIn, a=who):
    """The app signed in on the phone itself and hands over that session, so scans can run on the server."""
    sk = _sk(a, pid, body.platform)
    _consent_needed(pid, sk)
    try:
        at = browser.import_session(sk, body.cookies)
    except ValueError as e:
        raise HTTPException(400, str(e))
    if monitorstore.get_monitor(sk):
        monitorstore.save_monitor(sk, connected_at=at, status="ok", status_at=time.time())
    return {"connected": at}


@router.delete("/sessions/{pid}")
def session_disconnect(pid: str, platform: str = "ig", a=who):
    sk = _sk(a, pid, platform)
    live.cancel(sk)
    browser.disconnect(sk)
    if monitorstore.get_monitor(sk):
        monitorstore.save_monitor(sk, connected_at=None, enabled=0, status="disconnected")
    return {"ok": True}


# ---------------- monitors ----------------
class MonitorIn(BaseModel):
    name: str = ""
    enabled: bool = False
    interval_min: int = 120
    consent: bool = False
    platform: str = "ig"


def _monitor_out(m, a):
    pid, code = _out(a, m["profile_id"])
    return {**m, "profile_id": pid, "platform": code, "connected": browser.connected_at(m["profile_id"]) is not None, "consent": bool(m.get("consent_at"))}


@router.get("/monitors")
def monitors(a=who):
    return [_monitor_out(m, a) for m in monitorstore.list_monitors() if a.owns(m["profile_id"])]


@router.put("/monitors/{pid}")
def put_monitor(pid: str, body: MonitorIn, a=who):
    raw = pid
    base = _ns(a, pid)
    pid = _sk(a, raw, body.platform)
    cur = monitorstore.get_monitor(pid) or {}
    if a.is_user and raw != "me" and not cur and base not in accounts.kid_bases(a.uid):  # another site for a child already counted is not another child
        plan = accounts.plan_of(a.uid)
        if accounts.children_used(a.uid) >= plan["children"]:
            raise HTTPException(402, f"The {plan['name']} plan has no child profiles. Upgrade to add one." if plan["children"] == 0 else f"The {plan['name']} plan includes {plan['children']} child profiles. Upgrade to add more.")
    fields = {"name": body.name.strip()[:40] or cur.get("name") or raw, "interval_min": max(30, min(body.interval_min, 1440))}
    if raw != "me":
        if body.consent and not cur.get("consent_at"):
            fields["consent_at"] = time.time()
        elif not body.consent:
            fields["consent_at"] = None
        if body.enabled and not (fields.get("consent_at") or cur.get("consent_at")):
            raise HTTPException(400, "Monitoring needs your child's knowledge. Tick the confirmation first.")
        if not body.consent:
            body.enabled = False
    else:
        fields["consent_at"] = cur.get("consent_at") or time.time()
    fields["enabled"] = 1 if body.enabled else 0
    if body.enabled:
        fields["next_scan"] = time.time() + 60
    fields["connected_at"] = browser.connected_at(pid)
    return _monitor_out(monitorstore.save_monitor(pid, **fields), a)


# ---------------- scans ----------------
class ScanIn(BaseModel):
    profile: str = "me"
    kind: str = "explore"
    terms: list[str] = []
    limit: int = 10
    platform: str = "ig"


@router.post("/scans", dependencies=[browser_ready])
def start_scan(body: ScanIn, a=who):
    code = _plat(body.platform)
    pid = _sk(a, body.profile, code)
    site = platforms.name(code)
    if body.kind not in scanner.KINDS:
        raise HTTPException(400, "Unknown scan type")
    if body.kind not in platforms.PLATFORMS[code]["modes"]:
        raise HTTPException(400, f"{site} doesn't have a \"{scanner.KINDS[body.kind]}\" check. Choose one of: {', '.join(platforms.PLATFORMS[code]['modes'].values())}.")
    if browser.connected_at(pid) is None:
        raise HTTPException(400, f"Log in to {site} first.")
    m = monitorstore.get_monitor(pid)
    if body.profile != "me" and not (m and m.get("consent_at")):
        raise HTTPException(400, "Confirm that your child knows before checking their account.")
    if body.kind == "terms" and not [t for t in body.terms if t.strip()]:
        raise HTTPException(400, "Add at least one topic to search.")
    if a.is_user and accounts.remaining(a.uid) <= 0:
        raise HTTPException(402, "You have used this month's analyses. Upgrade your plan or wait until it resets.")
    sid = scanner.start(pid, body.kind, {"limit": body.limit, "terms": body.terms[:5], "alerts": body.profile != "me"})
    return {"id": sid}


def _scan_out(s, a):
    pid, code = _out(a, s["profile"])
    return {**s, "profile": pid, "platform": code}


@router.get("/scans")
def scans(profile: str | None = None, platform: str | None = None, a=who):
    if not profile:
        return [_scan_out(s, a) for s in monitorstore.list_scans(None, prefix=a.prefix or None)]
    rows = [s for sk in _sks(a, profile, platform) for s in monitorstore.list_scans(sk, prefix=a.prefix or None)]  # no site given: all of that profile's sites
    return [_scan_out(s, a) for s in sorted(rows, key=lambda r: -(r["createdAt"] or 0))[:20]]


@router.get("/scans/{sid}")
def scan(sid: str, a=who):
    s = monitorstore.get_scan(sid) if HEX32.match(sid) else None
    if not s or not a.owns(s["profile"]):
        raise HTTPException(404, "Unknown scan")
    return _scan_out(s, a)


# ---------------- alerts ----------------
@router.get("/alerts")
def alerts(profile: str | None = None, platform: str | None = None, since: float = 0, limit: int = 50, a=who):
    limit = min(limit, 200)
    if not profile:
        r = monitorstore.list_alerts(None, since, limit, prefix=a.prefix or None)
    else:  # one profile: one site's alerts, or (no site given) all of that profile's sites together
        parts = [monitorstore.list_alerts(sk, since, limit, prefix=a.prefix or None) for sk in _sks(a, profile, platform)]
        r = {"alerts": sorted((x for p in parts for x in p["alerts"]), key=lambda x: -x["createdAt"])[:limit], "unread": sum(p["unread"] for p in parts)}
    r["alerts"] = [{**x, "profile": _out(a, x["profile"])[0], "platform": _out(a, x["profile"])[1]} for x in r["alerts"]]
    return r


class ReadIn(BaseModel):
    ids: list[str] = []


@router.post("/alerts/read")
def alerts_read(body: ReadIn, a=who):
    monitorstore.mark_read(body.ids or None, prefix=a.prefix or None)
    return {"ok": True}


# ---------------- push (browser notifications, per person) ----------------
@router.get("/push/key")
def push_key(a=who):
    return {"key": push.public_key()}


@router.post("/push/subscribe")
def push_subscribe(sub: dict, a=who):
    if not isinstance(sub.get("endpoint"), str) or not isinstance(sub.get("keys"), dict):
        raise HTTPException(400, "Invalid subscription")
    monitorstore.save_sub(sub, a.uid if a.is_user else None)
    return {"ok": True}


@router.post("/push/test")
def push_test(a=who):
    return {"sent": push.send("NeuroLens notifications are on", "You will get alerts like this when something in a monitored feed needs a look.", "pages/feed.html", uid=a.uid if a.is_user else None)}


# ---------------- a finished analysis, by id (feed items open in the results page) ----------------
@router.get("/results/{job_id}")
def result(job_id: str):
    r = logstore.get_result(job_id) if HEX32.match(job_id) else None
    if not r:
        raise HTTPException(404, "Not found")
    return {"id": job_id, "result": r}
