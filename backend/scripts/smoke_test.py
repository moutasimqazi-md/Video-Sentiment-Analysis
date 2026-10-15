"""End-to-end check of a running server, local or deployed.

    python scripts/smoke_test.py http://127.0.0.1:8000
    python scripts/smoke_test.py https://your-domain.example --deployed
    python scripts/smoke_test.py https://your-domain.example --deployed --no-analyze     # skip the model run

--deployed also checks that the owner-only routes are closed to the public. A throwaway account is made and deleted again.
Needs requests; the analysis step also needs opencv and numpy (the backend's own environment has them)."""

import argparse
import sys
import tempfile
import time
import uuid
from pathlib import Path

import requests

PAGES = ["/", "/pages/feed.html", "/pages/account.html", "/pages/checkout.html", "/pages/login.html", "/pages/pricing.html", "/pages/privacy.html", "/pages/report.html"]
PUBLIC_GETS = ["/api/model/info", "/api/plans", "/api/feedback/stats", "/api/owner/state"]

results = []


def check(name, ok, info=""):
    results.append(bool(ok))
    print(("PASS  " if ok else "FAIL  ") + name + (f"   [{info}]" if info and not ok else ""))


def make_video():
    import cv2
    import numpy as np

    path = Path(tempfile.gettempdir()) / "nl_smoke.mp4"
    w = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), 24, (320, 240))
    for i in range(24 * 6):
        f = np.zeros((240, 320, 3), np.uint8)
        f[:] = ((i * 3) % 255, (i * 5) % 255, 120)
        cv2.circle(f, (160, 120), 20 + i % 40, (255, 255, 255), -1)
        w.write(f)
    w.release()
    return path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base")
    ap.add_argument("--deployed", action="store_true", help="expect the owner-only routes to be closed to this caller")
    ap.add_argument("--no-analyze", action="store_true")
    a = ap.parse_args()
    base = a.base.rstrip("/")
    s = requests.Session()
    s.headers["ngrok-skip-browser-warning"] = "1"

    def get(p, **kw):
        return s.get(base + p, timeout=60, **kw)

    for p in PAGES:
        r = get(p)
        check(f"page {p}", r.status_code == 200, r.status_code)
    for p in PUBLIC_GETS:
        r = get(p)
        check(f"GET {p}", r.status_code == 200, f"{r.status_code} {r.text[:80]}")
    check("unknown job is a 404", get("/api/jobs/nope").status_code == 404)

    if a.deployed:
        r = get("/api/owner/state")
        check("owner routes closed to the public", r.status_code == 200 and r.json().get("ok") is False, r.text[:80])
        check("analysis list is owner only", get("/api/feedback/recent").status_code == 401)
        check("owner-only route is refused", get("/api/owner/check").status_code == 401)
        check("monitors are refused without a user", get("/api/monitors").status_code == 401)

    email, pw = f"smoke_{uuid.uuid4().hex[:8]}@example.com", "Sm0ke-Test-pass!"
    r = s.post(base + "/api/auth/signup", json={"name": "Smoke", "email": email, "password": pw}, timeout=60)
    check("signup", r.status_code == 200, f"{r.status_code} {r.text[:100]}")
    if r.status_code != 200:
        return finish()
    H = {"X-User-Token": r.json()["token"]}
    check("GET /api/me", s.get(base + "/api/me", headers=H, timeout=60).status_code == 200)
    check("wrong password is refused", s.post(base + "/api/auth/login", json={"email": email, "password": "x"}, timeout=60).status_code == 401)
    check("user can list monitors", s.get(base + "/api/monitors", headers=H, timeout=60).status_code == 200)
    r = s.get(base + "/api/push/key", headers=H, timeout=60)
    check("user gets the push key", r.status_code == 200 and r.json().get("key"), f"{r.status_code} {r.text[:80]}")

    if not a.no_analyze:
        with open(make_video(), "rb") as fh:
            r = s.post(base + "/api/analyze", files={"file": ("smoke.mp4", fh, "video/mp4")}, headers=H, timeout=300)
        check("upload accepted", r.status_code == 200, f"{r.status_code} {r.text[:100]}")
        if r.status_code == 200:
            jid, st = r.json()["job_id"], {}
            for _ in range(150):  # up to 5 minutes: the first run on a fresh host also downloads the models
                st = s.get(f"{base}/api/jobs/{jid}", timeout=60).json()
                if st.get("status") in ("done", "error"):
                    break
                time.sleep(2)
            check("analysis finished", st.get("status") == "done", f"{st.get('status')} {st.get('error')}")
            if st.get("status") == "done":
                check("results readable", s.get(f"{base}/api/results/{jid}", timeout=60).status_code == 200)
                check("thumbnail served", s.get(f"{base}/api/thumbnails/{jid}.jpg", timeout=60).status_code == 200)

    r = s.post(base + "/api/me/delete", headers=H, json={"password": pw}, timeout=60)
    check("throwaway account deleted", r.status_code == 200, f"{r.status_code} {r.text[:100]}")
    finish()


def finish():
    print(f"\n{sum(results)}/{len(results)} passed")
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
