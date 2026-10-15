"""How the four sites the feed check can read differ: where their pages live, what "signed in" looks like, and which links on a page are
videos. Nothing else in the feed check knows about a particular site; it asks this module.

A person's session on a site is kept under one *session key*: the plain profile id for Instagram (so everything saved before other
sites existed keeps working) and `<profile>.<site>` for the others, e.g. `me.tt`. Profile ids can't contain a dot, so a key can never
collide with someone's profile. Monitors, scans, alerts, session folders and per-user prefixes all work on these keys unchanged.

Page addresses and selectors for YouTube, TikTok and Facebook are written from how those sites are laid out, not tested against live
accounts, and the sites change their pages often: expect to tune the `paths` and `item` rules below when one stops finding videos.
Tests point every site at a local stand-in through the NL_<SITE>_BASE variables."""

import os
import re
from urllib.parse import quote, urlparse

CODES = ("ig", "yt", "tt", "fb")


def _base(env, default):
    return os.environ.get(env, default).rstrip("/")


def _item_ig(href, base):
    m = re.search(r"/(reel|reels|p)/([A-Za-z0-9_-]{5,})", href or "")
    if not m:
        return None
    kind = "post" if m.group(1) == "p" else "reel"
    return {"url": f"{base}/{'p' if kind == 'post' else 'reel'}/{m.group(2)}/", "kind": kind}


def _item_yt(href, base):
    h = href or ""
    m = re.search(r"/watch\?(?:[^#]*&)?v=([A-Za-z0-9_-]{11})(?:[&#]|$)", h)
    if m:
        return {"url": f"{base}/watch?v={m.group(1)}", "kind": "reel"}
    m = re.search(r"/shorts/([A-Za-z0-9_-]{11})", h)
    return {"url": f"{base}/shorts/{m.group(1)}", "kind": "reel"} if m else None


def _item_tt(href, base):
    m = re.search(r"/@([\w.-]*)/video/(\d{8,})", href or "")
    return {"url": f"{base}/@{m.group(1)}/video/{m.group(2)}", "kind": "reel"} if m else None


def _item_fb(href, base):
    h = href or ""
    m = re.search(r"/reels?/(\d{6,})", h)
    if m:
        return {"url": f"{base}/reel/{m.group(1)}", "kind": "reel"}
    m = re.search(r"/watch/?\?(?:[^#]*&)?v=(\d{6,})", h) or re.search(r"/videos/(?:[^/?#]+/)?(\d{6,})", h)
    return {"url": f"{base}/watch/?v={m.group(1)}", "kind": "reel"} if m else None


def _login_ig(base, real):
    return f"{base}/accounts/login/"


def _login_yt(base, real):
    # Google refuses sign-in in browsers it thinks are automated, so this can be turned down at the sign-in step; nothing here can prevent that.
    return f"https://accounts.google.com/ServiceLogin?service=youtube&hl=en&continue={quote(base + '/', safe='')}" if real else f"{base}/signin"


def _login_tt(base, real):
    return f"{base}/login"


def _login_fb(base, real):
    return f"{base}/login/"


