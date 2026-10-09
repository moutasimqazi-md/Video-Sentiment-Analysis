/* Family page: child profiles, 7-day summaries and recent concern alerts. */
(() => {
  const $ = (id) => document.getElementById(id);
  const WEEK = 7 * 864e5;

  function render() {
    const plan = NL.plan.get();
    const kids = NL.profiles.children();
    $("seatText").textContent = plan.children ? `${kids.length} of ${plan.children} profiles` : "Included in Creator & Family";

    const all = NL.history.list();
    const recent = (id, ms) => all.filter((h) => h.profileId === id && h.createdAt >= Date.now() - ms);

    $("kids").innerHTML = kids.length ? kids.map((c) => {
      const agg = NL.wellbeing.aggregate(recent(c.id, WEEK));
      const body = agg.count
        ? `<div class="alert-banner ${agg.overall.key}" style="margin:12px 0"><div class="ico">${NL.wellbeing.iconSvg(agg.overall)}</div>
            <div><b>${agg.overall.label}</b><p>${agg.count} Reel${agg.count > 1 ? "s" : ""} this week · ${agg.levels.watch + agg.levels.high} flagged</p></div></div>`
        : `<p class="muted" style="margin:12px 0">No Reels reviewed in the last 7 days.</p>`;
      return `<article class="card"><div class="card-head" style="margin:0"><h2 class="h3">${NL.esc(c.name)}${c.age ? ` <span class="muted" style="font-weight:500">· ${c.age}</span>` : ""}</h2>
          <button class="btn sm ghost" data-del="${NL.esc(c.id)}" aria-label="Remove profile: ${NL.esc(c.name)}">${NL.icon("trash", 18)}</button></div>${body}
        <div style="display:flex;gap:8px;flex-wrap:wrap">
          <a class="btn primary sm" href="analyze.html?profile=${encodeURIComponent(c.id)}" aria-label="Analyze a Reel for ${NL.esc(c.name)}">${NL.icon("plus", 16)}Analyze a Reel</a>
          <a class="btn sm" href="report.html?profile=${encodeURIComponent(c.id)}&days=7" aria-label="Weekly report for ${NL.esc(c.name)}">Weekly report</a>
          <a class="btn sm" href="feed.html?profile=${encodeURIComponent(c.id)}" aria-label="Feed monitoring for ${NL.esc(c.name)}">Feed monitoring</a>
          ${NL.imp && NL.imp.store && NL.imp.store.sourcesFor(c.id).length ? NL.imp.store.sourcesFor(c.id).map((s) => `<a class="btn sm" href="habits.html?profile=${encodeURIComponent(c.id)}&src=${s}" aria-label="${s === "ig" ? "Instagram" : "YouTube"} habits report for ${NL.esc(c.name)}">${s === "ig" ? "Instagram" : "YouTube"} report</a>`).join("") : `<a class="btn sm" href="import.html?profile=${encodeURIComponent(c.id)}" aria-label="Import ${NL.esc(c.name)}'s Instagram or YouTube history">Import history</a>`}</div></article>`;
    }).join("") : `<div class="card empty"><div class="e-ico">${NL.icon("users", 32)}</div><h2 class="h3">No child profiles yet</h2><p>Add one to start reviewing their Reels.</p></div>`;

    // alert feed: flagged analyses for any child in the last 14 days
    const flagged = all
      .filter((h) => h.profileId && h.profileId !== "me" && h.createdAt >= Date.now() - 2 * WEEK)
      .map((h) => ({ h, a: NL.wellbeing.assess(h.result) }))
      .filter((x) => x.a.level.key !== "calm")
      .sort((x, y) => (y.a.level.key === "high") - (x.a.level.key === "high") || y.h.createdAt - x.h.createdAt)
      .slice(0, 5);
    $("alerts").innerHTML = flagged.length ? `<div class="card" style="margin-bottom:22px"><div class="card-head"><h2 class="h3">Recent alerts</h2><span class="muted" style="font-size:12px">last 14 days</span></div>
      ${flagged.map(({ h, a }) => `<div class="insight"><div class="ico">${NL.wellbeing.iconSvg(a.level)}</div>${NL.thumbHTML(h, NL.moodEmoji(Object.entries(h.result.averages).sort((x, y) => y[1] - x[1])[0][0]), "th th-sm")}
        <div style="flex:1"><b>${NL.esc(NL.profiles.name(h.profileId))} · ${NL.esc(h.title || "Reel")}</b><span>${NL.esc(a.summary)}</span></div>
        <div class="row-actions">${NL.watchLink(h)}<a class="btn sm" href="results.html?id=${encodeURIComponent(h.id)}" aria-label="View analysis: ${NL.esc(h.title || "Reel")}">View</a></div></div>`).join("")}</div>` : "";
  }

  $("kids").addEventListener("click", (e) => {
    const b = e.target.closest("[data-del]");
    if (b && confirm("Remove this profile and its saved analyses from this browser?")) { NL.profiles.remove(b.dataset.del); render(); }
  });

  $("kAdd").onclick = () => {
    const plan = NL.plan.get();
    const name = $("kName").value.trim(), err = $("kErr");
    err.hidden = true;
    if (NL.profiles.children().length >= plan.children) {
      return NL.upgradeModal(plan.children ? `Your ${plan.name} plan includes ${plan.children} child profiles.` : "Child monitoring profiles are part of Creator & Family and Studio.");
    }
    if (!name) { err.textContent = "Enter a name or nickname."; err.hidden = false; return; }
    if (!$("kConsent").checked) { err.textContent = "Please confirm you'll be open with your child."; err.hidden = false; return; }
    const c = NL.profiles.add(name, $("kAge").value);
    NL.profiles.setActive(c.id);
    $("kName").value = $("kAge").value = ""; $("kConsent").checked = false;
    NL.toast(`${c.name} added`);
    render();
  };

  $("tips").innerHTML = NL.wellbeing.TIPS.map((t) => `<li>${NL.esc(t)}</li>`).join("");
  if (new URLSearchParams(location.search).get("add")) $("kName").focus();
  render();
  NL.hydrateIcons();
})();
