/* Import page: read ZIPs / folders / files in the browser, show what was found, build + save the report. */
(() => {
  const $ = (id) => document.getElementById(id);
  const P = NL.imp.parse, S = NL.imp.store;
  let pending = null;   // { events:{ig,yt}, ranges, recognized, intake, problems }

  /* ---------- helpers ---------- */
  const fmt = (t) => (t ? NL.fmtDate(t * 1000) : "–");
  const showErr = (msg) => { $("importErr").textContent = msg; $("importErr").hidden = !msg; };
  function busy(on, stage, frac) {
    $("readState").classList.toggle("show", on);
    if (stage) $("readStage").textContent = stage;
    if (frac != null) { $("readProg").style.width = Math.round(frac * 100) + "%"; $("readProgWrap").setAttribute("aria-valuenow", String(Math.round(frac * 100))); }
  }
  const platformOf = (cat) => (cat.startsWith("ig") ? "Instagram" : "YouTube");

  /* ---------- target profile ---------- */
  const sel = $("targetProfile");
  sel.innerHTML = `<option value="me">Me</option>` + NL.profiles.children().map((c) => `<option value="${NL.esc(c.id)}">${NL.esc(c.name)} (child)</option>`).join("");
  const wanted = new URLSearchParams(location.search).get("profile");
  if (wanted && [...sel.options].some((o) => o.value === wanted)) sel.value = wanted;
  const syncConsent = () => { $("consentRow").hidden = sel.value === "me"; if (sel.value === "me") $("consentBox").checked = false; syncMerge(); };
  sel.onchange = syncConsent;

  async function syncMerge() {
    if (!pending) return;
    const ex = await S.getEvents(sel.value);
    const have = ["ig", "yt"].filter((k) => ex[k].length && !pending.events[k].length);
    const replace = ["ig", "yt"].filter((k) => ex[k].length && pending.events[k].length);
    const name = { ig: "Instagram", yt: "YouTube" };
    const parts = [];
    if (have.length) parts.push(`This report will also include your earlier ${have.map((k) => name[k]).join(" and ")} import.`);
    if (replace.length) parts.push(`Your earlier ${replace.map((k) => name[k]).join(" and ")} import will be replaced by this newer one, and the report will show what changed.`);
    $("mergeNote").hidden = !parts.length;
    $("mergeText").textContent = parts.join(" ");
  }

  /* ---------- read files ---------- */
  async function handle(input) {
    showErr(""); $("foundPanel").hidden = true; pending = null;
    busy(true, "Opening your files…", 0.02);
    try {
      const intake = await P.intake(input, (m) => busy(true, m, 0.05));
      if (!intake.sources.length) {
        busy(false);
        if (intake.igHtml) return showErr("This looks like an Instagram export in HTML format. Please request it again and choose JSON as the format.");
        if (!intake.totalEntries) return showErr("We couldn't find any files to read. Choose a .zip from Instagram or Google Takeout, or the unzipped files.");
        return showErr("None of the history files we know were found in these files. For Instagram, include Likes, Saved, Story interactions and Ads information (posts / videos viewed). For YouTube, include History. Use JSON format.");
      }
      const parsed = await P.run(intake.sources, ({ stage, done, total }) => busy(true, stage + "…", 0.1 + 0.85 * (done / Math.max(total, 1))));
      busy(false);
      if (!parsed.events.ig.length && !parsed.events.yt.length) return showErr("The files were read but contained no history entries. " + (parsed.problems[0] || ""));
      pending = { ...parsed, intake };
      renderFound();
      syncConsent();
      $("foundPanel").hidden = false;
      $("foundPanel").scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth", block: "start" });
      $("foundHead").setAttribute("tabindex", "-1"); $("foundHead").focus({ preventScroll: true });
    } catch (e) {
      busy(false);
      showErr(e && e.message ? e.message : "Something went wrong while reading those files.");
    }
  }

  function renderFound() {
    const { recognized, ranges, intake, problems, adsSkipped, events } = pending;
    const rows = Object.entries(ranges).filter(([, r]) => r.n > 0).sort((a, b) => b[1].n - a[1].n);
    const total = events.ig.length + events.yt.length;
    $("foundSummary").textContent = `Found ${total.toLocaleString()} history items across ${rows.length} kinds of data. ${intake.ignoredPrivate ? `${intake.ignoredPrivate.toLocaleString()} private files (messages and personal details) were ignored and never read.` : ""}`;
    $("foundTable").innerHTML = `<caption class="sr-only">Data found in your export</caption><thead><tr><th scope="col">Source</th><th scope="col">Data</th><th scope="col">Items</th><th scope="col">From</th><th scope="col">To</th></tr></thead><tbody>${rows.map(([cat, r]) => `<tr><th scope="row">${platformOf(cat)}</th><td>${NL.esc(P.LABELS[cat])}</td><td>${r.n.toLocaleString()}</td><td>${fmt(r.from)}</td><td>${fmt(r.to)}</td></tr>`).join("")}</tbody>`;
    const notes = [];
    if (events.ig.length) {
      const w = ranges.igVideosWatched;
      if (w && w.from && (w.to - w.from) / 86400 < 14) notes.push(`Instagram only included ${Math.max(1, Math.round((w.to - w.from) / 86400))} days of watched reels. That's how Instagram exports it. Longer-term patterns come from your likes and stories.`);
      if (!ranges.igLikes) notes.push("No likes file was found. Add \"Likes\" to your Instagram export for the best long-term picture.");
    }
    if (events.yt.length) {
      if (adsSkipped) notes.push(`${adsSkipped.toLocaleString()} entries that were Google Ads were left out of your YouTube history.`);
      if (!ranges.ytWatch) notes.push("No YouTube watch history was found. Choose the \"history\" option in Takeout.");
    }
    if (pending.htmlDateProblems) notes.push(`${pending.htmlDateProblems} entries had dates we couldn't read. For the most accurate result, export YouTube history as JSON.`);
    problems.forEach((p) => notes.push(p));
    if (intake.igHtml) notes.push("Some Instagram files are in HTML format and were skipped. Request the export in JSON for the full picture.");
    $("foundNotes").innerHTML = notes.map((n) => `<li><i data-icon="alert" data-size="16"></i><span>${NL.esc(n)}</span></li>`).join("");
    NL.hydrateIcons($("foundPanel"));
  }

  /* ---------- build ---------- */
  $("buildBtn").onclick = async () => {
    if (!pending) return;
    const profile = sel.value;
    if (profile !== "me" && !$("consentBox").checked) { showErr("Please confirm your child knows you're reviewing their data."); $("consentBox").focus(); return; }
    showErr("");
    $("buildBtn").disabled = true;
    busy(true, "Building your report…", 0.97);
    try {
      const existing = await S.getEvents(profile);
      const merged = { ig: pending.events.ig.length ? pending.events.ig : existing.ig, yt: pending.events.yt.length ? pending.events.yt : existing.yt };
      const meta = { files: pending.intake.files, ignoredPrivate: pending.intake.ignoredPrivate, ranges: pending.ranges };
      await new Promise((r) => setTimeout(r, 30));
      const report = NL.imp.habits.analyze(merged, meta);
      await S.putEvents(profile, merged);
      S.saveReport(profile, report);
      location.href = `habits.html?profile=${encodeURIComponent(profile)}`;
    } catch (e) {
      busy(false); $("buildBtn").disabled = false;
      showErr("We couldn't save the report: " + (e && e.message ? e.message : "unknown error") + ". If your browser is in private mode, storage may be disabled.");
    }
  };
  $("cancelBtn").onclick = () => { pending = null; $("foundPanel").hidden = true; showErr(""); $("importFiles").value = ""; $("importDrop").focus(); };

  /* ---------- inputs: click, drop, folder ---------- */
  $("importFiles").onchange = (e) => e.target.files.length && handle(e.target.files);
  $("pickFolder").onclick = () => $("importFolder").click();
  $("importFolder").onchange = (e) => e.target.files.length && handle(e.target.files);
  const dz = $("importDrop");
  ["dragenter", "dragover"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.remove("over"); }));
  dz.addEventListener("drop", (e) => handle(e.dataTransfer));
  dz.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); $("importFiles").click(); } });
  dz.setAttribute("tabindex", "0");

  /* ---------- saved reports ---------- */
  function renderSaved() {
    const ids = S.profilesWithReports();
    $("savedSection").hidden = !ids.length;
    $("savedList").innerHTML = ids.map((id) => {
      const r = S.getReport(id), who = NL.profiles.name(id);
      const plats = Object.keys(r.platforms).map((k) => (k === "ig" ? "Instagram" : "YouTube")).join(" + ");
      const lvl = r.overall.level;
      return `<article class="card saved-card"><div class="saved-main"><b>${NL.esc(who === "Me" ? "My report" : who + "'s report")}</b>
        <span class="muted">${plats} · imported ${NL.fmtDate(r.createdAt)}</span></div>
        <span class="score-pill ${lvl}" aria-label="Habits score ${r.overall.score ?? "n/a"} out of 100">${r.overall.score ?? "–"}</span>
        <div class="row-actions"><a class="btn sm primary" href="habits.html?profile=${encodeURIComponent(id)}">Open report</a>
        <button class="btn sm ghost" data-del="${NL.esc(id)}" aria-label="Delete imported data for ${NL.esc(who)}">${NL.icon("trash", 18)}</button></div></article>`;
    }).join("");
  }
  $("savedList").addEventListener("click", async (e) => {
    const b = e.target.closest("[data-del]");
    if (b && confirm("Delete this imported data and report from this browser?")) { await S.remove(b.dataset.del); renderSaved(); NL.toast("Imported data deleted"); }
  });

  renderSaved();
  NL.hydrateIcons();
})();
