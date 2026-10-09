"""Runs one feed check: reads the logged-in account's pages, analyzes what it finds with the same engine as everything else,
writes a short report, and (for child monitoring) raises alerts for anything that needs a look."""

import shutil
import tempfile
import threading
import time
import uuid
from pathlib import Path

import requests

from neurolens import alerts, browser, logstore, monitorstore, wellbeing

KINDS = {"foryou": "For You reels", "explore": "Explore", "terms": "Search topics", "profile": "Account review"}
MAX_ITEMS = 24
SCAN_SLOT = threading.Semaphore(1)  # one browser session at a time on this machine


def _name(pid):
    m = monitorstore.get_monitor(pid)
    return (m and m.get("name")) or ("you" if pid == "me" else pid)


def _fetch_thumb(url, workdir):
    r = requests.get(url, timeout=15, headers={"User-Agent": "Mozilla/5.0"})
    r.raise_for_status()
    if len(r.content) > 8 * 1024 * 1024 or not r.headers.get("content-type", "").startswith("image/"):
        raise ValueError("not an image")
    path = Path(workdir) / f"{uuid.uuid4().hex}.jpg"
    path.write_bytes(r.content)
    return str(path)


def _analyze_item(app, it, workdir, cookiefile):
    """Returns (job_id, result|None). Reels are downloaded; image posts, and reels that can't be fetched, fall back to the preview image."""
    cached = logstore.get_cached(it["url"])
    if cached:
        return cached["job_id"], cached["result"]
    job_id = uuid.uuid4().hex
    with app.JOBS_LOCK:
        app.JOBS[job_id] = {"status": "queued", "stage": "Queued", "progress": 0.0, "result": None, "error": None, "created": time.time()}
    source = {"kind": "link", "url": it["url"]}
    if it["kind"] == "reel":
        app._run_link_job(job_id, it["url"], cookiefile)
        job = app.JOBS.get(job_id) or {}
        if job.get("status") == "done":
            return job_id, job["result"]
        with app.JOBS_LOCK:  # the failed attempt is logged under this id; use a fresh one for the fallback
            app.JOBS.pop(job_id, None)
        job_id = uuid.uuid4().hex
        with app.JOBS_LOCK:
            app.JOBS[job_id] = {"status": "queued", "stage": "Queued", "progress": 0.0, "result": None, "error": None, "created": time.time()}
    if it.get("thumb"):
        try:
            path = _fetch_thumb(it["thumb"], workdir)
            app._run_file_job(job_id, path, source)
            job = app.JOBS.get(job_id) or {}
            if job.get("status") == "done":
                return job_id, job["result"]
        except Exception as e:
            print(f"preview fallback failed: {e!r}", flush=True)
    return job_id, None


def summarize(kind, items):
    ok = [i for i in items if i.get("ok")]
    n = len(ok)
    moods = {}
    levels = {"calm": 0, "watch": 0, "high": 0}
    flagged = []
    for i in ok:
        moods[i["mood"]] = moods.get(i["mood"], 0) + 1
        levels[i["level"]] += 1
        if i["level"] != "calm" or i.get("safety") == "review":
            flagged.append(i["jobId"])
    mix = sorted(([m, round(100 * c / n)] for m, c in moods.items()), key=lambda x: -x[1]) if n else []
    heavy = round(100 * (levels["watch"] + levels["high"]) / n) if n else 0
    lines = []
    if n:
        lines.append(f"Checked {n} {'item' if n == 1 else 'items'}. The most common feeling is {mix[0][0]} ({mix[0][1]}%)" + (f", then {mix[1][0]} ({mix[1][1]}%)." if len(mix) > 1 else "."))
        lines.append(f"{heavy}% carried a heavier emotional tone." if heavy else "Nothing carried a heavy emotional tone.")
        rev = sum(1 for i in ok if i.get("safety") == "review")
        if rev:
            lines.append(f"{rev} {'item was' if rev == 1 else 'items were'} flagged for revealing or suggestive content. Worth a look.")
    out = {"analyzed": n, "failed": len(items) - n, "moods": mix, "heavyShare": heavy, "levels": levels, "flagged": flagged, "lines": lines}
    if kind == "profile" and n:
        top = mix[0][1]
        obs = []
        obs.append(f"Your account has a clear theme: {mix[0][0]}." if top >= 50 else "Your posts cover a mix of moods, with no single theme dominating.")
        if heavy >= 30:
            obs.append("A good share of your posts read as heavy in tone. If that's intentional, great. If not, lighter posts can balance the feel of the account.")
        if len([m for m in mix if m[1] >= 10]) <= 2:
            obs.append("Variety is low. Mixing in a second kind of content can widen who the account speaks to.")
        out["review"] = obs
    return out


