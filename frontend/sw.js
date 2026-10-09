/* NeuroLens service worker: shows push notifications for feed-check alerts, even when no NeuroLens tab is open. */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { body: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.title || "NeuroLens", {
    body: d.body || "",
    icon: new URL("assets/img/apple-touch-icon.png", self.registration.scope).href,
    badge: new URL("assets/img/favicon-48.png", self.registration.scope).href,
    data: { url: d.url || "pages/feed.html" },
    tag: d.url || "neurolens",
  }));
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL(e.notification.data && e.notification.data.url || "pages/feed.html", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) if ("focus" in c) { c.navigate(url); return c.focus(); }
    return self.clients.openWindow(url);
  }));
});
