"""Owner-only protection for the endpoints that open Instagram sessions, run scans and read alerts.

The site is reachable from the internet (ngrok) and has no real accounts, so these routes are open only to the person at this
computer. A page opened on this computer (http://localhost:8000) needs nothing at all. Any other device (a phone, the public
ngrok address) connects once through a single-use link made on this computer, so nothing is ever typed or pasted."""

import hmac
import json
import secrets
import threading
import time
import urllib.request
from urllib.parse import urlparse

from fastapi import HTTPException, Request

from neurolens import logstore

TOKEN_FILE = logstore.DATA_DIR / "owner_token.txt"
LOCAL_HOSTS = {"localhost", "127.0.0.1", "[::1]"}
CODE_TTL = 10 * 60
MAX_BAD_REDEEMS = 10  # per minute, across everyone

_codes = {}  # single-use pairing code -> expiry
_bad = []  # timestamps of failed redeems
_lock = threading.Lock()


def token():
    logstore.DATA_DIR.mkdir(exist_ok=True)
    if not TOKEN_FILE.exists():
        TOKEN_FILE.write_text(secrets.token_urlsafe(24), encoding="utf-8")
    return TOKEN_FILE.read_text(encoding="utf-8").strip()


def is_local(request: Request):
    """True only for a request made on this machine itself: loopback client, and no proxy (ngrok) in between."""
    host = request.client.host if request.client else ""
    if host not in ("127.0.0.1", "::1", "localhost"):
        return False
    if any(h in request.headers for h in ("x-forwarded-for", "x-forwarded-host", "x-forwarded-proto", "forwarded")):
        return False
    origin = request.headers.get("origin")
    return origin is None or (urlparse(origin).hostname or "") in {h.strip("[]") for h in LOCAL_HOSTS}  # another website in this browser can't act as you


def require_owner(request: Request):
    if is_local(request):
        return True
    given = request.headers.get("x-owner-token", "")
    if given and hmac.compare_digest(given, token()):
        return True
    raise HTTPException(401, "Owner access required")


def new_code():
    code = secrets.token_urlsafe(18)
    with _lock:
        now = time.time()
        for c in [c for c, exp in _codes.items() if exp < now]:
            del _codes[c]
        _codes[code] = now + CODE_TTL
    return code


def redeem(code):
    """Returns the long-lived token if the single-use code is valid, else None."""
    now = time.time()
    with _lock:
        _bad[:] = [t for t in _bad if now - t < 60]
        if len(_bad) >= MAX_BAD_REDEEMS:
            raise HTTPException(429, "Too many tries. Wait a minute.")
        exp = _codes.pop(code or "", None)
        if exp is None or exp < now:
            _bad.append(now)
            return None
    return token()


def public_url():
    """The ngrok address of this server, read from ngrok's local API. None when no tunnel is running."""
    try:
        with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=1.5) as r:
            for t in json.loads(r.read()).get("tunnels", []):
                if t.get("public_url", "").startswith("https://"):
                    return t["public_url"]
    except Exception:
        pass
    return None
