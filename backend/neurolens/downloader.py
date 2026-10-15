"""Downloads a YouTube / Instagram / TikTok / Facebook video into a caller-supplied temp folder.

Only those sites are allowed: this server fetches URLs on behalf of whoever can reach
it, so an open "fetch any URL" endpoint would let people probe the machine's network.
Two layers keep it closed: the link's host must be on the list below, and yt-dlp is limited to
those four sites' extractors, so its generic "fetch any page" extractor can never run."""

import os
from urllib.parse import urljoin, urlparse

import imageio_ffmpeg
import requests
import yt_dlp
from yt_dlp.utils import DownloadError

ALLOWED_HOSTS = {
    "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be",
    "instagram.com", "www.instagram.com",
    "tiktok.com", "www.tiktok.com", "m.tiktok.com", "vm.tiktok.com", "vt.tiktok.com", "tiktokv.com", "www.tiktokv.com",
    "facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com", "fb.watch",
}
ALLOWED_EXTRACTORS = [r"(?i)(.*\.)?(youtube|instagram|tiktok|facebook).*"]   # names look like "tiktok", "tiktok:user", "vm.tiktok"
BROWSER_UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
MAX_DURATION_SECONDS = 10 * 60
MAX_BYTES = 300 * 1024 * 1024


class LinkError(Exception):
    """A problem the user can act on; the message is safe to show as-is."""


def platform_of(url):
    """"youtube" | "instagram" | "tiktok" | "facebook" | "" for a link."""
    host = (urlparse(url or "").hostname or "").lower()
    for name, key in (("youtube", "youtu"), ("instagram", "instagram."), ("tiktok", "tiktok"), ("facebook", "facebook.")):
        if key in host:
            return name
    return "facebook" if host == "fb.watch" else ""


def validate_url(raw):
    url = (raw or "").strip()
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        raise LinkError("Paste a full link starting with https://")
    if parsed.hostname.lower() not in ALLOWED_HOSTS:
        raise LinkError("Only Instagram, YouTube, TikTok and Facebook links are supported")
    if parsed.username or parsed.password:
        raise LinkError("That link isn't valid")
    return url


def _is_redirect_link(parsed):
    """fb.watch and facebook.com/share/... are short links that yt-dlp has no extractor for; they are followed here instead."""
    host = (parsed.hostname or "").lower()
    return host == "fb.watch" or (host.endswith("facebook.com") and parsed.path.startswith("/share/"))


def resolve_short_link(url, max_hops=5):
    """Follows a short link one redirect at a time, and refuses to leave the allowed hosts at any hop (so a redirect can't be used to
    make this server fetch an internal address). Returns the final facebook.com address."""
    for _ in range(max_hops + 1):
        parsed = urlparse(url)
        if not _is_redirect_link(parsed):
            return url
        try:
            r = requests.get(url, allow_redirects=False, timeout=8, stream=True, headers={"User-Agent": BROWSER_UA})
            status, loc = r.status_code, r.headers.get("Location")
            r.close()
        except requests.RequestException:
            raise LinkError("Couldn't open that Facebook link. Open it in your browser and paste the full facebook.com address, or upload a screen recording.")
        if status in (301, 302, 303, 307, 308) and loc:
            nxt = urljoin(url, loc)
            p = urlparse(nxt)
            if p.scheme != "https" or (p.hostname or "").lower() not in ALLOWED_HOSTS or p.username or p.password:
                raise LinkError("That link redirects somewhere we can't open.")
            url = nxt
            continue
        break
    raise LinkError("Couldn't open that Facebook link. Open it in your browser and paste the full facebook.com address, or upload a screen recording.")


def _friendly(err):
    msg = str(err)
    low = msg.lower()
    if "tiktok" in low and any(k in low for k in ("unable to extract", "blocked", "ip address", "login", "private", "captcha", "rehydration", "status code", "not available", "unable to download")):
        return "TikTok wouldn't let us download this video from our server (it may be private, removed or blocking servers). Upload a screen recording instead."
    if "facebook" in low and any(k in low for k in ("cannot parse", "login", "private", "isn't available", "not available", "checkpoint", "rate", "unable to extract", "content isn't")):
        return "Facebook only lets us download public videos, and often blocks servers. Upload a screen recording instead."
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


def download(url, dest_dir, on_progress=None, cookiefile=None):
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
        "allowed_extractors": ALLOWED_EXTRACTORS,
    }
    if cookiefile:
        opts["cookiefile"] = cookiefile  # a logged-in session, so private-account reels this person can see download too
    url = resolve_short_link(url)
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
