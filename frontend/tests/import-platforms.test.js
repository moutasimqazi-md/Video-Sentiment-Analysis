/* Tests for the TikTok and Facebook import adapters, and that Instagram / YouTube still import as before.
   IMPORTANT: the TikTok and Facebook fixtures below are *assumed* shapes (written from published descriptions and Meta's conventions), not
   real exports. Real files must be tried on the import screen; see DEPLOY/README notes. Run: node --test frontend/tests/import-platforms.test.js */
const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

global.window = global;
global.NL = {};
["data/lexicon.js", "core/imports/parse.js"].forEach((f) => require(path.join(__dirname, "..", "js", f)));
const P = NL.imp.parse;
const T0 = Date.UTC(2026, 9, 1, 10, 0, 0) / 1000; // 2026-10-01 10:00:00 UTC

const tiktok = () => ({
  Profile: { "Profile Information": { ProfileMap: { userName: "someone", bioDescription: "private bio" } } },
  "Direct Message": { "Direct Messages": { ChatHistory: { "Chat with a friend": [{ Date: "2026-10-01 10:00:00", From: "friend", Content: "SECRET MESSAGE" }] } } },
  Activity: {
    "Video Browsing History": { VideoList: [
      { Date: "2026-10-01 10:00:00", Link: "https://www.tiktokv.com/share/video/7100000000000000001/" },
      { Date: "2026-10-01 10:01:00", Link: "https://www.tiktok.com/@some.user/video/7100000000000000002?is_from_webapp=1" },
    ] },
    "Like List": { ItemFavoriteList: [{ date: "2026-10-02 11:00:00", link: "https://www.tiktokv.com/share/video/7100000000000000003/" }] },
    "Favorite Videos": { FavoriteVideoList: [{ Date: "2026-10-03 12:00:00", Link: "https://www.tiktokv.com/share/video/7100000000000000004/" }] },
    "Search History": { SearchList: [{ Date: "2026-10-04 13:00:00", SearchTerm: "learn python" }, { Date: "2026-10-04 13:05:00", SearchTerm: "" }] },
    "Share History": { ShareHistoryList: [{ Date: "2026-10-05 14:00:00", SharedContent: "video", Link: "https://www.tiktokv.com/share/video/7100000000000000005/", Method: "copy" }] },
    Comments: { CommentsList: [{ Date: "2026-10-06 15:00:00", Comment: "great video", Url: "https://www.tiktokv.com/share/video/7100000000000000006/" }] },
    "Login History": { LoginHistoryList: [{ Date: "2026-10-07 16:00:00", IP: "203.0.113.9", DeviceModel: "phone" }] },
  },
});

test("TikTok: sections are recognised by name, with UTC times and rewritten video links", () => {
  const ev = P._tt(tiktok());
  const by = (a) => ev.filter((e) => e.act === a);
  assert.equal(by("view").length, 2);
  assert.equal(by("like").length, 1);
  assert.equal(by("save").length, 1);
  assert.equal(by("search").length, 1, "the empty search term is dropped");
  assert.equal(by("share").length, 1);
  assert.equal(by("comment").length, 1);
  assert.equal(by("view")[0].t, T0);
  assert.equal(by("view")[0].url, "https://www.tiktok.com/@/video/7100000000000000001");
  assert.equal(by("view")[1].url, "https://www.tiktok.com/@/video/7100000000000000002");
  assert.equal(by("search")[0].text, "learn python");
  assert.ok(ev.every((e) => e.src === "tt"));
});

test("TikTok: direct messages, login history and profile details are never read", () => {
  const ev = P._tt(tiktok());
  const dump = JSON.stringify(ev);
  assert.ok(!dump.includes("SECRET MESSAGE"));
  assert.ok(!dump.includes("203.0.113.9"));
  assert.ok(!dump.includes("private bio"));
});

test("TikTok: tolerates other key casing, epoch times and a different wrapper", () => {
  const ev = P._tt({ activity: { "watch history": { videolist: [{ time: T0, url: "https://www.tiktok.com/@a/video/7200000000000000001" }, { timestamp: String(T0 * 1000), Link: "https://vm.tiktok.com/ZMabc123/" }] } } });
  assert.equal(ev.length, 2);
  assert.equal(ev[0].t, T0);
  assert.equal(ev[1].t, T0);
  assert.equal(ev[1].url, "https://vm.tiktok.com/ZMabc123/", "short links are kept as they are");
});

test("TikTok: an export with nothing recognisable gives no events (not an error)", () => {
  assert.deepEqual(P._tt({ Settings: { Foo: [{ bar: 1 }] } }), []);
  assert.deepEqual(P._tt([]), []);
  assert.deepEqual(P._tt(null), []);
});

test("TikTok: video link rewriting", () => {
  assert.equal(P.ttUrl("https://www.tiktokv.com/share/video/7300000000000000009/"), "https://www.tiktok.com/@/video/7300000000000000009");
  assert.equal(P.ttUrl("https://www.tiktok.com/@x/video/7300000000000000009?lang=en"), "https://www.tiktok.com/@/video/7300000000000000009");
  assert.equal(P.ttUrl("https://vm.tiktok.com/ZM1/"), "https://vm.tiktok.com/ZM1/");
  assert.equal(P.ttUrl(""), "");
});

