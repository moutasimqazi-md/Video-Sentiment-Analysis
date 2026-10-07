/* Header tray for background analyses: a bolt button with a count badge, a panel listing every job, and a "ready" notice with a link. */
window.NL = window.NL || {};

NL.jobTray = (() => {
  const $ = (id) => document.getElementById(id);
  const wrap = $("jobsWrap"), btn = $("jobsBtn"), panel = $("jobsPanel"), badge = $("jobsBadge");
  if (!wrap || !NL.jobs) return null;
  const root = document.body.dataset.root || "";
  const live = (j) => ["uploading", "queued", "running"].includes(j.status);

  function row(j) {
    const pct = Math.round((j.progress || 0) * 100);
    const name = `<b class="jt-title">${NL.esc(j.title || "Untitled")}</b>`;
    if (live(j)) {
      return `<div class="jt-row">${name}<span class="jt-sub">${NL.esc(j.stage || "Working")}</span>
        <div class="progress" role="progressbar" aria-label="${NL.esc(j.title || "Analysis")} progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="${pct}"><i style="width:${pct}%"></i></div></div>`;
    }
    if (j.status === "done") {
      return `<div class="jt-row">${name}<span class="jt-sub ok">Ready</span>
        <span class="jt-actions"><a class="btn sm primary" href="${root}pages/results.html?id=${encodeURIComponent(j.entryId)}">View results</a><button class="btn sm ghost" data-dismiss="${j.id}" aria-label="Dismiss ${NL.esc(j.title || "analysis")}">Dismiss</button></span></div>`;
    }
    return `<div class="jt-row">${name}<span class="jt-sub err">${NL.esc(j.error || "Didn't finish")}</span>
      <span class="jt-actions">${j.kind === "link" ? `<button class="btn sm" data-retry="${j.id}">Try again</button>` : ""}<button class="btn sm ghost" data-dismiss="${j.id}" aria-label="Dismiss ${NL.esc(j.title || "analysis")}">Dismiss</button></span></div>`;
  }

  function render() {
    const list = NL.jobs.list();
    wrap.hidden = !list.length;
    const n = list.filter(live).length;
    badge.hidden = !n;
    badge.textContent = n;
    btn.setAttribute("aria-label", n ? `${n} ${n === 1 ? "analysis" : "analyses"} in progress` : "Analyses");
    btn.classList.toggle("busy", n > 0);
    const finished = list.some((j) => !live(j));
    panel.innerHTML = `<div class="who">${n ? `${n} running in the background` : "Recent analyses"}</div>${list.slice(0, 8).map(row).join("") || `<p class="jt-empty">Nothing running.</p>`}
      ${finished ? `<button class="jt-clear" id="jtClear">Clear finished</button>` : ""}`;
  }

  const setOpen = (open) => { panel.classList.toggle("open", open); btn.setAttribute("aria-expanded", String(open)); };
  btn.onclick = (e) => { e.stopPropagation(); setOpen(!panel.classList.contains("open")); };
  document.addEventListener("click", (e) => { if (!panel.contains(e.target)) setOpen(false); });
  panel.addEventListener("keydown", (e) => { if (e.key === "Escape") { setOpen(false); btn.focus(); } });
  panel.addEventListener("click", (e) => {
    const d = e.target.closest("[data-dismiss]"), r = e.target.closest("[data-retry]");
    if (d) NL.jobs.remove(d.dataset.dismiss);
    else if (r) NL.jobs.retry(r.dataset.retry);
    else if (e.target.id === "jtClear") NL.jobs.clearFinished();
  });

  /* "ready" notice: stays 9 s, has a link, and doesn't steal focus */
  let noticeTimer;
  function notice(html) {
    let el = document.querySelector(".job-notice");
    if (!el) { el = document.createElement("div"); el.className = "job-notice"; el.setAttribute("role", "status"); document.body.appendChild(el); }
    el.innerHTML = html;
    el.classList.add("show");
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => el.classList.remove("show"), 9000);
  }
  NL.jobs.on("done", ({ job }) => {
    if (document.body.dataset.jobsQuiet === "1") return; // the page that started it handles its own hand-off
    notice(`<span>${NL.esc(job.title || "Your analysis")} is ready</span><a href="${root}pages/results.html?id=${encodeURIComponent(job.entryId)}">View results</a>`);
  });
  NL.jobs.on("error", ({ title }) => {
    if (document.body.dataset.jobsQuiet === "1") return;
    notice(`<span>${NL.esc(title || "An analysis")} didn't finish</span><button type="button" id="jnOpen">Details</button>`);
    const o = document.getElementById("jnOpen"); if (o) o.onclick = () => { setOpen(true); btn.focus(); };
  });
  NL.jobs.on("change", render);
  render();
  return { render, open: () => setOpen(true) };
})();
