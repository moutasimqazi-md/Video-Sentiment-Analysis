"""Logs every analysis (scores + a thumbnail + raw embeddings) and lets the
viewer mark a guess as good/bad. This is the "data maker": once enough runs
are marked, the (embedding, correct_label) pairs can train a small classifier
that beats the current zero-shot prompts — see logstore.export_training_set().

Nothing here leaves the machine; it's a local SQLite file plus small files on disk.
"""

import json
import re
import sqlite3
import threading
import time
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).resolve().parents[1] / "data"
DB_PATH = DATA_DIR / "analysis_log.db"
THUMB_DIR = DATA_DIR / "thumbnails"
EMBED_DIR = DATA_DIR / "embeddings"
KEY_DIR = DATA_DIR / "keyframes"

_lock = threading.Lock()  # sqlite3 connections aren't shared across threads; serialize instead


def resolve(kind, name):
    """Absolute path of a saved file. `name` may be a bare file name (current format) or a legacy absolute path."""
    if not name:
        return None
    base = {"thumb": THUMB_DIR, "embed": EMBED_DIR}[kind]
    return base / Path(str(name).replace("\\", "/")).name


def _migrate_paths(con):
    """Older rows stored absolute paths (e.g. an old project folder). Keep only the file name."""
    for col in ("thumbnail_path", "visual_embedding_path", "audio_embedding_path"):
        for job_id, val in con.execute(f"SELECT job_id, {col} FROM analyses WHERE {col} IS NOT NULL").fetchall():
            name = Path(str(val).replace("\\", "/")).name
            if name != val:
                con.execute(f"UPDATE analyses SET {col}=? WHERE job_id=?", (name, job_id))


NEW_COLUMNS = {
    "kind": "TEXT",               # video | image
    "embedding_model": "TEXT",    # which backbone produced the saved embeddings (they are only comparable within one model)
    "result_json": "TEXT",        # the full result returned to the app, so the same link never needs analyzing twice
    "url_key": "TEXT",            # normalized source link (video id / shortcode) for cache lookups
    "safety_max": "REAL",         # highest visual-safety score, for quick filtering
}


def url_key(url):
    """Stable identity for a media link: YouTube video id, Instagram shortcode, or the URL without query/fragment."""
    if not url:
        return None
    m = re.search(r"(?:youtube\.com/(?:watch\?v=|shorts/|embed/)|youtu\.be/)([A-Za-z0-9_-]{11})", url)
    if m:
        return "yt:" + m.group(1)
    m = re.search(r"instagram\.com/(?:[^/]+/)?(?:reel|reels|p|tv)/([A-Za-z0-9_-]+)", url)
    if m:
        return "ig:" + m.group(1)
    return re.sub(r"[?#].*$", "", url.strip().lower()).rstrip("/")


def _add_columns(con):
    have = {r[1] for r in con.execute("PRAGMA table_info(analyses)")}
    for col, typ in NEW_COLUMNS.items():
        if col not in have:
            con.execute(f"ALTER TABLE analyses ADD COLUMN {col} {typ}")
    con.execute("CREATE INDEX IF NOT EXISTS idx_analyses_urlkey ON analyses(url_key)")


