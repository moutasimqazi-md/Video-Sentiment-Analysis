"""An isolated browser you use inside the NeuroLens page (no window opens on the computer).

A headless Chrome with its own private profile is streamed to the page as JPEG frames over a WebSocket, and the page sends
clicks, scrolling and typing back. You sign in to Instagram directly inside it: NeuroLens never sees the password, it only
notices that the browser now holds a logged-in session, then closes the browser and keeps that session folder.

Same idea as the isolated-browser step in savv-mvp, but streamed with Chrome's own screencast instead of VNC, so it needs
nothing extra on Windows."""

import os
import queue
import random
import secrets
import shutil
import threading
import time
from urllib.parse import urlparse

from neurolens import browser

VIEW_W, VIEW_H, SCALE = 440, 780, 1.5
# Sign-in runs in a real (not headless) Chrome placed off-screen: Instagram's checks trust that far more than headless Chrome.
# Tests set NL_LIVE_HEADLESS=1 so no window is created.
HEADLESS = os.environ.get("NL_LIVE_HEADLESS") == "1"
PENDING_CHECK = ("/challenge", "/accounts/login", "two_factor", "checkpoint", "/accounts/suspended")
LIVE_MINUTES = 12
ALLOWED_SUFFIXES = ("instagram.com", "facebook.com", "fbcdn.net", "cdninstagram.com", "meta.com", "fb.com")
VIEW_TOKEN_TTL = 60

_live = {}  # pid -> Live
_tokens = {}  # view token -> (pid, expiry)
_glock = threading.Lock()


def _host_ok(url):
    host = (urlparse(url).hostname or "").lower()
    base_host = (urlparse(browser.BASE).hostname or "").lower()
    return not host or host in ("about", "") or host == base_host or host.endswith(ALLOWED_SUFFIXES) or url.startswith("about:")


