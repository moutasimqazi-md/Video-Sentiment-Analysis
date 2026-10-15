"""The feed check's browser work against local stand-ins for Instagram, YouTube, TikTok and Facebook (tests/fake_sites.py): signing in,
importing a sign-in made on a phone, reading every kind of page on every site, an expired session, and keeping each site's session
separate. Needs Google Chrome (the same browser the app drives); skipped if it isn't installed.

Run from the backend folder:  python -m unittest tests.test_sites -v"""
import os
import time
import unittest

from tests.fake_sites import Fake

_fake = Fake().start()
os.environ.update(_fake.env())  # before the app code reads the site addresses

from neurolens import browser, live, platforms  # noqa: E402

try:
    from playwright.sync_api import sync_playwright

    with sync_playwright() as _p:
        _p.chromium.launch(channel="chrome", headless=True).close()
    HAVE_CHROME = True
except Exception:
    HAVE_CHROME = False

SITES = list(platforms.CODES)
COOKIES = {
    "ig": [("sessionid", "igsess1")],
    "yt": [("SAPISID", "ytsess1"), ("__Secure-3PSID", "ytsess2")],
    "tt": [("sessionid", "ttsess1")],
    "fb": [("c_user", "1001"), ("xs", "fbsess1")],
}


def cookies_for(code):
    return [{"name": n, "value": v, "domain": "127.0.0.1", "path": f"/{code}"} for n, v in COOKIES[code]]


def setUpModule():
    browser._pause = lambda *a, **k: time.sleep(0.15)  # the real pauses are for politeness to real sites


def tearDownModule():
    _fake.stop()


def key(pid, code):
    return platforms.session_key(pid, code)


@unittest.skipUnless(HAVE_CHROME, "Google Chrome is not installed")
class SignInFromAPhone(unittest.TestCase):
    def test_each_site_accepts_its_own_session_and_remembers_it(self):
        for code in SITES:
            with self.subTest(code):
                sk = key("phone1", code)
                self.assertIsNone(browser.connected_at(sk))
                at = browser.import_session(sk, cookies_for(code))
                self.assertEqual(browser.connected_at(sk), at)
                dest = browser._dir(sk).parent / f"{sk}-cookies-test.txt"
                self.assertTrue(browser.session_cookies_to(sk, str(dest)))
                text = dest.read_text()
                for name, _ in COOKIES[code]:
                    self.assertIn(name, text)
                dest.unlink()

    def test_half_a_sign_in_is_refused_with_the_sites_name(self):
        with self.assertRaises(ValueError) as c:
            browser.import_session(key("phone2", "fb"), [cookies_for("fb")[0]])  # c_user but no xs
        self.assertIn("Facebook", str(c.exception))
        with self.assertRaises(ValueError) as c:
            browser.import_session(key("phone2", "tt"), cookies_for("fb"))  # another site's cookies
        self.assertIn("TikTok", str(c.exception))
        self.assertIsNone(browser.connected_at(key("phone2", "fb")))

    def test_cookies_for_some_other_domain_are_dropped(self):
        evil = [{**c, "domain": "evil.example"} for c in cookies_for("ig")]
        with self.assertRaises(ValueError):
            browser.import_session(key("phone3", "ig"), evil)

    def test_one_persons_sites_are_separate_sessions(self):
        browser.import_session(key("sep", "tt"), cookies_for("tt"))
        self.assertIsNotNone(browser.connected_at("sep.tt"))
        self.assertIsNone(browser.connected_at("sep"), "TikTok is not Instagram")
        self.assertIsNone(browser.connected_at("sep.fb"))
        browser.import_session(key("sep", "fb"), cookies_for("fb"))
        browser.disconnect("sep.tt")
        self.assertIsNone(browser.connected_at("sep.tt"))
        self.assertIsNotNone(browser.connected_at("sep.fb"), "disconnecting one site leaves the others")