def _conn():
    con = sqlite3.connect(DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def init_db():
    DATA_DIR.mkdir(exist_ok=True)
    THUMB_DIR.mkdir(exist_ok=True)
    EMBED_DIR.mkdir(exist_ok=True)
    KEY_DIR.mkdir(exist_ok=True)
    with _lock, _conn() as con:
        con.execute(
            """
            CREATE TABLE IF NOT EXISTS analyses (
                job_id TEXT PRIMARY KEY,
                created_at REAL,
                source_kind TEXT,
                source_title TEXT,
                source_url TEXT,
                duration_seconds REAL,
                frames_analyzed INTEGER,
                audio_available INTEGER,
                dominant_mood TEXT,
                averages_json TEXT,
                visual_averages_json TEXT,
                audio_averages_json TEXT,
                verdict TEXT,
                error TEXT,
                thumbnail_path TEXT,
                visual_embedding_path TEXT,
                audio_embedding_path TEXT,
                feedback TEXT,
                corrected_mood TEXT,
                feedback_note TEXT,
                feedback_at REAL
            )
            """
        )
        _migrate_paths(con)
        _add_columns(con)
        for job_id, url in con.execute("SELECT job_id, source_url FROM analyses WHERE url_key IS NULL AND source_url IS NOT NULL").fetchall():
            con.execute("UPDATE analyses SET url_key=? WHERE job_id=?", (url_key(url), job_id))


def record(job_id, source, result, embeddings=None, thumbnail_jpg=None, error=None, embedding_model=None, kind="video"):
    """Called once per finished job, success or failure. `result` must already have
    any internal-only keys (embeddings, thumbnail) popped out by the caller."""
    thumb_path = None
    if thumbnail_jpg:
        thumb_path = THUMB_DIR / f"{job_id}.jpg"
        thumb_path.write_bytes(thumbnail_jpg)

    visual_path = audio_path = None
    if embeddings:
        if embeddings.get("visual") is not None:
            visual_path = EMBED_DIR / f"{job_id}_visual.npy"
            np.save(visual_path, np.asarray(embeddings["visual"], dtype=np.float32))
        if embeddings.get("audio") is not None:
            audio_path = EMBED_DIR / f"{job_id}_audio.npy"
            np.save(audio_path, np.asarray(embeddings["audio"], dtype=np.float32))

    r = result or {}
    audio = r.get("audio") or {}
    src = source or {}
    with _lock, _conn() as con:
        con.execute(
            """
            INSERT OR REPLACE INTO analyses (
                job_id, created_at, source_kind, source_title, source_url,
                duration_seconds, frames_analyzed, audio_available, dominant_mood,
                averages_json, visual_averages_json, audio_averages_json, verdict, error,
                thumbnail_path, visual_embedding_path, audio_embedding_path,
                kind, embedding_model, result_json, url_key, safety_max
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """,
            (
                job_id, time.time(), src.get("kind"), src.get("title"), src.get("url"),
                r.get("duration_seconds"), r.get("frames_analyzed"), int(bool(audio.get("available"))),
                r.get("dominant_mood"),
                json.dumps(r.get("averages")) if r.get("averages") else None,
                json.dumps(r.get("visual_averages")) if r.get("visual_averages") else None,
                json.dumps(audio.get("averages")) if audio.get("averages") else None,
                r.get("verdict"), error,
                thumb_path.name if thumb_path else None,
                visual_path.name if visual_path else None,
                audio_path.name if audio_path else None,
                kind, embedding_model,
                json.dumps(r) if r and not error else None,
                url_key(src.get("url")),
                ((r.get("safety") or {}).get("max_score") if r else None),
            ),
        )


def set_feedback(job_id, rating, corrected_mood=None, note=None):
    if rating not in ("good", "bad"):
        raise ValueError("rating must be 'good' or 'bad'")
    with _lock, _conn() as con:
        cur = con.execute(
            "UPDATE analyses SET feedback=?, corrected_mood=?, feedback_note=?, feedback_at=? WHERE job_id=?",
            (rating, corrected_mood, note, time.time(), job_id),
        )
        if cur.rowcount == 0:
            raise KeyError(job_id)


def stats():
    with _lock, _conn() as con:
        row = con.execute(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN feedback IS NOT NULL THEN 1 ELSE 0 END) AS rated,
                SUM(CASE WHEN feedback = 'good' THEN 1 ELSE 0 END) AS good,
                SUM(CASE WHEN feedback = 'bad' THEN 1 ELSE 0 END) AS bad,
                SUM(CASE WHEN visual_embedding_path IS NOT NULL THEN 1 ELSE 0 END) AS with_embeddings
            FROM analyses WHERE error IS NULL
            """
        ).fetchone()
        by_mood = con.execute(
            "SELECT dominant_mood, COUNT(*) AS n FROM analyses WHERE error IS NULL GROUP BY dominant_mood ORDER BY n DESC"
        ).fetchall()
    return {
        "total": row["total"] or 0,
        "rated": row["rated"] or 0,
        "good": row["good"] or 0,
        "bad": row["bad"] or 0,
        "with_embeddings": row["with_embeddings"] or 0,
        "by_dominant_mood": {r["dominant_mood"]: r["n"] for r in by_mood if r["dominant_mood"]},
    }


def list_recent(limit=50):
    with _lock, _conn() as con:
        rows = con.execute(
            """
            SELECT job_id, created_at, source_kind, source_title, dominant_mood, verdict,
                   feedback, corrected_mood, feedback_note, error
            FROM analyses ORDER BY created_at DESC LIMIT ?
            """,
            (limit,),
        ).fetchall()
    return [dict(r) for r in rows]


def export_training_set():
    """Rows with feedback and a saved visual embedding: the (X, y) pairs a linear
    probe would train on. 'good' -> label is dominant_mood; 'bad' with a
    corrected_mood -> label is corrected_mood. 'bad' with no correction is skipped
    (we know it's wrong but not what it should be)."""
    with _lock, _conn() as con:
        rows = con.execute(
            """
            SELECT job_id, dominant_mood, feedback, corrected_mood, visual_embedding_path, audio_embedding_path
            FROM analyses
            WHERE feedback IS NOT NULL AND visual_embedding_path IS NOT NULL
            """
        ).fetchall()

    examples = []
    for r in rows:
        label = r["dominant_mood"] if r["feedback"] == "good" else r["corrected_mood"]
        if not label:
            continue
        examples.append(
            {
                "job_id": r["job_id"],
                "label": label,
                "visual_embedding_path": str(resolve("embed", r["visual_embedding_path"])),
                "audio_embedding_path": str(resolve("embed", r["audio_embedding_path"])) if r["audio_embedding_path"] else None,
            }
        )
    return examples


def get_cached(url, max_age_days=60):
    """The newest successful result for this link (so imports and repeat analyses are instant), or None."""
    key = url_key(url)
    if not key:
        return None
    with _lock, _conn() as con:
        row = con.execute(
            "SELECT job_id, result_json, created_at, feedback, corrected_mood FROM analyses WHERE url_key=? AND error IS NULL AND result_json IS NOT NULL "
            "AND created_at > ? ORDER BY created_at DESC LIMIT 1",
            (key, time.time() - max_age_days * 86400),
        ).fetchone()
    if not row:
        return None
    result = json.loads(row["result_json"])
    return {"job_id": row["job_id"], "result": result, "created_at": row["created_at"]}


def get_result(job_id):
    with _lock, _conn() as con:
        row = con.execute("SELECT result_json FROM analyses WHERE job_id=? AND result_json IS NOT NULL", (job_id,)).fetchone()
    return json.loads(row["result_json"]) if row else None
