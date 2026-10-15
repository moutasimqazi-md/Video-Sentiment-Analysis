"""Link handling for Instagram, YouTube, TikTok and Facebook: which links are accepted, how short links are followed, what a user sees when
a platform refuses the download, and how a video is recognised when it comes back. No network: requests is mocked.

Run from the backend folder:  python -m unittest discover -s tests -t . -v"""
import unittest
from unittest import mock

import requests
import yt_dlp
from yt_dlp.extractor import gen_extractor_classes

from neurolens import downloader as d
from neurolens import logstore

GOOD = {
    "instagram": ["https://www.instagram.com/reel/AAA/", "https://instagram.com/p/AAA/"],
    "youtube": ["https://www.youtube.com/watch?v=abcdefghijk", "https://youtu.be/abcdefghijk", "https://www.youtube.com/shorts/abcdefghijk"],
    "tiktok": ["https://www.tiktok.com/@some.user/video/7100000000000000001", "https://www.tiktok.com/@/video/7100000000000000001", "https://vm.tiktok.com/ZMabc123/",
               "https://vt.tiktok.com/ZSabc123/", "https://www.tiktok.com/t/ZTabc123/", "https://www.tiktokv.com/share/video/7100000000000000001/"],
    "facebook": ["https://www.facebook.com/watch/?v=123456789", "https://www.facebook.com/reel/123456789", "https://www.facebook.com/somepage/videos/123456789",
                 "https://m.facebook.com/watch/?v=123456789", "https://fb.watch/abcDEF123/", "https://www.facebook.com/share/r/1AbCdEf/"],
}


class Accepting(unittest.TestCase):
    def test_every_supported_platform_link_is_accepted(self):
        for platform, urls in GOOD.items():
            for u in urls:
                with self.subTest(u):
                    self.assertEqual(d.validate_url(u), u)
                    self.assertEqual(d.platform_of(u), platform)

    def test_lookalikes_internal_addresses_and_odd_links_are_refused(self):
        for u in ["https://tiktok.com.evil.example/video/1", "https://evil.example/tiktok.com/video/1", "https://facebook.com.evil.example/watch/?v=1",
                  "https://notfacebook.com/watch/?v=1", "https://fb.watch.evil.example/x", "https://169.254.169.254/latest/meta-data/",
                  "https://localhost/video", "http://127.0.0.1:8000/", "ftp://www.tiktok.com/@a/video/1", "file:///etc/passwd", "javascript:alert(1)",
                  "https://user:pw@www.tiktok.com/@a/video/1", "www.tiktok.com/@a/video/1", "", None, "   "]:
            with self.subTest(u):
                with self.assertRaises(d.LinkError):
                    d.validate_url(u)

    def test_refusal_message_names_all_four_platforms(self):
        with self.assertRaises(d.LinkError) as c:
            d.validate_url("https://example.com/v")
        self.assertIn("TikTok", str(c.exception))
        self.assertIn("Facebook", str(c.exception))


class ShortLinks(unittest.TestCase):
    @staticmethod
    def resp(status, location=None):
        r = mock.Mock(); r.status_code = status; r.headers = {"Location": location} if location else {}; return r

    def test_a_normal_link_is_returned_without_touching_the_network(self):
        with mock.patch.object(d.requests, "get") as g:
            self.assertEqual(d.resolve_short_link("https://www.facebook.com/watch/?v=1"), "https://www.facebook.com/watch/?v=1")
            self.assertEqual(d.resolve_short_link("https://vm.tiktok.com/ZM1/"), "https://vm.tiktok.com/ZM1/", "yt-dlp has its own extractor for these")
            g.assert_not_called()

    def test_fb_watch_is_followed_to_the_real_address(self):
        with mock.patch.object(d.requests, "get", return_value=self.resp(302, "https://www.facebook.com/reel/123456789?mibextid=x")) as g:
            self.assertEqual(d.resolve_short_link("https://fb.watch/abc/"), "https://www.facebook.com/reel/123456789?mibextid=x")
            self.assertFalse(g.call_args.kwargs["allow_redirects"], "each hop is checked by hand, never followed automatically")

    def test_share_links_are_followed_and_relative_redirects_work(self):
        hops = [self.resp(301, "/share/r/xyz/?x=1"), self.resp(302, "https://m.facebook.com/reel/555555")]
        with mock.patch.object(d.requests, "get", side_effect=hops):
            self.assertEqual(d.resolve_short_link("https://www.facebook.com/share/r/abc/"), "https://m.facebook.com/reel/555555")

    def test_a_redirect_off_the_allowed_hosts_is_refused(self):
        for bad in ["https://evil.example/x", "http://www.facebook.com/reel/1", "https://169.254.169.254/latest/", "https://user:pw@www.facebook.com/reel/1", "https://www.facebook.com.evil.example/reel/1"]:
            with self.subTest(bad):
                with mock.patch.object(d.requests, "get", return_value=self.resp(302, bad)):
                    with self.assertRaises(d.LinkError):
                        d.resolve_short_link("https://fb.watch/abc/")

    def test_loops_dead_ends_and_network_errors_are_clean_errors(self):
        with mock.patch.object(d.requests, "get", return_value=self.resp(302, "https://fb.watch/again/")):
            with self.assertRaises(d.LinkError):
                d.resolve_short_link("https://fb.watch/abc/")
        with mock.patch.object(d.requests, "get", return_value=self.resp(200)):
            with self.assertRaises(d.LinkError):
                d.resolve_short_link("https://fb.watch/abc/")
        with mock.patch.object(d.requests, "get", side_effect=requests.ConnectionError("boom")):
            with self.assertRaises(d.LinkError) as c:
                d.resolve_short_link("https://fb.watch/abc/")
        self.assertIn("screen recording", str(c.exception))


