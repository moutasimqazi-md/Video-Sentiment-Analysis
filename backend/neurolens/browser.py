"""Reads Instagram, YouTube, TikTok or Facebook as a logged-in account through a private Chrome profile (Playwright, one folder per
person and site; see platforms.py for the session key).

You sign in yourself, inside the isolated browser shown in the page (see live.py); NeuroLens never sees or stores your
password, only the browser's own session folder (data/sessions/<session key>/). Scans are slow and small on purpose, and read
what the site serves that account: recommendations, Explore, search pages, the account's own profile grid, or (YouTube) the watch
history. Apart from YouTube's history they cannot see what was actually watched."""

import os
import random
import re
import shutil
import threading
import time
from pathlib import Path
from urllib.parse import quote

from neurolens import logstore, platforms

SESS_DIR = logstore.DATA_DIR / "sessions"
BASE = platforms.base("ig")  # Instagram's address (kept for older callers); other sites: platforms.base(code)
PID_OK = re.compile(r"^[a-z0-9_-]{1,60}(\.(ig|yt|tt|fb))?$")

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


plat_of = platforms.plat_of


def _has_session(ctx, code="ig"):
    return platforms.has_session(code, ctx.cookies(platforms.base(code)))


# ---------------- session folder ----------------
def connected_at(pid):
    f = _dir(pid) / "connected"
    return int(f.read_text()) if f.exists() else None


def disconnect(pid):
    with _lock(pid):
        shutil.rmtree(_dir(pid), ignore_errors=True)


def import_session(pid, cookies):
    """Sign-in done on the person's own phone: put those cookies into this profile's private Chrome and check they work.
    Only the site's own cookies are kept; the password was never sent here. `pid` is a session key (see platforms.py)."""
    from playwright.sync_api import sync_playwright

    code = plat_of(pid)
    site = platforms.name(code)
    default_domain = "." + platforms.PLATFORMS[code]["cookie_domains"][0]
    clean = []
    for c in cookies[:80]:
        name, value = str(c.get("name", ""))[:100], str(c.get("value", ""))[:4000]
        domain = str(c.get("domain") or default_domain).lower()
        if not name or not value or not platforms.cookie_domain_ok(code, domain):
            continue
        item = {"name": name, "value": value, "domain": domain, "path": str(c.get("path") or "/"), "secure": True,
                "httpOnly": bool(c.get("httpOnly"))}
        exp = c.get("expires")
        # A phone's cookie jar hands over name and value only. Without an expiry Chrome treats the cookie as session-only and drops it
        # when the profile closes, which would silently log the account out again, so give it a long life like Instagram's own.
        item["expires"] = float(exp) if isinstance(exp, (int, float)) and exp > time.time() else time.time() + 180 * 86400
        clean.append(item)
    if not platforms.has_session(code, clean):
        raise ValueError(f"{site} sign-in wasn't completed.")
    with _lock(pid), sync_playwright() as p:
        ctx = _launch(p, pid, True)
        try:
            ctx.add_cookies(clean)
            ok = _has_session(ctx, code)
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            page.wait_for_timeout(800)
        finally:
            ctx.close()
    if not ok:
        raise ValueError(f"{site} sign-in wasn't completed.")
    at = int(time.time())
    (_dir(pid) / "connected").write_text(str(at))
    try:
        _write_cookies([{**c, "secure": True} for c in clean], _dir(pid) / "cookies.txt", code)  # lets link downloads use this sign-in too
    except Exception:
        pass
    return at


def session_cookies_to(pid, dest):
    """Copies this profile's sign-in to `dest` in the format the downloader reads. Returns False when not connected."""
    if connected_at(pid) is None:
        return False
    src = _dir(pid) / "cookies.txt"
    if not src.exists():  # a sign-in made in the private browser: read the cookies out of the profile once
        from playwright.sync_api import sync_playwright

        code = plat_of(pid)
        with _lock(pid), sync_playwright() as p:
            ctx = _launch(p, pid, True)
            try:
                cookies = ctx.cookies(platforms.base(code))
            finally:
                ctx.close()
        if not platforms.has_session(code, cookies):
            return False
        _write_cookies(cookies, src, code)
    shutil.copyfile(src, dest)
    return True


# ---------------- reading ----------------
class SessionExpired(Exception):
    pass


def _norm(href, code="ig"):
    return platforms.item(code, href)


def _pause(lo=1.4, hi=3.2):
    time.sleep(random.uniform(lo, hi))


