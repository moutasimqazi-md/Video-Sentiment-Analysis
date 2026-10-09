"""Reads Instagram as a logged-in account through a private Chrome profile (Playwright, one folder per person).

You sign in yourself, inside the isolated browser shown in the page (see live.py); NeuroLens never sees or stores your
password, only the browser's own session folder (data/sessions/<profile>/). Scans are slow and small on purpose, and read
what Instagram serves that account: the For You reels, Explore, tag pages, or the account's own profile grid. They cannot
see what was actually watched."""

import os
import random
import re
import shutil
import threading
import time
from pathlib import Path

from neurolens import logstore

SESS_DIR = logstore.DATA_DIR / "sessions"
BASE = os.environ.get("NL_IG_BASE", "https://www.instagram.com").rstrip("/")
PID_OK = re.compile(r"^[a-z0-9_-]{1,40}$")
ITEM = re.compile(r"/(reel|reels|p)/([A-Za-z0-9_-]{5,})")

_profile_locks = {}


def _lock(pid):
    return _profile_locks.setdefault(pid, threading.Lock())


def _dir(pid):
    if not PID_OK.match(pid):
        raise ValueError("bad profile id")
    d = SESS_DIR / pid
    d.mkdir(parents=True, exist_ok=True)
    return d


def launch(p, pid, headless, viewport=None, scale=1):
    """Real Chrome with its own private profile. The automation banner flags are off, so the browser reports itself like a normal
    one (Instagram's bot checks loop forever on browsers that announce they are automated). A visible-mode browser is placed
    off-screen, so it never appears on the desktop."""
    args = ["--disable-blink-features=AutomationControlled", "--no-first-run", "--no-default-browser-check"]
    if not headless:
        args.append("--window-position=-32000,-32000")
    return p.chromium.launch_persistent_context(
        str(_dir(pid) / "chrome"), channel="chrome", headless=headless, viewport=viewport or {"width": 430, "height": 900},
        device_scale_factor=scale, locale="en-US", args=args, ignore_default_args=["--enable-automation"],
    )


def _launch(p, pid, headless):
    return launch(p, pid, headless)


def _has_session(ctx):
    return any(c["name"] == "sessionid" and c.get("value") for c in ctx.cookies(BASE))


# ---------------- session folder ----------------
def connected_at(pid):
    f = _dir(pid) / "connected"
    return int(f.read_text()) if f.exists() else None


def disconnect(pid):
    with _lock(pid):
        shutil.rmtree(_dir(pid), ignore_errors=True)


# ---------------- reading ----------------
class SessionExpired(Exception):
    pass


def _norm(href):
    m = ITEM.search(href or "")
    if not m:
        return None
    kind = "post" if m.group(1) == "p" else "reel"
    return {"url": f"{BASE}/{'p' if kind == 'post' else 'reel'}/{m.group(2)}/", "kind": kind}


def _pause(lo=1.4, hi=3.2):
    time.sleep(random.uniform(lo, hi))


def _check_login(page):
    if "/accounts/login" in page.url or "/challenge" in page.url:
        raise SessionExpired()


def _grid(page, scrolls):
    seen, out = set(), []
    for _ in range(scrolls):
        for a in page.query_selector_all('a[href*="/reel/"], a[href*="/p/"], a[href*="/reels/"]'):
            it = _norm(a.get_attribute("href"))
            if it and it["url"] not in seen:
                img = a.query_selector("img")
                it["thumb"] = (img.evaluate("e => e.currentSrc || e.src") or None) if img else None  # absolute URL
                seen.add(it["url"])
                out.append(it)
        page.mouse.wheel(0, 900)
        _pause()
    return out


def collect(pid, mode, limit=12, terms=None, cookie_out=None):
    """mode: "explore" | "foryou" | "terms" | "profile". Returns a list of {url, kind, thumb, source}.
    If cookie_out is a path, the session cookies are written there (Netscape format) so the downloader can fetch private reels."""
    from playwright.sync_api import sync_playwright

    items = []
    with _lock(pid), sync_playwright() as p:
        ctx = _launch(p, pid, True)
        try:
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            if mode == "foryou":
                page.goto(f"{BASE}/reels/", wait_until="domcontentloaded")
                _pause(2.5, 4)
                _check_login(page)
                seen = set()
                for _ in range(limit + 4):
                    it = _norm(page.url)
                    if it and it["url"] not in seen:
                        seen.add(it["url"])
                        it["source"] = "For You"
                        items.append(it)
                    if len(items) >= limit:
                        break
                    page.keyboard.press("ArrowDown")
                    _pause(2.0, 3.5)
            elif mode == "terms":
                for term in (terms or [])[:5]:
                    tag = re.sub(r"[^\w]", "", term.lower().lstrip("#"), flags=re.UNICODE)
                    if not tag:
                        continue
                    page.goto(f"{BASE}/explore/tags/{tag}/", wait_until="domcontentloaded")
                    _pause(2, 3.5)
                    _check_login(page)
                    for it in _grid(page, 2)[: max(3, limit // max(1, len(terms)))]:
                        it["source"] = f"#{tag}"
                        items.append(it)
            elif mode == "profile":
                page.goto(f"{BASE}/accounts/edit/", wait_until="domcontentloaded")
                _pause(2, 3)
                _check_login(page)
                u = page.query_selector('input[name="username"]')
                username = (u.input_value() if u else "") or ""
                if not username:
                    raise SessionExpired()
                page.goto(f"{BASE}/{username}/", wait_until="domcontentloaded")
                _pause(2, 3.5)
                for it in _grid(page, 3)[:limit]:
                    it["source"] = "Your profile"
                    items.append(it)
                items.insert(0, {"username": username, "url": None})  # first row carries the username, stripped by the caller
            else:  # explore
                page.goto(f"{BASE}/explore/", wait_until="domcontentloaded")
                _pause(2.5, 4)
                _check_login(page)
                for it in _grid(page, 3)[:limit]:
                    it["source"] = "Explore"
                    items.append(it)
            if cookie_out:
                _write_cookies(ctx.cookies(BASE), cookie_out)
        finally:
            ctx.close()
    return items


def _write_cookies(cookies, path):
    lines = ["# Netscape HTTP Cookie File"]
    for c in cookies:
        dom = c["domain"]
        lines.append("\t".join([dom, "TRUE" if dom.startswith(".") else "FALSE", c.get("path", "/"), "TRUE" if c.get("secure") else "FALSE",
                                str(int(c.get("expires", 0) or 0)), c["name"], c["value"]]))
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
