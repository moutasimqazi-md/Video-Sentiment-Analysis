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

  const key = (p) => "imp_" + (p || "me");
  const getReport = (profile) => NL.store.get(key(profile), null);
  /** Saves a report; the previous one is kept as a compact snapshot so the next import can show what changed. */
  function saveReport(profile, report) {
    const prev = getReport(profile);
    if (prev && prev.platforms) report.prev = snapshot(prev);
    return NL.store.set(key(profile), report);
  }
  function snapshot(r) {
    const out = { createdAt: r.createdAt, overall: r.overall && r.overall.score, platforms: {} };
    for (const [k, P] of Object.entries(r.platforms || {})) {
      const s = Object.values(P.series).filter(Boolean).sort((a, b) => b.n - a.n)[0];
      out.platforms[k] = { score: P.verdict.score, night: s ? s.nightShare : null, perDay: s ? s.perActiveDay : null, heavy: P.content ? P.content.heavyShare : null, n: s ? s.n : 0 };
    }
    return out;
  }
  const profilesWithReports = () => ["me", ...NL.profiles.children().map((c) => c.id)].filter((id) => getReport(id));
  async function remove(profile) { NL.store.del(key(profile)); try { await dropEvents(profile); } catch (e) { /* nothing stored */ } }

  return { getEvents, putEvents, getReport, saveReport, profilesWithReports, remove, snapshot };
})();
