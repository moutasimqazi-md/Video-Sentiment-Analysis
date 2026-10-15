/* Feed check: sign in to Instagram, YouTube, TikTok or Facebook inside a private browser shown in this page, run a check, read the report.
   For a child's account: consent, automatic monitoring settings, and the alerts it raised. */
(() => {
  const $ = (id) => document.getElementById(id);
  const esc = NL.esc, call = (m, p, b) => NL.owner.call(m, p, b);
  const root = document.body.dataset.root || "";
  const params = new URLSearchParams(location.search);
  /* The four sites and which checks each has (the server's GET api/platforms is the authority; this is what the page draws from). */
  const SITES = { ig: { name: "Instagram", icon: "instagram" }, yt: { name: "YouTube", icon: "play" }, tt: { name: "TikTok", icon: "tiktok" }, fb: { name: "Facebook", icon: "facebook" } };
  const MODES = {
    ig: [["explore", "Explore", "compass", "What Instagram suggests to this account"], ["foryou", "For You reels", "film", "The reels feed, scrolled a few times"], ["terms", "Search topics", "search", "Top posts for topics you enter"], ["profile", "Account review", "chart", "How the account's own posts come across"]],
    yt: [["foryou", "Home recommendations", "compass", "The videos YouTube puts on this account's home page"], ["history", "Watch history", "clock", "What this account actually watched recently"], ["terms", "Search topics", "search", "Top videos for topics you enter"]],
    tt: [["foryou", "For You", "film", "The For You feed"], ["explore", "Explore", "compass", "What TikTok suggests to this account"], ["terms", "Search topics", "search", "Top videos for topics you enter"]],
    fb: [["foryou", "Watch feed", "film", "The videos Facebook Watch recommends"], ["explore", "Reels", "compass", "The Reels Facebook recommends"], ["terms", "Search topics", "search", "Top videos for topics you enter"]],
  };
  const KIND = { explore: "Explore", foryou: "For You", terms: "Search topics", profile: "Account review", history: "Watch history" };
  const kindLabel = (site, mode) => ((MODES[site] || []).find((m) => m[0] === mode) || [0, KIND[mode]])[1] || "Check";
  let site = SITES[params.get("platform")] ? params.get("platform") : (() => { try { const v = localStorage.getItem("feed_site"); return SITES[v] ? v : "ig"; } catch (e) { return "ig"; } })();
  const siteName = () => SITES[site].name;
  const qs = () => `?platform=${site}`;
  const LEVEL = { calm: ["Calm", "green"], watch: ["Worth a look", "amber"], high: ["High concern", "coral"] };
  const STEPS = ["Account", "Sign in", "Check", "Report"];

  let pid = params.get("profile") || NL.profiles.active() || "me";
  let monitor = null, session = { connected: null }, scanTimer = null, liveOpen = false, hasReport = false;
  const isChild = () => pid !== "me";
  const nameOf = () => (pid === "me" ? "you" : NL.profiles.name(pid));

  /* ---------- access ---------- */
  async function boot() {
    NL.hydrateIcons();
    if (await NL.owner.ready()) return start();
    $("pairCard").hidden = false;
    if (NL.owner.pairFailed()) { $("pairErr").textContent = "That link has expired or was already used. Make a new one on the computer running NeuroLens."; $("pairErr").hidden = false; }
  }
  async function offerOtherDevice() {
    try { const s = await (await fetch(NL.api.base + "api/owner/state", { headers: { "ngrok-skip-browser-warning": "1" } })).json(); $("otherCard").hidden = !(s.ok && s.local); } catch (e) { $("otherCard").hidden = true; }
  }
  $("otherBtn").onclick = async () => {
    try {
      const r = await call("POST", "api/owner/pair-link");
      $("otherLink").value = `${r.publicUrl || location.origin}/${r.path}`;
      $("otherNote").textContent = r.publicUrl ? "This link opens your public NeuroLens address." : "No public address was found, so this link only works on your home network.";
      $("otherOut").hidden = false;
    } catch (e) { NL.toast(e.message); }
  };
  $("otherCopy").onclick = async () => { try { await navigator.clipboard.writeText($("otherLink").value); NL.toast("Link copied"); } catch (e) { $("otherLink").select(); } };

  /* ---------- which site ---------- */
  function renderSite() {
    const n = siteName(), icon = SITES[site].icon;
    $("siteBar").innerHTML = Object.entries(SITES).map(([k, v]) => `<button class="chip site-chip" type="button" data-site="${k}" aria-pressed="${k === site}">${NL.icon(v.icon, 18)}${esc(v.name)}</button>`).join("");
    document.querySelectorAll("[data-site-name]").forEach((el) => (el.textContent = n));
    $("feedTitle").textContent = `See what ${/^[AEIOU]/i.test(n) ? "an" : "a"} ${n} feed is really showing`;
    $("connHead").textContent = `Sign in to ${n}, privately`;
    $("siteArt").innerHTML = NL.icon(icon, 40);
    $("loginBtn").innerHTML = `${NL.icon(icon, 18)}Open private browser`;
    $("rbCanvas").setAttribute("aria-label", `Private browser showing ${n}. Click and type here to sign in.`);
    $("kinds").innerHTML = `<legend class="sr-only">What to check</legend>` + MODES[site].map(([id, label, ic, desc], i) =>
      `<label class="kind"><input type="radio" name="kind" value="${id}"${i === 0 ? " checked" : ""}><span class="kind-ico">${NL.icon(ic, 20)}</span><span><b>${esc(label)}</b><small>${esc(desc)}</small></span></label>`).join("");
    document.querySelectorAll('input[name="kind"]').forEach((r) => (r.onchange = () => { $("termsRow").hidden = kindValue() !== "terms"; }));
    $("termsRow").hidden = true;
    $("servedNote").innerHTML = site === "yt"
      ? "Home recommendations show what YouTube <b>serves</b> the account. <b>Watch history</b> is the one check that shows what the account actually watched."
      : `This shows what ${esc(n)} <b>serves</b> the account, not what was actually watched. Scrolling the feed counts as viewing those videos, so it can nudge that account's recommendations.`;
    const warn = { yt: "Google sometimes refuses to let a browser it thinks is automated sign in (you may see \"This browser or app may not be secure\"). If that happens, YouTube checks can't run for this account.", tt: "TikTok may ask you to solve a puzzle while signing in. You can do that in the browser here.", fb: "Facebook may ask for a security check or a code the first time. You can complete it in the browser here." }[site];
    $("siteNote").textContent = warn || ""; $("siteNote").hidden = !warn;
  }
  function chooseSite(k) {
    if (!SITES[k] || k === site) return;
    stopLive(); site = k; hasReport = false;
    try { localStorage.setItem("feed_site", site); } catch (e) { /* remembering is optional */ }
    history.replaceState(null, "", `?profile=${pid}&platform=${site}`);
    renderSite(); load();
  }
  $("siteBar").addEventListener("click", (e) => { const b = e.target.closest("[data-site]"); if (b) chooseSite(b.dataset.site); });

  /* ---------- who ---------- */
  function start() {
    $("feedApp").hidden = false;
    offerOtherDevice();
    const kids = NL.profiles.children();
    $("whoSel").innerHTML = `<option value="me">Me</option>` + kids.map((c) => `<option value="${esc(c.id)}">${esc(c.name)} (child)</option>`).join("");
    if (![...$("whoSel").options].some((o) => o.value === pid)) pid = "me";
    $("whoSel").value = pid;
    $("whoSel").onchange = () => { stopLive(); pid = $("whoSel").value; NL.profiles.setActive(pid); history.replaceState(null, "", `?profile=${pid}&platform=${site}`); load(); };
    renderSite();
    load();
    if (params.get("scan")) openScan(params.get("scan"));
  }
  const kindValue = () => document.querySelector('input[name="kind"]:checked').value;

  function renderStepper() {
    const cur = session.connected ? (hasReport ? 3 : 2) : 1;
    $("stepper").innerHTML = STEPS.map((s, i) => `<li class="fk-step ${i < cur ? "done" : i === cur ? "now" : ""}"${i === cur ? ' aria-current="step"' : ""}><span class="fk-dot">${i < cur ? NL.icon("check", 14) : i + 1}</span><span>${s}</span></li>`).join("");
  }

  async function load() {
    clearInterval(scanTimer);
    hasReport = false;
    $("reportBox").hidden = true; $("scanErr").hidden = true; $("loginStatus").textContent = "";
    $("childBox").hidden = !isChild();
    $("consentName").textContent = nameOf();
    try { monitor = (await call("GET", "api/monitors")).find((m) => m.profile_id === pid && (m.platform || "ig") === site) || null; } catch (e) { monitor = null; }
    renderMonitor();
    await refreshSession();
    loadPast();
    loadAlerts();
  }

  /* ---------- session + private browser ---------- */
  async function refreshSession() {
    try { session = await call("GET", `api/sessions/${pid}${qs()}`); } catch (e) { session = { connected: null, login: { state: "idle" } }; }
    const on = !!session.connected;
    $("stageConnect").hidden = on;
    $("scanCard").hidden = !on;
    $("sessText").textContent = on ? `${siteName()} connected · ${NL.fmtDate(session.connected * 1000)}` : "Not connected";
    $("sessHelp").textContent = isChild()
      ? `${NL.profiles.name(pid)} signs in (or you do, together) inside the private browser. Their password never reaches NeuroLens.`
      : "You sign in yourself, inside the private browser. Your password never reaches NeuroLens.";
    if (!liveOpen) $("loginBtn").disabled = isChild() && !$("consentBox").checked;
    renderStepper();
    // a sign-in already in progress (page refreshed): pick it back up
    if (!on && session.login && ["starting", "live"].includes(session.login.state) && !liveOpen) showBrowser();
  }

  function showIdle(msg) {
    liveOpen = false; NL.browserView.close();
    $("rb").hidden = true; $("connIdle").hidden = false;
    $("loginBtn").disabled = isChild() && !$("consentBox").checked;
    $("loginStatus").textContent = msg || "";
  }
  async function showBrowser() {
    liveOpen = true;
    $("connIdle").hidden = true; $("rb").hidden = false;
    $("rb").scrollIntoView({ block: "nearest", behavior: "smooth" });
    await NL.browserView.open(pid, {
      platform: site, host: siteName().toLowerCase() + ".com",
      onState: async (m) => {
        if (m.state === "connected") {
          liveOpen = false;
          try { await call("POST", `api/sessions/${pid}/connected${qs()}`); } catch (e) { /* the session folder is already saved */ }
          NL.browserView.close(); $("rb").hidden = true; $("connIdle").hidden = false;
          NL.toast(`${siteName()} connected`);
          load();
        } else if (m.state === "closed") showIdle("The private browser closed before you signed in. Open it again to continue.");
        else if (m.state === "error") showIdle(m.error || "The private browser couldn't start.");
      },
    });
  }
  function stopLive() { if (liveOpen) { call("POST", `api/sessions/${pid}/login/cancel${qs()}`).catch(() => {}); } liveOpen = false; NL.browserView.close(); }

  $("loginBtn").onclick = async () => {
    $("loginStatus").textContent = "";
    $("loginBtn").disabled = true;
    try {
      if (isChild() && !(monitor && monitor.consent)) {  // record that the child knows before their account is connected
        monitor = await call("PUT", `api/monitors/${pid}`, { name: NL.profiles.name(pid), enabled: false, interval_min: Number($("monEvery").value), consent: true, platform: site });
      }
      await call("POST", `api/sessions/${pid}/login${qs()}`);
    } catch (e) { $("loginStatus").textContent = e.message; $("loginBtn").disabled = false; return; }
    showBrowser();
  };
  $("rbCancel").onclick = () => { stopLive(); showIdle(""); };
  $("logoutBtn").onclick = async () => {
    if (!confirm(`Disconnect ${siteName()} and delete the saved session from this computer? Automatic checks will stop.`)) return;
    await call("DELETE", `api/sessions/${pid}${qs()}`); load();
  };

  /* ---------- monitoring (child) ---------- */
  function renderMonitor() {
    if (!isChild()) return;
    $("consentBox").checked = !!(monitor && monitor.consent);
    $("monOn").checked = !!(monitor && monitor.enabled);
    $("monEvery").value = String((monitor && monitor.interval_min) || 120);
    $("monBadge").hidden = !(monitor && monitor.enabled && monitor.connected);
    const st = monitor && monitor.status;
    $("monStatus").textContent = !monitor ? "Not set up yet." : st === "needs_login" ? "The session expired. Sign in again to resume checks." : monitor.last_scan ? `Last check ${NL.fmtDate(monitor.last_scan * 1000)}.` : monitor.enabled ? "First check runs shortly." : "Automatic checks are off.";
  }
  $("consentBox").onchange = () => { if (!liveOpen) $("loginBtn").disabled = !$("consentBox").checked; };
  $("monSave").onclick = async () => {
    try {
      monitor = await call("PUT", `api/monitors/${pid}`, { name: NL.profiles.name(pid), enabled: $("monOn").checked, interval_min: Number($("monEvery").value), consent: $("consentBox").checked, platform: site });
      NL.toast("Monitoring settings saved");
      renderMonitor(); refreshSession();
    } catch (e) { NL.toast(e.message); }
  };

  /* ---------- run a check ---------- */
  $("scanBtn").onclick = async () => {
    $("scanErr").hidden = true;
    const kind = kindValue();
    const terms = $("termsIn").value.split(",").map((t) => t.trim()).filter(Boolean);
    try {
      if (isChild() && !(monitor && monitor.consent)) throw new Error("Tick the confirmation that your child knows, and save, first.");
      const { id } = await call("POST", "api/scans", { profile: pid, kind, terms, limit: Number($("limitSel").value), platform: site });
      follow(id);
    } catch (e) { $("scanErr").textContent = e.message; $("scanErr").hidden = false; }
  };
  function follow(id) {
    $("scanRun").classList.add("show"); $("scanBtn").hidden = true; $("reportBox").hidden = true;
    clearInterval(scanTimer);
    const tick = async () => {
      let s;
      try { s = await call("GET", `api/scans/${id}`); } catch (e) { return; }
      $("scanStage").textContent = s.stage || "Working";
      const pct = Math.round((s.progress || 0) * 100);
      $("scanBar").style.width = pct + "%"; $("scanProg").setAttribute("aria-valuenow", String(pct));
      if (s.status === "running") return;
      clearInterval(scanTimer);
      $("scanRun").classList.remove("show"); $("scanBtn").hidden = false;
      if (s.status === "error") { $("scanErr").textContent = s.error || "The check couldn't finish."; $("scanErr").hidden = false; refreshSession(); }
      else renderReport(s);
      loadPast(); loadAlerts();
      try { localStorage.setItem("nl_alerts_ping", String(Date.now())); } catch (e) { /* ignore */ }
    };
    scanTimer = setInterval(tick, 2000); tick();
  }
  async function openScan(id) { try { const s = await call("GET", `api/scans/${id}`); if (s.status === "running") follow(id); else renderReport(s); } catch (e) { /* ignore */ } }

  /* ---------- report ---------- */
  function ring(n, total) {
    const f = total ? n / total : 0, C = 2 * Math.PI * 46;
    return `<svg viewBox="0 0 110 110" aria-hidden="true"><circle cx="55" cy="55" r="46" fill="none" stroke="var(--surface-2)" stroke-width="10"/><circle cx="55" cy="55" r="46" fill="none" stroke="url(#rg)" stroke-width="10" stroke-linecap="round" stroke-dasharray="${C.toFixed(1)}" stroke-dashoffset="${(C * (1 - f)).toFixed(1)}" transform="rotate(-90 55 55)"/><defs><linearGradient id="rg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ff8f7e"/><stop offset="1" stop-color="#f4685f"/></linearGradient></defs></svg><div class="rr-num"><b>${n}</b><small>checked</small></div>`;
  }
  function renderReport(s) {
    hasReport = true; renderStepper();
    const sm = s.summary || { lines: [], moods: [] };
    $("reportBox").hidden = false;
    $("repHead").textContent = `${SITES[s.platform || "ig"].name} · ${kindLabel(s.platform || "ig", s.kind)} report`;
    $("repMeta").textContent = `${NL.fmtDate((s.finishedAt || s.createdAt) * 1000)}${sm.username ? " · @" + sm.username : ""} · for ${s.profile === "me" ? "you" : NL.profiles.name(s.profile)}`;
    const total = (s.items || []).length;
    $("repRing").setAttribute("aria-label", `${sm.analyzed || 0} of ${total} items checked`);
    $("repRing").innerHTML = ring(sm.analyzed || 0, total);
    $("repLines").innerHTML = (sm.lines.length ? sm.lines : ["Nothing could be analyzed in this check."]).map((l) => `<li>${esc(l)}</li>`).join("");
    $("repReview").hidden = !(sm.review && sm.review.length);
    $("repReviewList").innerHTML = (sm.review || []).map((l) => `<li>${esc(l)}</li>`).join("");
    $("repMoods").innerHTML = (sm.moods || []).slice(0, 6).map(([m, v]) => `<div class="bar-row"><span class="emo" aria-hidden="true">${NL.moodEmoji(m)}</span><span class="name">${NL.cap(m)}</span><span class="track"><i style="width:${v}%"></i></span><span class="pct">${v}%</span></div>`).join("");
    const items = s.items || [];
    $("repItems").innerHTML = items.filter((i) => i.ok).map((i) => {
      const [lbl, cls] = LEVEL[i.level] || LEVEL.calm;
      return `<article class="feed-item"><a class="fi-thumb" href="${root}pages/results.html?id=${encodeURIComponent(i.jobId)}" aria-label="Open the result for this ${i.kind === "reel" ? "reel" : "post"}"><span class="th-emoji" aria-hidden="true">${NL.moodEmoji(i.mood)}</span><img src="${root}api/thumbnails/${esc(i.jobId)}.jpg" alt="" loading="lazy" onerror="this.remove()"></a>
        <div class="fi-body"><b>${NL.moodEmoji(i.mood)} ${NL.cap(i.mood)}</b><span class="badge ${cls}">${lbl}</span>${i.safety === "review" ? `<span class="badge amber">Revealing?</span>` : ""}
        <small class="muted">${esc(i.source || "")} · ${i.kind === "reel" ? "Reel" : i.kind === "image" ? "Post" : "Video"}</small>
        <a class="fi-link" href="${esc(i.url)}" target="_blank" rel="noopener noreferrer">Open on ${esc(SITES[s.platform || "ig"].name)}<span class="sr-only"> (opens in a new tab)</span></a></div></article>`;
    }).join("");
    const failed = items.filter((i) => !i.ok).length;
    $("repFailed").hidden = !failed;
    $("repFailed").textContent = `${failed} ${failed === 1 ? "item" : "items"} couldn't be checked (private or removed).`;
    $("reportBox").scrollIntoView({ block: "start", behavior: "smooth" });
  }
  $("repPrint").onclick = () => window.print();

  /* ---------- history + alerts ---------- */
  async function loadPast() {
    try {
      const list = await call("GET", `api/scans?profile=${pid}&platform=${site}`);
      $("pastCard").hidden = !list.length;
      $("pastList").innerHTML = list.slice(0, 8).map((s) => `<button class="past-row" data-id="${esc(s.id)}"><b>${esc(kindLabel(s.platform || "ig", s.kind))}</b><span class="muted">${NL.fmtDate(s.createdAt * 1000)} · ${s.status === "done" ? `${s.summary ? s.summary.analyzed : 0} checked` : s.status === "running" ? "running" : "didn't finish"}</span></button>`).join("");
    } catch (e) { $("pastCard").hidden = true; }
  }
  $("pastList").addEventListener("click", (e) => { const b = e.target.closest("[data-id]"); if (b) openScan(b.dataset.id); });
  async function loadAlerts() {
    if (!isChild()) { $("alertsCard").hidden = true; return; }
    try {
      const { alerts } = await call("GET", `api/alerts?profile=${pid}&limit=10`);  // every site that child is checked on
      $("alertsCard").hidden = !alerts.length;
      $("alertList").innerHTML = alerts.map((a) => `<a class="al-row ${a.level}" href="${root}${esc(a.link || "pages/feed.html")}"><span class="al-ico">${NL.icon(a.level === "high" ? "alert" : a.level === "watch" ? "eye" : "check", 16)}</span><span><b>${esc(a.title)}</b><small>${esc(a.body)}</small><em>${NL.fmtDate(a.createdAt * 1000)}</em></span></a>`).join("");
    } catch (e) { $("alertsCard").hidden = true; }
  }

  boot();
})();
