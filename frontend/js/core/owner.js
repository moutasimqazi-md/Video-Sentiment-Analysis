/* Owner access for the features that open Instagram sessions, run feed checks and read alerts.
   On the computer running NeuroLens there is nothing to do. Another device connects once from a single-use link made
   on that computer (Feed check > "Use on another device"); the page then remembers it. */
window.NL = window.NL || {};

NL.owner = (() => {
  const KEY = "owner";
  const H = { "ngrok-skip-browser-warning": "1" };
  let token = NL.store.get(KEY, null);
  let pairFailed = false;
  const url = (p) => NL.api.base + p;

  /** Redeem a ?pair=CODE link, if this page was opened from one. */
  async function redeemFromUrl() {
    const code = new URLSearchParams(location.search).get("pair");
    if (!code) return;
    try {
      const r = await fetch(url("api/owner/redeem"), { method: "POST", headers: { ...H, "Content-Type": "application/json" }, body: JSON.stringify({ code }) });
      if (r.ok) { token = (await r.json()).token; NL.store.set(KEY, token); } else pairFailed = true;
    } catch (e) { pairFailed = true; }
    const u = new URL(location.href); u.searchParams.delete("pair"); history.replaceState(null, "", u.pathname + u.search + u.hash); // the single-use code leaves the address bar
  }

  /** true when this browser can use the owner-only features */
  async function ready() {
    await redeemFromUrl();
    try {
      const r = await fetch(url("api/owner/state"), { headers: { ...H, "X-Owner-Token": token || "" } });
      if (r.ok && (await r.json()).ok) return true;
    } catch (e) { /* offline */ }
    if (token) { token = null; NL.store.del(KEY); }
    return false;
  }

  /** JSON call. Throws Error(message) on failure. */
  async function call(method, path, body) {
    let res;
    try {
      res = await fetch(url(path.replace(/^\//, "")), {
        method, headers: { ...H, "Content-Type": "application/json", ...(token ? { "X-Owner-Token": token } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (e) { throw new Error("We can't reach the server right now. Please try again in a moment."); }
    let data = null;
    try { data = await res.json(); } catch (e) { /* no body */ }
    if (!res.ok) throw new Error(res.status === 401 ? "Owner access needed" : (data && typeof data.detail === "string" && data.detail) || `Request failed (${res.status})`);
    return data;
  }

  return { ready, call, has: () => !!token, pairFailed: () => pairFailed, forget: () => { token = null; NL.store.del(KEY); } };
})();
