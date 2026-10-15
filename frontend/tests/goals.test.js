/* Tests for the goals engine and the shared taxonomy. Run: node --test frontend/tests/ */
const test = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const path = require("node:path");

global.window = global;
global.NL = {};
const js = (f) => require(path.join(__dirname, "..", "js", f));
["data/lexicon.js", "data/taxonomy.js", "core/imports/themes.js", "core/imports/goals.js"].forEach(js);
const G = NL.imp.goals;
const NOW = 1_800_000_000;
const ev = (text, act = "like", daysAgo = 1, src = "ig") => ({ src, kind: "reel", act, t: NOW - daysAgo * 86400, url: "https://www.instagram.com/reel/x/", text, by: "" });

test("taxonomy copies are in sync with shared/taxonomy.json", () => {
  execFileSync("node", [path.join(__dirname, "..", "..", "shared", "sync.js"), "--check"], { stdio: "pipe" });
});

test("the classifier places clear captions on the right topic", () => {
  assert.equal(G.classify("Learn Python for machine learning #ai #coding").theme, "ai_tech");
  assert.equal(G.classify("when he cheated on me #breakup #toxicrelationship").theme, "relationship_conflict");
  assert.equal(G.classify("how to get over her after the breakup").theme, "relationship_conflict");
  assert.equal(G.classify("sunset in the mountains #travel").theme, "travel_nature");
  assert.equal(G.classify("🔥🔥"), null);
  assert.equal(G.classify(""), null);
});

test("generic spam hashtags do not decide a topic", () => {
  assert.equal(G.classify("nice shot #explore #fyp #reels"), null);
  assert.equal(G.classify("#love"), null);
  assert.equal(G.classify("watching a pakistani drama serial tonight"), null);
});

test("goals suggest topics to avoid, but never one another goal supports", () => {
  assert.ok(G.defaultAvoid(["ai_career"]).includes("relationship_conflict"));
  assert.ok(G.defaultAvoid(["ai_career"]).includes("romance"));
  const both = G.defaultAvoid(["ai_career", "commitment"]);
  assert.ok(!both.includes("romance"), "commitment supports romance");
  assert.ok(both.includes("relationship_conflict"));
});

test("normalize drops unknown goals and topics from saved data", () => {
  assert.deepEqual(G.normalize({ goals: ["ai_career", "nope"], avoid: ["gaming", "nope", "gaming"] }), { goals: ["ai_career"], avoid: ["gaming"] });
  assert.deepEqual(G.normalize(null), { goals: [], avoid: [] });
});

test("evaluate counts supports / neutral / against and ignores unplaced items", () => {
  const events = [
    ...Array(6).fill(0).map(() => ev("Learn Python #ai #coding")),
    ...Array(3).fill(0).map(() => ev("when he cheated #breakup")),
    ...Array(1).fill(0).map(() => ev("funny meme #comedy")),
    ...Array(5).fill(0).map(() => ev("🔥")),
  ];
  const r = G.evaluate(events, { goals: ["ai_career"], avoid: G.defaultAvoid(["ai_career"]) });
  const g = r.groups.find((x) => x.key === "liked");
  assert.equal(g.n, 15);
  assert.equal(g.classified, 10);
  assert.deepEqual(g.counts, { supports: 6, neutral: 1, against: 3 });
  assert.ok(Math.abs(g.share.supports - 0.6) < 1e-9 && Math.abs(g.share.against - 0.3) < 1e-9);
  assert.equal(g.examples.length, 3);
  assert.equal(g.topics[0].key, "ai_tech");
});

test("what the person chose to avoid wins over what a goal supports", () => {
  const events = Array(30).fill(0).map(() => ev("our wedding day #couplegoals"));
  const r = G.evaluate(events, { goals: ["commitment"], avoid: ["romance"] });
  assert.equal(r.groups[0].counts.against, 30);
  assert.equal(r.groups[0].counts.supports, 0);
});

test("watched and liked are reported separately; stories and music are not 'watched'", () => {
  const events = [ev("Learn Python #ai", "view", 2), ev("Learn Python #ai", "like", 2), { ...ev("Learn Python #ai", "view", 2), kind: "story" }, { ...ev("Learn Python #ai", "view", 2, "yt"), kind: "music" }];
  const r = G.evaluate(events, { goals: ["ai_career"], avoid: [] });
  assert.equal(r.groups.find((g) => g.key === "watched").n, 1);
  assert.equal(r.groups.find((g) => g.key === "liked").n, 1);
});

test("YouTube channel names count toward the topic", () => {
  const e = { ...ev("episode 4", "view", 1, "yt"), kind: "video", by: "Python Programming Tutorials" };
  assert.equal(G.evaluate([e], { goals: ["ai_career"], avoid: [] }).groups[0].counts.supports, 1);
});

test("long histories get a monthly trend, short ones none", () => {
  const long = G.evaluate([ev("Learn Python #ai", "like", 200), ev("Learn Python #ai", "like", 1)], { goals: ["ai_career"], avoid: [] }).groups[0];
  assert.equal(long.grain, "month");
  assert.ok(long.periods.length >= 2);
  const short = G.evaluate([ev("Learn Python #ai", "like", 3), ev("Learn Python #ai", "like", 1)], { goals: ["ai_career"], avoid: [] }).groups[0];
  assert.equal(short.grain, null);
});

test("findings are honest about too little data", () => {
  const r = G.evaluate([ev("Learn Python #ai"), ev("🔥")], { goals: ["ai_career"], avoid: [] });
  const f = G.findings(r.groups[0], r);
  assert.equal(f.length, 1);
  assert.match(f[0].title, /Too few/);
  assert.equal(f[0].confidence, "low");
});

test("findings call out an avoided topic with its tip and a basis", () => {
  const events = [...Array(40).fill(0).map(() => ev("he cheated on me #breakup")), ...Array(40).fill(0).map(() => ev("Learn Python #ai"))];
  const sel = { goals: ["ai_career"], avoid: G.defaultAvoid(["ai_career"]) };
  const r = G.evaluate(events, sel);
  const f = G.findings(r.groups[0], r);
  const c = f.find((x) => /Breakups, cheating/.test(x.title));
  assert.ok(c && /Not interested/.test(c.tip));
  assert.match(c.basis, /80 of 80/);
});
