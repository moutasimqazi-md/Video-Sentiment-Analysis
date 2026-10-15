"""Local stand-ins for Instagram, YouTube, TikTok and Facebook, for testing the feed check without real accounts.

One server, four sites under /ig, /yt, /tt and /fb. Each behaves the way the feed check relies on:
  - its login page signs you in (sets that site's session cookies) and sends you home, like a successful sign-in;
  - every other page sends a signed-out visitor to the login page, and so does a session that was expired with expire(site);
  - its feed, explore, search, history and profile pages list videos with that site's own link style and a thumbnail picture.
Point the app at it with NL_IG_BASE=http://127.0.0.1:<port>/ig (and _YT_, _TT_, _FB_).

These pages are written from how the real sites are laid out, so passing against them proves the app's own logic (sessions, scanning,
scoring, alerts, per-site separation), not that a real site's pages still match. See platforms.py."""

import io
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from PIL import Image

LOGIN = {"ig": "/accounts/login/", "yt": "/signin", "tt": "/login", "fb": "/login/"}
COOKIES = {"ig": ["sessionid=igsess1"], "yt": ["SAPISID=ytsess1", "__Secure-3PSID=ytsess2"], "tt": ["sessionid=ttsess1"], "fb": ["c_user=1001", "xs=fbsess1"]}
NEEDS = {"ig": ["sessionid"], "yt": ["SAPISID"], "tt": ["sessionid"], "fb": ["c_user", "xs"]}


def link(site, n, kind="video"):
    """The n-th video's link in the site's own style."""
    if site == "ig":
        return f"/{'p' if kind == 'post' else 'reel'}/CODE{n:04d}x/"
    if site == "yt":
        return f"/watch?v=ytvid{n:06d}"  # a YouTube id is 11 characters
    if site == "tt":
        return f"/@creator{n % 3}/video/71000000000{n:05d}"
    return [f"/reel/9000{n:05d}", f"/watch/?v=8000{n:05d}", f"/somepage/videos/7000{n:05d}"][n % 3]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="text/html; charset=utf-8", headers=()):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        m = re.match(r"^/(ig|yt|tt|fb)(/.*)?$", u.path)
        if u.path.startswith("/img/"):
            n = int(re.sub(r"\D", "", u.path) or 0)
            im = Image.new("RGB", (160, 160), ((n * 37) % 255, (n * 91) % 255, (n * 53) % 255))
            buf = io.BytesIO()
            im.save(buf, "JPEG")
            return self._send(200, buf.getvalue(), "image/jpeg")
        if not m:
            return self._send(404, b"not found")
        site, path = m.group(1), m.group(2) or "/"
        srv = self.server
        srv.hits.append((site, self.path))
        cookie = self.headers.get("Cookie", "")
        signed_in = all(f"{n}=" in cookie for n in NEEDS[site]) and site not in srv.expired
        login = LOGIN[site]
        if path.rstrip("/") == login.rstrip("/"):
            if "next" in parse_qs(u.query):  # sent here by a page that needed a session: show the form, like a real site does
                return self._send(200, b"<html><body><form>Log in</form></body></html>")
            srv.expired.discard(site)  # a direct visit to the login page stands for a successful sign-in, which renews the session
            ck = [("Set-Cookie", f"{c}; Path=/{site}; Max-Age=86400") for c in COOKIES[site]]
            return self._send(302, b"", headers=ck + [("Location", f"/{site}/")])
        if not signed_in:
            return self._send(302, b"", headers=[("Location", f"/{site}{login}?next=" + path)])
        q = parse_qs(u.query)
        return self._send(200, self.page(site, path, q).encode())

    # ---- pages ----
    def grid(self, site, start, count, kinds=("video",)):
        out = []
        for i in range(count):
            n = start + i
            kind = kinds[i % len(kinds)]
            out.append(f'<a href="/{site}{link(site, n, kind)}"><img src="/img/{n}.jpg" width="120" height="120"></a>')
        return "\n".join(out)

    def page(self, site, path, q):
        head = f"<html><head><title>{site}</title><style>body{{height:4000px}}</style></head><body>"
        if site == "ig":
            if path.startswith("/reels"):
                return head + """<script>let n=0;document.addEventListener('keydown',e=>{if(e.key==='ArrowDown'){n++;history.replaceState(null,'','/ig/reel/FORYOU'+String(n).padStart(3,'0')+'/')}});</script>For You</body></html>"""
            if path.startswith("/accounts/edit"):
                return head + '<input name="username" value="tester"></body></html>'
            if path.startswith("/explore/tags/"):
                tag = path.split("/")[-2]
                return head + f"<h1>#{tag}</h1>" + self.grid(site, 100 + len(tag), 6, ("video", "post")) + "</body></html>"
            if path.startswith("/explore"):
                return head + self.grid(site, 1, 8, ("video", "post")) + "</body></html>"
            if path.startswith("/tester"):
                return head + self.grid(site, 50, 5, ("video", "post")) + "</body></html>"
            return head + self.grid(site, 1, 6, ("video",)) + "</body></html>"
        if site == "yt":
            if path.startswith("/results"):
                term = (q.get("search_query") or [""])[0]
                return head + f"<h1>{term}</h1>" + self.grid(site, 200 + len(term), 6) + "</body></html>"
            if path.startswith("/feed/history"):
                return head + self.grid(site, 300, 6) + "</body></html>"
            return head + self.grid(site, 1, 8) + "</body></html>"
        if site == "tt":
            if path.startswith("/search"):
                term = (q.get("q") or [""])[0]
                return head + self.grid(site, 400 + len(term), 6) + "</body></html>"
            if path.startswith("/explore"):
                return head + self.grid(site, 20, 7) + "</body></html>"
            return head + self.grid(site, 1, 8) + "</body></html>"
        if path.startswith("/search"):
            term = (q.get("q") or [""])[0]
            return head + self.grid(site, 500 + len(term), 6) + "</body></html>"
        if path.startswith("/reel"):
            return head + self.grid(site, 30, 6) + "</body></html>"
        return head + self.grid(site, 1, 8) + "</body></html>"


class Fake(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.hits, self.expired = [], set()
        self.thread = threading.Thread(target=self.serve_forever, daemon=True)

    @property
    def port(self):
        return self.server_address[1]

    def base(self, site):
        return f"http://127.0.0.1:{self.port}/{site}"

    def env(self):
        return {f"NL_{s.upper()}_BASE": self.base(s) for s in ("ig", "yt", "tt", "fb")}

    def start(self):
        self.thread.start()
        return self

    def stop(self):
        self.shutdown()
        self.server_close()

    def expire(self, site):
        self.expired.add(site)


if __name__ == "__main__":
    f = Fake().start()
    print(f.port, f.env())
    threading.Event().wait()
