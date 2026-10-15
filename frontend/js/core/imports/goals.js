/* Goal alignment: how much of what someone watches or likes helps the goals they chose, and how much works against them.
   Quick estimate from captions, hashtags and titles using the shared taxonomy (shared/taxonomy.json). It never sees the video itself;
   the video check refines it. Pure functions over normalized events, so it runs in the browser and in Node tests. */
window.NL = window.NL || {};
NL.imp = NL.imp || {};

NL.imp.goals = (() => {
  const T = NL.TAXONOMY;
  const classify = NL.imp.themes.makeClassifier(T.topics);
  const GOALS = T.goals, byId = Object.fromEntries(GOALS.map((g) => [g.id, g]));
  const topicLabel = (k) => (T.topics[k] ? T.topics[k].label : k);
  const pct = (x) => Math.round(x * 100);
  const conf = (n, days) => (n >= 500 && days >= 60 ? "high" : n >= 100 && days >= 14 ? "medium" : "low");
  const pad = (n) => String(n).padStart(2, "0");
  const monthKey = (t) => { const d = new Date(t * 1000); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`; };
  const weekKey = (t) => { const d = new Date(t * 1000); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; };
  const textOf = (e) => (e.src === "yt" ? `${e.text || ""} ${e.by || ""}` : e.text || "");

  /** Topics a person is probably best off seeing less of, given the goals they picked (a topic one goal supports is never suggested). */
  function defaultAvoid(goalIds) {
    const sup = new Set(), av = new Set();
    for (const id of goalIds || []) { const g = byId[id]; if (g) { g.supports.forEach((t) => sup.add(t)); g.avoid.forEach((t) => av.add(t)); } }
    return [...av].filter((t) => !sup.has(t));
  }
  /** Drops anything that is not a known goal or topic (saved data can outlive a taxonomy change). */
  function normalize(sel) {
    const goals = [...new Set((sel && sel.goals) || [])].filter((id) => byId[id]);
    const avoid = [...new Set((sel && sel.avoid) || [])].filter((t) => T.topics[t]);
    return { goals, avoid };
  }

  const GROUPS = [
    { key: "watched", label: "What you watched", noun: "watched items", pick: (e) => e.act === "view" && e.kind !== "story" && e.kind !== "music" },
    { key: "liked", label: "What you liked", noun: "liked items", pick: (e) => e.act === "like" },
  ];

  /** events: normalized events (any platform mix). sel: { goals:[ids], avoid:[topic keys] }.
      -> { sel, supports:[topic keys], groups:[ per group: counts, shares, topics, examples, periods ] } */
  function evaluate(events, selection) {
    const sel = normalize(selection);
    const avoid = new Set(sel.avoid), supports = new Set();
    sel.goals.forEach((id) => byId[id].supports.forEach((t) => supports.add(t)));
    avoid.forEach((t) => supports.delete(t)); // what the person chose to avoid wins over what a goal would help
    const groups = [];
    for (const g of GROUPS) {
      const evs = events.filter((e) => g.pick(e) && e.t > 0);
      if (!evs.length) continue;
      const from = Math.min(...evs.map((e) => e.t)), to = Math.max(...evs.map((e) => e.t));
      const days = Math.max(1, Math.ceil((to - from) / 86400) + 1);
      const bucket = days >= 60 ? monthKey : days >= 14 ? weekKey : null;
      const counts = { supports: 0, neutral: 0, against: 0 }, topics = {}, periods = {}, examples = [];
      let classified = 0;
      for (const e of evs) {
        const c = classify(textOf(e));
        if (!c) continue;
        classified++;
        const stance = avoid.has(c.theme) ? "against" : supports.has(c.theme) ? "supports" : "neutral";
        counts[stance]++;
        topics[c.theme] = (topics[c.theme] || 0) + 1;
        if (bucket) { const p = (periods[bucket(e.t)] = periods[bucket(e.t)] || { n: 0, supports: 0, against: 0 }); p.n++; if (stance !== "neutral") p[stance]++; }
        if (stance === "against" && e.url) examples.push({ url: e.url, text: (e.text || "").replace(/\s+/g, " ").slice(0, 140), t: e.t, src: e.src, topic: c.theme, label: topicLabel(c.theme), score: c.score });
      }
      const share = (n) => (classified ? n / classified : 0);
      examples.sort((a, b) => b.score - a.score || b.t - a.t);
      groups.push({
        key: g.key, label: g.label, noun: g.noun, n: evs.length, classified, coverage: classified / evs.length, from, to, days, confidence: conf(classified, days),
        counts, share: { supports: share(counts.supports), neutral: share(counts.neutral), against: share(counts.against) },
        topics: Object.entries(topics).sort((a, b) => b[1] - a[1]).map(([k, n]) => ({ key: k, label: topicLabel(k), n, share: share(n), stance: avoid.has(k) ? "against" : supports.has(k) ? "supports" : "neutral" })),
        examples: examples.slice(0, 8),
        periods: Object.entries(periods).sort().map(([k, v]) => ({ k, ...v })),
        grain: bucket === monthKey ? "month" : bucket === weekKey ? "week" : null,
      });
    }
    return { sel, supports: [...supports], groups };
  }

  /** Plain-language findings for one group, in the same shape the habits report renders ({severity,title,text,tip,confidence,basis}). */
  function findings(group, result) {
    const out = [], g = group, sel = result.sel;
    const basis = `${g.classified.toLocaleString()} of ${g.n.toLocaleString()} ${g.noun} recognised over ${g.days} day${g.days === 1 ? "" : "s"}`;
    const base = { confidence: g.confidence, basis };
    if (g.classified < 20) {
      return [{ severity: "info", title: "Too few items recognised", text: `Only ${g.classified} of ${g.n} ${g.noun} matched a topic, which is too few to say anything reliable. Captions and titles are often short or empty, so this is a rough guide at best.`, tip: "The video check looks at what is in the videos themselves, so it does not depend on captions.", ...base }];
    }
    const sup = g.topics.filter((t) => t.stance === "supports");
    if (sel.goals.length && result.supports.length) {
      const s = g.share.supports, top = sup.slice(0, 3).map((t) => t.label).join(", ");
      out.push({ severity: s >= 0.4 ? "good" : s >= 0.15 ? "info" : "watch", title: s >= 0.4 ? "Much of it supports your goals" : s >= 0.15 ? "Some of it supports your goals" : "Little of it supports your goals", ...base,
        text: s > 0 ? `About ${pct(s)}% of the items we could place are about topics that help your goals${top ? ` (mostly ${top})` : ""}.` : "None of the items we could place were about topics that help your goals.",
        tip: s < 0.15 ? "Following a few accounts on these topics, and searching for them, teaches the feed to show more of them." : "" });
    }
    const against = g.topics.filter((t) => t.stance === "against");
    const a = g.share.against;
    if (sel.avoid.length) {
      out.push({ severity: a >= 0.25 ? "high" : a >= 0.1 ? "watch" : a > 0 ? "info" : "good", title: a >= 0.25 ? "A lot of content you wanted to see less of" : a >= 0.1 ? "Some content you wanted to see less of" : a > 0 ? "Only a little content you wanted to see less of" : "Nothing you wanted to see less of", ...base,
        text: a > 0 ? `About ${pct(a)}% of the items we could place (${g.counts.against.toLocaleString()}) are about topics you chose to see less of.` : "None of the items we could place were about topics you chose to see less of.",
        tip: "" });
    }
    for (const t of against.slice(0, 3)) {
      if (t.share < 0.03) continue;
      const tip = (T.topics[t.key] && T.topics[t.key].tip) || "Use \"Not interested\" on these and mute the accounts that post them.";
      out.push({ severity: t.share >= 0.15 ? "high" : "watch", title: `${t.label}: ${pct(t.share)}%`, ...base, text: `${t.n.toLocaleString()} of the ${g.classified.toLocaleString()} items we could place were about ${t.label.toLowerCase()}.`, tip });
    }
    return out;
  }

  return { GOALS, byId, topicLabel, defaultAvoid, normalize, evaluate, findings, classify };
})();
