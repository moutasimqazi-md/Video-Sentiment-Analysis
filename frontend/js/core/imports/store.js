/* Storage for imports. Reports (summaries) live in localStorage; the browsable items (15k+ rows) live in IndexedDB.
   The raw export files are never stored anywhere. */
window.NL = window.NL || {};
NL.imp = NL.imp || {};

NL.imp.store = (() => {
  const DB = "neurolens", STORE = "imports";
  const open = () => new Promise((res, rej) => {
    if (!window.indexedDB) return rej(new Error("IndexedDB is not available in this browser."));
    const r = indexedDB.open(DB, 1);
    r.onupgradeneeded = () => r.result.createObjectStore(STORE);
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  async function run(mode, fn) {
    const db = await open();
    return new Promise((res, rej) => {
      const t = db.transaction(STORE, mode);
      const req = fn(t.objectStore(STORE));
      t.oncomplete = () => { db.close(); res(req ? req.result : undefined); };
      t.onerror = t.onabort = () => { db.close(); rej(t.error); };
    });
  }

  const slim = (e) => ({ s: e.src, k: e.kind, a: e.act, t: e.t, u: e.url, x: (e.text || "").slice(0, 240), b: e.by || "" });
  const unslim = (e) => ({ src: e.s, kind: e.k, act: e.a, t: e.t, url: e.u, text: e.x, by: e.b });

  /** { ig:[], yt:[] } of normalized events for a profile */
  async function getEvents(profile) {
    try {
      const v = await run("readonly", (s) => s.get("items:" + profile));
      return v ? { ig: (v.ig || []).map(unslim), yt: (v.yt || []).map(unslim) } : { ig: [], yt: [] };
    } catch (e) { return { ig: [], yt: [] }; }
  }
  const putEvents = (profile, ev) => run("readwrite", (s) => s.put({ ig: (ev.ig || []).map(slim), yt: (ev.yt || []).map(slim), savedAt: Date.now() }, "items:" + profile));
  const dropEvents = (profile) => run("readwrite", (s) => s.delete("items:" + profile));

  /* One report per profile AND platform: Instagram and YouTube are never merged into a single report. */
  const SRCS = ["ig", "yt"];
  const key = (p, src) => "imp_" + (p || "me") + "_" + src;

  /** Older versions saved one combined report per profile. Split it into one report per platform, once. */
  function migrate() {
    for (const id of ["me", ...NL.profiles.children().map((c) => c.id)]) {
      const old = NL.store.get("imp_" + id, null);
      if (!old || !old.platforms) continue;
      for (const [src, P] of Object.entries(old.platforms)) {
        const v = P.verdict || {};
        const prev = old.prev && old.prev.platforms && old.prev.platforms[src];
        const r = { ...old, platforms: { [src]: P }, overall: { score: v.score ?? null, label: v.label, level: v.level, summary: v.summary }, prev: prev ? { createdAt: old.prev.createdAt, overall: prev.score, platforms: { [src]: prev } } : undefined };
        if (!NL.store.get(key(id, src), null)) NL.store.set(key(id, src), r);
      }
      NL.store.del("imp_" + id);
      const deep = NL.store.get("imp_deep_" + id, null);
      if (deep) { NL.store.del("imp_deep_" + id); for (const src of Object.keys(old.platforms)) NL.store.set("imp_deep_" + id + "_" + src, deep); }
    }
  }

  const getReport = (profile, src) => NL.store.get(key(profile, src), null);
  /** Saves a single-platform report; the previous one is kept as a compact snapshot so the next import can show what changed. */
  function saveReport(profile, src, report) {
    const prev = getReport(profile, src);
    if (prev && prev.platforms) report.prev = snapshot(prev);
    return NL.store.set(key(profile, src), report);
  }
  function snapshot(r) {
    const out = { createdAt: r.createdAt, overall: r.overall && r.overall.score, platforms: {} };
    for (const [k, P] of Object.entries(r.platforms || {})) {
      const s = Object.values(P.series).filter(Boolean).sort((a, b) => b.n - a.n)[0];
      out.platforms[k] = { score: P.verdict.score, night: s ? s.nightShare : null, perDay: s ? s.perActiveDay : null, heavy: P.content ? P.content.heavyShare : null, n: s ? s.n : 0 };
    }
    return out;
  }
  /** Every saved report as { id, src, report } */
  const allReports = () => ["me", ...NL.profiles.children().map((c) => c.id)].flatMap((id) => SRCS.map((src) => ({ id, src, report: getReport(id, src) })).filter((x) => x.report));
  /** The platforms this profile has a report for, e.g. ["ig", "yt"] */
  const sourcesFor = (profile) => SRCS.filter((src) => getReport(profile, src));
  async function remove(profile, src) {
    NL.store.del(key(profile, src));
    try {
      const ev = await getEvents(profile);
      ev[src] = [];
      if (ev.ig.length || ev.yt.length) await putEvents(profile, ev); else await dropEvents(profile);
    } catch (e) { /* nothing stored */ }
  }

  migrate();
  return { getEvents, putEvents, getReport, saveReport, allReports, sourcesFor, remove, snapshot, SRCS };
})();
