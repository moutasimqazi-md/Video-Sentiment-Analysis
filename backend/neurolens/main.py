import re
import shutil
import tempfile
import threading
import time
import uuid
from pathlib import Path

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pydantic import BaseModel

from neurolens import analyzer, calibration, downloader, feed_api, logstore, monitor, monitorstore
from neurolens.analyzer import analyze_video

FRONTEND_DIR = Path(__file__).resolve().parents[2] / "frontend"

app = FastAPI(title="Video Sentiment Analyzer")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

VIDEO_EXTENSIONS = {".mp4", ".mov", ".avi", ".mkv", ".webm"}
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png", ".webp"}
ALLOWED_EXTENSIONS = VIDEO_EXTENSIONS | IMAGE_EXTENSIONS
MAX_UPLOAD_BYTES = 300 * 1024 * 1024  # 300 MB
JOB_TTL_SECONDS = 30 * 60
TEMP_PREFIX = "vsa_"  # everything this app writes to the temp dir starts with this

GENERIC_ERROR = "We couldn't analyze that video. Please try a different one."

JOBS = {}
JOBS_LOCK = threading.Lock()
ANALYSIS_SLOT = threading.Semaphore(1)  # one CPU-heavy analysis at a time; the rest queue


class LinkRequest(BaseModel):
    url: str


class FeedbackRequest(BaseModel):
    rating: str  # "good" | "bad"
    corrected_mood: str | None = None
    note: str | None = None


def _sweep_temp():
    """Remove leftovers from a run that was killed mid-analysis, so no video outlives its job."""
    for p in Path(tempfile.gettempdir()).glob(f"{TEMP_PREFIX}*"):
        if p.is_dir():
            shutil.rmtree(p, ignore_errors=True)
        else:
            p.unlink(missing_ok=True)


@app.on_event("startup")
def start_warm_up():
    _sweep_temp()
    logstore.init_db()
    monitorstore.init()
    monitorstore.abort_stale_scans()
    monitor.start()

    def run():
        try:
            analyzer.warm_up()
            print("models warmed up", flush=True)
        except Exception as e:
            print(f"warm-up failed (will load on first request): {e}", flush=True)

    threading.Thread(target=run, daemon=True).start()


def _prune_jobs():
    cutoff = time.time() - JOB_TTL_SECONDS
    with JOBS_LOCK:
        for jid in [j for j, v in JOBS.items() if v["created"] < cutoff]:
            del JOBS[jid]


def _update(job_id, **fields):
    with JOBS_LOCK:
        JOBS[job_id].update(fields)


def _start_job(target, arg):
    _prune_jobs()
    job_id = uuid.uuid4().hex
    with JOBS_LOCK:
        JOBS[job_id] = {
            "status": "queued",
            "stage": "Queued",
            "progress": 0.0,
            "result": None,
            "error": None,
            "created": time.time(),
        }
    threading.Thread(target=target, args=(job_id, arg), daemon=True).start()
    return {"job_id": job_id}


def _analyze(job_id, video_path, lo=0.0, hi=1.0):
    if Path(video_path).suffix.lower() in IMAGE_EXTENSIONS:
        return analyzer.analyze_image(
            video_path, progress=lambda stage, frac: _update(job_id, stage=stage, progress=round(lo + (hi - lo) * frac, 3))
        )
    return analyze_video(
        video_path,
        progress=lambda stage, frac: _update(job_id, stage=stage, progress=round(lo + (hi - lo) * frac, 3)),
    )


def _finish(job_id, result, error, deleted, source):
    if error:
        _update(job_id, status="error", error=error, deleted=deleted)
        logstore.record(job_id, source=source, result=None, error=error)
        return

    embeddings = result.pop("_embeddings", None)
    thumbnail_jpg = result.pop("_thumbnail_jpg", None)
    keyframes = result.pop("_keyframes", None) or []
    result["keyframes"] = []
    for n, k in enumerate(keyframes):
        (logstore.KEY_DIR / f"{job_id}_{n}.jpg").write_bytes(k.pop("jpg"))
        k["url"] = f"api/keyframes/{job_id}/{n}.jpg"
        result["keyframes"].append(k)
    if result.get("audio", {}).get("embedding") is not None:
        result["audio"] = {k: v for k, v in result["audio"].items() if k != "embedding"}

    result["video_deleted"] = deleted
    result["source"] = source
    logstore.record(job_id, source=source, result=result, embeddings=embeddings, thumbnail_jpg=thumbnail_jpg, kind=result.get("kind", "video"))
    _update(job_id, status="done", stage="Done", progress=1.0, result=result, deleted=deleted)


def _run_file_job(job_id, tmp_path, source=None):
    result = error = None
    try:
        _update(job_id, stage="Waiting for the analyzer", progress=0.0)
        with ANALYSIS_SLOT:
            _update(job_id, status="running")
            result = _analyze(job_id, tmp_path)
    except Exception as e:
        print(f"analysis failed: {e!r}", flush=True)  # detail stays in the server log
        error = GENERIC_ERROR
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    _finish(job_id, result, error, not Path(tmp_path).exists(), source or {"kind": "upload"})


