"""End-to-end test of the multi-site feed check through the real HTTP API.

Starts the real server (uvicorn) against local stand-ins for Instagram, YouTube, TikTok and Facebook, then signs in, scans, monitors a
child, raises alerts and checks accounts and plan limits, all over HTTP, like the website and the mobile app do.

    python tests/e2e_feed.py            (from the backend folder; needs Chrome; takes several minutes the first time: it loads the models)"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

import requests

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests.fake_sites import Fake  # noqa: E402

PORT = 8011
B = f"http://127.0.0.1:{PORT}"
SITES = {"ig": "Instagram", "yt": "YouTube", "tt": "TikTok", "fb": "Facebook"}
results = []


def check(name, ok, info=""):
    results.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + name + (f"   [{info}]" if info and not ok else ""), flush=True)


def wait(fn, timeout=120, every=1.0):
    end = time.time() + timeout
    while time.time() < end:
        try:
            v = fn()
        except requests.RequestException:
            v = None  # the server is still starting
        if v:
            return v
        time.sleep(every)
    return None


def call(method, path, token=None, **kw):
    h = {"X-User-Token": token} if token else {}
    return requests.request(method, B + path, headers=h, timeout=60, **kw)


def sign_in(profile, site, token=None, expect=True):
    r = call("POST", f"/api/sessions/{profile}/login?platform={site}", token)
    if not expect:
        return r
    assert r.status_code == 200, (site, r.status_code, r.text)
    got = wait(lambda: (call("GET", f"/api/sessions/{profile}?platform={site}", token).json().get("connected")), 90)
    return got


def scan(profile, site, kind, token=None, terms=None, limit=4):
    r = call("POST", "/api/scans", token, json={"profile": profile, "platform": site, "kind": kind, "terms": terms or [], "limit": limit})
    if r.status_code != 200:
        return r.status_code, r.json().get("detail")
    sid = r.json()["id"]
    s = wait(lambda: (lambda x: x if x["status"] != "running" else None)(call("GET", f"/api/scans/{sid}", token).json()), 240, 2)
    return 200, s


def main():
    fake = Fake().start()
    data = tempfile.mkdtemp(prefix="nl_e2e_")
    env = {**os.environ, **fake.env(), "NL_DATA_DIR": data, "NL_LIVE_HEADLESS": "1", "NL_PAYMENTS": "demo", "PYTHONIOENCODING": "utf-8"}
    log = open(os.path.join(data, "server.log"), "w")
    srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "neurolens.main:app", "--host", "127.0.0.1", "--port", str(PORT)], env=env, stdout=log, stderr=log, cwd=str(Path(__file__).resolve().parents[1]))
    try:
        if not wait(lambda: requests.get(B + "/api/model/info", timeout=3).ok, 120, 1):
            print("server did not start; log:\n" + open(os.path.join(data, "server.log")).read()[-1500:])
            return 1
        print("server up; models warming ...", flush=True)

        # ---- the list of sites
        r = call("GET", "/api/platforms").json()
        check("platforms: four sites with their own checks", [p["id"] for p in r] == ["ig", "yt", "tt", "fb"] and all(p["modes"] for p in r), r)
        modes = {p["id"]: {m["id"] for m in p["modes"]} for p in r}
        check("platforms: only Instagram offers an account review; only YouTube offers watch history", "profile" in modes["ig"] and not any("profile" in modes[c] for c in ("yt", "tt", "fb")) and "history" in modes["yt"] and "history" not in modes["tt"])

        # ---- sessions: each site separate; Instagram works with no platform given (older apps)
        st = call("GET", "/api/sessions/me").json()
        check("sessions: no platform given means Instagram, as before", st["platform"] == "ig" and st["connected"] is None, st)
        check("sessions: unknown site is refused", call("GET", "/api/sessions/me?platform=myspace").status_code == 400)
        for site in SITES:
            at = sign_in("me", site)
            check(f"sign-in: {SITES[site]} connects through the private browser", bool(at), at)
        c = {s: call("GET", f"/api/sessions/me?platform={s}").json()["connected"] for s in SITES}
        check("sign-in: all four sessions exist side by side", all(c.values()), c)

        # ---- scans on every site and every check
        want = {"ig": ["explore", "foryou", "terms", "profile"], "yt": ["foryou", "history", "terms"], "tt": ["foryou", "explore", "terms"], "fb": ["foryou", "explore", "terms"]}
        for site, kinds in want.items():
            for kind in kinds:
                code, s = scan("me", site, kind, terms=["python tutorial", "ai"] if kind == "terms" else None, limit=4)
                if (site, kind) == ("ig", "foryou"):  # Instagram's reel viewer gives links only (no thumbnails to fall back on), and the stand-in can't be downloaded
                    ok = code == 200 and s and s["status"] == "done" and len(s["items"]) >= 2
                else:
                    ok = code == 200 and s and s["status"] == "done" and s["summary"]["analyzed"] >= 2
                check(f"scan: {SITES[site]} / {kind} finds, analyses and summarises videos", ok, (code, s and (s["status"], s.get("error"), s.get("summary"))) if not ok else "")
                if code == 200 and s:
                    check(f"scan: {SITES[site]} / {kind} is labelled with its site", s.get("platform") == site, s.get("platform"))
        code, s = scan("me", "ig", "profile", limit=3)
        check("scan: Instagram account review still reports the account name", code == 200 and s["summary"].get("username") == "tester", s and s.get("summary"))

        # ---- refusals
        code, detail = scan("me", "yt", "profile")
        check("scan: YouTube has no account review (clear message)", code == 400 and "YouTube" in detail, (code, detail))
        code, detail = scan("me", "tt", "history")
        check("scan: TikTok has no watch history (clear message)", code == 400 and "TikTok" in detail, (code, detail))
        code, detail = scan("nobody", "fb", "foryou")
        check("scan: a site that isn't signed in says so by name", code == 400 and "Log in to Facebook" in detail, (code, detail))

        # ---- the history lists them all, or one site
        allscans = call("GET", "/api/scans?profile=me").json()
        check("history: all of a profile's sites appear together, newest first", {s["platform"] for s in allscans} == set(SITES) and allscans == sorted(allscans, key=lambda x: -x["createdAt"]), {s["platform"] for s in allscans})
        tts = call("GET", "/api/scans?profile=me&platform=tt").json()
        check("history: one site's can be asked for on its own", tts and all(s["platform"] == "tt" for s in tts))
        check("history: every scan reports the plain profile id", all(s["profile"] == "me" for s in allscans))

        # ---- a child, on two sites, with consent
        r = call("PUT", "/api/monitors/kid1", json={"name": "Sam", "enabled": False, "consent": True, "platform": "tt", "interval_min": 120}).json()
        check("monitor: a child's TikTok monitor is created and labelled", r["platform"] == "tt" and r["profile_id"] == "kid1" and r["consent"], r)
        call("PUT", "/api/monitors/kid1", json={"name": "Sam", "enabled": False, "consent": True, "platform": "fb", "interval_min": 120})
        ms = [m for m in call("GET", "/api/monitors").json() if m["profile_id"] == "kid1"]
        check("monitor: the same child on two sites is two monitors with one profile id", sorted(m["platform"] for m in ms) == ["fb", "tt"], ms)
        r = call("POST", "/api/sessions/kid2/login?platform=tt")
        check("child: signing in needs that child's consent first", r.status_code == 400 and "child" in r.json()["detail"].lower(), r.text)
        check("child: signs in on TikTok", bool(sign_in("kid1", "tt")))
        code, s = scan("kid1", "tt", "foryou", limit=4)
        check("child: a TikTok scan runs and is tied to the child", code == 200 and s["status"] == "done" and s["profile"] == "kid1" and s["platform"] == "tt", (code, s and s.get("error")))
        al = call("GET", "/api/alerts?profile=kid1").json()
        check("alerts: every one of the child's alerts carries the site", al["alerts"] and all(a["platform"] == "tt" and a["profile"] == "kid1" for a in al["alerts"]), al["alerts"][:1])
        check("alerts: the summary names the site and links back to that site's tab", any(a["kind"] == "digest" and "TikTok" in a["title"] and "platform=tt" in (a["link"] or "") and "profile=kid1" in a["link"] for a in al["alerts"]), [(a["kind"], a["title"], a["link"]) for a in al["alerts"]][:3])
        only_fb = call("GET", "/api/alerts?profile=kid1&platform=fb").json()
        check("alerts: asking for another site gives only that site's", only_fb["alerts"] == [])
        check("child: the other site is not signed in just because one is", call("GET", "/api/sessions/kid1?platform=fb").json()["connected"] is None)

        # ---- disconnect one site
        check("disconnect: TikTok", call("DELETE", "/api/sessions/me?platform=tt").status_code == 200)
        now = {s: call("GET", f"/api/sessions/me?platform={s}").json()["connected"] for s in SITES}
        check("disconnect: only TikTok went", now["tt"] is None and all(now[s] for s in ("ig", "yt", "fb")), now)

        # ---- accounts: sessions and limits per user
        email = f"e2e_{uuid.uuid4().hex[:8]}@example.com"
        tok = call("POST", "/api/auth/signup", json={"name": "E2E", "email": email, "password": "Sm0ke-Test-pass!"}).json()["token"]
        check("account: a user sees none of the owner's sessions", call("GET", "/api/sessions/me?platform=yt", tok).json()["connected"] is None)
        check("account: a user signs in to YouTube in their own space", bool(sign_in("me", "yt", tok)))
        mine = call("GET", "/api/sessions/me?platform=yt", tok).json()
        check("account: ...and only they have it", mine["connected"] and call("GET", "/api/sessions/me?platform=yt").json()["connected"] is not None)
        r = call("PUT", "/api/monitors/kid1", tok, json={"name": "Sam", "enabled": False, "consent": True, "platform": "tt"})
        check("plan: the free plan has no child profiles on any site", r.status_code == 402, r.text)
        call("POST", "/api/me/subscribe", tok, json={"plan": "pro", "cycle": "monthly"})
        for kid in ("a1", "a2", "a3"):
            call("PUT", f"/api/monitors/{kid}", tok, json={"name": kid, "enabled": False, "consent": True, "platform": "tt"})
        call("PUT", "/api/monitors/a1", tok, json={"name": "a1", "enabled": False, "consent": True, "platform": "fb"})
        me = call("GET", "/api/me", tok).json()
        check("plan: a child on two sites counts as one child", me["childrenUsed"] == 3, me["childrenUsed"])
        r = call("PUT", "/api/monitors/a4", tok, json={"name": "a4", "enabled": False, "consent": True, "platform": "yt"})
        check("plan: a fourth child is refused", r.status_code == 402, r.text)
        r = call("PUT", "/api/monitors/a2", tok, json={"name": "a2", "enabled": False, "consent": True, "platform": "yt"})
        check("plan: an existing child can still get another site", r.status_code == 200, r.text)
        sess_before = [d.name for d in Path(data, "sessions").iterdir()]
        check("account: the user's session folders are namespaced", any(n.startswith("u") and n.endswith(".yt") for n in sess_before), sess_before)
        r = call("POST", "/api/me/delete", tok, json={"password": "Sm0ke-Test-pass!"})
        sess_after = [d.name for d in Path(data, "sessions").iterdir()]
        check("account: deleting the account removes every site's session for that user", r.status_code == 200 and not any(n.startswith(f"u{me['userId']}-") for n in sess_after), sess_after)
        check("account: the owner's sessions are untouched by that", {"me", "me.yt", "me.fb"} <= set(sess_after), sess_after)
    finally:
        srv.terminate()
        try:
            srv.wait(10)
        except Exception:
            srv.kill()
        log.close()
        fake.stop()
        shutil.rmtree(data, ignore_errors=True)
    print(f"\n{sum(results)}/{len(results)} passed")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
