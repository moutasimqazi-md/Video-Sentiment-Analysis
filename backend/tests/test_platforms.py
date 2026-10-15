"""The per-site rules the feed check runs on (platforms.py): session keys, which links are videos, what counts as signed in, which pages the
sign-in browser may show, which cookies may be imported. Pure logic, no browser.

Run from the backend folder:  python -m unittest discover -s tests -t . -v"""
import os
import unittest
from unittest import mock

from neurolens import platforms as P

SITE_ENV = [P.PLATFORMS[c]["env"] for c in P.CODES]


class SessionKeys(unittest.TestCase):
    def test_instagram_keeps_the_plain_id_and_others_get_a_suffix(self):
        self.assertEqual(P.session_key("me", "ig"), "me")
        self.assertEqual(P.session_key("me"), "me")
        self.assertEqual(P.session_key("me", "tt"), "me.tt")
        self.assertEqual(P.session_key("u1abc-kid1", "fb"), "u1abc-kid1.fb")

    def test_a_key_splits_back_into_profile_and_site(self):
        for pid in ("me", "kid1", "u1abc-me", "u1abc-kid_2"):
            for code in P.CODES:
                self.assertEqual(P.split_key(P.session_key(pid, code)), (pid, code))

    def test_anything_without_a_known_suffix_is_instagram(self):
        for k in ("me", "u1-me", "me.xx", "me.", ".tt", ""):
            self.assertEqual(P.plat_of(k), "ig", k)
        self.assertEqual(P.split_key(None), (None, "ig"))


class Videos(unittest.TestCase):
    def test_each_site_recognises_its_own_video_links(self):
        cases = {
            "ig": [("/reel/ABCDE12345/", "reel", "/reel/ABCDE12345/"), ("https://www.instagram.com/p/ABCDE12345/?x=1", "post", "/p/ABCDE12345/"), ("/reels/ABCDE12345/", "reel", "/reel/ABCDE12345/")],
            "yt": [("/watch?v=abcdefghijk", "reel", "/watch?v=abcdefghijk"), ("/watch?list=PL1&v=abcdefghijk&t=3", "reel", "/watch?v=abcdefghijk"), ("/shorts/abcdefghijk", "reel", "/shorts/abcdefghijk")],
            "tt": [("/@some.user/video/7100000000000000001", "reel", "/@some.user/video/7100000000000000001"), ("https://www.tiktok.com/@a_b-c/video/7100000000000000002?lang=en", "reel", "/@a_b-c/video/7100000000000000002")],
            "fb": [("/reel/1234567890", "reel", "/reel/1234567890"), ("/reels/1234567890/", "reel", "/reel/1234567890"), ("/watch/?v=1234567890", "reel", "/watch/?v=1234567890"),
                   ("https://www.facebook.com/somepage/videos/1234567890/", "reel", "/watch/?v=1234567890")],
        }
        for code, rows in cases.items():
            for href, kind, path in rows:
                with self.subTest(code=code, href=href):
                    it = P.item(code, href)
                    self.assertIsNotNone(it)
                    self.assertEqual(it["kind"], kind)
                    self.assertEqual(it["url"], P.base(code) + path)  # read now, not at import: other test files point the sites at stand-ins

    def test_other_links_are_not_videos(self):
        junk = {"ig": ["/accounts/login/", "/explore/", "/someuser/", ""], "yt": ["/@channel", "/feed/history", "/watch?v=short", "/playlist?list=PL1", "/results?search_query=x"],
                "tt": ["/@someone", "/foryou", "/video/123", "/@a/video/12"], "fb": ["/groups/123", "/watch/", "/reel/12", "/somepage/", "/profile.php?id=1"]}
        for code, hrefs in junk.items():
            for h in hrefs:
                with self.subTest(code=code, href=h):
                    self.assertIsNone(P.item(code, h))

    def test_a_video_link_from_one_site_is_not_read_as_another_sites(self):
        self.assertIsNone(P.item("tt", "/reel/1234567890"))
        self.assertIsNone(P.item("yt", "/@a/video/7100000000000000001"))
        self.assertIsNone(P.item("fb", "/watch?v=abcdefghijk"))


