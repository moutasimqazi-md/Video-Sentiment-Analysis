/* Caption / title classifier: what is this feed *about*, and what mood does it carry?
   Runs locally on captions, hashtags and titles. It's a keyword estimate (see js/data/lexicon.js), not a model of the video itself. */
window.NL = window.NL || {};
NL.imp = NL.imp || {};

NL.imp.themes = (() => {
  const L = NL.LEXICON;
  const tokenMap = new Map(), tagMap = new Map(), phrases = [];
  const add = (m, k, v) => { if (!m.has(k)) m.set(k, []); m.get(k).push(v); };
  for (const [key, th] of Object.entries(L.themes)) {
    th.tags.forEach((t) => add(tagMap, t.toLowerCase(), key));
    th.words.forEach((w) => { w = w.toLowerCase(); if (/\s/.test(w)) phrases.push([w, key]); else add(tokenMap, w, key); });
  }
  const heavy = new Set(L.heavyMoods);
  const monthKey = (t) => { const d = new Date(t * 1000); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`; };

  /** -> { theme, mood, score } or null when nothing in the text is recognised. */
  function classify(text) {
    const t = (text || "").toLowerCase();
    if (t.length < 3) return null;
    const scores = {};
    const bump = (k, w) => { scores[k] = (scores[k] || 0) + w; };
    for (const m of t.matchAll(/#([\p{L}\p{N}_]+)/gu)) {
      const ks = tagMap.get(m[1]) || tokenMap.get(m[1]);
      if (ks) ks.forEach((k) => bump(k, tagMap.has(m[1]) ? 2 : 1));
    }
    const seen = new Set();
    for (const m of t.replace(/#[\p{L}\p{N}_]+/gu, " ").matchAll(/[\p{L}\p{N}_']+/gu)) {
      if (seen.has(m[0])) continue; seen.add(m[0]);
      const ks = tokenMap.get(m[0]); if (ks) ks.forEach((k) => bump(k, 1));
    }
    for (const [ph, k] of phrases) if (t.includes(ph)) bump(k, 1.5);
    let best = null, b = 0;
    for (const k in scores) if (scores[k] > b) { b = scores[k]; best = k; }
    return best && b >= 1 ? { theme: best, mood: L.themes[best].mood, score: b } : null;
  }

  /** Summarise a list of events (anything with .text). */
  function summarize(events) {
    const total = events.length;
    const themes = {}, moods = {}, months = {}, flagged = [];
    let classified = 0, heavyN = 0;
    for (const e of events) {
      const c = classify(e.text);
      if (!c) continue;
      classified++;
      themes[c.theme] = (themes[c.theme] || 0) + 1;
      moods[c.mood] = (moods[c.mood] || 0) + 1;
      const isHeavy = heavy.has(c.mood);
      if (isHeavy) heavyN++;
      if (e.t) { const m = (months[monthKey(e.t)] = months[monthKey(e.t)] || { n: 0, heavy: 0 }); m.n++; if (isHeavy) m.heavy++; }
      if (isHeavy && c.score >= 2 && e.url) flagged.push({ url: e.url, text: e.text.replace(/\s+/g, " ").slice(0, 140), t: e.t, src: e.src, theme: c.theme, mood: c.mood, score: c.score });
    }
    const pct = (n) => (classified ? (n / classified) * 100 : 0);
    flagged.sort((a, b) => b.t - a.t);
    return {
      total, classified, classifiedShare: total ? classified / total : 0,
      themes: Object.entries(themes).sort((a, b) => b[1] - a[1]).slice(0, 10).map(([k, n]) => ({ key: k, label: L.themes[k].label, mood: L.themes[k].mood, n, share: pct(n) })),
      moods: Object.fromEntries(Object.entries(moods).map(([k, n]) => [k, pct(n)])),
      heavyShare: classified ? heavyN / classified : 0, heavyN,
      monthly: Object.entries(months).sort().map(([m, v]) => ({ m, n: v.n, heavy: v.heavy })),
      flagged: flagged.slice(0, 12),
    };
  }
  return { classify, summarize };
})();
