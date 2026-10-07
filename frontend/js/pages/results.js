/* Results page: renders one saved analysis (or the built-in sample). */
(() => {
  const $ = (id) => document.getElementById(id);
  const root = document.body.dataset.root;
  const id = new URLSearchParams(location.search).get("id");
  const entry = id === "sample" ? NL.SAMPLE : NL.history.get(id);

  if (!entry) { $("missing").hidden = false; return; }
  $("report").hidden = false;

  const r = entry.result;
  const labels = r.mood_labels;
  const audio = r.audio || { available: false };
  const isImage = r.kind === "image";
  const isSample = entry.id === "sample";
  let source = "combined";
  let showAll = false;

  const scoresFor = (src) =>
    src === "visual" ? r.visual_averages || r.averages
    : src === "audio" && audio.available ? audio.averages
    : r.averages;
  const ranked = (src) => Object.entries(scoresFor(src)).sort((a, b) => b[1] - a[1]);

  /* ---- header card ---- */
  const [topMood, topPct] = ranked("combined")[0];
  $("title").textContent = entry.title || (isImage ? "Untitled image" : "Untitled video");
  $("meta").textContent = isImage ? `${NL.fmtDate(entry.createdAt)} · Image` : `${NL.fmtDate(entry.createdAt)} · ${NL.fmtDuration(r.duration_seconds)} · ${r.frames_analyzed} frames analyzed`;
  const th = $("thumb");
  th.innerHTML = `<span class="th-emoji">${NL.moodEmoji(topMood)}</span>` + (NL.thumbUrl(entry) ? `<img src="${NL.esc(NL.thumbUrl(entry))}" alt="" decoding="async" onerror="this.remove()">` : "");
  const watch = NL.watchLink(entry, { cls: "btn sm", text: `Watch the original ${NL.platform(entry) === "Instagram" ? "reel" : "video"}` });
  if (watch) $("meta").insertAdjacentHTML("afterend", `<div class="watch-row no-print">${watch}</div>`);
  $("domEmoji").textContent = NL.moodEmoji(topMood);
  $("domName").textContent = NL.cap(topMood);
  $("domLabel").textContent = NL.moodLabel(topMood, labels);
  $("ringVal").textContent = topPct.toFixed(1) + "%";
  requestAnimationFrame(() => { $("ringArc").style.strokeDashoffset = 326.7 * (1 - Math.min(topPct, 100) / 100); });
  $("verdict").innerHTML = NL.icon("sparkle", 18) + `<span>${NL.esc(r.verdict || "")}</span>`;
  if (r.confidence) {
    const c = r.confidence, el = $("conf");
    el.hidden = false;
    el.className = "conf " + c.level;
    el.textContent = c.level === "clear" ? "A clear read: one mood stands well ahead of the rest."
      : c.level === "leaning" ? "Leaning " + topMood + ", with other moods close behind."
      : "A mixed read: several moods score about the same, so treat the top result as a starting point.";
  }

  /* ---- key moments + visual check (evidence frames saved with the analysis) ---- */
  const kfs = (r.keyframes || []).filter((k) => !k.flag);
  if (kfs.length) {
    $("momentsCard").hidden = false;
    $("moments").innerHTML = kfs.map((k) => `<figure><img src="${NL.esc(NL.api.url(k.url))}" alt="Frame at ${k.t} seconds, reading as ${NL.esc(k.mood || topMood)}" loading="lazy" decoding="async" onerror="this.closest('figure').remove()"><figcaption>${isImage ? "" : k.t + "s · "}${NL.cap(k.mood || topMood)}</figcaption></figure>`).join("");
  }
  const sf = r.safety;
  if (sf && sf.checked) {
    $("safetyCard").hidden = false;
    const flagged = sf.flags && sf.flags.length;
    $("safetyBadge").className = "badge " + (flagged ? "amber" : "green");
    $("safetyBadge").textContent = flagged ? "Worth a look" : "Nothing flagged";
    $("safetyText").textContent = flagged
      ? `${sf.flags[0].label} showed up in ${sf.flags[0].frames} of ${sf.flags[0].of} frames checked. Review the frame below and decide for yourself.`
      : `We checked ${sf.frames_checked} ${sf.frames_checked === 1 ? "frame" : "frames"} and found nothing that looked revealing.`;
    $("safetyFrames").innerHTML = (r.keyframes || []).filter((k) => k.flag).map((k) => `<figure><img src="${NL.esc(NL.api.url(k.url))}" alt="Flagged frame at ${k.t} seconds" loading="lazy" onerror="this.closest('figure').remove()"><figcaption>${isImage ? "Flagged frame" : k.t + "s"}</figcaption></figure>`).join("");
  }
  if (isSample) $("subtitle").textContent = "This is a built-in sample report — analyze your own video to get real results.";

  /* ---- wellbeing + danger alert ---- */
  const wb = NL.wellbeing.assess(r);
  const forChild = entry.profileId && entry.profileId !== "me";
  $("wbBadge").innerHTML = `${NL.wellbeing.iconSvg(wb.level, 14)}${wb.level.label}`;
  $("wbBadge").className = "badge " + (wb.level.key === "high" ? "coral" : wb.level.key === "calm" ? "green" : "amber");
  $("wbText").textContent = wb.summary;
  $("wbDrivers").innerHTML = wb.drivers.map(([m, v]) => `<span class="chip">${NL.moodEmoji(m)} ${NL.cap(m)} ${v.toFixed(0)}%</span>`).join("");
  if (forChild && wb.level.key !== "calm") {
    $("alertBox").innerHTML = `<div class="alert-banner ${wb.level.key}" role="alert">
      <div class="ico">${NL.icon("alert", 20)}</div>
      <div><b>${wb.level.key === "high" ? "Concern flagged" : "Worth a look"} — ${NL.esc(NL.profiles.name(entry.profileId))}</b>
      <p>${NL.esc(wb.summary)} ${wb.level.key === "high" ? "If you think your child may be at risk, talk with them today and reach out to a counselor, doctor or local crisis service." : ""}</p></div></div>`;
  }
  if (forChild) $("subtitle").textContent = `Reviewed for ${NL.profiles.name(entry.profileId)}.`;

  if (isImage) {
    $("timelineCard").hidden = true;
    $("srcChips").hidden = true;
    $("subtitle").textContent = "Here's what the image shows.";
  }
  /* ---- stat tiles ---- */
  const cm = r.color_metrics || {};
  const cuts = cm.cuts_per_minute || 0;
  const pace = cuts < 12 ? "Slow" : cuts < 30 ? "Medium" : "Fast";
  const topVisual = Object.entries(r.visual_averages || r.averages).sort((a, b) => b[1] - a[1])[0][0];
  $("stats").innerHTML = (isImage ? [
    ["eye", "Visual vibe", NL.cap(topVisual), ""],
    ["sun", "Brightness", (cm.avg_brightness ?? 0) + "%", ""],
    ["palette", "Color richness", (cm.avg_saturation ?? 0) + "%", ""],
  ] : [
    ["eye", "Visual vibe", NL.cap(topVisual), ""],
    ["music", "Audio vibe", audio.available ? NL.cap(audio.dominant) : "No audio", ""],
    ["gauge", "Pacing", pace, ` <em>${cuts}/min</em>`],
    ["sun", "Brightness", (cm.avg_brightness ?? 0) + "%", ""],
  ]).map(([i, k, v, x]) => `<div class="stat"><small>${NL.icon(i, 14)}${k}</small><b>${NL.esc(v)}${x}</b></div>`).join("");

  /* ---- emotion bars ---- */
  function renderBars() {
    const rows = ranked(source);
    const shown = showAll ? rows : rows.slice(0, 8);
    $("bars").innerHTML = shown.map(([m, v], i) => `
      <div class="bar-row ${i === 0 ? "top" : ""}">
        <span class="emo" aria-hidden="true">${NL.moodEmoji(m)}</span>
        <span class="name">${NL.cap(m)}<small>${NL.esc(NL.moodLabel(m, labels))}</small></span>
        <span class="track"><i data-w="${Math.min(v, 100)}"></i></span>
        <span class="pct">${v.toFixed(1)}%</span>
      </div>`).join("");
    requestAnimationFrame(() => document.querySelectorAll("#bars .track i").forEach((el) => (el.style.width = el.dataset.w + "%")));
    $("moreBtn").textContent = showAll ? "Show top 8" : `Show all ${rows.length} emotions`;
    $("srcNote").textContent =
      source === "visual" ? "From the video frames only."
      : source === "audio" ? `From the soundtrack only · ${audio.windows_analyzed} clips · loudness ${audio.loudness_db} dB.`
      : audio.available ? `Mostly from what the camera sees, with the soundtrack as a supporting signal · loudness ${audio.loudness_db} dB.`
      : `Visual only — ${audio.reason || "audio unavailable"}.`;
  }
  document.querySelectorAll("#srcChips .chip").forEach((c) => {
    if (c.dataset.src === "audio" && !audio.available) { c.disabled = true; c.title = audio.reason || "No audio"; }
    c.onclick = () => {
      source = c.dataset.src;
      document.querySelectorAll("#srcChips .chip").forEach((x) => { x.classList.toggle("active", x === c); x.setAttribute("aria-pressed", String(x === c)); });
      renderBars();
    };
  });
  $("moreBtn").onclick = () => { showAll = !showAll; renderBars(); };
  renderBars();

  /* ---- timeline (inline SVG) ---- */
  function renderChart() {
    const tl = r.timeline || [];
    if (tl.length < 2) { $("chartWrap").innerHTML = `<p class="muted">Not enough frames for a timeline.</p>`; return; }
    const top3 = ranked("visual").slice(0, 3).map((x) => x[0]);
    const colors = ["#f4685f", "#4a7cf0", "#2fa77a"];
    const W = Math.max(260, Math.round($("chartWrap").clientWidth || 600)), H = W < 420 ? 210 : 190, pl = 34, pr = 8, pt = 10, pb = 22;
    const maxT = tl[tl.length - 1].t || 1;
    const maxV = Math.max(0.1, ...tl.flatMap((f) => top3.map((m) => f[m] || 0)));
    const x = (t) => pl + (t / maxT) * (W - pl - pr);
    const y = (v) => pt + (1 - v / maxV) * (H - pt - pb);
    const grid = [0, 0.5, 1].map((k) => {
      const yy = y(maxV * k);
      return `<line x1="${pl}" x2="${W - pr}" y1="${yy}" y2="${yy}" stroke="var(--border)"/><text x="${pl - 6}" y="${yy + 3}" text-anchor="end">${Math.round(maxV * k * 100)}%</text>`;
    }).join("");
    const lines = top3.map((m, i) => {
      const pts = tl.map((f) => `${x(f.t).toFixed(1)},${y(f[m] || 0).toFixed(1)}`).join(" ");
      const last = tl[tl.length - 1];
      const area = i === 0 ? `<polygon points="${x(0)},${y(0)} ${pts} ${x(last.t)},${y(0)}" fill="url(#areaFill)"/>` : "";
      const dot = `<circle cx="${x(last.t).toFixed(1)}" cy="${y(last[m] || 0).toFixed(1)}" r="4" fill="${colors[i]}" stroke="var(--surface)" stroke-width="2"/>`;
      return `${area}<polyline points="${pts}" fill="none" stroke="${colors[i]}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>${dot}`;
    }).join("");
    const ticks = [0, 0.5, 1].map((k) => `<text x="${x(maxT * k)}" y="${H - 5}" text-anchor="middle">${(maxT * k).toFixed(0)}s</text>`).join("");
    $("chartWrap").innerHTML = `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Emotion timeline"><defs><linearGradient id="areaFill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f4685f" stop-opacity=".25"/><stop offset="1" stop-color="#f4685f" stop-opacity="0"/></linearGradient></defs>${grid}${lines}${ticks}</svg>`;
    $("legend").innerHTML = top3.map((m, i) => `<span><i style="background:${colors[i]}"></i>${NL.cap(m)}</span>`).join("");
  }
  renderChart();
  let lastW = innerWidth, rt;
  addEventListener("resize", () => { clearTimeout(rt); rt = setTimeout(() => { if (Math.abs(innerWidth - lastW) > 30) { lastW = innerWidth; renderChart(); } }, 250); });

  /* ---- creator insights ---- */
  const bright = cm.avg_brightness ?? 50, sat = cm.avg_saturation ?? 50;
  const insights = [
    ["palette", "coral", "Visuals", `${bright > 65 ? "Bright" : bright < 35 ? "Dark, moody" : "Balanced"} lighting with ${sat > 60 ? "rich, vivid" : sat < 30 ? "muted" : "natural"} color. Looks ${topVisual}.`],
    ...(isImage ? [] : [["music", "blue", "Audio", audio.available ? `The soundtrack feels ${audio.dominant} at ${audio.loudness_db} dB.` : `No audio analyzed (${audio.reason || "unavailable"}).`],
    ["bolt", "amber", "Pacing", `${cuts} cuts per minute — ${pace.toLowerCase()} pacing. ${pace === "Fast" ? "Great for holding attention; leave a beat on your key shot." : pace === "Slow" ? "Calm and cinematic; consider a tighter hook in the first 2 seconds." : "A comfortable rhythm for most feeds."}`]]),
    ["target", "green", "Overall response", `Viewers are most likely to feel ${topMood} (${topPct.toFixed(0)}%). ${topPct > 50 ? "A very clear, focused vibe." : "The vibe is mixed — pick one emotion to lean into."}`],
  ];
  $("insights").innerHTML = insights.map(([i, c, t, d]) => `<div class="insight"><div class="ico ${c === "coral" ? "" : c}">${NL.icon(i, 18)}</div><div><b>${t}</b><span>${NL.esc(d)}</span></div></div>`).join("");

  /* ---- copy / export ---- */
  const summary = () => [
    `NeuroLens analysis — ${entry.title || "video"}`,
    `Dominant emotion: ${NL.cap(topMood)} (${topPct.toFixed(1)}%) · ${NL.moodLabel(topMood, labels)}`,
    `Pacing: ${pace} (${cuts} cuts/min) · Brightness ${cm.avg_brightness}% · Saturation ${cm.avg_saturation}%`,
    audio.available ? `Audio vibe: ${audio.dominant}` : "Audio: not analyzed",
    "", r.verdict || "", "",
    "Top emotions:", ...ranked("combined").slice(0, 5).map(([m, v]) => `  ${NL.moodEmoji(m)} ${NL.cap(m)} — ${v.toFixed(1)}%`),
  ].join("\n");

  $("copyBtn").onclick = async () => {
    try { await navigator.clipboard.writeText(summary()); NL.toast("Summary copied"); }
    catch (e) { NL.toast("Couldn't copy — select and copy manually"); }
  };
  $("exportBtn").onclick = () => {
    if (!NL.plan.get().export) return NL.upgradeModal("Downloading reports is part of a paid plan.");
    location.href = `report.html?id=${encodeURIComponent(entry.id)}`;
  };

  /* ---- feedback ---- */
  const fix = $("fixMood");
  Object.keys(NL.MOODS).forEach((m) => fix.insertAdjacentHTML("beforeend", `<option value="${m}">${NL.moodEmoji(m)} ${NL.cap(m)}</option>`));
  let rating = null;
  async function send(corrected) {
    if (isSample) { $("fbMsg").textContent = "Thanks! (Feedback isn't saved for the sample.)"; return; }
    try {
      await NL.api.sendFeedback(entry.id, rating, corrected);
      NL.history.update(entry.id, { feedback: rating });
      $("fbMsg").textContent = "Thanks — feedback recorded.";
      $("fixBox").hidden = true;
    } catch (e) { $("fbMsg").textContent = e.message; }
  }
  document.querySelectorAll("[data-rate]").forEach((b) => (b.onclick = () => {
    rating = b.dataset.rate;
    if (rating === "bad") $("fixBox").hidden = false; else send(null);
  }));
  $("sendFix").onclick = () => send(fix.value || null);
  NL.hydrateIcons();
})();
