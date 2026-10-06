/* Browser-side state: account, plan, usage quota, analysis history.
   Everything lives in localStorage — a real product would move this behind the backend + a payment provider. */
window.NL = window.NL || {};

NL.PLANS = {
  free: {
    id: "free", name: "Starter", monthly: 0, yearly: 0, quota: 5, history: 10,
    link: true, export: true, children: 0, weekly: false, seats: 1,
    blurb: "Analyze your own Reels and download a report.",
    features: ["5 Reel analyses / month", "Paste Instagram Reel links or upload", "Download & print reports", "Emotion timeline + wellbeing signal", "Last 10 analyses saved"],
    off: ["Child monitoring profiles", "Weekly summary reports"],
  },
  pro: {
    id: "pro", name: "Creator & Family", monthly: 12, yearly: 9, quota: 100, history: 200, featured: true,
    link: true, export: true, children: 3, weekly: true, seats: 1,
    blurb: "For creators and parents who want ongoing insight.",
    features: ["100 analyses / month", "3 child monitoring profiles", "Concern alerts on every analysis", "Weekly summary reports", "Full history (200 analyses)", "Priority queue"],
    off: [],
  },
  studio: {
    id: "studio", name: "Studio", monthly: 39, yearly: 29, quota: 500, history: 1000,
    link: true, export: true, children: 10, weekly: true, seats: 5,
    blurb: "For agencies, schools and brand teams.",
    features: ["500 analyses / month", "Everything in Creator & Family", "10 monitoring profiles", "5 team seats", "API access"],
    off: [],
  },
};

NL.store = {
  get(key, fallback) {
    try {
      const raw = localStorage.getItem("nl_" + key);
      return raw == null ? fallback : JSON.parse(raw);
    } catch (e) { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem("nl_" + key, JSON.stringify(value)); return true; } catch (e) { return false; }
  },
  del(key) { try { localStorage.removeItem("nl_" + key); } catch (e) { /* ignore */ } },
};

/* ---- account & plan ---- */
NL.user = {
  get: () => NL.store.get("user", null),
  login(name, email) { NL.store.set("user", { name, email, since: Date.now() }); },
  logout() { NL.store.del("user"); },
};

NL.plan = {
  id: () => NL.store.get("plan", { id: "free" }).id,
  get() { return NL.PLANS[this.id()] || NL.PLANS.free; },
  set(id, cycle) { NL.store.set("plan", { id, cycle: cycle || "monthly", since: Date.now() }); },
  cycle: () => NL.store.get("plan", {}).cycle || "monthly",
};

/* ---- profiles: "me" is implicit; child profiles are for parental monitoring ---- */
NL.profiles = {
  children: () => NL.store.get("children", []),
  get(id) { return this.children().find((c) => c.id === id) || null; },
  add(name, age) {
    const c = { id: "c" + Date.now().toString(36), name, age: Number(age) || null, createdAt: Date.now() };
    NL.store.set("children", [...this.children(), c]);
    return c;
  },
  remove(id) {
    NL.store.set("children", this.children().filter((c) => c.id !== id));
    NL.store.set("history", NL.history.list().filter((h) => h.profileId !== id));
  },
  active: () => NL.store.get("active_profile", "me"),
  setActive(id) { NL.store.set("active_profile", id); },
  name(id) { return id === "me" || !id ? "Me" : (this.get(id) || { name: "Unknown" }).name; },
};

/* ---- monthly usage quota ---- */
NL.usage = {
  _key: () => new Date().toISOString().slice(0, 7),
  count() {
    const u = NL.store.get("usage", {});
    return u.month === this._key() ? u.count : 0;
  },
  left() { return Math.max(0, NL.plan.get().quota - this.count()); },
  record() { NL.store.set("usage", { month: this._key(), count: this.count() + 1 }); },
};

/* ---- history ---- */
NL.history = {
  list: () => NL.store.get("history", []),
  get(id) { return this.list().find((h) => h.id === id) || null; },
  add(entry) {
    const max = NL.plan.get().history;
    const list = [entry, ...this.list().filter((h) => h.id !== entry.id)].slice(0, max);
    if (!NL.store.set("history", list)) {
      // storage full (thumbnails) — retry without the oldest thumbnails
      NL.store.set("history", list.map((h, i) => (i > 4 ? { ...h, thumb: null } : h)));
    }
  },
  update(id, patch) { NL.store.set("history", this.list().map((h) => (h.id === id ? { ...h, ...patch } : h))); },
  remove(id) { NL.store.set("history", this.list().filter((h) => h.id !== id)); },
  clear() { NL.store.del("history"); },
};