def _check_login(page, code="ig"):
    if platforms.is_login_url(code, page.url):
        raise SessionExpired()


def _grid(page, scrolls, code="ig"):
    sel = platforms.PLATFORMS[code]["selector"]
    seen, out = set(), []
    for _ in range(scrolls):
        for a in page.query_selector_all(sel):
            it = _norm(a.get_attribute("href"), code)
            if it and it["url"] not in seen:
                img = a.query_selector("img")
                it["thumb"] = (img.evaluate("e => e.currentSrc || e.src") or None) if img else None  # absolute URL
                seen.add(it["url"])
                out.append(it)
        page.mouse.wheel(0, 900)
        _pause()
    return out


def collect(pid, mode, limit=12, terms=None, cookie_out=None):
    """mode: one of the site's modes (platforms.PLATFORMS[code]["modes"]): "explore" | "foryou" | "terms" | "profile" | "history".
    Returns a list of {url, kind, thumb, source}. `pid` is a session key. If cookie_out is a path, the session cookies are written
    there (Netscape format) so the downloader can fetch private videos."""
    from playwright.sync_api import sync_playwright

    code = plat_of(pid)
    P = platforms.PLATFORMS[code]
    base = platforms.base(code)
    if mode not in P["modes"]:
        raise ValueError(f"{P['name']} has no '{mode}' check")
    items = []
    with _lock(pid), sync_playwright() as p:
        ctx = _launch(p, pid, True)
        try:
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            if code == "ig":
                items = _collect_instagram(page, base, mode, limit, terms)
            elif mode == "terms":
                for term in (terms or [])[:5]:
                    q = re.sub(r"\s+", " ", (term or "").strip().lstrip("#"))[:60]
                    if not q:
                        continue
                    page.goto(base + P["paths"]["terms"].format(q=quote(q)), wait_until="domcontentloaded")
                    _pause(2, 3.5)
                    _check_login(page, code)
                    for it in _grid(page, 2, code)[: max(3, limit // max(1, len(terms)))]:
                        it["source"] = f"\u201c{q}\u201d"
                        items.append(it)
            else:  # foryou | explore | history: open the page and read the videos it lists
                page.goto(base + P["paths"][mode], wait_until="domcontentloaded")
                _pause(2.5, 4)
                _check_login(page, code)
                for it in _grid(page, 3 if limit <= 12 else 5, code)[:limit]:
                    it["source"] = P["modes"][mode]
                    items.append(it)
            if cookie_out:
                _write_cookies(ctx.cookies(base), cookie_out, code)
        finally:
            ctx.close()
    return items


def _collect_instagram(page, base, mode, limit, terms):
    items = []
    if mode == "foryou":
        page.goto(f"{base}/reels/", wait_until="domcontentloaded")
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
            page.goto(f"{base}/explore/tags/{tag}/", wait_until="domcontentloaded")
            _pause(2, 3.5)
            _check_login(page)
            for it in _grid(page, 2)[: max(3, limit // max(1, len(terms)))]:
                it["source"] = f"#{tag}"
                items.append(it)
    elif mode == "profile":
        page.goto(f"{base}/accounts/edit/", wait_until="domcontentloaded")
        _pause(2, 3)
        _check_login(page)
        u = page.query_selector('input[name="username"]')
        username = (u.input_value() if u else "") or ""
        if not username:
            raise SessionExpired()
        page.goto(f"{base}/{username}/", wait_until="domcontentloaded")
        _pause(2, 3.5)
        for it in _grid(page, 3)[:limit]:
            it["source"] = "Your profile"
            items.append(it)
        items.insert(0, {"username": username, "url": None})  # first row carries the username, stripped by the caller
    else:  # explore
        page.goto(f"{base}/explore/", wait_until="domcontentloaded")
        _pause(2.5, 4)
        _check_login(page)
        for it in _grid(page, 3)[:limit]:
            it["source"] = "Explore"
            items.append(it)
    return items


def _write_cookies(cookies, path, code="ig"):
    lines = ["# Netscape HTTP Cookie File"]
    suffixes = platforms.PLATFORMS[code]["cookie_domains"]
    for c in cookies:
        dom = c["domain"]
        if not dom.startswith(".") and dom.endswith(suffixes):
            dom = "." + dom.lstrip(".")
        lines.append("\t".join([dom, "TRUE" if dom.startswith(".") else "FALSE", c.get("path", "/"), "TRUE" if c.get("secure") else "FALSE",
                                str(int(c.get("expires", 0) or 0)), c["name"], c["value"]]))
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