def run(scan_id, pid, kind, params):
    from neurolens import main as app  # imported late: main imports this module's siblings

    store = monitorstore
    workdir = tempfile.mkdtemp(prefix=app.TEMP_PREFIX)
    cookiefile = str(Path(workdir) / "cookies.txt")
    items = []
    try:
        store.update_scan(scan_id, stage="Waiting for the browser", progress=0.02)
        with SCAN_SLOT:
            store.update_scan(scan_id, stage="Opening Instagram", progress=0.05)
            limit = max(1, min(int(params.get("limit") or 10), MAX_ITEMS))
            found = browser.collect(pid, kind, limit=limit, terms=params.get("terms"), cookie_out=cookiefile)
        username = None
        if found and found[0].get("username"):
            username = found[0]["username"]
            found = found[1:]
        urls = {}
        for it in found:
            urls.setdefault(logstore.url_key(it["url"]) or it["url"], it)
        keys = list(urls)
        if params.get("new_only"):
            fresh = set(store.unseen(pid, keys))
            keys = [k for k in keys if k in fresh]
        todo = [urls[k] for k in keys][:limit]
        store.update_scan(scan_id, stage=f"Found {len(todo)} to check", progress=0.1)
        for n, it in enumerate(todo, 1):
            store.update_scan(scan_id, stage=f"Checking {n} of {len(todo)}", progress=round(0.1 + 0.85 * (n - 1) / max(1, len(todo)), 3))
            rec = {"url": it["url"], "kind": it["kind"], "source": it.get("source"), "ok": False}
            try:
                job_id, result = _analyze_item(app, it, workdir, cookiefile)
                rec["jobId"] = job_id
                if result:
                    a = wellbeing.assess(result)
                    sf = (result.get("safety") or {}).get("level", "clear")
                    rec.update(ok=True, mood=result["dominant_mood"], level=a["level"], safety=sf, conf=(result.get("confidence") or {}).get("level"),
                               title=(result.get("source") or {}).get("title"), kind=result.get("kind", it["kind"]))
                    if params.get("alerts"):
                        alerts.for_item(pid, scan_id, rec, a)
            except Exception as e:
                print(f"scan item failed: {e!r}", flush=True)
            logstore_key = logstore.url_key(it["url"])
            if logstore_key:
                store.mark_seen(pid, logstore_key)
            items.append(rec)
            store.update_scan(scan_id, items=items)
        summary = summarize(kind, items)
        if username:
            summary["username"] = username
        store.update_scan(scan_id, status="done", stage="Done", progress=1.0, finished_at=time.time(), items=items, summary=summary)
        if params.get("alerts"):
            alerts.digest(pid, scan_id, summary)
        m = store.get_monitor(pid)
        if m:
            store.save_monitor(pid, last_scan=time.time(), status="ok", status_at=time.time())
    except browser.SessionExpired:
        store.update_scan(scan_id, status="error", stage="Login needed", finished_at=time.time(), error="The Instagram session has expired. Log in again.", items=items)
        m = store.get_monitor(pid)
        if m:
            store.save_monitor(pid, status="needs_login", status_at=time.time(), connected_at=None)
            alerts.needs_login(pid)
    except Exception as e:
        print(f"scan failed: {e!r}", flush=True)
        store.update_scan(scan_id, status="error", stage="Failed", finished_at=time.time(), error="The scan couldn't finish. Please try again.", items=items)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)  # the session cookies and any downloaded media never outlive the scan


def start(pid, kind, params):
    sid = monitorstore.new_scan(pid, kind, params)
    threading.Thread(target=run, args=(sid, pid, kind, params), daemon=True).start()
    return sid
