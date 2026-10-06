/* Injects the shared header + footer and wires site-wide behaviour (theme, menus, scroll effects, reveal).
   Pages set <body data-root="../" data-active="analyze"> and include <div id="site-header"></div> / <div id="site-footer"></div>. */
(() => {
  const root = document.body.dataset.root || "";
  const active = document.body.dataset.active || "";
  const page = (p) => `${root}pages/${p}.html`;

  // Light is the default; dark only when the visitor chose it.
  const theme = NL.store.get("theme", "light");
  document.documentElement.dataset.theme = theme;

  const LOGO = `<img class="logo-img" src="${root}assets/img/logo-mark.png" alt="" width="34" height="37" decoding="async">`;
  const BRAND = `${LOGO}<span class="wm">Neuro<b>Lens</b></span>`;
  NL.LOGO = LOGO;
  NL.BRAND = BRAND;

  const links = [
    ["home", "Home", `${root}index.html`, "film"],
    ["dashboard", "Dashboard", page("dashboard"), "chart"],
    ["analyze", "Analyze", page("analyze"), "instagram"],
    ["family", "Family", page("family"), "users"],
    ["history", "History", page("history"), "history"],
    ["pricing", "Pricing", page("pricing"), "star"],
    ["about", "About", page("about"), "shield"],
  ];

  function header() {
    const user = NL.user.get();
    const plan = NL.plan.get();
    // History / Account / Report live under the Dashboard tab in the top bar (the sidebar shows the exact page)
    const navActive = { history: "dashboard", account: "dashboard", report: "dashboard", results: "dashboard" }[active] || active;
    const nav = links.filter(([k]) => k !== "history").map(([k, t, h]) => `<a href="${h}" class="${k === navActive ? "active" : ""}"${k === navActive ? ' aria-current="page"' : ""}>${t}</a>`).join("");
    const mnav = links.map(([k, t, h, i]) => `<a class="link ${k === active ? "active" : ""}" href="${h}"${k === active ? ' aria-current="page"' : ""}>${NL.icon(i, 20)}${t}</a>`).join("");
    const right = user
      ? `<span class="plan-chip">${NL.esc(plan.name)}</span>
         <div class="menu-wrap"><button class="avatar" id="userBtn" aria-label="Account menu" aria-haspopup="true" aria-expanded="false" aria-controls="userMenu">${NL.esc(user.name[0].toUpperCase())}</button>
           <div class="dropdown" id="userMenu"><div class="who"><b>${NL.esc(user.name)}</b>${NL.esc(user.email)}</div>
             <a href="${page("dashboard")}">Dashboard</a><a href="${page("account")}">Account &amp; billing</a><a href="${page("history")}">My analyses</a><a href="${page("family")}">Family monitoring</a>
             <button id="logoutBtn">Log out</button></div></div>`
      : `<a class="btn primary sm btn-login" href="${page("login")}">Log in</a>`;

    document.getElementById("site-header").outerHTML = `
      <header class="site-header" id="siteHeader"><div class="container nav">
        <a class="brand" href="${root}index.html" aria-label="NeuroLens home">${BRAND}</a>
        <nav class="nav-links" aria-label="Main">${nav}</nav>
        <div class="nav-right">
          <button class="icon-btn" id="themeBtn" aria-label="Dark mode" aria-pressed="${theme === "dark"}">${NL.icon(theme === "dark" ? "sun" : "moon", 18)}</button>
          ${right}
          <button class="icon-btn menu-btn" id="menuBtn" aria-label="Open menu" aria-expanded="false" aria-controls="mobileNav">${NL.icon("menu", 20)}</button>
        </div></div></header>
      <div class="mobile-nav" id="mobileNav" role="dialog" aria-modal="true" aria-label="Menu">
        <div class="top"><a class="brand" href="${root}index.html">${BRAND}</a><button class="icon-btn" id="menuClose" aria-label="Close menu">${NL.icon("close", 20)}</button></div>
        ${mnav}<div class="spacer"></div>
        ${user ? `<a class="btn full" href="${page("account")}">Account</a>` : `<a class="btn primary full lg" href="${page("login")}">Log in</a>`}
      </div>`;
  }

  function footer() {
    document.getElementById("site-footer").outerHTML = `
      <footer class="site-footer">
        <div class="container footer-grid">
          <div><a class="brand" href="${root}index.html">${BRAND}</a>
            <p>Understand the emotions behind every Instagram Reel — for the content you make and the content your family watches.</p>
            <div class="footer-trust"><span>${NL.icon("lock", 14)}Videos deleted after analysis</span><span>${NL.icon("shield", 14)}Private by design</span></div></div>
          <div><h2 class="foot-h">Product</h2><a href="${page("dashboard")}">Dashboard</a><a href="${page("analyze")}">Analyze a Reel</a><a href="${page("import")}">Import your data</a><a href="${page("family")}">Family monitoring</a><a href="${page("history")}">History</a><a href="${page("pricing")}">Pricing</a></div>
          <div><h2 class="foot-h">Learn</h2><a href="${root}index.html#how">How it works</a><a href="${page("results")}?id=sample">Sample report</a><a href="${root}index.html#faq">FAQ</a><a href="${page("about")}">About</a></div>
          <div><h2 class="foot-h">Account</h2><a href="${page("login")}">Log in</a><a href="${page("account")}">Billing</a><a href="${page("history")}">My analyses</a></div>
        </div>
        <div class="container footer-bottom"><span>© ${new Date().getFullYear()} NeuroLens. All rights reserved.</span><span class="footer-legal"><a href="${page("privacy")}">Privacy</a><a href="${page("terms")}">Terms</a><span>Emotion insights are a guide, not a diagnosis.</span></span></div>
      </footer>`;
  }

  header();
  footer();

  /* App shell: account pages share one persistent sidebar (set <body data-shell="app" data-nav="history">). */
  function appShell() {
    const main = document.querySelector("main");
    if (!main || document.body.dataset.shell !== "app") return;
    const cur = document.body.dataset.nav || "";
    const item = (key, href, icon, label) => `<a href="${href}"${cur === key ? ' class="active" aria-current="page"' : ""}>${NL.icon(icon, 18)}${label}</a>`;
    const p = NL.plan.get(), used = NL.usage.count();
    const shell = document.createElement("div");
    shell.className = "container dash-shell";
    shell.innerHTML = `<aside class="dash-side no-print" aria-label="Account area">
      <nav class="side-nav" aria-label="Account sections">
        ${item("overview", page("dashboard"), "chart", "Overview")}
        ${item("analyze", page("analyze"), "plus", "New analysis")}
        ${item("import", page("import"), "upload", "Import data")}
        ${item("history", page("history"), "history", "History")}
        ${item("family", page("family"), "users", "Family")}
        ${item("report", page("report") + "?profile=me&days=30", "file", "Monthly report")}
        ${item("account", page("account"), "settings", "Account")}
      </nav>
      <div class="side-plan card" id="sidePlan"><div class="pn"><span>${NL.esc(p.name)}</span><span class="plan-chip">${p.monthly ? "Paid" : "Free"}</span></div>
        <div class="progress" role="progressbar" aria-label="Analyses used this month" aria-valuemin="0" aria-valuemax="${p.quota}" aria-valuenow="${used}"><i style="width:${Math.min(100, (used / p.quota) * 100)}%"></i></div>
        <small>${used} of ${p.quota} analyses used this month</small>
        ${NL.plan.id() === "studio" ? "" : `<a class="btn primary sm full" href="${page("pricing")}">Upgrade plan</a>`}</div>
    </aside>`;
    main.parentNode.insertBefore(shell, main);
    main.classList.remove("container", "page");
    main.classList.add("dash-main", "app-page");
    shell.appendChild(main);
    const act = shell.querySelector(".side-nav a.active"), bar = shell.querySelector(".side-nav");
    if (act) requestAnimationFrame(() => { bar.scrollLeft = act.offsetLeft - (bar.clientWidth - act.offsetWidth) / 2; });
  }
  appShell();

  /* Smart back links: <a class="back" data-back href="fallback.html" data-back-label="Back to history"
       [data-back-skip="analyze,login"] [data-back-optional]><span class="back-label"></span></a>
     - came from another page on this site  -> "Back to <that page>" and really goes back (keeps scroll/filters)
     - opened directly / new tab / from a flow page we skip -> the fallback destination
     - data-back-optional hides the link when there is nothing sensible to go back to */
  (function backLinks() {
    const NAMES = { index: "Home", dashboard: "Dashboard", analyze: "Analyze", results: "the results", history: "History", family: "Family",
      pricing: "Pricing", account: "Account", report: "the report", checkout: "Checkout", login: "Log in", about: "About", privacy: "Privacy", terms: "Terms" };
    let ref = null;
    try {
      if (document.referrer) {
        const u = new URL(document.referrer);
        if (u.origin === location.origin && u.pathname !== location.pathname) ref = u;
      }
    } catch (e) { /* ignore */ }
    document.querySelectorAll("a[data-back]").forEach((a) => {
      const text = a.querySelector(".back-label");
      const fallback = a.dataset.backLabel || "Back";
      const skip = (a.dataset.backSkip || "").split(",").filter(Boolean);
      const file = ref ? (ref.pathname.split("/").pop().replace(".html", "") || "index") : null;
      const name = file && !skip.includes(file) ? NAMES[file] : null;
      if (name) {
        text.textContent = `Back to ${name}`;
        a.setAttribute("href", ref.pathname + ref.search);
        a.addEventListener("click", (e) => { if (history.length > 1) { e.preventDefault(); history.back(); } });
      } else {
        text.textContent = fallback;
        if (a.hasAttribute("data-back-optional")) a.hidden = true;
      }
    });
  })();
  NL.hydrateIcons();

  const $ = (id) => document.getElementById(id);
  $("themeBtn").onclick = () => {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    NL.store.set("theme", next);
    $("themeBtn").innerHTML = NL.icon(next === "dark" ? "sun" : "moon", 18);
    $("themeBtn").setAttribute("aria-pressed", String(next === "dark"));
  };
  const mnav = $("mobileNav");
  const openMenu = () => { mnav.classList.add("open"); $("menuBtn").setAttribute("aria-expanded", "true"); document.body.style.overflow = "hidden"; $("menuClose").focus(); };
  const closeMenu = () => { if (!mnav.classList.contains("open")) return; mnav.classList.remove("open"); $("menuBtn").setAttribute("aria-expanded", "false"); document.body.style.overflow = ""; $("menuBtn").focus(); };
  $("menuBtn").onclick = openMenu;
  $("menuClose").onclick = closeMenu;
  mnav.addEventListener("click", (e) => { if (e.target.closest("a")) { mnav.classList.remove("open"); document.body.style.overflow = ""; } });
  // keep keyboard focus inside the open menu
  mnav.addEventListener("keydown", (e) => {
    if (e.key !== "Tab") return;
    const f = [...mnav.querySelectorAll("a[href], button")];
    const first = f[0], last = f[f.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });
  const ub = $("userBtn");
  if (ub) {
    const um = $("userMenu");
    const setUm = (open) => { um.classList.toggle("open", open); ub.setAttribute("aria-expanded", String(open)); };
    ub.onclick = (e) => { e.stopPropagation(); const open = !um.classList.contains("open"); setUm(open); if (open) um.querySelector("a").focus(); };
    document.addEventListener("click", () => setUm(false));
    um.addEventListener("keydown", (e) => {
      if (e.key === "Escape") { setUm(false); ub.focus(); }
      if (e.key === "Tab") { const f = [...um.querySelectorAll("a, button")]; if (!e.shiftKey && document.activeElement === f[f.length - 1]) setUm(false); }
    });
    $("logoutBtn").onclick = () => { NL.user.logout(); location.href = `${root}index.html`; };
  }
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeMenu();
  });

  // header gets a border + shadow once the page scrolls
  const sh = $("siteHeader");
  const onScroll = () => sh.classList.toggle("scrolled", window.scrollY > 8);
  onScroll();
  addEventListener("scroll", onScroll, { passive: true });

  // scroll-reveal for .reveal elements
  NL.observeReveal = (scope = document) => {
    const els = scope.querySelectorAll(".reveal:not(.in)");
    if (!("IntersectionObserver" in window)) { els.forEach((e) => e.classList.add("in")); return; }
    const io = new IntersectionObserver((entries) => entries.forEach((en) => {
      if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
    }), { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    els.forEach((e) => io.observe(e));
  };
  NL.observeReveal();
})();