PLATFORMS = {
    "ig": {
        "name": "Instagram",
        "default_base": "https://www.instagram.com",
        "env": "NL_IG_BASE",
        "login": _login_ig,
        "session": [["sessionid"]],                      # every group needs one of its cookies
        "cookie_domains": ("instagram.com",),
        "hosts": ("instagram.com", "facebook.com", "fbcdn.net", "cdninstagram.com", "meta.com", "fb.com"),
        "pending": ("/challenge", "/accounts/login", "two_factor", "checkpoint", "/accounts/suspended"),
        "login_urls": ("/accounts/login", "/challenge"),
        "selector": 'a[href*="/reel/"], a[href*="/p/"], a[href*="/reels/"]',
        "item": _item_ig,
        "modes": {"explore": "Explore", "foryou": "For You reels", "terms": "Search topics", "profile": "Account review"},
        "paths": {"explore": "/explore/", "foryou": "/reels/", "terms": "/explore/tags/{q}/"},
        "monitor_mode": "explore",
    },
    "yt": {
        "name": "YouTube",
        "default_base": "https://www.youtube.com",
        "env": "NL_YT_BASE",
        "login": _login_yt,
        "session": [["SAPISID", "__Secure-3PAPISID", "__Secure-3PSID"]],
        "cookie_domains": ("youtube.com", "google.com"),
        "hosts": ("youtube.com", "google.com", "gstatic.com", "googleusercontent.com", "ytimg.com", "ggpht.com", "googleapis.com", "youtube-nocookie.com"),
        "pending": ("/signin/challenge", "/v3/signin/challenge", "/signin/v2/challenge", "/signin/rejected", "/ServiceLogin", "accounts.google.com", "/signin"),
        "login_urls": ("accounts.google.com", "/ServiceLogin", "/signin"),
        "selector": 'a[href*="/watch?v="], a[href*="/shorts/"]',
        "item": _item_yt,
        "modes": {"foryou": "Home recommendations", "history": "Watch history", "terms": "Search topics"},
        "paths": {"foryou": "/", "history": "/feed/history", "terms": "/results?search_query={q}"},
        "monitor_mode": "foryou",
    },
    "tt": {
        "name": "TikTok",
        "default_base": "https://www.tiktok.com",
        "env": "NL_TT_BASE",
        "login": _login_tt,
        "session": [["sessionid", "sid_tt"]],
        "cookie_domains": ("tiktok.com",),
        "hosts": ("tiktok.com", "tiktokcdn.com", "tiktokcdn-us.com", "tiktokv.com", "ttwstatic.com", "byteoversea.com", "ibytedtos.com", "muscdn.com"),
        "pending": ("/login", "/captcha", "/verify"),
        "login_urls": ("/login",),
        "selector": 'a[href*="/video/"]',
        "item": _item_tt,
        "modes": {"foryou": "For You", "explore": "Explore", "terms": "Search topics"},
        "paths": {"foryou": "/foryou", "explore": "/explore", "terms": "/search/video?q={q}"},
        "monitor_mode": "foryou",
    },
    "fb": {
        "name": "Facebook",
        "default_base": "https://www.facebook.com",
        "env": "NL_FB_BASE",
        "login": _login_fb,
        "session": [["c_user"], ["xs"]],
        "cookie_domains": ("facebook.com",),
        "hosts": ("facebook.com", "fbcdn.net", "fb.com", "meta.com", "fbsbx.com"),
        "pending": ("/login", "/checkpoint", "two_step_verification", "/recover"),
        "login_urls": ("/login", "/checkpoint"),
        "selector": 'a[href*="/reel/"], a[href*="/reels/"], a[href*="/watch/?v="], a[href*="/videos/"]',
        "item": _item_fb,
        "modes": {"foryou": "Watch feed", "explore": "Reels", "terms": "Search topics"},
        "paths": {"foryou": "/watch/", "explore": "/reel/", "terms": "/search/videos/?q={q}"},
        "monitor_mode": "foryou",
    },
}


def base(code):
    p = PLATFORMS[code]
    return _base(p["env"], p["default_base"])


def is_real(code):
    """True when pointed at the real site (tests point it at a local stand-in)."""
    return base(code) == PLATFORMS[code]["default_base"]


def login_url(code):
    return PLATFORMS[code]["login"](base(code), is_real(code))


def name(code):
    return PLATFORMS[code]["name"] if code in PLATFORMS else "Instagram"


def item(code, href):
    return PLATFORMS[code]["item"](href, base(code))


def host_ok(code, url):
    """Anything the sign-in browser may show: the site, its own helpers, and a blank page. Everything else is sent back to sign-in."""
    host = (urlparse(url).hostname or "").lower()
    own = (urlparse(base(code)).hostname or "").lower()
    return not host or url.startswith("about:") or host == own or any(host == h or host.endswith("." + h) for h in PLATFORMS[code]["hosts"])  # not a bare endswith: evilfacebook.com is not facebook.com


def has_session(code, cookies):
    """cookies: the browser's cookies for the site. Signed in when every cookie group has at least one real value."""
    have = {c["name"] for c in cookies if c.get("value")}
    return all(any(n in have for n in group) for group in PLATFORMS[code]["session"])


def cookie_domain_ok(code, domain):
    d = (domain or "").lower().lstrip(".")
    own = (urlparse(base(code)).hostname or "").lower()
    return d == own or any(d == s or d.endswith("." + s) for s in PLATFORMS[code]["cookie_domains"])


def is_login_url(code, url):
    return any(k in (url or "") for k in PLATFORMS[code]["login_urls"])


def is_pending_url(code, url):
    return any(k in (url or "") for k in PLATFORMS[code]["pending"])


# ---- session keys ----
def session_key(pid, code="ig"):
    return pid if code == "ig" else f"{pid}.{code}"


def split_key(sk):
    """session key -> (profile id, site code). A key with no site suffix is Instagram (everything saved before other sites existed)."""
    head, dot, tail = (sk or "").rpartition(".")
    return (head, tail) if dot and tail in CODES and head else (sk, "ig")


def plat_of(sk):
    return split_key(sk)[1]
