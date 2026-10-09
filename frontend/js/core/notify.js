/* Alerts bell in the header: unread badge, a list of what your feed checks found, and the switch for browser notifications. */
window.NL = window.NL || {};

NL.notify = (async () => {
  const $ = (id) => document.getElementById(id);
  const wrap = $("alertsWrap"), btn = $("alertsBtn"), panel = $("alertsPanel"), badge = $("alertsBadge");
  if (!wrap || !NL.owner) return null;
  if (!(await NL.owner.ready())) return null;
  const root = document.body.dataset.root || "";
  const ICON = { high: "alert", watch: "eye", info: "check" };
  const when = (t) => { const m = Math.round((Date.now() / 1000 - t) / 60); return m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : NL.fmtDate(t * 1000); };

  let data = { alerts: [], unread: 0 };
  let subscribed = NL.store.get("push_on", false);
  const supported = "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;

  function render() {
    wrap.hidden = false;
    badge.hidden = !data.unread;
    badge.textContent = data.unread > 99 ? "99+" : data.unread;
    btn.setAttribute("aria-label", data.unread ? `${data.unread} unread alerts` : "Alerts");
    const perm = supported ? Notification.permission : "denied";
    const bar = !supported ? "" : subscribed && perm === "granted"
      ? `<p class="al-note">Notifications are on for this browser. <button class="al-link" id="alTest">Send a test</button></p>`
      : perm === "denied" ? `<p class="al-note">Notifications are blocked in this browser's settings.</p>`
      : `<button class="btn sm primary full" id="alEnable">Turn on notifications</button>`;
    panel.innerHTML = `<div class="who">Alerts ${data.unread ? `· ${data.unread} unread` : ""}</div>
      ${data.alerts.length ? data.alerts.slice(0, 8).map((a) => `<a class="al-row ${a.level} ${a.seen ? "" : "unread"}" href="${root}${NL.esc(a.link || "pages/feed.html")}" data-id="${NL.esc(a.id)}">
        <span class="al-ico">${NL.icon(ICON[a.level] || "check", 16)}</span><span><b>${NL.esc(a.title)}</b><small>${NL.esc(a.body)}</small><em>${when(a.createdAt)}</em></span></a>`).join("") : `<p class="al-empty">No alerts yet. They appear here when a feed check finds something worth a look.</p>`}
      <div class="al-foot">${bar}${data.unread ? `<button class="al-link" id="alRead">Mark all read</button>` : ""}<a class="al-link" href="${root}pages/feed.html">Open Feed check</a></div>`;
  }

  async function refresh() {
    try {
      const prev = new Set(data.alerts.map((a) => a.id));
      data = await NL.owner.call("GET", "api/alerts?limit=20");
      // while a tab is open in the background and push isn't set up, still surface new alerts
      if (!subscribed && supported && Notification.permission === "granted" && document.hidden) {
        data.alerts.filter((a) => !a.seen && !prev.has(a.id) && prev.size).forEach((a) => new Notification(a.title, { body: a.body }));
      }
      render();
    } catch (e) { /* try again next tick */ }
  }

  const setOpen = (open) => { panel.classList.toggle("open", open); btn.setAttribute("aria-expanded", String(open)); };
  btn.onclick = (e) => { e.stopPropagation(); setOpen(!panel.classList.contains("open")); };
  document.addEventListener("click", (e) => { if (!panel.contains(e.target)) setOpen(false); });
  panel.addEventListener("keydown", (e) => { if (e.key === "Escape") { setOpen(false); btn.focus(); } });
  panel.addEventListener("click", async (e) => {
    const row = e.target.closest(".al-row");
    if (row && row.dataset.id) NL.owner.call("POST", "api/alerts/read", { ids: [row.dataset.id] }).catch(() => {});
    if (e.target.id === "alRead") { await NL.owner.call("POST", "api/alerts/read", { ids: [] }); refresh(); }
    if (e.target.id === "alEnable") await enablePush();
    if (e.target.id === "alTest") { await NL.owner.call("POST", "api/push/test"); NL.toast("Test notification sent"); }
  });

  const b64 = (s) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(s.length / 4) * 4, "=")), (c) => c.charCodeAt(0));
  async function enablePush() {
    try {
      const perm = await Notification.requestPermission();
      if (perm !== "granted") { render(); return NL.toast("Notifications weren't allowed"); }
      const reg = await navigator.serviceWorker.register(root + "sw.js");
      await navigator.serviceWorker.ready;
      const { key } = await NL.owner.call("GET", "api/push/key");
      const sub = (await reg.pushManager.getSubscription()) || (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: b64(key) }));
      await NL.owner.call("POST", "api/push/subscribe", sub.toJSON());
      subscribed = true; NL.store.set("push_on", true);
      render(); NL.toast("Notifications are on");
    } catch (e) { NL.toast("Couldn't turn on notifications in this browser"); }
  }

  await refresh();
  setInterval(() => { if (!document.hidden) refresh(); }, 45000);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) refresh(); });
  addEventListener("storage", (e) => { if (e.key === "nl_alerts_ping") refresh(); });
  return { refresh };
})();