class Live:
    def __init__(self, pid):
        self.pid = pid
        self.cmds = queue.Queue()
        self.subs = []  # callables (kind, payload)
        self.state = "starting"  # starting | live | connected | closed | error
        self.error = None
        self.last_frame = None
        self.last_frame_t = 0.0
        self.input_t = 0.0
        self.snap_requested = True  # a viewer just connected: send a current picture
        self.dirty = False  # the page repainted since the last picture
        self.stopping = False
        self.mx = self.my = 0.0
        self.url = ""
        self.started = time.time()
        self.thread = threading.Thread(target=self._run, daemon=True)

    # ---- fan-out to viewers (called from this worker thread) ----
    def publish(self, kind, payload):
        if kind == "frame":
            self.last_frame = payload
            self.last_frame_t = time.time()
        for cb in list(self.subs):
            try:
                cb(kind, payload)
            except Exception:
                self.subs.remove(cb)

    def set_state(self, state, error=None):
        self.state, self.error = state, error
        self.publish("state", {"state": state, "error": error})

    # ---- input from the page ----
    def send(self, msg):
        if self.state in ("starting", "live"):
            self.cmds.put(msg)

    def stop(self):
        self.stopping = True  # from now on a new sign-in starts a fresh browser instead of reusing this one
        self.cmds.put({"t": "stop"})

    # ---- worker ----
    def _run(self):
        from playwright.sync_api import sync_playwright

        locked = browser._lock(self.pid).acquire(timeout=30)
        if not locked:
            self.set_state("error", "The browser for this account is busy. Try again in a moment.")
            return
        ok = False
        try:
            with sync_playwright() as p:
                if browser.connected_at(self.pid) is None:  # never reuse a half-finished or flagged attempt
                    shutil.rmtree(browser._dir(self.pid) / "chrome", ignore_errors=True)
                ctx = browser.launch(p, self.pid, HEADLESS, {"width": VIEW_W, "height": VIEW_H}, SCALE)
                page = ctx.pages[0] if ctx.pages else ctx.new_page()
                page.goto(f"{browser.BASE}/accounts/login/", wait_until="domcontentloaded")
                cdp = ctx.new_cdp_session(page)
                acks = []

                def on_frame(ev):  # Chrome says the page repainted; the picture itself is taken below, at full sharpness
                    acks.append(ev["sessionId"])
                    self.dirty = True

                cdp.on("Page.screencastFrame", on_frame)
                cdp.send("Page.startScreencast", {"format": "jpeg", "quality": 20, "maxWidth": 120, "maxHeight": 200, "everyNthFrame": 1})  # tiny: only used as a repaint signal
                self.set_state("live")
                deadline = time.time() + LIVE_MINUTES * 60
                last_check = 0.0
                settled = 0  # consecutive checks that show a finished sign-in
                while True:
                    try:
                        msg = self.cmds.get(timeout=0.02)
                    except queue.Empty:
                        msg = None
                    if msg:
                        if msg.get("t") == "stop":
                            break
                        self._input(page, msg)
                        self.input_t = time.time()
                    while acks:
                        try:
                            cdp.send("Page.screencastFrameAck", {"sessionId": acks.pop(0)})
                        except Exception:
                            acks.clear()
                    page.wait_for_timeout(1)  # lets Playwright deliver screencast frames
                    now = time.time()
                    # Chrome only streams a frame when the page repaints, so a still page (a login form) would show nothing.
                    # Take a snapshot when a viewer connects, shortly after each input, and as a keepalive.
                    if self.snap_requested or now - self.last_frame_t > 1.5 or (self.dirty and now - self.last_frame_t > 0.1) or (self.input_t > self.last_frame_t and now - self.input_t > 0.12):
                        self.snap_requested = False
                        self.dirty = False
                        try:
                            self.publish("frame", page.screenshot(type="jpeg", quality=62))
                        except Exception:
                            pass
                    if now - last_check > 1.0:
                        last_check = now
                        if not ctx.pages:
                            break
                        if page.url != self.url:
                            self.url = page.url
                            if not _host_ok(self.url):
                                page.goto(f"{browser.BASE}/accounts/login/", wait_until="domcontentloaded")
                            self.publish("url", {"host": urlparse(self.url).hostname or ""})
                            asking = any(k in self.url for k in ("/challenge", "checkpoint", "two_factor"))
                            self.publish("hint", {"text": "Instagram is asking for a security check. Complete it in the browser above, slowly, like on your phone." if asking else ""})
                        # signed in only when the session exists AND no security step is still pending
                        if browser._has_session(ctx) and not any(k in self.url for k in PENDING_CHECK):
                            settled += 1
                            if settled >= 2:
                                ok = True
                                break
                        else:
                            settled = 0
                    if now > deadline:
                        break
                if ok:
                    self.publish("state", {"state": "finishing", "error": None})
                    page.wait_for_timeout(2500)  # let the browser flush its cookies to disk
                try:
                    cdp.send("Page.stopScreencast")
                except Exception:
                    pass
                ctx.close()
            if ok:
                at = int(time.time())
                (browser._dir(self.pid) / "connected").write_text(str(at))
                try:
                    from neurolens import monitorstore

                    if monitorstore.get_monitor(self.pid):
                        monitorstore.save_monitor(self.pid, connected_at=at, status="ok", status_at=time.time())
                except Exception:
                    pass
                self.set_state("connected")
            else:
                self.set_state("closed")
        except Exception as e:
            print(f"live browser failed: {e!r}"[:300], flush=True)
            self.set_state("error", "The private browser couldn't start on this computer.")
        finally:
            browser._lock(self.pid).release()

    def _input(self, page, m):
        t = m.get("t")
        try:
            if t == "mouse":
                x, y = float(m["x"]), float(m["y"])
                kind = m.get("type")
                btn = m.get("button", "left")
                if btn not in ("left", "right", "middle"):
                    btn = "left"
                if kind == "move":
                    page.mouse.move(x, y)
                elif kind == "down":
                    # glide to the target like a hand would, instead of teleporting
                    dist = ((x - self.mx) ** 2 + (y - self.my) ** 2) ** 0.5
                    page.mouse.move(x + random.uniform(-1.5, 1.5), y + random.uniform(-1.5, 1.5), steps=max(2, min(18, int(dist / 30))))
                    page.wait_for_timeout(random.uniform(35, 110))
                    page.mouse.down(button=btn, click_count=int(m.get("clicks", 1)))
                elif kind == "up":
                    page.wait_for_timeout(random.uniform(45, 120))
                    page.mouse.up(button=btn, click_count=int(m.get("clicks", 1)))
                elif kind == "wheel":
                    page.mouse.move(x, y)
                    page.mouse.wheel(float(m.get("dx", 0)), float(m.get("dy", 0)))
                self.mx, self.my = x, y
            elif t == "text":
                text = str(m.get("text", ""))[:500]
                if 0 < len(text) <= 60:
                    for ch in text:  # typed one key at a time, with human-like gaps
                        page.keyboard.type(ch)
                        page.wait_for_timeout(random.uniform(40, 125))
                elif text:
                    page.keyboard.insert_text(text)
            elif t == "key":
                key = str(m.get("key", ""))
                if key in ("Backspace", "Enter", "Tab", "Escape", "Delete", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown", "Space"):
                    page.keyboard.press(key)
            elif t == "nav" and m.get("action") in ("back", "reload"):
                page.go_back() if m["action"] == "back" else page.reload()
        except Exception as e:
            print(f"live input ignored: {e!r}"[:160], flush=True)


# ---------------- control (called from the API) ----------------
def start(pid):
    with _glock:
        cur = _live.get(pid)
        if cur and cur.state in ("starting", "live") and not cur.stopping:
            return cur
        live = Live(pid)
        _live[pid] = live
        live.thread.start()
        return live


def get(pid):
    return _live.get(pid)


def cancel(pid):
    cur = _live.get(pid)
    if cur:
        cur.stop()


def view_token(pid):
    tok = secrets.token_urlsafe(24)
    now = time.time()
    with _glock:
        for k in [k for k, (_, exp) in _tokens.items() if exp < now]:
            del _tokens[k]
        _tokens[tok] = (pid, now + VIEW_TOKEN_TTL)
    return tok


def redeem_view_token(tok, pid):
    with _glock:
        got = _tokens.pop(tok or "", None)
    return bool(got and got[0] == pid and got[1] > time.time())


def status(pid):
    cur = _live.get(pid)
    return {"state": cur.state if cur else "idle", "error": cur.error if cur else None}
