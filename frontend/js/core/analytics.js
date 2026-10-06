/* Dashboard analytics over saved analyses: filtering, bucketing, KPIs, insights, CSV export, demo data. */
window.NL = window.NL || {};

NL.analytics = (() => {
  const DAY = 864e5;
  const HEAVY = ["depressed", "heartbroken", "sad", "lost", "angry", "tired"];
  const MOODS = () => Object.keys(NL.MOODS);

  const top = (h) => Object.entries(h.result.averages).sort((a, b) => b[1] - a[1])[0];
  const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0);
  const dayKey = (ts) => { const d = new Date(ts); d.setHours(0, 0, 0, 0); return d.toISOString().slice(0, 10); };

  /** entries for one profile ("me" | child id | "all") inside the last `days` days (0 = all time). */
  function select(entries, { profile = "me", days = 30, offset = 0 } = {}) {
    const end = Date.now() - offset * DAY;
    const start = days ? end - days * DAY : 0;
    return entries
      .filter((h) => (profile === "all" || (h.profileId || "me") === profile) && h.createdAt <= end && h.createdAt >= start)
      .sort((a, b) => a.createdAt - b.createdAt);
  }

  /** Group entries into time buckets sized to the span: daily / weekly / monthly. */
  function buckets(entries, days) {
    if (!entries.length) return [];
    const first = days ? Date.now() - days * DAY : entries[0].createdAt;
    const span = (Date.now() - first) / DAY;
    const size = span <= 21 ? 1 : span <= 120 ? 7 : 30;
    const start = new Date(first); start.setHours(0, 0, 0, 0);
    const out = [];
    for (let t = start.getTime(); t <= Date.now(); t += size * DAY) {
      const items = entries.filter((h) => h.createdAt >= t && h.createdAt < t + size * DAY);
      const d = new Date(t);
      out.push({
        start: t, items,
        label: size === 30 ? d.toLocaleString(undefined, { month: "short" }) : d.toLocaleDateString(undefined, { month: "short", day: "numeric" }),
      });
    }
    return out;
  }

  const avgOf = (items, getter) => mean(items.map(getter).filter((v) => v != null && !Number.isNaN(v)));

  function metrics(entries) {
    const n = entries.length;
    const counts = {};
    entries.forEach((h) => { const m = top(h)[0]; counts[m] = (counts[m] || 0) + 1; });
    const mix = {};
    MOODS().forEach((m) => { mix[m] = avgOf(entries, (h) => h.result.averages[m] || 0); });
    const heavy = entries.filter((h) => NL.wellbeing.assess(h.result).level.key !== "calm").length;
    const withAudio = entries.filter((h) => h.result.audio && h.result.audio.available);
    return {
      n, counts, mix,
      topEmotion: Object.entries(counts).sort((a, b) => b[1] - a[1])[0] || null,
      avgStrength: avgOf(entries, (h) => top(h)[1]),
      avgCuts: avgOf(entries, (h) => (h.result.color_metrics || {}).cuts_per_minute),
      avgBright: avgOf(entries, (h) => (h.result.color_metrics || {}).avg_brightness),
      avgSat: avgOf(entries, (h) => (h.result.color_metrics || {}).avg_saturation),
      avgDuration: avgOf(entries, (h) => h.result.duration_seconds),
      heavyShare: n ? Math.round((heavy / n) * 100) : 0,
      positivity: n ? Math.round(100 - HEAVY.reduce((a, m) => a + mix[m], 0)) : 0,
      withAudio: withAudio.length,
    };
  }

  function delta(cur, prev) {
    if (!prev || !prev) return null;
    if (!prev) return null;
    return Math.round((cur - prev) * 10) / 10;
  }

  function streak(entries) {
    const days = new Set(entries.map((h) => dayKey(h.createdAt)));
    let s = 0;
    for (let d = new Date(); ; d.setDate(d.getDate() - 1)) {
      if (days.has(dayKey(d.getTime()))) s++;
      else if (s === 0 && dayKey(d.getTime()) === dayKey(Date.now())) continue; // today not yet analysed doesn't break it
      else break;
    }
    return s;
  }

  /** Plain-English observations drawn from the numbers. */
  function insights(entries, m, prev) {
    const out = [];
    if (!m.n) return out;
    const [tm, tc] = m.topEmotion;
    out.push({ icon: "target", tone: "coral", title: `Your signature vibe is ${tm}`, text: `${Math.round((tc / m.n) * 100)}% of your analyses lead with ${tm} (${NL.moodLabel(tm)}).` });

    const strength = Math.round(m.avgStrength);
    out.push({ icon: "gauge", tone: "blue", title: strength >= 45 ? "Clear, focused emotion" : "Mixed emotional signal", text: strength >= 45 ? `Your strongest emotion averages ${strength}%. Viewers get a consistent feeling.` : `Your strongest emotion averages only ${strength}%. Picking one feeling to lean into would sharpen the effect.` });

    if (m.avgCuts) {
      const pace = m.avgCuts < 12 ? "slow and calm" : m.avgCuts < 30 ? "medium" : "fast";
      out.push({ icon: "bolt", tone: "amber", title: `Your pacing is ${pace}`, text: `You average ${m.avgCuts.toFixed(0)} cuts per minute. ${m.avgCuts >= 30 ? "Great for holding attention." : "Consider a tighter hook in the first two seconds."}` });
    }

    if (prev && prev.n) {
      const d = Math.round(m.avgStrength - prev.avgStrength);
      if (Math.abs(d) >= 3) out.push({ icon: d > 0 ? "trend" : "chart", tone: d > 0 ? "green" : "amber", title: d > 0 ? "Emotion is getting clearer" : "Emotion is getting blurrier", text: `Your lead emotion strength moved ${d > 0 ? "up" : "down"} ${Math.abs(d)} points versus the previous period.` });
    }
    if (m.heavyShare >= 40) out.push({ icon: "heart", tone: "coral", title: "Heavier tone showing up", text: `${m.heavyShare}% of these Reels carry a heavier emotional tone. If that's intentional, great; if not, balance with lighter content.` });
    if (m.avgBright < 35) out.push({ icon: "sun", tone: "amber", title: "Your videos run dark", text: `Average brightness is ${m.avgBright.toFixed(0)}%. Brighter footage tends to read as warmer and more inviting.` });
    return out;
  }

  function toCSV(entries) {
    const mm = MOODS();
    const rows = [["date", "profile", "title", "dominant", "dominant_pct", "duration_s", "cuts_per_min", "brightness", "saturation", "wellbeing", ...mm]];
    entries.forEach((h) => {
      const [m, v] = top(h), cm = h.result.color_metrics || {};
      rows.push([new Date(h.createdAt).toISOString(), NL.profiles.name(h.profileId), h.title || "", m, v.toFixed(1), h.result.duration_seconds ?? "", cm.cuts_per_minute ?? "", cm.avg_brightness ?? "", cm.avg_saturation ?? "", NL.wellbeing.assess(h.result).level.label, ...mm.map((k) => (h.result.averages[k] ?? 0).toFixed(1))]);
    });
    return rows.map((r) => r.map((c) => `"${String(c).replace(/"/g, '""')}"`).join(",")).join("\n");
  }

  /* ---------- demo data (never saved) ---------- */
  function demo(days = 90, count = 42) {
    let seed = 20261006;
    const rnd = () => { seed = (seed * 1664525 + 1013904223) % 4294967296; return seed / 4294967296; };
    const themes = [
      ["peaceful", 0.30, ["Sunset time-lapse", "Morning coffee ritual", "Beach walk", "Cabin in the woods"]],
      ["hungry", 0.22, ["Street food crawl", "Ramen deep dive", "Brunch spot review", "Dessert tour"]],
      ["motivated", 0.16, ["Gym motivation montage", "5am routine", "Run club recap"]],
      ["happy", 0.14, ["Weekend with friends", "Dance trend", "Puppy tricks"]],
      ["inspired", 0.08, ["Glow-up transformation", "Studio makeover"]],
      ["romantic", 0.05, ["Anniversary trip"]],
      ["sad", 0.05, ["Rainy day thoughts"]],
    ];
    const pick = () => { let r = rnd(), acc = 0; for (const t of themes) { acc += t[1]; if (r <= acc) return t; } return themes[0]; };
    const out = [];
    for (let i = 0; i < count; i++) {
      const [dom, , titles] = pick();
      const age = Math.pow(rnd(), 0.8) * days;                       // more recent activity
      const strength = 34 + rnd() * 32 + (days - age) * 0.08;        // gently improving over time
      const avg = {};
      let rest = 100 - strength;
      const others = MOODS().filter((m) => m !== dom);
      const w = others.map(() => rnd() + 0.05); const ws = w.reduce((a, b) => a + b, 0);
      others.forEach((m, j) => { avg[m] = (w[j] / ws) * rest; });
      avg[dom] = strength;
      const vis = {}; MOODS().forEach((m) => { vis[m] = Math.max(0, avg[m] + (rnd() - 0.5) * 8); });
      const aud = {}; MOODS().forEach((m) => { aud[m] = Math.max(0, avg[m] * 0.7 + rnd() * 6); });
      const audTop = Object.entries(aud).sort((a, b) => b[1] - a[1])[0][0];
      const cuts = 8 + rnd() * 34;
      out.push({
        id: "demo" + i, profileId: "me", createdAt: Date.now() - age * DAY - rnd() * DAY * 0.5,
        title: titles[Math.floor(rnd() * titles.length)],
        result: {
          duration_seconds: 12 + rnd() * 40, frames_analyzed: 12, dominant_mood: dom, averages: avg, visual_averages: vis,
          audio: { available: true, dominant: audTop, loudness_db: -26 + rnd() * 12, averages: aud },
          color_metrics: { cuts_per_minute: Math.round(cuts * 10) / 10, avg_brightness: Math.round((38 + rnd() * 40) * 10) / 10, avg_saturation: Math.round((30 + rnd() * 45) * 10) / 10 },
          verdict: "", timeline: [],
        },
      });
    }
    return out.sort((a, b) => a.createdAt - b.createdAt);
  }

  return { HEAVY, top, mean, dayKey, select, buckets, metrics, delta, streak, insights, toCSV, demo, avgOf };
})();
