/* Background analysis queue. Jobs run on the server, so they keep going while you browse; this module tracks them across pages,
   shows progress in the header tray, saves each result to History when it finishes, and tells you when it's ready.
   One browser tab at a time polls (a tiny leader lock), the others just follow along through localStorage. */
window.NL = window.NL || {};

NL.jobs = (() => {
  const KEY = "jobs", LEADER = "jobs_leader";
  const listeners = { change: [], done: [], error: [] };
  const emit = (t, p) => listeners[t].forEach((f) => { try { f(p); } catch (e) { /* listener errors never break the queue */ } });
  const uid = () => "j" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
  const raw = () => NL.store.get(KEY, []);
  const save = (list) => { NL.store.set(KEY, list.slice(0, 60)); emit("change", list); };
  const root = () => document.body.dataset.root || "";

  const list = () => raw();
  const active = () => raw().filter((j) => ["uploading", "queued", "running"].includes(j.status));
  const get = (id) => raw().find((j) => j.id === id) || null;
  function patch(id, p) { const l = raw(); const j = l.find((x) => x.id === id); if (j) { Object.assign(j, p); save(l); } return j; }
  function add(job) { const j = { id: uid(), createdAt: Date.now(), status: "queued", stage: "Queued", progress: 0, ...job }; save([j, ...raw()]); return j; }
  function remove(id) { save(raw().filter((j) => j.id !== id)); }
  const clearFinished = () => save(raw().filter((j) => ["uploading", "queued", "running"].includes(j.status)));

  /* ---------- starting work ---------- */
  /** Start analyzing a link. Returns the local job immediately; the server job id arrives a moment later. */
  async function startLink(url, opts = {}) {
    const j = add({ kind: "link", url, title: opts.title || url, profileId: opts.profileId || "me", status: "queued", stage: "Sending" });
    try {
      const sid = await NL.api.analyzeLink(url);
      patch(j.id, { serverId: sid });
      poll();
    } catch (e) { fail(j.id, e.message); }
    return j;
  }
  /** Start analyzing an uploaded video or image. Stay on the page until `uploading` finishes. */
  async function startFile(file, opts = {}) {
    const j = add({ kind: "file", title: file.name, thumb: opts.thumb || null, profileId: opts.profileId || "me", status: "uploading", stage: "Uploading", isImage: /^image\//.test(file.type) });
    try {
      const sid = await NL.api.uploadFile(file, (f) => patch(j.id, { progress: f * 0.1, stage: `Uploading ${Math.round(f * 100)}%` }));
      patch(j.id, { serverId: sid, status: "queued", stage: "Queued" });
      poll();
    } catch (e) { fail(j.id, e.message); }
    return j;
  }
  function fail(id, message) { const j = patch(id, { status: "error", stage: "Failed", error: message, finishedAt: Date.now() }); if (j) emit("error", j); }
  function retry(id) { const j = get(id); if (j && j.kind === "link") { remove(id); return startLink(j.url, { profileId: j.profileId, title: j.title }); } }

  /* ---------- polling (leader tab only) ---------- */
  let timer = null;
  const isLeader = () => { const l = NL.store.get(LEADER, null); return !l || l.id === tabId || Date.now() - l.t > 5000; };
  const tabId = uid();
  const beat = () => NL.store.set(LEADER, { id: tabId, t: Date.now() });

  async function tick() {
    if (!active().length) { timer = null; return; }
    if (isLeader()) {
      beat();
      for (const j of active().filter((x) => x.serverId)) {
        try {
          const s = await NL.api.jobStatus(j.serverId);
          if (s.status === "done") finish(j, s.result);
          else if (s.status === "error") fail(j.id, s.error || "Analysis failed");
          else patch(j.id, { status: s.status === "running" ? "running" : "queued", stage: s.stage || "Working", progress: Math.max(j.progress || 0, s.progress || 0) });
        } catch (e) {
          if (/not found|expired|Unknown/i.test(e.message)) fail(j.id, "This analysis expired before it finished. Please run it again.");
          // network hiccups: try again next tick
        }
      }
    }
    timer = setTimeout(tick, 1400);
  }
  function poll() { if (!timer) timer = setTimeout(tick, 400); }

  function finish(j, result) {
    if (get(j.id).status === "done") return;
    NL.usage.record();
    const entry = {
      id: j.serverId, createdAt: Date.now(), result, thumb: j.thumb || null, profileId: j.profileId,
      title: j.title && j.title !== j.url ? j.title : (result.source && result.source.title) || j.title || "Untitled",
      source: j.kind === "link" ? { kind: "link", url: j.url } : { kind: "upload" },
      kindOfMedia: j.isImage ? "image" : "video",
    };
    NL.history.add(entry);
    const done = patch(j.id, { status: "done", stage: "Ready", progress: 1, entryId: entry.id, finishedAt: Date.now(), title: entry.title });
    emit("done", { job: done, entry });
  }

  function on(type, f) { (listeners[type] = listeners[type] || []).push(f); }

  /* keep other tabs in sync */
  addEventListener("storage", (e) => { if (e.key === "nl_" + KEY) emit("change", raw()); });
  addEventListener("beforeunload", (e) => { if (raw().some((j) => j.status === "uploading")) { e.preventDefault(); e.returnValue = ""; } });
  if (active().length) poll();

  return { list, active, get, add, remove, patch, clearFinished, startLink, startFile, retry, on, poll, root };
})();