/* ---- tiny UI helpers ---- */
NL.toast = (msg) => {
  let t = document.querySelector(".toast");
  if (!t) { t = document.createElement("div"); t.className = "toast"; t.setAttribute("role", "status"); t.setAttribute("aria-live", "polite"); document.body.appendChild(t); }
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(NL._toastT);
  NL._toastT = setTimeout(() => t.classList.remove("show"), 2400);
};

NL.upgradeModal = (reason) => {
  const root = document.body.dataset.root || "";
  const opener = document.activeElement;
  let m = document.getElementById("upgradeModal");
  const close = () => { m.classList.remove("open"); document.body.style.overflow = ""; if (opener && opener.focus) opener.focus(); };
  if (!m) {
    m = document.createElement("div");
    m.id = "upgradeModal";
    m.className = "modal-back";
    document.body.appendChild(m);
    m.addEventListener("click", (e) => { if (e.target === m || (e.target.dataset && e.target.dataset.close)) m._close(); });
    m.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { e.stopPropagation(); m._close(); }
      if (e.key === "Tab") {
        const f = [...m.querySelectorAll("a[href], button")];
        const first = f[0], last = f[f.length - 1];
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    });
  }
  m._close = close;
  m.innerHTML = `<div class="modal" role="dialog" aria-modal="true" aria-labelledby="upTitle" aria-describedby="upDesc">
    <div class="m-ico" aria-hidden="true">${NL.icon("sparkle", 30)}</div><h2 id="upTitle">Upgrade to keep going</h2><p id="upDesc">${NL.esc(reason)}</p>
    <div class="row"><button class="btn" data-close="1">Not now</button>
    <a class="btn primary" href="${root}pages/pricing.html">See plans</a></div></div>`;
  m.classList.add("open");
  document.body.style.overflow = "hidden";
  m.querySelector("a.btn.primary").focus();
};

NL.fmtDate = (ts) => new Date(ts).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
NL.fmtDuration = (s) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;


/* ---- thumbnails + links back to the original video ---- */
/** Best available preview image: browser-made frame (uploads) > sample art > the frame the server saved for this analysis. */
NL.thumbUrl = (h) => {
  const root = document.body.dataset.root || "";
  if (h.thumb) return /^(data:|https?:)/.test(h.thumb) ? h.thumb : root + h.thumb;
  if (h.id && /^[0-9a-f]{32}$/.test(h.id)) return `${root}api/thumbnails/${h.id}.jpg`;
  return null;
};
/** Thumbnail box: the mood emoji shows underneath and is revealed if the image can't load. */
NL.thumbHTML = (h, emoji, cls = "thumb") => {
  const u = NL.thumbUrl(h);
  return `<div class="${cls}" aria-hidden="true"><span class="th-emoji">${emoji}</span>${u ? `<img src="${NL.esc(u)}" alt="" loading="lazy" decoding="async" onerror="this.remove()">` : ""}</div>`;
};
/** The original video/reel link, only if it is a plain http(s) URL. */
NL.sourceUrl = (h) => {
  const u = (h.source && h.source.url) || (h.result && h.result.source && h.result.source.url) || "";
  return /^https?:\/\//i.test(u) ? u : null;
};
NL.platform = (h) => {
  const u = NL.sourceUrl(h);
  if (u) return /instagram\.com/i.test(u) ? "Instagram" : /youtu/i.test(u) ? "YouTube" : "Web";
  const k = (h.source && h.source.kind) || (h.result && h.result.source && h.result.source.kind);
  return k === "upload" ? "Upload" : k === "sample" ? "Sample" : "";
};
/** "Watch" link to the original; empty string when the analysis came from an uploaded file. */
NL.watchLink = (h, { cls = "btn sm ghost", text = "Watch" } = {}) => {
  const u = NL.sourceUrl(h);
  if (!u) return "";
  const kind = NL.platform(h) === "Instagram" ? "reel" : "video";
  return `<a class="${cls}" href="${NL.esc(u)}" target="_blank" rel="noopener noreferrer" aria-label="Watch the original ${kind}: ${NL.esc(h.title || "untitled")} (opens in a new tab)">${NL.icon("external", 15)}${text}</a>`;
};