class SignedIn(unittest.TestCase):
    def c(self, *names):
        return [{"name": n, "value": "x"} for n in names]

    def test_each_site_has_its_own_idea_of_signed_in(self):
        self.assertTrue(P.has_session("ig", self.c("sessionid")))
        self.assertTrue(P.has_session("tt", self.c("sid_tt")))
        self.assertTrue(P.has_session("yt", self.c("SAPISID")))
        self.assertTrue(P.has_session("yt", self.c("__Secure-3PSID")))
        self.assertTrue(P.has_session("fb", self.c("c_user", "xs")))

    def test_half_a_login_or_the_wrong_sites_cookie_is_not_signed_in(self):
        self.assertFalse(P.has_session("fb", self.c("c_user")), "Facebook needs both cookies")
        self.assertFalse(P.has_session("fb", self.c("xs")))
        self.assertFalse(P.has_session("ig", self.c("sid_tt")))
        self.assertFalse(P.has_session("tt", self.c("c_user", "xs")))
        self.assertFalse(P.has_session("ig", []))
        self.assertFalse(P.has_session("ig", [{"name": "sessionid", "value": ""}]), "an empty value is not a session")

    def test_login_and_security_pages_are_recognised(self):
        self.assertTrue(P.is_login_url("ig", "https://www.instagram.com/accounts/login/?next=/"))
        self.assertTrue(P.is_login_url("tt", "https://www.tiktok.com/login?redirect=x"))
        self.assertTrue(P.is_login_url("fb", "https://www.facebook.com/login/?next=x"))
        self.assertTrue(P.is_login_url("yt", "https://accounts.google.com/v3/signin/identifier"))
        self.assertFalse(P.is_login_url("ig", "https://www.instagram.com/explore/"))
        self.assertTrue(P.is_pending_url("fb", "https://www.facebook.com/checkpoint/1234/"))
        self.assertTrue(P.is_pending_url("ig", "https://www.instagram.com/challenge/"))
        self.assertFalse(P.is_pending_url("fb", "https://www.facebook.com/watch/"))


class Safety(unittest.TestCase):
    def test_the_sign_in_browser_only_shows_the_site_and_its_helpers(self):
        self.assertTrue(P.host_ok("fb", "https://www.facebook.com/login/"))
        self.assertTrue(P.host_ok("fb", "https://static.xx.fbcdn.net/x.js"))
        self.assertTrue(P.host_ok("yt", "https://accounts.google.com/signin"))
        self.assertTrue(P.host_ok("tt", "https://www.tiktok.com/login"))
        self.assertTrue(P.host_ok("ig", "about:blank"))
        self.assertTrue(P.host_ok("ig", ""))

    def test_other_sites_and_lookalikes_are_turned_away(self):
        for code, url in [("fb", "https://evil.example/"), ("fb", "https://evilfacebook.com/"), ("fb", "https://facebook.com.evil.example/"), ("ig", "https://www.tiktok.com/"),
                          ("tt", "https://www.facebook.com/"), ("yt", "https://google.com.evil.example/"), ("ig", "http://169.254.169.254/latest/"), ("tt", "https://nottiktok.com/")]:
            with self.subTest(code=code, url=url):
                self.assertFalse(P.host_ok(code, url))

    def test_only_the_sites_own_cookies_can_be_imported(self):
        for code, ok, bad in [("ig", ".instagram.com", ".facebook.com"), ("tt", ".tiktok.com", "tiktok.com.evil.example"), ("fb", "www.facebook.com", "evilfacebook.com"),
                              ("yt", ".youtube.com", ".google.com.evil.example")]:
            with self.subTest(code=code):
                self.assertTrue(P.cookie_domain_ok(code, ok))
                self.assertFalse(P.cookie_domain_ok(code, bad))
        self.assertTrue(P.cookie_domain_ok("yt", ".google.com"), "YouTube sign-in lives on google.com too")


class Registry(unittest.TestCase):
    def test_every_site_is_fully_described(self):
        for code, p in P.PLATFORMS.items():
            with self.subTest(code=code):
                self.assertIn(code, P.CODES)
                self.assertTrue(p["name"] and p["modes"] and p["paths"] and p["selector"] and p["session"] and p["hosts"] and p["login_urls"])
                self.assertIn(p["monitor_mode"], p["modes"])
                for mode in p["modes"]:
                    if mode not in ("profile",):
                        self.assertIn(mode, p["paths"], f"{code} mode {mode} has no page")
                self.assertTrue(P.login_url(code).startswith("http"))
                self.assertIn("{q}", p["paths"]["terms"])

    def test_instagram_still_has_all_four_checks_and_the_others_do_not_claim_an_account_review(self):
        self.assertEqual(set(P.PLATFORMS["ig"]["modes"]), {"explore", "foryou", "terms", "profile"})
        for code in ("yt", "tt", "fb"):
            self.assertNotIn("profile", P.PLATFORMS[code]["modes"])
        self.assertIn("history", P.PLATFORMS["yt"]["modes"], "YouTube's watch history is the one place a feed check sees what was really watched")

    def test_the_real_login_addresses(self):
        with mock.patch.dict(os.environ):
            for k in SITE_ENV:
                os.environ.pop(k, None)  # the real sites, whatever other tests pointed at
            self.assertEqual(P.login_url("ig"), "https://www.instagram.com/accounts/login/")
            self.assertEqual(P.login_url("fb"), "https://www.facebook.com/login/")
            self.assertEqual(P.login_url("tt"), "https://www.tiktok.com/login")
            self.assertTrue(P.login_url("yt").startswith("https://accounts.google.com/ServiceLogin"))
            self.assertIn("youtube.com", P.login_url("yt"))


if __name__ == "__main__":
    unittest.main()
