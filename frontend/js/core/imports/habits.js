/* Habits analysis + judgement over imported Instagram / YouTube history.
   Every export covers a different window (e.g. 12 months of likes but only 7 days of watched reels), so each metric comes from one
   named *series* and every finding states its basis and confidence. Thresholds are conservative and listed in `RULES` (shown to the user). */
window.NL = window.NL || {};
NL.imp = NL.imp || {};

NL.imp.habits = (() => {
  const pad = (n) => String(n).padStart(2, "0");
  const dayKey = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const median = (a) => { if (!a.length) return 0; const s = [...a].sort((x, y) => x - y); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
  const hourLabel = (h) => `${h % 12 === 0 ? 12 : h % 12}${h < 12 ? "am" : "pm"}`;
  const WD = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
  const pct = (x) => Math.round(x * 100);
  const friendly = (k) => { const [y, m, d] = k.split("-").map(Number); return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }); };
  const mins = (m) => (m < 1 ? "under a minute" : `${Math.round(m)} min`);
  const nf = (n) => Math.round(n).toLocaleString();
  const conf = (n, days) => (n >= 500 && days >= 60 ? "high" : n >= 100 && days >= 14 ? "medium" : "low");

  /* ---------- one series of timestamped events -> everything we can say about it ---------- */
  function stats(events, { gapSec, minBinge }) {
    const ev = events.filter((e) => e.t > 0).sort((a, b) => a.t - b.t);
    if (!ev.length) return null;
    const from = ev[0].t, to = ev[ev.length - 1].t, days = Math.max(1, Math.ceil((to - from) / 86400) + 1);
    const byHour = Array(24).fill(0), byWeekday = Array(7).fill(0), grid = Array.from({ length: 7 }, () => Array(24).fill(0)), daily = {}, monthly = {};
    for (const e of ev) {
      const d = new Date(e.t * 1000), h = d.getHours(), wd = (d.getDay() + 6) % 7, dk = dayKey(d);
      byHour[h]++; byWeekday[wd]++; grid[wd][h]++; daily[dk] = (daily[dk] || 0) + 1; monthly[dk.slice(0, 7)] = (monthly[dk.slice(0, 7)] || 0) + 1;
    }
    const dayKeys = Object.keys(daily).sort(), vals = dayKeys.map((k) => daily[k]);
    const med = median(vals), threshold = Math.max(minBinge, med * 3);
    const bingeDays = dayKeys.filter((k) => daily[k] >= threshold).map((k) => ({ date: k, n: daily[k] })).sort((a, b) => b.n - a.n);
    const night = (byHour[0] + byHour[1] + byHour[2] + byHour[3] + byHour[4]) / ev.length;
    // sessions: a break of more than gapSec starts a new one
    const sessions = []; let cur = null;
    for (const e of ev) { if (!cur || e.t - cur.last > gapSec) { cur = { start: e.t, last: e.t, n: 1 }; sessions.push(cur); } else { cur.last = e.t; cur.n++; } }
    sessions.forEach((s) => { s.min = (s.last - s.start) / 60; });
    const longest = sessions.reduce((m, s) => (!m || s.min > m.min ? s : m), null);
    // trend: last 30 days vs the 30 before (only when the series is long enough to say)
    let trend = null;
    if (days >= 60) {
      const a = ev.filter((e) => e.t > to - 30 * 86400).length, b = ev.filter((e) => e.t <= to - 30 * 86400 && e.t > to - 60 * 86400).length;
      if (b >= 20) trend = { last: a, prev: b, change: (a - b) / b };
    }
    const trimmed = Object.fromEntries(dayKeys.slice(-200).map((k) => [k, daily[k]]));
    return {
      n: ev.length, from, to, days, activeDays: dayKeys.length, perActiveDay: med, meanPerActiveDay: ev.length / dayKeys.length, maxDay: Math.max(...vals),
      byHour, byWeekday, grid, daily: trimmed, monthly, nightShare: night, peakHour: byHour.indexOf(Math.max(...byHour)), peakWeekday: byWeekday.indexOf(Math.max(...byWeekday)),
      binge: { threshold, days: bingeDays.slice(0, 8), count: bingeDays.length },
      sessions: { count: sessions.length, medianMin: median(sessions.map((s) => s.min)), longest: longest ? { min: longest.min, n: longest.n, date: dayKey(new Date(longest.start * 1000)) } : null, perActiveDay: sessions.length / dayKeys.length },
      trend,
    };
  }
  const topTerms = (events, n) => { const m = {}; events.forEach((e) => { const k = (e.text || "").trim().toLowerCase(); if (k) m[k] = (m[k] || 0) + 1; }); return Object.entries(m).sort((a, b) => b[1] - a[1]).slice(0, n).map(([q, c]) => ({ q, n: c })); };
  const countBy = (arr, f) => { const m = {}; arr.forEach((e) => { const k = f(e); m[k] = (m[k] || 0) + 1; }); return m; };

  /* ---------- the rules the verdict is built from (also shown to the user) ---------- */
  const RULES = [
    { id: "ig-likes", platform: "Instagram", what: "Likes on a typical active day", bands: "< 30 fine · 30–60 · 60–120 · > 120" },
    { id: "ig-stories", platform: "Instagram", what: "Stories viewed on a typical day", bands: "< 50 fine · 50–150 · 150–300 · > 300" },
    { id: "yt-views", platform: "YouTube", what: "Videos watched on a typical active day", bands: "< 15 fine · 15–40 · 40–80 · > 80" },
    { id: "night", platform: "Both", what: "Share of activity between midnight and 5am", bands: "< 5% fine · 5–10% · 10–15% · 15–25% · 25–35% · > 35%" },
    { id: "binge", platform: "Both", what: "Unusually heavy days (3× your normal, per 30 days)", bands: "< 0.5 fine · 0.5–2 · 2–5 · > 5" },
    { id: "session-ig", platform: "Instagram", what: "Longest unbroken run (a gap of 10 minutes ends it)", bands: "< 30 min fine · 30–60 · 60–120 · > 120" },
    { id: "session-yt", platform: "YouTube", what: "Longest unbroken run (a gap of 30 minutes ends it)", bands: "< 60 min fine · 60–120 · 120–240 · > 240" },
    { id: "variety", platform: "YouTube", what: "Share of videos from your 10 most-watched channels", bands: "< 50% fine · 50–70% · > 70%" },
    { id: "trend", platform: "Both", what: "Last 30 days vs the 30 before", bands: "< +40% fine · +40–100% · > +100%" },
    { id: "tone", platform: "Both", what: "Share of captions / titles with a heavy emotional tone", bands: "< 10% fine · 10–20% · 20–30% · > 30%" },
  ];

  /* ---------- judgement ---------- */
  function judge(platform, P) {
    const f = []; let score = 100;
    const add = (o) => { score -= o.penalty || 0; f.push(o); };
    const sev = (p, hi, mid) => (p >= hi ? "high" : p >= mid ? "watch" : p > 0 ? "info" : "good");
    const S = P.series;
    const basis = (s, what) => `${nf(s.n)} ${what} over ${s.days} day${s.days === 1 ? "" : "s"}`;

    if (platform === "ig") {
      const L = S.likes;
      if (L && L.n >= 30) {
        const m = Math.round(L.perActiveDay), p = m < 30 ? 0 : m < 60 ? 5 : m < 120 ? 12 : 20;
        add({ id: "ig-likes", severity: sev(p, 20, 12), title: p >= 12 ? "Heavy liking" : p ? "Fairly active liking" : "Moderate liking", penalty: p, confidence: conf(L.n, L.days), basis: basis(L, "likes"),
          text: `Active on ${L.activeDays} of ${L.days} days. A typical active day has about ${m} likes (the busiest had ${L.maxDay}).`,
          tip: p ? "Likes happen while scrolling, so this is a good proxy for time spent. A daily limit in Instagram's Time Management can help." : "Nothing to change here." });
      }
      const T = S.stories;
      if (T && T.n >= 100) {
        const m = Math.round(T.perActiveDay), p = m < 50 ? 0 : m < 150 ? 5 : m < 300 ? 12 : 18;
        add({ id: "ig-stories", severity: sev(p, 18, 12), title: p >= 12 ? "High story volume" : p ? "Regular story viewing" : "Light story viewing", penalty: p, confidence: conf(T.n, T.days), basis: basis(T, "stories viewed"),
          text: `About ${m} stories viewed on a typical day (peak ${T.maxDay}). Stories autoplay one after another, so volume adds up quickly.`,
          tip: p ? "Muting or hiding accounts you don't care about shortens the story tray a lot." : "" });
      }
    }
    if (platform === "yt") {
      const V = S.views;
      if (V && V.n >= 30) {
        const m = Math.round(V.perActiveDay), p = m < 15 ? 0 : m < 40 ? 5 : m < 80 ? 12 : 20;
        add({ id: "yt-views", severity: sev(p, 20, 12), title: p >= 12 ? "Frequent watching" : p ? "Regular watching" : "Light watching", penalty: p, confidence: conf(V.n, V.days), basis: basis(V, "videos watched"),
          text: `Active on ${V.activeDays} of ${V.days} days, with about ${m} videos on a typical active day (busiest day ${V.maxDay}). YouTube doesn't record watch time, so this counts videos.`,
          tip: p ? "Use YouTube's \"Remind me to take a break\" and turn autoplay off." : "" });
      }
    }
    // night-time: judge on the series with the most data
    const main = Object.values(S).filter(Boolean).sort((a, b) => b.n - a.n)[0];
    const mainName = Object.entries(S).find(([, v]) => v === main)?.[0];
    if (main && main.n >= 100) {
      const ns = main.nightShare, p = ns < 0.05 ? 0 : ns < 0.1 ? 4 : ns < 0.15 ? 8 : ns < 0.25 ? 14 : ns < 0.35 ? 20 : 25;
      add({ id: "night", severity: sev(p, 20, 8), title: p >= 8 ? "Late-night activity" : p ? "Some late-night activity" : "Little late-night activity", penalty: p, confidence: conf(main.n, main.days), basis: basis(main, mainName === "likes" ? "likes" : mainName === "stories" ? "stories" : "views"),
        text: `${pct(ns)}% of activity happens between midnight and 5am. The busiest hour is ${hourLabel(main.peakHour)}, and ${WD[main.peakWeekday]} is the busiest day.`,
        tip: p ? `Set a wind-down time and use ${platform === "ig" ? "Sleep mode" : "Bedtime reminders"} so scrolling stops before sleep.` : "A healthy pattern for sleep." });
    }
    // binge days
    const bs = Object.entries(S).filter(([, v]) => v && v.days >= 7 && v.n >= 40);
    if (bs.length) {
      const tot = bs.reduce((a, [, v]) => a + v.binge.count, 0), days = bs.reduce((a, [, v]) => a + v.days, 0), rate = (tot * 30) / Math.max(days, 1);
      const p = rate < 0.5 ? 0 : rate < 2 ? 5 : rate < 5 ? 10 : 15;
      const top = bs.flatMap(([, v]) => v.binge.days).sort((a, b) => b.n - a.n)[0];
      add({ id: "binge", severity: sev(p, 15, 10), title: p >= 10 ? "Unusually heavy days" : tot ? "A few heavy days" : "Steady days", penalty: p, confidence: conf(bs.reduce((a, [, v]) => a + v.n, 0), Math.max(...bs.map(([, v]) => v.days))), basis: `${tot} day${tot === 1 ? "" : "s"} well above normal`,
        text: tot ? `${tot} day${tot === 1 ? "" : "s"} were at least 3× a normal day${top ? `, the biggest on ${friendly(top.date)} with ${nf(top.n)} items` : ""}.` : "No days stand out as much heavier than the rest.",
        tip: tot ? "Look at what happened on those days: a bad day, boredom, or waiting around. Naming the trigger makes it easier to plan around." : "" });
    }
    // longest unbroken run (only where views are timestamped densely)
    const sv = platform === "ig" ? S.views : S.views;
    if (sv && sv.n >= 40 && sv.sessions.longest) {
      const m = sv.sessions.longest.min, lim = platform === "ig" ? [30, 60, 120] : [60, 120, 240], pts = platform === "ig" ? [0, 4, 8, 12] : [0, 5, 10, 15];
      const p = m < lim[0] ? pts[0] : m < lim[1] ? pts[1] : m < lim[2] ? pts[2] : pts[3];
      add({ id: "session", severity: sev(p, pts[3], pts[2]), title: p >= 8 ? "Long unbroken sessions" : p ? "Some long sessions" : "Sessions stay short", penalty: p, confidence: conf(sv.n, sv.days), basis: basis(sv, "timestamped views"),
        text: `Longest unbroken run: about ${Math.round(m)} minutes (${sv.sessions.longest.n} items) on ${friendly(sv.sessions.longest.date)}. The median of ${nf(sv.sessions.count)} sessions is ${mins(sv.sessions.medianMin)}.`,
        tip: p ? "A short pause between sessions breaks the autoplay loop." : "" });
    }
    // variety (YouTube has channel names)
    if (platform === "yt" && P.creators && P.creators.total >= 100) {
      const s = P.creators.top10Share, p = s > 0.7 ? 10 : s > 0.5 ? 5 : 0;
      add({ id: "variety", severity: p ? "watch" : "good", title: p ? "Narrow viewing" : "Varied viewing", penalty: p, confidence: conf(P.creators.total, S.views ? S.views.days : 1), basis: `${nf(P.creators.total)} videos from ${nf(P.creators.unique)} channels`,
        text: `Your 10 most-watched channels make up ${pct(s)}% of what you watch, out of ${nf(P.creators.unique)} channels in total.`,
        tip: p ? "A few channels dominating can narrow what you see. Try a couple of new topics." : "A varied mix is a healthier one." });
    }
    // trend on the longest series
    const tr = Object.values(S).filter((v) => v && v.trend).sort((a, b) => b.n - a.n)[0];
    if (tr) {
      const c = tr.trend.change, p = c > 1 ? 10 : c > 0.4 ? 5 : 0;
      add({ id: "trend", severity: c > 0.4 ? "watch" : c < -0.25 ? "good" : "info", title: c > 0.4 ? "Usage is rising" : c < -0.25 ? "Usage is falling" : "Usage is steady", penalty: p, confidence: conf(tr.n, tr.days), basis: basis(tr, "events"),
        text: `${nf(tr.trend.last)} in the last 30 days versus ${nf(tr.trend.prev)} in the 30 days before (${c >= 0 ? "+" : ""}${pct(c)}%).`,
        tip: c > 0.4 ? "A sudden jump is worth noticing. What changed: stress, boredom, a new habit?" : "" });
    }
    // content tone (from captions / titles)
    const C = P.content;
    if (C && C.classified >= 100) {
      const h = C.heavyShare, p = h < 0.1 ? 0 : h < 0.2 ? 5 : h < 0.3 ? 10 : 15;
      add({ id: "tone", severity: sev(p, 15, 10), title: p >= 10 ? "Heavier-toned content" : p ? "Somewhat heavier-toned content" : "Mostly light-toned content", penalty: p, confidence: C.classified >= 500 ? "medium" : "low", basis: `${nf(C.classified)} of ${nf(C.total)} captions/titles recognised`,
        text: `${pct(h)}% of recognised content carries a heavier emotional tone (sadness, anger, loneliness, stress). Biggest themes: ${C.themes.slice(0, 3).map((t) => t.label).join(", ") || "none recognised"}.`,
        tip: p ? "Heavy content isn't bad in itself, but a feed that is mostly heavy can weigh on mood. Add some lighter accounts and topics." : "" });
    }
    score = Math.max(0, Math.min(100, Math.round(score)));
    const enough = f.length > 0;
    const label = !enough ? "Not enough data" : score >= 80 ? "Balanced" : score >= 60 ? "Mostly healthy, a few things to watch" : score >= 40 ? "Several habits worth a look" : "Needs attention";
    const level = !enough ? "info" : score >= 80 ? "good" : score >= 60 ? "info" : score >= 40 ? "watch" : "high";
    const flagged = f.filter((x) => x.severity === "watch" || x.severity === "high");
    return { score, label, level, findings: f, summary: !enough ? "Not enough history in this export to judge." : flagged.length ? `Worth a look: ${flagged.map((x) => x.title.toLowerCase()).join(", ")}.` : "No habits stand out as a concern." };
  }

  /* ---------- platform reports ---------- */
  function platformReport(platform, events) {
    const P = { src: platform, counts: { byAct: countBy(events, (e) => e.act), byKind: countBy(events, (e) => e.kind) }, series: {} };
    if (platform === "ig") {
      P.series.likes = stats(events.filter((e) => e.act === "like"), { gapSec: 600, minBinge: 60 });
      P.series.stories = stats(events.filter((e) => e.kind === "story" && e.act === "view"), { gapSec: 600, minBinge: 300 });
      P.series.views = stats(events.filter((e) => e.act === "view" && e.kind !== "story"), { gapSec: 600, minBinge: 60 });
      const likes = events.filter((e) => e.act === "like");
      P.mix = { likes: countBy(likes, (e) => e.kind), views: countBy(events.filter((e) => e.act === "view" && e.kind !== "story"), (e) => e.kind) };
      P.searches = { total: events.filter((e) => e.act === "search").length, top: topTerms(events.filter((e) => e.act === "search"), 8) };
      P.controls = { notInterested: events.filter((e) => e.act === "hide" && e.kind === "post").length, topicsHidden: events.filter((e) => e.act === "hide" && e.kind === "profile").map((e) => e.text).filter(Boolean).slice(0, 12), ads: events.filter((e) => e.act === "ad").length };
      P.social = { following: events.filter((e) => e.act === "follow").length, saved: events.filter((e) => e.act === "save").length, comments: events.filter((e) => e.act === "comment").length };
      P.content = NL.imp.themes.summarize(events.filter((e) => ["like", "save", "view"].includes(e.act) && e.text));
    } else {
      const views = events.filter((e) => e.act === "view" && e.kind !== "music");
      P.series.views = stats(views, { gapSec: 1800, minBinge: 60 });
      const cnt = {}; views.forEach((e) => { if (e.by) cnt[e.by] = (cnt[e.by] || 0) + 1; });
      const ranked = Object.entries(cnt).sort((a, b) => b[1] - a[1]), total = ranked.reduce((a, b) => a + b[1], 0);
      P.creators = { total: views.length, withChannel: total, unique: ranked.length, top: ranked.slice(0, 12).map(([name, n]) => ({ name, n })), top10Share: total ? ranked.slice(0, 10).reduce((a, b) => a + b[1], 0) / total : 0 };
      P.mix = { kinds: countBy(events.filter((e) => e.act === "view"), (e) => (e.kind === "video" && /#shorts?\b/i.test(e.text) ? "short" : e.kind)) };
      P.searches = { total: events.filter((e) => e.act === "search").length, top: topTerms(events.filter((e) => e.act === "search"), 8) };
      P.social = { subscriptions: events.filter((e) => e.act === "sub").length, liked: events.filter((e) => e.act === "like").length };
      P.content = NL.imp.themes.summarize(views.map((e) => ({ ...e, text: `${e.text} ${e.by}` })));
    }
    P.verdict = judge(platform, P);
    return P;
  }

  /** events = { ig:[], yt:[] } -> report (summary only; raw items are stored separately). */
  function analyze(events, meta = {}) {
    const report = { version: 2, createdAt: Date.now(), meta, platforms: {} };
    if (events.ig && events.ig.length) report.platforms.ig = platformReport("ig", events.ig);
    if (events.yt && events.yt.length) report.platforms.yt = platformReport("yt", events.yt);
    const ps = Object.values(report.platforms).filter((p) => p.verdict.findings.length);
    if (ps.length) {
      const w = ps.map((p) => Math.log10(1 + Object.values(p.series).filter(Boolean).reduce((a, s) => a + s.n, 0)));
      const score = Math.round(ps.reduce((a, p, i) => a + p.verdict.score * w[i], 0) / w.reduce((a, b) => a + b, 0));
      const flagged = ps.flatMap((p) => p.verdict.findings.filter((x) => x.severity === "watch" || x.severity === "high").map((x) => x.title.toLowerCase()));
      report.overall = { score, label: score >= 80 ? "Balanced" : score >= 60 ? "Mostly healthy, a few things to watch" : score >= 40 ? "Several habits worth a look" : "Needs attention", level: score >= 80 ? "good" : score >= 60 ? "info" : score >= 40 ? "watch" : "high", summary: flagged.length ? `Worth a look: ${[...new Set(flagged)].join(", ")}.` : "No habits stand out as a concern." };
    } else report.overall = { score: null, label: "Not enough data", level: "info", summary: "These files don't contain enough history to judge habits." };
    return report;
  }

  return { analyze, judge, stats, RULES, hourLabel, WD, dayKey };
})();
