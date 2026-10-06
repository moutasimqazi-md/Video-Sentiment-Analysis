/* History page: list, search, sort, delete saved analyses. */
(() => {
  const $ = (id) => document.getElementById(id);
  const root = document.body.dataset.root;

  const top = (h) => Object.entries(h.result.averages).sort((a, b) => b[1] - a[1])[0];

  function usage() {
    const plan = NL.plan.get();
    const used = NL.usage.count();
    $("usedText").textContent = `${used} of ${plan.quota} analyses (${plan.name})`;
    $("usedBar").style.width = Math.min(100, (used / plan.quota) * 100) + "%";
  }

  function render() {
    const q = $("search").value.trim().toLowerCase();
    const pf = $("profile").value;
    $("weekly").href = `report.html?profile=${encodeURIComponent(pf === "all" ? "me" : pf)}&days=7`;
    let items = NL.history.list().filter((h) => (pf === "all" || (h.profileId || "me") === pf) && (!q || (h.title || "").toLowerCase().includes(q) || top(h)[0].includes(q)));
    const sort = $("sort").value;
    items.sort((a, b) => sort === "old" ? a.createdAt - b.createdAt : sort === "pct" ? top(b)[1] - top(a)[1] : b.createdAt - a.createdAt);

    if (!items.length) {
      const none = NL.history.list().length === 0;
      $("list").innerHTML = `<div class="empty"><div class="e-ico">${NL.icon("film", 32)}</div><h3>${none ? "No analyses yet" : "Nothing matches your search"}</h3>
        <p style="margin:8px 0 16px">${none ? "Run your first analysis, or open the sample report to see what you'll get." : "Try a different word."}</p>
        ${none ? `<a class="btn primary" href="analyze.html">Analyze a video</a> <a class="btn" href="results.html?id=sample">Sample report</a>` : ""}</div>`;
      return;
    }
    $("list").innerHTML = items.map((h) => {
      const [m, v] = top(h);
      return `<article class="card hist-item">
        ${NL.thumbHTML(h, NL.moodEmoji(m))}
        <div class="info"><b>${NL.esc(h.title || "Untitled video")}</b>
          <span><span>${NL.moodEmoji(m)} ${NL.cap(m)} ${v.toFixed(1)}%</span><span>${NL.fmtDate(h.createdAt)}</span><span>${NL.esc(NL.profiles.name(h.profileId))}</span>${NL.platform(h) ? `<span>${NL.platform(h)}</span>` : ""}${(() => { const l = NL.wellbeing.assess(h.result).level; return `<span class="lvl ${l.key}"><i></i>${l.label}</span>`; })()}</span></div>
        <div class="hist-actions">${NL.watchLink(h)}<a class="btn sm" href="results.html?id=${encodeURIComponent(h.id)}" aria-label="Open analysis: ${NL.esc(h.title || "Untitled video")}">Open</a>
          <button class="btn sm ghost" data-del="${NL.esc(h.id)}" aria-label="Delete analysis: ${NL.esc(h.title || "Untitled video")}">${NL.icon("trash", 18)}</button></div></article>`;
    }).join("");
  }

  $("list").addEventListener("click", (e) => {
    const b = e.target.closest("[data-del]");
    if (b) { NL.history.remove(b.dataset.del); render(); NL.toast("Deleted"); }
  });
  $("clearAll").onclick = () => { if (confirm("Delete all saved analyses from this browser?")) { NL.history.clear(); render(); } };
  $("profile").innerHTML = `<option value="all">Everyone</option><option value="me">Me</option>` +
    NL.profiles.children().map((c) => `<option value="${NL.esc(c.id)}">${NL.esc(c.name)}</option>`).join("");
  $("profile").onchange = render;
  $("search").oninput = render;
  $("sort").onchange = render;
  usage();
  render();
})();