def _run_link_job(job_id, url, cookiefile=None):
    workdir = tempfile.mkdtemp(prefix=TEMP_PREFIX)
    source = {"kind": "link", "url": url}
    result = error = None
    try:
        _update(job_id, status="running", stage="Downloading video", progress=0.02)
        path, title = downloader.download(
            url,
            workdir,
            lambda f: _update(job_id, stage="Downloading video", progress=round(0.02 + 0.18 * f, 3)),
            cookiefile=cookiefile,
        )
        source["title"] = title
        _update(job_id, stage="Waiting for the analyzer", progress=0.2)
        with ANALYSIS_SLOT:
            result = _analyze(job_id, path, lo=0.2, hi=1.0)
    except downloader.LinkError as e:
        error = str(e)
    except Exception as e:
        print(f"analysis failed: {e!r}", flush=True)  # detail stays in the server log
        error = GENERIC_ERROR
    finally:
        shutil.rmtree(workdir, ignore_errors=True)  # the downloaded video is always removed
    _finish(job_id, result, error, not Path(workdir).exists(), source)


@app.post("/api/analyze")
async def analyze(file: UploadFile = File(...)):
    suffix = Path(file.filename or "").suffix.lower()
    if suffix not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, f"Unsupported file type: {suffix or 'unknown'}")

    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, prefix=TEMP_PREFIX, suffix=suffix) as tmp:
            tmp_path = tmp.name
            size = 0
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(400, "File too large (max 300MB)")
                tmp.write(chunk)
    except HTTPException:
        if tmp_path:
            Path(tmp_path).unlink(missing_ok=True)
        raise
    except Exception as e:
        if tmp_path:
            Path(tmp_path).unlink(missing_ok=True)
        print(f"upload failed: {e!r}", flush=True)
        raise HTTPException(500, "Upload failed. Please try again.")

    return _start_job(_run_file_job, tmp_path)


@app.post("/api/analyze-link")
def analyze_link(req: LinkRequest):
    try:
        url = downloader.validate_url(req.url)
    except downloader.LinkError as e:
        raise HTTPException(400, str(e))
    return _start_job(_run_link_job, url)


@app.get("/api/jobs/{job_id}")
def job_status(job_id: str):
    with JOBS_LOCK:
        job = JOBS.get(job_id)
        if job is None:
            raise HTTPException(404, "Unknown or expired job")
        return {k: v for k, v in job.items() if k not in ("created", "started")}


@app.post("/api/feedback/{job_id}")
def submit_feedback(job_id: str, req: FeedbackRequest):
    if req.rating not in ("good", "bad"):
        raise HTTPException(400, "rating must be 'good' or 'bad'")
    if req.corrected_mood and req.corrected_mood not in analyzer.CATEGORY_PROMPTS:
        raise HTTPException(400, f"Unknown mood: {req.corrected_mood}")
    try:
        logstore.set_feedback(job_id, req.rating, req.corrected_mood, req.note)
    except KeyError:
        raise HTTPException(404, "Unknown job_id — nothing was logged for it (maybe it errored?)")
    threading.Thread(target=calibration.rebuild, args=(list(analyzer.CATEGORY_PROMPTS),), daemon=True).start()
    return {"ok": True}


@app.get("/api/feedback/stats")
def feedback_stats():
    return logstore.stats()


@app.get("/api/feedback/recent")
def feedback_recent(limit: int = 50):
    return logstore.list_recent(min(limit, 200))


THUMB_NAME = re.compile(r"^[0-9a-f]{32}$")


@app.get("/api/thumbnails/{job_id}.jpg")
def thumbnail(job_id: str):
    """The preview frame saved for an analysis (the video itself is long gone). Ids are unguessable uuids."""
    if not THUMB_NAME.match(job_id):
        raise HTTPException(404, "Not found")
    path = logstore.THUMB_DIR / f"{job_id}.jpg"
    if not path.is_file():
        raise HTTPException(404, "Not found")
    return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=86400, immutable"})


@app.get("/api/keyframes/{job_id}/{n}.jpg")
def keyframe(job_id: str, n: int):
    """Evidence frames saved with an analysis."""
    if not THUMB_NAME.match(job_id) or not 0 <= n < 12:
        raise HTTPException(404, "Not found")
    path = logstore.KEY_DIR / f"{job_id}_{n}.jpg"
    if not path.is_file():
        raise HTTPException(404, "Not found")
    return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "public, max-age=86400, immutable"})


@app.get("/api/model/info")
def model_info():
    c = calibration.info()
    return {"learning": c["active"], "rated_examples": c["examples"]}


app.include_router(feed_api.router)


# Registered last so the /api routes win; serves index.html at "/" and pages/*.html, css/, js/, assets/.
app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")
