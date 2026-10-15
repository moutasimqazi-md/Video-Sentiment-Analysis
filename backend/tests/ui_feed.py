"""The website's Feed check page, driven in real Chrome against the real server and local stand-ins for the four sites.

    python tests/ui_feed.py        (from the backend folder; needs Chrome; a few minutes: it signs in and scans on every site)"""
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import requests
from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from tests.fake_sites import Fake  # noqa: E402

PORT = 8012
B = f"http://127.0.0.1:{PORT}"
SITES = {"ig": "Instagram", "yt": "YouTube", "tt": "TikTok", "fb": "Facebook"}
KINDS = {"ig": ["Explore", "For You reels", "Search topics", "Account review"], "yt": ["Home recommendations", "Watch history", "Search topics"], "tt": ["For You", "Explore", "Search topics"], "fb": ["Watch feed", "Reels", "Search topics"]}
results, errors = [], []


def check(name, ok, info=""):
    results.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + name + (f"   [{info}]" if info and not ok else ""), flush=True)


def main():
    fake = Fake().start()
    data = tempfile.mkdtemp(prefix="nl_ui_")
    env = {**os.environ, **fake.env(), "NL_DATA_DIR": data, "NL_LIVE_HEADLESS": "1", "PYTHONIOENCODING": "utf-8"}
    log = open(os.path.join(data, "server.log"), "w")
    srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "neurolens.main:app", "--host", "127.0.0.1", "--port", str(PORT)], env=env, stdout=log, stderr=log, cwd=str(Path(__file__).resolve().parents[1]))
    try:
        for _ in range(120):
            try:
                if requests.get(B + "/api/model/info", timeout=3).ok:
                    break
            except requests.RequestException:
                time.sleep(1)
        api_modes = {p["id"]: [m["label"] for m in p["modes"]] for p in requests.get(B + "/api/platforms").json()}
        with sync_playwright() as p:
            b = p.chromium.launch(headless=True, channel="chrome")
            ctx = b.new_context(viewport={"width": 1280, "height": 900})
            page = ctx.new_page()
            page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.on("dialog", lambda d: d.accept())
            page.goto(B + "/pages/feed.html"); page.wait_for_selector("#siteBar .site-chip")
            check("page: four site buttons, Instagram first and selected", page.locator(".site-chip").count() == 4 and page.get_attribute('[data-site="ig"]', "aria-pressed") == "true")
            check("page: Instagram heading", "an Instagram feed" in page.inner_text("#feedTitle"))
            for code, name in SITES.items():
                page.click(f'[data-site="{code}"]')
                page.wait_for_function(f"document.querySelector('[data-site={code}]').getAttribute('aria-pressed')==='true'")
                check(f"{name}: heading and sign-in text follow the site", name in page.inner_text("#feedTitle") and f"Sign in to {name}" in page.inner_text("#connHead"), page.inner_text("#feedTitle"))
                labels = page.eval_on_selector_all("#kinds .kind b", "els => els.map(e => e.textContent)")
                check(f"{name}: shows exactly the checks the server offers for it", labels == KINDS[code] and labels == api_modes[code], (labels, api_modes[code]))
                body = page.evaluate("[...document.querySelectorAll('#feedApp > :not(#siteBar)')].map((e) => e.innerText).join(' ')")  # everything except the picker, which lists all four on purpose
                check(f"{name}: no other site's name leaks into the page", not any(o in body for o in SITES.values() if o != name), [o for o in SITES.values() if o != name and o in body])
                if code == "yt":
                    check("YouTube: warns that Google may refuse the sign-in", "Google" in page.inner_text("#siteNote"))
            page.click('[data-site="ig"]')

            # ---- sign in and check, on every site
            for code, name in SITES.items():
                page.click(f'[data-site="{code}"]'); page.wait_for_function(f"document.querySelector('[data-site={code}]').getAttribute('aria-pressed')==='true'")
                page.click("#loginBtn")
                try:
                    page.wait_for_selector("#scanCard:not([hidden])", timeout=60000)
                    ok = True
                except Exception:
                    ok = False
                check(f"{name}: signs in through the private browser in the page", ok and f"{name} connected" in page.inner_text("#sessText"), page.inner_text("#sessText") if ok else "timed out")
                if not ok:
                    continue
                page.check('#kinds input[type="radio"] >> nth=0')
                page.select_option("#limitSel", "6")
                page.click("#scanBtn")
                try:
                    page.wait_for_selector("#reportBox:not([hidden])", timeout=240000)
                    done = True
                except Exception:
                    done = False
                head = page.inner_text("#repHead") if done else ""
                check(f"{name}: a check produces a report that names the site", done and name in head, head or page.inner_text("#scanErr"))
                if done:
                    check(f"{name}: the report lists what was checked, with links back to {name}", page.locator("#repItems .feed-item").count() >= 2 and f"Open on {name}" in page.inner_text("#repItems"))
                    check(f"{name}: the earlier-checks list shows it", page.locator("#pastList .past-row").count() >= 1)
                check(f"{name}: sign-in stays separate (other sites still ask)", all(requests.get(f"{B}/api/sessions/me?platform={o}").json()["connected"] is None for o in SITES if o not in [c for c in list(SITES)[: list(SITES).index(code) + 1]]))

            # ---- disconnect one
            page.click('[data-site="tt"]'); page.wait_for_selector("#scanCard:not([hidden])")
            page.click("#logoutBtn"); page.wait_for_selector("#stageConnect:not([hidden])", timeout=15000)
            check("disconnect: TikTok asks to sign in again", page.is_visible("#loginBtn"))
            page.click('[data-site="fb"]'); page.wait_for_selector("#scanCard:not([hidden])", timeout=15000)
            check("disconnect: Facebook is still connected", "Facebook connected" in page.inner_text("#sessText"))

            # ---- a child on TikTok
            page.evaluate("""() => { NL.store.set('children', [{id: 'kid1', name: 'Sam'}]); }""")
            page.goto(B + "/pages/feed.html?profile=kid1&platform=tt"); page.wait_for_selector("#siteBar .site-chip")
            check("child: opens on the TikTok tab from the link", page.get_attribute('[data-site="tt"]', "aria-pressed") == "true" and page.is_visible("#childBox"))
            check("child: the consent line names the site", "TikTok" in page.inner_text("#childBox"), page.inner_text("#childBox")[:120])
            check("child: cannot sign in until the child's consent is ticked", page.is_disabled("#loginBtn"))
            page.check("#consentBox"); page.click("#loginBtn")
            page.wait_for_selector("#scanCard:not([hidden])", timeout=60000)
            page.click("#scanBtn"); page.wait_for_selector("#reportBox:not([hidden])", timeout=240000)
            page.wait_for_selector("#alertsCard:not([hidden])", timeout=20000)
            al = page.inner_text("#alertList")
            check("child: the alert says which site it is about", "TikTok" in al, al[:200])
            href = page.get_attribute("#alertList a", "href")
            check("child: the alert link returns to that site's tab", "platform=tt" in href and "profile=kid1" in href, href)
            page.click('[data-site="fb"]')
            page.wait_for_function("document.querySelector('[data-site=fb]').getAttribute('aria-pressed')==='true'")
            page.wait_for_selector("#stageConnect:not([hidden])", timeout=15000)  # the page asks the server about this site before it draws
            check("child: Facebook for the same child is a separate sign-in", page.is_visible("#loginBtn"))
            page.click('[data-site="tt"]'); page.wait_for_selector("#scanCard:not([hidden])")
            page.check("#monOn"); page.click("#monSave")
            page.wait_for_selector("#monBadge:not([hidden])", timeout=15000)
            ms = requests.get(B + "/api/monitors").json()
            check("child: monitoring is saved for TikTok only", [m["platform"] for m in ms if m["profile_id"] == "kid1" and m["enabled"]] == ["tt"], ms)
            ctx.close()

            # ---- phone
            ctx = b.new_context(viewport={"width": 390, "height": 844}); ph = ctx.new_page()
            ph.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
            ph.goto(B + "/pages/feed.html"); ph.wait_for_selector("#siteBar .site-chip")
            sw = ph.evaluate("[document.documentElement.scrollWidth, innerWidth]")
            check("phone: no sideways scrolling, all four buttons reachable", sw[0] <= sw[1] + 1 and ph.locator(".site-chip").count() == 4, sw)
            ph.screenshot(path=os.path.join(os.environ.get("SHOTS", tempfile.gettempdir()), "feed_phone.png"))
            ctx.close(); b.close()
        bad = [e for e in errors if "favicon" not in e and "fonts.g" not in e and "ERR_" not in e]
        check("no JavaScript errors", not bad, bad[:3])
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
