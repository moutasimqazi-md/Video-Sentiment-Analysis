/* Dashboard: KPIs, trends, distribution, radar, audio-vs-visual, activity, scatter, wellbeing, insights.
   Accessibility: every chart has a text alternative + a data table, controls expose pressed state, updates are announced. */
(() => {
  const $ = (id) => document.getElementById(id);
  const A = NL.analytics, C = NL.charts;
  const user = NL.user.get();

  let days = NL.store.get("dash_days", 30);
  let profile = NL.store.get("dash_profile", "me");
  let demo = false;
  let firstRender = true;
  let quiet = false;

  /* ---------- header, sidebar, controls ---------- */
  const hour = new Date().getHours();
  $("greeting").textContent = `${hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"}${user ? ", " + user.name.split(" ")[0] : ""}`;
  $("guestNote").hidden = !!user;
  /* import prompt: invite to import, or link to the existing habits report */
  (function importCta() {
    const box = $("importCta"); if (!box) return;
    const found = NL.imp && NL.imp.store ? NL.imp.store.allReports() : [];
    box.hidden = false;
    if (found.length) {
      const { id, src, report: r } = found[0], plat = src === "ig" ? "Instagram" : "YouTube";
      box.querySelector("h2").textContent = found.length > 1 ? "Your habits reports are ready" : `Your ${plat} habits report is ready`;
      box.querySelector("p").textContent = found.length > 1 ? `${found.length} separate reports (${found.map((f) => (f.src === "ig" ? "Instagram" : "YouTube")).join(", ")}). Open one from your imports.` : `Score ${r.overall.score ?? "–"}/100 · ${r.overall.label}. Imported ${NL.fmtDate(r.createdAt)}.`;
      const a = box.querySelector("a.btn");
      a.href = found.length > 1 ? "import.html" : `habits.html?profile=${encodeURIComponent(id)}&src=${src}`; a.lastChild.textContent = found.length > 1 ? "Choose a report" : "Open report";
    }
  })();


  const sel = $("profileSel");
  sel.innerHTML = `<option value="me">Me</option>` + NL.profiles.children().map((c) => `<option value="${NL.esc(c.id)}">${NL.esc(c.name)} (child)</option>`).join("") + `<option value="all">Everyone</option>`;
  if ([...sel.options].some((o) => o.value === profile)) sel.value = profile; else profile = "me";
  sel.onchange = () => { profile = sel.value; NL.store.set("dash_profile", profile); render(); };

  function paintChips() {
    document.querySelectorAll("#periodChips .chip").forEach((c) => {
      const on = Number(c.dataset.days) === days;
      c.classList.toggle("active", on);
      c.setAttribute("aria-pressed", String(on));
    });
  }
  document.querySelectorAll("#periodChips .chip").forEach((c) => {
    c.onclick = () => { days = Number(c.dataset.days); NL.store.set("dash_days", days); paintChips(); render(); };
  });
  paintChips();

  $("printBtn").onclick = () => window.print();
  $("csvBtn").onclick = () => {
    const rows = A.select(getSource(), { profile, days });
    if (!rows.length) return NL.toast("Nothing to export for this period");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([A.toCSV(rows)], { type: "text/csv" }));
    a.download = `neurolens-analyses-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click(); URL.revokeObjectURL(a.href);
    NL.toast(`Exported ${rows.length} ${rows.length === 1 ? "analysis" : "analyses"}`);
  };
  $("demoOn").onclick = () => { demo = true; render(); $("demoOff").focus(); };
  $("demoOff").onclick = () => { demo = false; render(); };
  $("widenBtn").onclick = () => { days = 0; NL.store.set("dash_days", 0); paintChips(); render(); };

  let demoCache = null;
  const getSource = () => { if (!demo) return NL.history.list(); return (demoCache = demoCache || A.demo(120, 96)); };

  /* ---------- helpers ---------- */
  const fmtDelta = (d, unit = "") => {
    if (d == null || Number.isNaN(d)) return "";
    if (d === 0) return `<span class="delta flat">No change</span>`;
    return `<span class="delta ${d > 0 ? "up" : "down"}"><span aria-hidden="true">${d > 0 ? "▲" : "▼"}</span> ${Math.abs(d)}${unit}<span class="sr-only"> ${d > 0 ? "increase" : "decrease"}</span></span>`;
  };
  const pct = (v) => Math.round(v * 10) / 10 + "%";

  const table = (caption, headers, rows) =>
    `<div class="table-wrap" tabindex="0" role="region" aria-label="${NL.esc(caption)} (scrolls sideways on small screens)"><table class="data-table"><caption class="sr-only">${NL.esc(caption)}</caption><thead><tr>${headers.map((h) => `<th scope="col">${NL.esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c, i) => (i === 0 ? `<th scope="row">${NL.esc(c)}</th>` : `<td>${NL.esc(c)}</td>`)).join("")}</tr>`).join("")}</tbody></table></div>`;

  /** Give a rendered chart a text alternative and (optionally) a data table. */
  function describe(containerId, label, tableHtml) {
    const box = $(containerId);
    const svg = box.querySelector("svg");
    if (svg) { svg.setAttribute("role", "img"); svg.setAttribute("aria-label", label); }
    else box.setAttribute("role", "group"), box.setAttribute("aria-label", label);
    if (tableHtml) box.insertAdjacentHTML("beforeend", `<details class="chart-data"><summary>View data as a table</summary>${tableHtml}</details>`);
  }

  /** Chart drawing width = the card's real width (so axis text isn't scaled down on phones). */
  const cw = (id, max, min = 260) => Math.max(min, Math.min(max, Math.round($(id).clientWidth || max)));
  const ch = (w, ratio, lo, hi) => Math.max(lo, Math.min(hi, Math.round(w * ratio)));
  const periodText = () => (days ? `the last ${days} days` : "all time");

  /* ---------- render ---------- */
  function render() {
    const all = getSource();
    const cur = A.select(all, { profile, days });
    const prevEntries = days ? A.select(all, { profile, days, offset: days }) : [];
    const m = A.metrics(cur);
    const pm = prevEntries.length ? A.metrics(prevEntries) : null;
    const who = profile === "me" ? "you" : profile === "all" ? "everyone" : NL.profiles.name(profile);

    const empty = cur.length === 0;
    const hasAnyHistory = A.select(all, { profile, days: 0 }).length > 0;
    $("emptyState").hidden = !empty;
    $("dashBody").hidden = empty;
    $("demoBar").hidden = !demo;
    $("emptyTitle").textContent = hasAnyHistory ? `No analyses in ${periodText()}` : "No analyses yet";
    $("emptyText").textContent = hasAnyHistory ? "Try a longer period to see your earlier Reels." : "Analyze your first Reel and your dashboard fills with trends, emotion breakdowns and insights.";
    $("widenBtn").hidden = !(hasAnyHistory && days !== 0);
    $("demoOn").hidden = hasAnyHistory;
    const title = profile === "me" ? "Your dashboard" : profile === "all" ? "Everyone's dashboard" : `${NL.profiles.name(profile)}'s dashboard`;
    $("dashTitle").textContent = title;
    document.title = `${title} — NeuroLens`;

    if (empty) { announce(`No analyses for ${who} in ${periodText()}.`); $("periodNote").textContent = ""; return; }

    const start = days ? new Date(Date.now() - days * 864e5) : new Date(cur[0].createdAt);
    $("periodNote").textContent = `${NL.fmtDate(start)} – ${NL.fmtDate(Date.now())}${pm ? ` · compared with the previous ${days} days` : ""}`;
    announce(`Showing ${m.n} ${m.n === 1 ? "analysis" : "analyses"} for ${who} in ${periodText()}. Signature emotion: ${m.topEmotion[0]}.`);

    const bks = A.buckets(cur, days);
    const labels = bks.map((b) => b.label);

    /* KPI cards */
    const counts = bks.map((b) => b.items.length);
    const kpi = (icon, tone, label, val, small, foot, spark) =>
      `<article class="card kpi" aria-label="${NL.esc(label)}"><div class="k-top"><span class="k-ico ${tone}" aria-hidden="true">${NL.icon(icon, 17)}</span>${label}</div>
       <div class="k-val">${val}${small ? `<small>${small}</small>` : ""}</div><div class="k-foot"><span>${foot || ""}</span><span aria-hidden="true">${spark || ""}</span></div></article>`;
    const [tm, tc] = m.topEmotion;
    const pace = m.avgCuts < 12 ? "Slow" : m.avgCuts < 30 ? "Medium" : "Fast";
    const strongStreak = A.streak(all.filter((h) => profile === "all" || (h.profileId || "me") === profile));
    $("kpis").innerHTML = [
      kpi("film", "", "Analyses", m.n, `in ${days ? days + " days" : "total"}`, pm ? fmtDelta(m.n - pm.n, " vs previous") : "", C.spark(counts, "#f4685f")),
      kpi("target", "blue", "Signature emotion", `<span aria-hidden="true">${NL.moodEmoji(tm)}</span> ${NL.cap(tm)}`, "", `<span class="muted" style="font-size:12.5px">${Math.round((tc / m.n) * 100)}% of analyses</span>`, ""),
      kpi("gauge", "green", "Emotion clarity", Math.round(m.avgStrength) + "%", "lead emotion", pm ? fmtDelta(Math.round(m.avgStrength - pm.avgStrength), " pts") : "", C.spark(bks.map((b) => A.avgOf(b.items, (h) => A.top(h)[1]) || 0), "#137350")),
      kpi("heart", "amber", "Positivity", m.positivity + "%", "light-toned", pm ? fmtDelta(m.positivity - pm.positivity, " pts") : "", C.spark(bks.map((b) => (b.items.length ? 100 - A.HEAVY.reduce((a, k) => a + A.avgOf(b.items, (h) => h.result.averages[k] || 0), 0) : 0)), "#e9a23b")),
      kpi("bolt", "", "Average pacing", Math.round(m.avgCuts), "cuts / min", `<span class="muted" style="font-size:12.5px">${pace} pacing</span>`, C.spark(bks.map((b) => A.avgOf(b.items, (h) => (h.result.color_metrics || {}).cuts_per_minute) || 0), "#f4685f")),
      kpi("clock", "blue", "Current streak", strongStreak, strongStreak === 1 ? "day" : "days", `<span class="muted" style="font-size:12.5px">avg ${Math.round(m.avgDuration)}s per Reel</span>`, ""),
    ].join("");

    /* Emotion trends: top 5 emotions in the period */
    const top5 = Object.entries(m.mix).sort((a, b) => b[1] - a[1]).slice(0, 5).map((x) => x[0]);
    const trendVals = top5.map((mood) => bks.map((b) => (b.items.length ? A.avgOf(b.items, (h) => h.result.averages[mood] || 0) : null)));
    const tw = cw("trendChart", 640);
    $("trendChart").innerHTML = C.line({
      labels, yFmt: (v) => v + "%", area: false, height: ch(tw, 0.6, 230, 360), width: tw,
      series: top5.map((mood, i) => ({ name: NL.cap(mood), color: C.PALETTE[i], values: trendVals[i] })),
    });
    describe("trendChart", `Line chart of the average score of ${top5.map(NL.cap).join(", ")} across ${labels.length} time periods. ${NL.cap(top5[0])} is highest on average at ${pct(m.mix[top5[0]])}.`,
      table("Average emotion score by period", ["Period", ...top5.map(NL.cap)], labels.map((l, i) => [l, ...trendVals.map((v) => (v[i] == null ? "–" : pct(v[i])))])));

    /* Donut of dominant emotions */
    const ranked = Object.entries(m.counts).sort((a, b) => b[1] - a[1]);
    const head = ranked.slice(0, 6), rest = ranked.slice(6).reduce((a, b) => a + b[1], 0);
    const items = head.map(([k, v]) => ({ label: NL.cap(k), value: v, color: C.moodColor(k) }));
    if (rest) items.push({ label: "Other", value: rest, color: "#9aa5bd" });
    $("donut").innerHTML = C.donut({ items, centerBig: String(m.n), centerSmall: m.n === 1 ? "analysis" : "analyses" });
    describe("donut", `Donut chart of dominant emotions across ${m.n} analyses: ${items.map((i) => `${i.label} ${Math.round((i.value / m.n) * 100)}%`).join(", ")}.`,
      table("Dominant emotion share", ["Emotion", "Analyses", "Share"], items.map((i) => [i.label, String(i.value), Math.round((i.value / m.n) * 100) + "%"])));

    /* Radar fingerprint */
    const keys = Object.keys(NL.MOODS);
    const vals = keys.map((k) => m.mix[k] || 0);
    $("radar").innerHTML = C.radar({ axes: keys.map((k) => ({ label: NL.cap(k), emoji: NL.moodEmoji(k) })), values: vals, max: Math.max(10, Math.ceil((Math.max(...vals) * 1.15) / 5) * 5) });
    const ranked16 = Object.entries(m.mix).sort((a, b) => b[1] - a[1]);
    describe("radar", `Radar chart of the average score for all 16 emotions. Highest: ${ranked16.slice(0, 3).map(([k, v]) => `${NL.cap(k)} ${pct(v)}`).join(", ")}. Lowest: ${NL.cap(ranked16[15][0])}.`,
      table("Average score per emotion", ["Emotion", "Average score"], ranked16.map(([k, v]) => [NL.cap(k), pct(v)])));
    $("radar").insertAdjacentHTML("afterbegin", ""); // keep chart first
    $("radar").querySelector("svg")?.insertAdjacentHTML("afterend", `<ul class="mini-list">${ranked16.slice(0, 3).map(([k, v]) => `<li><span><span aria-hidden="true">${NL.moodEmoji(k)}</span> ${NL.cap(k)}</span><b>${v.toFixed(1)}%</b></li>`).join("")}<li class="sep"><span class="muted">Least present</span><b class="muted"><span aria-hidden="true">${NL.moodEmoji(ranked16[15][0])}</span> ${NL.cap(ranked16[15][0])}</b></li></ul>`);

    /* Visual vs audio */
    const withAudio = cur.filter((h) => h.result.audio && h.result.audio.available);
    if (withAudio.length) {
      const t6 = Object.entries(m.mix).sort((a, b) => b[1] - a[1]).slice(0, 6).map((x) => x[0]);
      $("vsAudio").innerHTML = C.hbars({
        series: [{ name: "Visual", color: "#4a7cf0" }, { name: "Audio", color: "#f4685f" }],
        rows: t6.map((k) => ({ label: k, emoji: "", values: [A.avgOf(withAudio, (h) => (h.result.visual_averages || h.result.averages)[k] || 0), A.avgOf(withAudio, (h) => h.result.audio.averages[k] || 0)] })),
      }) + `<p class="muted" style="font-size:12.5px;margin-top:12px">Based on ${withAudio.length} ${withAudio.length === 1 ? "Reel" : "Reels"} with a soundtrack. Values are visual / audio.</p>`;
      $("vsAudio").setAttribute("role", "group");
      $("vsAudio").setAttribute("aria-label", "Visual versus audio score for your top six emotions");
    } else $("vsAudio").innerHTML = `<p class="muted">None of these Reels had an analyzable soundtrack.</p>`;

    /* Activity heatmap (last 12 weeks) */
    const mine = all.filter((h) => profile === "all" || (h.profileId || "me") === profile);
    const byDay = {}; mine.forEach((h) => { const k = A.dayKey(h.createdAt); byDay[k] = (byDay[k] || 0) + 1; });
    $("heatmap").innerHTML = C.heatmap({ counts: byDay, weeks: 12 });
    const st = A.streak(mine);
    $("streakText").textContent = st ? `${st}-day streak` : "last 12 weeks";
    const since = Date.now() - 84 * 864e5;
    const recent = mine.filter((h) => h.createdAt >= since);
    const wd = [0, 0, 0, 0, 0, 0, 0]; recent.forEach((h) => { wd[(new Date(h.createdAt).getDay() + 6) % 7]++; });
    const names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    const busiest = wd.indexOf(Math.max(...wd));
    const wdMax = Math.max(1, ...wd);
    describe("heatmap", `Activity calendar for the last 12 weeks: ${recent.length} analyses on ${new Set(recent.map((h) => A.dayKey(h.createdAt))).size} days.`);
    $("heatmap").insertAdjacentHTML("beforeend", `<div class="wd-bars" role="img" aria-label="Analyses by weekday: ${names.map((n, i) => `${n} ${wd[i]}`).join(", ")}">${wd.map((c, i) => `<div data-tip="${names[i]}: ${c}"><i style="height:${Math.max(4, (c / wdMax) * 100)}%"></i><span aria-hidden="true">${names[i][0]}</span></div>`).join("")}</div>`);
    $("heatmap").insertAdjacentHTML("beforeend", `<div class="heat-stats"><div><b>${recent.length}</b><span>analyses</span></div><div><b>${new Set(recent.map((h) => A.dayKey(h.createdAt))).size}</b><span>active days</span></div><div><b>${recent.length ? names[busiest].slice(0, 3) : "–"}</b><span>busiest day</span></div></div>`);

    /* Pacing vs strength scatter */
    const pts = cur.filter((h) => (h.result.color_metrics || {}).cuts_per_minute != null).map((h) => {
      const [mood, v] = A.top(h);
      return { x: h.result.color_metrics.cuts_per_minute, y: v, color: C.moodColor(mood), tip: `${h.title || "Reel"} · ${NL.cap(mood)} ${v.toFixed(0)}% · ${h.result.color_metrics.cuts_per_minute} cuts/min`, mood, title: h.title || "Reel" };
    });
    if (pts.length) {
      $("scatter").innerHTML = C.scatter({ points: pts, xLabel: "Cuts per minute (pacing)", yLabel: "Lead emotion strength", width: cw("scatter", 640), height: ch(cw("scatter", 640), 0.5, 220, 300) });
      describe("scatter", `Scatter plot of ${pts.length} Reels showing pacing in cuts per minute against lead emotion strength.`,
        table("Pacing and lead emotion strength per Reel", ["Reel", "Cuts per minute", "Lead emotion", "Strength"], pts.map((p) => [p.title, String(p.x), NL.cap(p.mood), Math.round(p.y) + "%"])));
    } else $("scatter").innerHTML = `<p class="muted">No pacing data yet.</p>`;

    /* Look & feel */
    const bright = bks.map((b) => (b.items.length ? A.avgOf(b.items, (h) => (h.result.color_metrics || {}).avg_brightness) : null));
    const satur = bks.map((b) => (b.items.length ? A.avgOf(b.items, (h) => (h.result.color_metrics || {}).avg_saturation) : null));
    $("lookChart").innerHTML = C.line({
      labels, yMax: 100, yFmt: (v) => v + "%", area: true, height: ch(cw("lookChart", 340), 0.85, 220, 280), width: cw("lookChart", 340),
      series: [{ name: "Brightness", color: "#e9a23b", values: bright }, { name: "Saturation", color: "#8b6cf0", values: satur }],
    });
    describe("lookChart", `Line chart of average brightness (${Math.round(m.avgBright)}%) and saturation (${Math.round(m.avgSat)}%) by period.`,
      table("Brightness and saturation by period", ["Period", "Brightness", "Saturation"], labels.map((l, i) => [l, bright[i] == null ? "–" : pct(bright[i]), satur[i] == null ? "–" : pct(satur[i])])));

    /* Wellbeing stacked bars */
    const lv = (b, key) => b.items.filter((h) => NL.wellbeing.assess(h.result).level.key === key).length;
    const calm = bks.map((b) => lv(b, "calm")), watch = bks.map((b) => lv(b, "watch")), high = bks.map((b) => lv(b, "high"));
    $("wellChart").innerHTML = C.stacked({
      labels, height: ch(cw("wellChart", 640), 0.62, 240, 400), width: cw("wellChart", 640),
      series: [{ name: "Calm", color: "#137350", values: calm }, { name: "Worth a look", color: "#e9a23b", values: watch }, { name: "High concern", color: "#f4685f", values: high }],
    });
    describe("wellChart", `Stacked bar chart of wellbeing by period. In total ${calm.reduce((a, b) => a + b, 0)} calm, ${watch.reduce((a, b) => a + b, 0)} worth a look and ${high.reduce((a, b) => a + b, 0)} high concern.`,
      table("Analyses by wellbeing level and period", ["Period", "Calm", "Worth a look", "High concern"], labels.map((l, i) => [l, String(calm[i]), String(watch[i]), String(high[i])])));

    /* Insights */
    const ins = A.insights(cur, m, pm);
    $("insightList").innerHTML = ins.map((i) => `<div class="insight"><div class="ico ${i.tone === "coral" ? "" : i.tone}" aria-hidden="true">${NL.icon(i.icon, 18)}</div><div><b>${NL.esc(i.title)}</b><span>${NL.esc(i.text)}</span></div></div>`).join("");

    /* Strongest vibes */
    const best = [...cur].sort((a, b) => A.top(b)[1] - A.top(a)[1]).slice(0, 5);
    $("topList").innerHTML = `<ol class="top-ol">` + best.map((h) => {
      const [mood, v] = A.top(h);
      const t = h.title || "Untitled";
      return `<li class="top-item">${NL.thumbHTML(h, NL.moodEmoji(mood), "th")}
        <div style="min-width:0"><b>${NL.esc(t)}</b><small>${NL.cap(mood)} · ${NL.fmtDate(h.createdAt)}</small></div>
        <span class="pct">${v.toFixed(0)}%<span class="sr-only"> ${NL.cap(mood)}</span></span><div class="row-actions">${demo ? "" : NL.watchLink(h)}${demo ? "" : `<a class="btn sm" href="results.html?id=${encodeURIComponent(h.id)}" aria-label="Open analysis: ${NL.esc(t)}">Open</a>`}</div></li>`;
    }).join("") + `</ol>`;

    NL.observeReveal && NL.observeReveal();
  }

  /** Politely announce changes to screen-reader users (not on first paint). */
  function announce(text) {
    if (quiet) return;
    if (firstRender) { firstRender = false; $("dashStatus").textContent = ""; return; }
    $("dashStatus").textContent = text;
  }

  render();
  firstRender = false;
  NL.hydrateIcons();

  let lastW = innerWidth, t;
  addEventListener("resize", () => {
    clearTimeout(t);
    t = setTimeout(() => { if (Math.abs(innerWidth - lastW) > 30) { lastW = innerWidth; quiet = true; render(); quiet = false; } }, 250);
  });
})();