class Messages(unittest.TestCase):
    def test_platform_specific_refusals_are_explained_in_plain_words(self):
        tt = d._friendly("ERROR: [TikTok] 710000: Unable to extract webpage video data")
        fb = d._friendly("ERROR: [facebook] 123: Cannot parse data; please report this issue")
        self.assertIn("TikTok", tt); self.assertIn("screen recording", tt)
        self.assertIn("Facebook", fb); self.assertIn("screen recording", fb)

    def test_existing_messages_are_unchanged(self):
        self.assertIn("Instagram wouldn't let us download", d._friendly("ERROR: [instagram] x: login required"))
        self.assertIn("YouTube blocked", d._friendly("Sign in to confirm you're not a bot"))
        self.assertEqual(d._friendly("ERROR: Video unavailable"), "That video is unavailable.")


class Identity(unittest.TestCase):
    def test_the_same_video_gets_the_same_key_however_it_was_linked(self):
        k = logstore.url_key
        self.assertEqual(k("https://www.tiktok.com/@/video/7100000000000000001"), "tt:7100000000000000001")
        self.assertEqual(k("https://www.tiktok.com/@someone/video/7100000000000000001?is_from_webapp=1"), "tt:7100000000000000001")
        self.assertEqual(k("https://www.tiktokv.com/share/video/7100000000000000001/"), "tt:7100000000000000001")
        self.assertEqual(k("https://www.facebook.com/reel/123456789"), "fb:123456789")
        self.assertEqual(k("https://www.facebook.com/watch/?v=987654321"), "fb:987654321")
        self.assertEqual(k("https://m.facebook.com/watch/?ref=x&v=987654321"), "fb:987654321")
        self.assertEqual(k("https://www.facebook.com/somepage/videos/123456789"), "fb:123456789")
        self.assertEqual(k("https://www.instagram.com/reel/AAA/"), "ig:AAA")
        self.assertEqual(k("https://youtu.be/abcdefghijk"), "yt:abcdefghijk")
        self.assertIsNone(k(""))


class Extractors(unittest.TestCase):
    """Guards the pinned yt-dlp: each platform's links are claimed by that platform's own extractor, and nothing generic can run."""

    def test_each_platform_link_is_claimed_by_its_own_extractor(self):
        classes = [c for c in gen_extractor_classes() if c.ie_key() != "Generic"]
        expect = {"tiktok": "tiktok", "facebook": "facebook", "instagram": "instagram", "youtube": "youtube"}
        no_own_extractor = {"https://fb.watch/abcDEF123/", "https://www.facebook.com/share/r/1AbCdEf/"}   # resolved by resolve_short_link first
        for platform, urls in GOOD.items():
            for u in urls:
                if u in no_own_extractor:
                    continue
                with self.subTest(u):
                    keys = [c.ie_key().lower() for c in classes if c.suitable(u)]
                    self.assertTrue(keys and all(k.startswith(expect[platform]) for k in keys), keys)

    def test_the_generic_extractor_is_switched_off(self):
        with yt_dlp.YoutubeDL({"quiet": True, "allowed_extractors": d.ALLOWED_EXTRACTORS}) as y:
            names = set(y._ies)
        self.assertNotIn("Generic", names)
        for needed in ("TikTok", "TikTokVM", "Facebook", "FacebookReel", "Instagram", "Youtube"):
            self.assertIn(needed, names)   # TikTokVM follows vm.tiktok.com / vt.tiktok.com / tiktok.com/t/ short links
        self.assertFalse([n for n in names if not any(w in n.lower() for w in ("youtube", "instagram", "tiktok", "facebook"))])


if __name__ == "__main__":
    unittest.main()
