"""Downloads a YouTube / Instagram video into a caller-supplied temp folder.

Only those sites are allowed: this server fetches URLs on behalf of whoever can reach
it, so an open "fetch any URL" endpoint would let people probe the machine's network."""

import os
from urllib.parse import urlparse

import imageio_ffmpeg
import yt_dlp
from yt_dlp.utils import DownloadError

ALLOWED_HOSTS = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
    "instagram.com", "www.instagram.com",
}
MAX_DURATION_SECONDS = 10 * 60
MAX_BYTES = 300 * 1024 * 1024


class LinkError(Exception):
    """A problem the user can act on; the message is safe to show as-is."""


def validate_url(raw):
    url = (raw or "").strip()
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise LinkError("Paste a full link starting with https://")
    if parsed.hostname.lower() not in ALLOWED_HOSTS:
        raise LinkError("Only YouTube and Instagram links are supported")
    if parsed.username or parsed.password:
        raise LinkError("That link isn't valid")
    return url


def _friendly(err):
    msg = str(err)
    low = msg.lower()
    if "instagram" in low and any(k in low for k in ("login", "cookies", "empty media", "rate-limit", "private")):
        return "Instagram wouldn't let us download this reel (it may be private or need a login). Upload the file instead."
    if "sign in to confirm" in low or "not a bot" in low:
        return "YouTube blocked the download from this network. Upload the file instead."
    if "private video" in low or "members-only" in low:
        return "That video is private or members-only."
    if "requested format is not available" in low:
        return "Couldn't find a downloadable version of that video. Upload the file instead."
    if "video unavailable" in low or "has been removed" in low:
        return "That video is unavailable."
    if "file is larger than" in low:
        return "That video is too large (limit 300 MB)."
    return "Couldn't download that link: " + msg.replace("ERROR: ", "")[:200]


def download(url, dest_dir, on_progress=None):
    """Download to dest_dir. Returns (file_path, title)."""

    def hook(d):
        if on_progress and d.get("status") == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            if total:
                on_progress(min(d.get("downloaded_bytes", 0) / total, 1.0))

    opts = {
        "outtmpl": os.path.join(dest_dir, "video.%(ext)s"),
        # Small is fine (frames are shrunk to 224px anyway). YouTube serves video and audio
        # separately, so they're merged with the bundled ffmpeg; Instagram is usually one file.
        "format": "bv*[height<=480]+ba/b[height<=480]/bv*+ba/b",
        "merge_output_format": "mkv",
        "ffmpeg_location": imageio_ffmpeg.get_ffmpeg_exe(),
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "max_filesize": MAX_BYTES,
        "socket_timeout": 20,
        "retries": 2,
        "cachedir": False,
        "progress_hooks": [hook],
        "js_runtimes": {"node": {}},
    }
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(url, download=False)
            if info.get("_type") == "playlist":
                entries = [e for e in (info.get("entries") or []) if e]
                if not entries:
                    raise LinkError("No video found at that link")
                info = entries[0]  # e.g. an Instagram carousel: analyse the first item
            duration = info.get("duration")
            if duration and duration > MAX_DURATION_SECONDS:
                raise LinkError(f"That video is {int(duration // 60)} min long; the limit is {MAX_DURATION_SECONDS // 60} min")
            ydl.process_ie_result(info, download=True)
    except DownloadError as e:
        raise LinkError(_friendly(e)) from e

    files = [f for f in os.listdir(dest_dir) if f.startswith("video.") and not f.endswith((".part", ".ytdl"))]
    if not files:
        raise LinkError("Download finished but no video file was produced")
    return os.path.join(dest_dir, files[0]), info.get("title") or "Linked video"