@unittest.skipUnless(HAVE_CHROME, "Google Chrome is not installed")
class Reading(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for code in SITES:
            browser.import_session(key("reader", code), cookies_for(code))

    def check_items(self, code, items, at_least=3, thumbs=True):
        self.assertGreaterEqual(len(items), at_least, items)
        urls = [i["url"] for i in items]
        self.assertEqual(len(urls), len(set(urls)), "no duplicates")
        for i in items:
            self.assertTrue(i["url"].startswith(platforms.base(code)), i)
            self.assertIn(i["kind"], ("reel", "post"))
            self.assertTrue(i.get("source"))
            if thumbs:
                self.assertTrue(i.get("thumb") and i["thumb"].startswith("http"), i)

    def test_every_check_on_every_site_finds_videos(self):
        for code in SITES:
            for mode in platforms.PLATFORMS[code]["modes"]:
                with self.subTest(code=code, mode=mode):
                    items = browser.collect(key("reader", code), mode, limit=6, terms=["python tutorial", "ai"])
                    if mode == "profile":
                        self.assertEqual(items[0].get("username"), "tester", "the first row carries the account name")
                        items = items[1:]
                    ig_reels = code == "ig" and mode == "foryou"  # Instagram's reel viewer is read from the address bar, so it has no thumbnails
                    self.check_items(code, items, at_least=2 if ig_reels else 3, thumbs=not ig_reels)

    def test_the_source_label_says_what_was_read(self):
        yt = browser.collect(key("reader", "yt"), "history", limit=4)
        self.assertTrue(all(i["source"] == "Watch history" for i in yt))
        tt = browser.collect(key("reader", "tt"), "terms", limit=6, terms=["python tutorial"])
        self.assertTrue(all("python tutorial" in i["source"] for i in tt))

    def test_a_site_only_offers_its_own_checks(self):
        with self.assertRaises(ValueError):
            browser.collect(key("reader", "tt"), "history")
        with self.assertRaises(ValueError):
            browser.collect(key("reader", "yt"), "profile")

    def test_the_limit_is_respected(self):
        self.assertLessEqual(len(browser.collect(key("reader", "yt"), "foryou", limit=3)), 3)

    def test_downloader_cookies_are_written_for_the_site(self):
        import tempfile

        for code in ("yt", "tt", "fb"):
            f = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
            f.close()
            browser.collect(key("reader", code), "foryou", limit=2, cookie_out=f.name)
            text = open(f.name).read()
            os.unlink(f.name)
            self.assertIn("Netscape HTTP Cookie File", text)
            self.assertIn(COOKIES[code][0][0], text, code)

    def test_an_expired_session_is_reported_not_swallowed(self):
        for code in SITES:
            with self.subTest(code):
                sk = key("expiring", code)
                browser.import_session(sk, cookies_for(code))
                _fake.expire(code)
                with self.assertRaises(browser.SessionExpired):
                    browser.collect(sk, "terms" if code != "ig" else "explore", limit=3, terms=["x"])
                _fake.expired.discard(code)


@unittest.skipUnless(HAVE_CHROME, "Google Chrome is not installed")
class SignInInThePrivateBrowser(unittest.TestCase):
    """The streamed browser notices a finished sign-in on each site, using that site's own cookies and pages."""

    def wait_connected(self, sk, timeout=70):
        end = time.time() + timeout
        while time.time() < end:
            st = live.status(sk)
            if st["state"] in ("connected", "error", "closed"):
                return st
            time.sleep(0.5)
        return live.status(sk)

    def test_each_site_signs_in_and_keeps_the_session(self):
        for code in SITES:
            with self.subTest(code):
                sk = key("live1", code)
                self.assertIsNone(browser.connected_at(sk))
                live.start(sk)
                st = self.wait_connected(sk)
                self.assertEqual(st["state"], "connected", st)
                self.assertIsNotNone(browser.connected_at(sk))
                # the session really is on disk: a fresh read of the site works without signing in again
                items = browser.collect(sk, "foryou" if code != "ig" else "explore", limit=3)
                self.assertGreaterEqual(len(items), 2)

    def test_signing_in_to_one_site_does_not_sign_in_to_another(self):
        live.start(key("live2", "tt"))
        self.assertEqual(self.wait_connected(key("live2", "tt"))["state"], "connected")
        self.assertIsNone(browser.connected_at(key("live2", "fb")))
        self.assertIsNone(browser.connected_at("live2"))

    def test_the_sign_in_never_stores_a_password(self):
        sk = key("live3", "fb")
        live.start(sk)
        self.assertEqual(self.wait_connected(sk)["state"], "connected")
        folder = browser._dir(sk)
        names = [p.name for p in folder.iterdir()]
        self.assertIn("connected", names)
        self.assertNotIn("password", " ".join(names).lower())


if __name__ == "__main__":
    unittest.main()
