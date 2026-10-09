"""Owner-only routes: Instagram session login, feed scans, child monitoring settings, alerts, push subscriptions."""

import asyncio
import re
import time
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Request, WebSocket
from pydantic import BaseModel

from neurolens import browser, guard, live, logstore, monitorstore, push, scanner

router = APIRouter(prefix="/api")
owner = Depends(guard.require_owner)
PID = re.compile(r"^[a-z0-9_-]{1,40}$")
HEX32 = re.compile(r"^[0-9a-f]{32}$")


def _pid(pid):
    if not PID.match(pid):
        raise HTTPException(400, "Invalid profile")
    return pid


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
@router.get("/sessions/{pid}", dependencies=[owner])
def session_status(pid: str):
    _pid(pid)
    return {"connected": browser.connected_at(pid), "login": live.status(pid)}


@router.post("/sessions/{pid}/login", dependencies=[owner])
def session_login(pid: str):
    _pid(pid)
    if pid != "me":
        m = monitorstore.get_monitor(pid)
        if not (m and m.get("consent_at")):
            raise HTTPException(400, "Confirm that your child knows before connecting their account.")
    lv = live.start(pid)
    return {"state": lv.state}


@router.post("/sessions/{pid}/view-token", dependencies=[owner])
def session_view_token(pid: str):
    """A single-use, 60-second key for the WebSocket that streams the private browser into the page."""
    _pid(pid)
    cur = live.get(pid)
    if not cur or cur.state not in ("starting", "live") or cur.stopping:
        raise HTTPException(400, "The private browser isn't open. Start it again.")
    return {"token": live.view_token(pid)}


@router.post("/sessions/{pid}/login/cancel", dependencies=[owner])
def session_login_cancel(pid: str):
    _pid(pid)
    live.cancel(pid)
    return {"ok": True}


@router.websocket("/sessions/{pid}/view")
async def session_view(ws: WebSocket, pid: str):
    """Streams the isolated browser (JPEG frames) and takes mouse/keyboard input. Opens only with a fresh view token."""
    origin = ws.headers.get("origin")
    if not PID.match(pid) or (origin and urlparse(origin).netloc != ws.headers.get("host")) or not live.redeem_view_token(ws.query_params.get("t"), pid):
        await ws.close(code=4401)
        return
    lv = live.get(pid)
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


@router.post("/sessions/{pid}/connected", dependencies=[owner])
def session_connected(pid: str):
    """Called by the page once the login window reports done, to stamp the monitor row."""
    _pid(pid)
    at = browser.connected_at(pid)
    if at and monitorstore.get_monitor(pid):
        monitorstore.save_monitor(pid, connected_at=at, status="ok", status_at=time.time())
    return {"connected": at}


@router.delete("/sessions/{pid}", dependencies=[owner])
def session_disconnect(pid: str):
    _pid(pid)
    live.cancel(pid)
    browser.disconnect(pid)
    if monitorstore.get_monitor(pid):
        monitorstore.save_monitor(pid, connected_at=None, enabled=0, status="disconnected")
    return {"ok": True}


# ---------------- monitors ----------------
class MonitorIn(BaseModel):
    name: str = ""
    enabled: bool = False
    interval_min: int = 120
    consent: bool = False


def _monitor_out(m):
    return {**m, "connected": browser.connected_at(m["profile_id"]) is not None, "consent": bool(m.get("consent_at"))}


@router.get("/monitors", dependencies=[owner])
def monitors():
    return [_monitor_out(m) for m in monitorstore.list_monitors()]


@router.put("/monitors/{pid}", dependencies=[owner])
def put_monitor(pid: str, body: MonitorIn):
    _pid(pid)
    cur = monitorstore.get_monitor(pid) or {}
    fields = {"name": body.name.strip()[:40] or cur.get("name") or pid, "interval_min": max(30, min(body.interval_min, 1440))}
    if pid != "me":
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
    return _monitor_out(monitorstore.save_monitor(pid, **fields))


# ---------------- scans ----------------
class ScanIn(BaseModel):
    profile: str = "me"
    kind: str = "explore"
    terms: list[str] = []
    limit: int = 10


@router.post("/scans", dependencies=[owner])
def start_scan(body: ScanIn):
    pid = _pid(body.profile)
    if body.kind not in scanner.KINDS:
        raise HTTPException(400, "Unknown scan type")
    if browser.connected_at(pid) is None:
        raise HTTPException(400, "Log in to Instagram first.")
    m = monitorstore.get_monitor(pid)
    if pid != "me" and not (m and m.get("consent_at")):
        raise HTTPException(400, "Confirm that your child knows before checking their account.")
    if body.kind == "terms" and not [t for t in body.terms if t.strip()]:
        raise HTTPException(400, "Add at least one topic to search.")
    sid = scanner.start(pid, body.kind, {"limit": body.limit, "terms": body.terms[:5], "alerts": pid != "me"})
    return {"id": sid}


@router.get("/scans", dependencies=[owner])
def scans(profile: str | None = None):
    return monitorstore.list_scans(_pid(profile) if profile else None)


@router.get("/scans/{sid}", dependencies=[owner])
def scan(sid: str):
    s = monitorstore.get_scan(sid) if HEX32.match(sid) else None
    if not s:
        raise HTTPException(404, "Unknown scan")
    return s


# ---------------- alerts ----------------
@router.get("/alerts", dependencies=[owner])
def alerts(profile: str | None = None, since: float = 0, limit: int = 50):
    return monitorstore.list_alerts(_pid(profile) if profile else None, since, min(limit, 200))


class ReadIn(BaseModel):
    ids: list[str] = []


@router.post("/alerts/read", dependencies=[owner])
def alerts_read(body: ReadIn):
    monitorstore.mark_read(body.ids or None)
    return {"ok": True}


# ---------------- push ----------------
@router.get("/push/key", dependencies=[owner])
def push_key():
    return {"key": push.public_key()}


@router.post("/push/subscribe", dependencies=[owner])
def push_subscribe(sub: dict):
    if not isinstance(sub.get("endpoint"), str) or not isinstance(sub.get("keys"), dict):
        raise HTTPException(400, "Invalid subscription")
    monitorstore.save_sub(sub)
    return {"ok": True}


@router.post("/push/test", dependencies=[owner])
def push_test():
    return {"sent": push.send("NeuroLens notifications are on", "You will get alerts like this when something in a monitored feed needs a look.", "pages/feed.html")}


# ---------------- a finished analysis, by id (feed items open in the results page) ----------------
@router.get("/results/{job_id}")
def result(job_id: str):
    r = logstore.get_result(job_id) if HEX32.match(job_id) else None
    if not r:
        raise HTTPException(404, "Not found")
    return {"id": job_id, "result": r}