const fbWatch = { watch_history_v2: [
  { timestamp: T0, title: "You watched a video from Some Page", attachments: [{ data: [{ external_context: { url: "https://www.facebook.com/watch/?v=111" } }] }] },
  { timestamp: T0 + 60, title: "You watched a reel", attachments: [{ data: [{ external_context: { url: "https://www.facebook.com/reel/222" } }] }] },
  { timestamp: T0 + 120, title: "no link and no text", data: [] },
] };
const fbLikes = { likes_and_reactions_v2: [
  { timestamp: T0, title: "Jane Doe liked Some Page's post", data: [{ reaction: { reaction: "LIKE", actor: "Jane Doe" } }], attachments: [{ data: [{ external_context: { url: "https://www.facebook.com/somepage/videos/333" } }] }] },
  { timestamp: T0 + 5, title: "Jane Doe reacted", attachments: [] },
] };
const fbSearch = { searches_v2: [{ timestamp: T0, data: [{ text: "python tutorial" }], title: "You searched for python tutorial" }, { timestamp: T0 + 1, title: "You searched for cheap flights" }] };

test("Facebook: watched videos and reels", () => {
  const ev = P._fb("fbWatched", fbWatch);
  assert.equal(ev.length, 3, "an entry with a time but no link is kept: it still counts for when and how much");
  assert.deepEqual(ev.map((e) => [e.kind, e.act, e.src]), [["video", "view", "fb"], ["reel", "view", "fb"], ["video", "view", "fb"]]);
  assert.equal(ev[0].t, T0);
  assert.equal(ev[0].url, "https://www.facebook.com/watch/?v=111", "links nested in attachments are found");
  assert.equal(ev[2].url, "");
});

test("Facebook: reactions keep the link but not the 'Name liked ...' title", () => {
  const ev = P._fb("fbLikes", fbLikes);
  assert.equal(ev.length, 2);
  assert.equal(ev[0].act, "like");
  assert.equal(ev[0].kind, "video");
  assert.ok(!ev.some((e) => /Jane/.test(e.text)), "names from titles are not kept");
});

test("Facebook: searches take the typed words", () => {
  const ev = P._fb("fbSearch", fbSearch);
  assert.deepEqual(ev.map((e) => e.text), ["python tutorial", "cheap flights"]);
  assert.ok(ev.every((e) => e.act === "search" && e.url === ""));
});

test("file names map to the right category and private folders are never opened", () => {
  const c = P.categorize;
  assert.equal(c("user_data_tiktok.json"), "ttData");
  assert.equal(c("TikTok/user_data.json"), "ttData");
  assert.equal(c("your_facebook_activity/watch/watch_history.json"), "fbWatched");
  assert.equal(c("your_facebook_activity/likes_and_reactions/posts_and_comments.json"), "fbLikes");
  assert.equal(c("search_history/your_search_history.json"), "fbSearch");
  assert.equal(c("your_instagram_activity/likes/liked_posts.json"), "igLikes", "Instagram is unchanged");
  assert.equal(c("Takeout/YouTube and YouTube Music/history/watch-history.json"), "ytWatch", "YouTube is unchanged");
  assert.equal(c("your_facebook_activity/messages/inbox/chat_1/message_1.json"), null);
  assert.equal(c("notes.json"), null);
  for (const p of ["your_facebook_activity/messages/inbox/a/message_1.json", "personal_information/profile_information/profile_information.json", "friends_and_followers/friends.json", "security_and_login_information/login.json"]) assert.ok(P.isPrivate(p), p);
});

test("run(): four platforms in one go, each in its own bucket, with TikTok listed per kind", async () => {
  const igLikes = { likes_media_likes: [{ timestamp: T0, label_values: [{ label: "URL", href: "https://www.instagram.com/reel/AAA/" }, { label: "Caption", value: "Learn Python #ai" }] }] };
  const sources = [
    { name: "instagram/your_instagram_activity/likes/liked_posts.json", read: async () => JSON.stringify(igLikes) },
    { name: "tiktok/user_data_tiktok.json", read: async () => JSON.stringify(tiktok()) },
    { name: "facebook/your_facebook_activity/watch/watch_history.json", read: async () => JSON.stringify(fbWatch) },
    { name: "facebook/search/your_search_history.json", read: async () => JSON.stringify(fbSearch) },
  ];
  const r = await P.run(sources);
  assert.equal(r.events.ig.length, 1);
  assert.equal(r.events.tt.length, 7);
  assert.equal(r.events.fb.length, 5);
  assert.equal(r.events.yt.length, 0);
  assert.deepEqual(Object.keys(r.recognized).sort(), ["fbSearch", "fbWatched", "igLikes", "ttComment", "ttLike", "ttSave", "ttSearch", "ttShare", "ttView"]);
  assert.equal(r.ranges.ttView.n, 2);
  assert.equal(P.LABELS.ttView, "Videos watched");
  assert.ok(r.events.tt.every((e) => !("_cat" in e)), "internal helper field is removed");
  assert.deepEqual(r.problems, []);
});

test("run(): a TikTok file with nothing readable reports a problem the user can act on", async () => {
  const r = await P.run([{ name: "user_data.json", read: async () => JSON.stringify({ Settings: { Foo: [] } }) }]);
  assert.equal(r.events.tt.length, 0);
  assert.match(r.problems[0], /choose JSON/i);
});

test("run(): broken JSON is reported, not thrown", async () => {
  const r = await P.run([{ name: "your_facebook_activity/watch/watch_history.json", read: async () => "{not json" }]);
  assert.equal(r.events.fb.length, 0);
  assert.equal(r.problems.length, 1);
});
