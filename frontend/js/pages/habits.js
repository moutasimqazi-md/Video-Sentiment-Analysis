/* Habits report: overview + verdict, per-platform charts, content themes, optional video "deep check", browsing, CSV/print. */
(() => {
  const $ = (id) => document.getElementById(id);
  const C = NL.charts, H = NL.imp.habits, S = NL.imp.store;
  const params = new URLSearchParams(location.search);
  const profile = params.get("profile") || "me";
  const report = S.getReport(profile);
  const esc = NL.esc;

  if (!report) { $("noReport").hidden = false; $("noReportCta").href = `import.html?profile=${encodeURIComponent(profile)}`; return; }
  $("reportWrap").hidden = false;

  /* ---------- basics ---------- */
  const who = NL.profiles.name(profile);
  const possessive = who === "Me" ? "Your" : `${who}'s`;
  const PLAT = { ig: "Instagram", yt: "YouTube" };
  const plats = Object.keys(report.platforms);
  const nf = (n) => Math.round(n).toLocaleString();
  const pct = (x) => Math.round(x * 100);
  const SEVICON = { good: "check", info: "eye", watch: "alert", high: "alert" };
  const kindEmoji = { reel: "🎬", post: "🖼️", story: "⏳", video: "▶️", short: "📱", music: "🎵" };
  const day = (k) => { const [y, m, d] = k.split("-").map(Number); return new Date(y, m - 1, d).toLocaleDateString(undefined, { month: "short", day: "numeric" }); };
  const monthName = (k) => { const [y, m] = k.split("-").map(Number); return new Date(y, m - 1, 1).toLocaleDateString(undefined, { month: "short", year: "2-digit" }); };
  const cw = (el, max, min = 260) => Math.max(min, Math.min(max, Math.round(el.clientWidth || max)));

  $("hbTitle").textContent = `${possessive} habits report`;
  $("subjectLine").textContent = plats.map((p) => PLAT[p]).join(" + ");
  $("hbSub").textContent = `Imported ${NL.fmtDate(report.createdAt)}. Everything here was calculated in this browser.`;
  document.title = `${possessive} habits report — NeuroLens`;
  $("updateBtn").href = `import.html?profile=${encodeURIComponent(profile)}`;

  const announce = (t) => { $("hbStatus").textContent = t; };
  const card = (title, sub, inner, cls = "") => `<section class="card ${cls}"><div class="card-head"><h3 class="h-card">${title}</h3>${sub ? `<span class="muted" style="font-size:12.5px">${sub}</span>` : ""}</div>${inner}</section>`;

  /* ---------- events (browse + deep check), loaded lazily ---------- */
  let eventsCache = null;
  const loadEvents = async () => (eventsCache = eventsCache || (await S.getEvents(profile)));

  /* ================= OVERVIEW ================= */
  function ring(score, level) {
    const col = { good: "var(--green)", info: "var(--blue)", watch: "var(--amber)", high: "var(--red)" }[level] || "var(--blue)";
    const off = 326.7 * (1 - (score || 0) / 100);
    return `<div class="score-ring" role="img" aria-label="Habits score ${score ?? "unknown"} out of 100"><svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="52" fill="none" stroke="var(--surface-2)" stroke-width="11"/><circle cx="60" cy="60" r="52" fill="none" stroke="${col}" stroke-width="11" stroke-linecap="round" stroke-dasharray="326.7" stroke-dashoffset="${off}"/></svg><div class="num"><div>${score ?? "–"}<small>of 100</small></div></div></div>`;
  }
  const finding = (f) => `<div class="finding"><span class="sev ${f.severity}" aria-hidden="true">${NL.icon(SEVICON[f.severity] || "eye", 18)}</span><div>
    <h3 class="ft">${esc(f.title)} <span class="conf">${f.confidence} confidence</span></h3><p>${esc(f.text)}</p>${f.tip ? `<p class="tip">${esc(f.tip)}</p>` : ""}<p class="meta">Based on ${esc(f.basis)}</p></div></div>`;

  function renderOverview() {
    const O = report.overall;
    const pill = (p) => { const v = report.platforms[p].verdict; return `<span class="plat-score"><span class="score-pill ${v.level}" style="min-width:34px;height:34px;font-size:13px">${v.score}</span>${PLAT[p]}</span>`; };
    let cmp = "";
    if (report.prev && report.prev.overall != null && O.score != null) {
      const d = O.score - report.prev.overall;
      cmp = `<p style="margin-top:10px"><span class="cmp ${d > 0 ? "up" : d < 0 ? "down" : "flat"}">${d > 0 ? "▲" : d < 0 ? "▼" : "•"} ${d === 0 ? "No change" : Math.abs(d) + " points"}</span> <span class="muted" style="font-size:13px">compared with your import on ${NL.fmtDate(report.prev.createdAt)}</span></p>`;
    }
    const rules = H.RULES.map((r) => `<tr><td>${esc(r.platform)}</td><td>${esc(r.what)}</td><td>${esc(r.bands)}</td></tr>`).join("");
    const cover = plats.map((p) => {
      const lines = Object.entries(report.platforms[p].series).filter(([, s]) => s).map(([k, s]) => {
        const lbl = { likes: "likes", stories: "stories viewed", views: p === "ig" ? "reels & posts viewed" : "videos watched" }[k];
        return `<li><b>${nf(s.n)}</b> ${lbl}, ${NL.fmtDate(s.from * 1000)} to ${NL.fmtDate(s.to * 1000)} (${s.days} day${s.days === 1 ? "" : "s"})</li>`;
      }).join("");
      return `<div><h3 class="ft" style="margin-bottom:6px">${PLAT[p]}</h3><ul class="side-list" style="margin:0;list-style:disc;padding-left:18px">${lines}</ul></div>`;
    }).join("");
    $("panel-overview").innerHTML = `
      <section class="card verdict-card">${ring(O.score, O.level)}<div><span class="eyebrow">Overall</span><h2>${esc(O.label)}</h2><p>${esc(O.summary)}</p>
        <div class="plat-scores">${plats.map(pill).join("")}</div>${cmp}</div></section>
      <div class="grid" style="margin-top:20px;gap:20px">
        ${plats.map((p) => card(`${PLAT[p]} · ${report.platforms[p].verdict.score}/100`, esc(report.platforms[p].verdict.label), report.platforms[p].verdict.findings.map(finding).join("") || `<p class="muted">Not enough history to judge.</p>`)).join("")}
        ${card("What this covers", "the windows differ between exports", `<div class="grid c2" style="gap:18px">${cover}</div><p class="disclaimer">Each export covers a different period, so every finding says what it is based on. Instagram only exports about 7 days of watched reels; YouTube doesn't record watch time.</p>`)}
        ${card("How the verdict is calculated", "", `<details class="how-calc"><summary>See the rules and thresholds</summary><div class="table-wrap" tabindex="0" role="region" aria-label="Scoring rules (scrolls sideways on small screens)"><table class="rules"><thead><tr><th scope="col">Platform</th><th scope="col">What is measured</th><th scope="col">Bands</th></tr></thead><tbody>${rules}</tbody></table></div></details>
          <p class="disclaimer">The score starts at 100 and loses points for each pattern that crosses a threshold. It describes patterns in your history, not your wellbeing, and it is not a diagnosis. If something here worries you, talking to someone you trust helps more than any score.</p>`)}
        ${report.prev ? card("Since your last import", NL.fmtDate(report.prev.createdAt), prevTable()) : ""}
      </div>`;
    NL.hydrateIcons($("panel-overview"));
  }
  function prevTable() {
    const rows = plats.filter((p) => report.prev.platforms[p]).map((p) => {
      const a = report.prev.platforms[p], b = report.platforms[p], s = Object.values(b.series).filter(Boolean).sort((x, y) => y.n - x.n)[0];
      const delta = (now, then, unit = "", mult = 1) => { if (now == null || then == null) return "–"; const d = Math.round((now - then) * mult * 10) / 10; return `${Math.round(now * mult * 10) / 10}${unit} <span class="cmp ${d > 0 ? "down" : d < 0 ? "up" : "flat"}">${d > 0 ? "+" : ""}${d}${unit}</span>`; };
      return [PLAT[p], `${b.verdict.score} <span class="cmp ${b.verdict.score > a.score ? "up" : b.verdict.score < a.score ? "down" : "flat"}">${b.verdict.score - a.score >= 0 ? "+" : ""}${b.verdict.score - a.score}</span>`, delta(s && s.nightShare, a.night, "%", 100), delta(s && s.perActiveDay, a.perDay, "", 1), delta(b.content && b.content.heavyShare, a.heavy, "%", 100)];
    });
    return `<div class="table-wrap" tabindex="0" role="region" aria-label="Changes since the previous import (scrolls sideways on small screens)"><table class="data-table"><thead><tr><th scope="col">Platform</th><th scope="col">Score</th><th scope="col">Late-night share</th><th scope="col">Typical per active day</th><th scope="col">Heavy-tone share</th></tr></thead><tbody>${rows.map((r) => `<tr><th scope="row">${r[0]}</th>${r.slice(1).map((c) => `<td>${c}</td>`).join("")}</tr>`).join("")}</tbody></table></div><p class="disclaimer">Green means moving in a healthier direction, red the opposite.</p>`;
  }

  /* ================= PLATFORM TABS ================= */
  const SERIES = { ig: [["likes", "Likes"], ["stories", "Stories viewed"], ["views", "Reels & posts viewed"]], yt: [["views", "Videos watched"]] };
  const sel = { ig: "likes", yt: "views" };

  function renderPlatform(p) {
    const P = report.platforms[p], box = $(`panel-${p}`);
    const avail = SERIES[p].filter(([k]) => P.series[k]);
    if (!avail.length) { box.innerHTML = `<div class="card empty"><h2 class="h3">No timestamped history</h2><p>This export had no dated ${PLAT[p]} activity.</p></div>`; return; }
    if (!avail.some(([k]) => k === sel[p])) sel[p] = avail[0][0];
    const s = P.series[sel[p]];
    const label = avail.find(([k]) => k === sel[p])[1].toLowerCase();
    const picker = avail.length > 1 ? `<div class="series-picker chips no-print" role="group" aria-label="Which data to show">${avail.map(([k, l]) => `<button class="chip" data-series="${k}" aria-pressed="${k === sel[p]}">${l} <span class="muted">· ${P.series[k].days}d</span></button>`).join("")}</div>` : "";
    const kv = [["Items", nf(s.n)], ["Active days", `${s.activeDays} of ${s.days}`], ["Typical active day", nf(s.perActiveDay)], ["Busiest day", nf(s.maxDay)], ["Late night (12–5am)", pct(s.nightShare) + "%"],
      ["Busiest hour", H.hourLabel(s.peakHour)], ["Busiest weekday", H.WD[s.peakWeekday]], ["Sessions", nf(s.sessions.count)], ["Longest run", s.sessions.longest ? Math.round(s.sessions.longest.min) + " min" : "–"]];
    box.innerHTML = `
      <div class="series-head"><h2 class="h3" style="font-size:20px">${PLAT[p]} · ${label}</h2><p class="coverage">${NL.fmtDate(s.from * 1000)} – ${NL.fmtDate(s.to * 1000)} · ${s.days} days</p></div>
      ${picker}
      <div class="kv">${kv.map(([k, v]) => `<div><small>${k}</small><b>${v}</b></div>`).join("")}</div>
      <div class="dgrid" style="margin-top:16px">
        ${card("When it happens", "weekday × hour of day", `<div id="${p}-grid"></div>`, "span2")}
        ${card("By hour", "all days combined", `<div id="${p}-hour"></div>`)}
        ${card("Over time", s.days > 1 ? "items per day" : "", `<div id="${p}-daily"></div>`, "span2")}
        ${card("By weekday", "", `<div id="${p}-wd"></div>`)}
        ${Object.keys(s.monthly).length > 1 ? card("By month", "", `<div id="${p}-month"></div>`, "span2") : ""}
        ${p === "ig" ? igExtras(P) : ytExtras(P)}
      </div>`;
    drawSeries(p, s, label);
    NL.hydrateIcons(box);
  }

  function igExtras(P) {
    const mix = P.mix.likes || {}, total = Object.values(mix).reduce((a, b) => a + b, 0);
    const donut = total ? card("What you like", "reels vs posts", `<div id="ig-mix"></div>`) : "";
    const soc = P.social, ctl = P.controls;
    const stats = card("Other activity", "", `<ul class="mini-list"><li><span>Accounts followed</span><b>${nf(soc.following)}</b></li><li><span>Saved</span><b>${nf(soc.saved)}</b></li><li><span>Comments</span><b>${nf(soc.comments)}</b></li><li><span>Marked "not interested"</span><b>${nf(ctl.notInterested)}</b></li><li><span>Topics hidden</span><b>${nf(ctl.topicsHidden.length)}</b></li><li><span>Ads seen (last 7 days)</span><b>${nf(ctl.ads)}</b></li></ul>
      <p class="disclaimer">Using "not interested" and hiding topics shows you're shaping your feed, which is a good habit.</p>`);
    return donut + stats + searchCard(P);
  }
  function ytExtras(P) {
    const cr = P.creators;
    const chan = cr && cr.top.length ? card("Most-watched channels", `top 10 = ${pct(cr.top10Share)}% of videos`, `<div id="yt-chan"></div>`, "span2") : "";
    const kinds = P.mix.kinds || {}, mixCard = Object.keys(kinds).length ? card("What you watch", "videos, Shorts, music", `<div id="yt-mix"></div>`) : "";
    const soc = card("Other activity", "", `<ul class="mini-list"><li><span>Subscriptions</span><b>${P.social.subscriptions ? nf(P.social.subscriptions) : "not in export"}</b></li><li><span>Liked videos</span><b>${P.social.liked ? nf(P.social.liked) : "not in export"}</b></li><li><span>Channels watched</span><b>${cr ? nf(cr.unique) : "–"}</b></li></ul>`);
    return chan + mixCard + soc + searchCard(P);
  }
  const searchCard = (P) => (P.searches.top.length ? card("What you search for", `${nf(P.searches.total)} searches`, `<ul class="mini-list">${P.searches.top.map((t) => `<li><span>${esc(t.q.length > 46 ? t.q.slice(0, 44) + "…" : t.q)}</span><b>${t.n}</b></li>`).join("")}</ul>`) : "");

  function drawSeries(p, s, label) {
    const hours = Array.from({ length: 24 }, (_, h) => H.hourLabel(h));
    const g = $(`${p}-grid`); g.innerHTML = C.hourGrid({ grid: s.grid, width: cw(g, 640, 300), unit: label });
    const flat = []; s.grid.forEach((row, d) => row.forEach((v, h) => flat.push([H.WD[d] + " " + H.hourLabel(h), v])));
    const top5 = flat.sort((a, b) => b[1] - a[1]).slice(0, 5);
    C.describe(g, `Heatmap of ${label} by weekday and hour. Busiest: ${top5.slice(0, 3).map((x) => `${x[0]} (${nf(x[1])})`).join(", ")}. ${pct(s.nightShare)}% falls between midnight and 5am.`, C.table("Busiest weekday and hour slots", ["Slot", "Items"], top5.map((x) => [x[0], nf(x[1])])));

    const hb = $(`${p}-hour`), wh = cw(hb, 520, 260);
    hb.innerHTML = C.stacked({ labels: hours, series: [{ name: "Activity", color: "#4a7cf0", values: s.byHour }], width: wh, height: Math.max(190, Math.round(wh * 0.55)) });
    C.describe(hb, `Bar chart of ${label} by hour of day. Busiest hour ${H.hourLabel(s.peakHour)}. ${pct(s.nightShare)}% between midnight and 5am.`, C.table("Items by hour", ["Hour", "Items"], hours.map((l, i) => [l, nf(s.byHour[i])])));

    const wb = $(`${p}-wd`), ww = cw(wb, 520, 260);
    wb.innerHTML = C.stacked({ labels: H.WD.map((x) => x.slice(0, 3)), series: [{ name: "Activity", color: "#f4685f", values: s.byWeekday }], width: ww, height: Math.max(190, Math.round(ww * 0.55)) });
    C.describe(wb, `Bar chart of ${label} by weekday. Busiest ${H.WD[s.peakWeekday]}.`, C.table("Items by weekday", ["Weekday", "Items"], H.WD.map((l, i) => [l, nf(s.byWeekday[i])])));

    const dkeys = Object.keys(s.daily).sort(); const filled = [];
    if (dkeys.length) { const a = new Date(dkeys[0] + "T00:00:00"), z = new Date(dkeys[dkeys.length - 1] + "T00:00:00"); for (let d = new Date(a); d <= z; d.setDate(d.getDate() + 1)) { const k = H.dayKey(d); filled.push([k, s.daily[k] || 0]); } }
    const db = $(`${p}-daily`), dw = cw(db, 640, 280);
    db.innerHTML = C.line({ labels: filled.map((x) => day(x[0])), series: [{ name: "Per day", color: "#f4685f", values: filled.map((x) => x[1]) }], width: dw, height: Math.max(210, Math.round(dw * 0.4)), area: true });
    C.describe(db, `Line chart of ${label} per day over ${filled.length} days. Busiest day ${nf(s.maxDay)}.`, C.table("Items per day (busiest days)", ["Date", "Items"], [...filled].sort((a, b) => b[1] - a[1]).slice(0, 15).map((x) => [day(x[0]), nf(x[1])])));

    const mk = Object.keys(s.monthly).sort();
    if ($(`${p}-month`)) {
      const mb = $(`${p}-month`), mw = cw(mb, 640, 280);
      mb.innerHTML = C.stacked({ labels: mk.map(monthName), series: [{ name: "Per month", color: "#1f9d6f", values: mk.map((k) => s.monthly[k]) }], width: mw, height: Math.max(200, Math.round(mw * 0.4)) });
      C.describe(mb, `Bar chart of ${label} by month, ${mk.length} months.`, C.table("Items by month", ["Month", "Items"], mk.map((k) => [monthName(k), nf(s.monthly[k])])));
    }
    const P = report.platforms[p];
    if (p === "ig" && $("ig-mix")) {
      const m = P.mix.likes, items = Object.entries(m).filter(([k]) => ["reel", "post", "story"].includes(k)).map(([k, v]) => ({ label: { reel: "Reels", post: "Posts", story: "Stories" }[k], value: v, color: { reel: "#f4685f", post: "#4a7cf0", story: "#8b6cf0" }[k] }));
      const tot = items.reduce((a, b) => a + b.value, 0);
      $("ig-mix").innerHTML = C.donut({ items, centerBig: nf(tot), centerSmall: "likes" });
      C.describe($("ig-mix"), `Donut of liked content: ${items.map((i) => `${i.label} ${Math.round((i.value / tot) * 100)}%`).join(", ")}.`, C.table("Liked content by type", ["Type", "Likes", "Share"], items.map((i) => [i.label, nf(i.value), Math.round((i.value / tot) * 100) + "%"])));
    }
    if (p === "yt") {
      if ($("yt-chan")) {
        const cb = $("yt-chan"), rows = P.creators.top.map((c) => ({ label: c.name.length > 22 ? c.name.slice(0, 20) + "…" : c.name, emoji: "", values: [c.n] }));
        cb.innerHTML = C.hbars({ rows, series: [{ name: "Videos", color: "#4a7cf0" }] });
        C.describe(cb, `Your ${rows.length} most-watched channels. The top 10 make up ${pct(P.creators.top10Share)}% of videos, from ${nf(P.creators.unique)} channels.`, C.table("Most-watched channels", ["Channel", "Videos"], P.creators.top.map((c) => [c.name, nf(c.n)])));
      }
      if ($("yt-mix")) {
        const k = P.mix.kinds, nm = { video: "Videos", short: "Shorts", music: "Music" }, col = { video: "#4a7cf0", short: "#f4685f", music: "#8b6cf0" };
        const items = Object.entries(k).filter(([x]) => nm[x]).map(([x, v]) => ({ label: nm[x], value: v, color: col[x] })), tot = items.reduce((a, b) => a + b.value, 0);
        $("yt-mix").innerHTML = C.donut({ items, centerBig: nf(tot), centerSmall: "watched" });
        C.describe($("yt-mix"), `Donut of watched content: ${items.map((i) => `${i.label} ${Math.round((i.value / tot) * 100)}%`).join(", ")}.`, C.table("Watched content by type", ["Type", "Videos", "Share"], items.map((i) => [i.label, nf(i.value), Math.round((i.value / tot) * 100) + "%"])));
      }
    }
  }

  /* ================= CONTENT ================= */
  const cState = { platform: plats[0] };
  function renderContent() {
    const box = $("panel-content");
    const P = report.platforms[cState.platform], Cn = P.content;
    const picker = plats.length > 1 ? `<div class="series-picker chips no-print" role="group" aria-label="Which platform">${plats.map((p) => `<button class="chip" data-cplat="${p}" aria-pressed="${p === cState.platform}">${PLAT[p]}</button>`).join("")}</div>` : "";
    if (!Cn || !Cn.classified) { box.innerHTML = `${picker}<div class="card empty"><h2 class="h3">Nothing recognised yet</h2><p>We couldn't match any captions or titles to known themes.</p></div>`; return; }
    const bars = Cn.themes.map((t, i) => `<div class="bar-row ${i === 0 ? "top" : ""}"><span class="emo" aria-hidden="true">${NL.moodEmoji(t.mood)}</span><span class="name">${esc(t.label)}</span><span class="track"><i style="width:${Math.min(100, t.share)}%"></i></span><span class="pct">${t.share.toFixed(0)}%</span></div>`).join("");
    const moods = Object.entries(Cn.moods).sort((a, b) => b[1] - a[1]).slice(0, 8).map(([m, v], i) => `<div class="bar-row ${i === 0 ? "top" : ""}"><span class="emo" aria-hidden="true">${NL.moodEmoji(m)}</span><span class="name">${NL.cap(m)}</span><span class="track"><i style="width:${Math.min(100, v)}%"></i></span><span class="pct">${v.toFixed(0)}%</span></div>`).join("");
    const flagged = Cn.flagged.map((f) => `<div class="flag-item"><div><p>${esc(f.text || "(no caption)")}</p><small>${NL.cap(f.mood)} · ${esc(Cn.themes.find((t) => t.key === f.theme)?.label || f.theme)} · ${NL.fmtDate(f.t * 1000)}</small></div><a class="btn sm ghost" href="${esc(f.url)}" target="_blank" rel="noopener noreferrer" aria-label="Open the original: ${esc((f.text || "").slice(0, 40))} (opens in a new tab)">${NL.icon("external", 15)}Open</a></div>`).join("");
    box.innerHTML = `${picker}
      <div class="series-head"><h2 class="h3" style="font-size:20px">${PLAT[cState.platform]} · what the content is about</h2><p class="coverage">${nf(Cn.classified)} of ${nf(Cn.total)} captions/titles recognised (${pct(Cn.classifiedShare)}%)</p></div>
      <p class="disclaimer" style="margin:0 0 14px">Estimated from captions, hashtags and titles using a keyword list (English and basic Roman Urdu/Hindi). It doesn't see the video itself. Use the video check below to test a sample.</p>
      <div class="dgrid">
        ${card("Themes", "share of recognised content", `<div class="themes">${bars}</div>`, "span2")}
        ${card("Moods", "estimated tone", `<div class="themes">${moods}</div><p class="disclaimer">Heavier tones: <b>${pct(Cn.heavyShare)}%</b> of recognised content.</p>`)}
        ${Cn.monthly.length > 1 ? card("Heavier-toned share over time", "per month", `<div id="c-month"></div>`, "span3") : ""}
        ${card("Heavier-toned examples", "most recent", flagged || `<p class="muted">Nothing with a strong heavy tone was found.</p>`, "span3")}
      </div>
      <div id="deepBox" style="margin-top:20px"></div>`;
    if (Cn.monthly.length > 1) {
      const el = $("c-month"), w = cw(el, 640, 280), ms = Cn.monthly;
      el.innerHTML = C.line({ labels: ms.map((x) => monthName(x.m)), series: [{ name: "Heavier-toned %", color: "#f4685f", values: ms.map((x) => Math.round((x.heavy / x.n) * 1000) / 10) }], width: w, height: Math.max(200, Math.round(w * 0.35)), yFmt: (v) => v + "%", area: true });
      C.describe(el, `Share of heavier-toned content by month, from ${monthName(ms[0].m)} to ${monthName(ms[ms.length - 1].m)}.`, C.table("Heavier-toned share by month", ["Month", "Recognised", "Heavier", "Share"], ms.map((x) => [monthName(x.m), nf(x.n), nf(x.heavy), Math.round((x.heavy / x.n) * 100) + "%"])));
    }
    renderDeep();
    NL.hydrateIcons(box);
  }

  /* ---------- deep check: run a sample of links through the video analyzer ---------- */
  const deepKey = "imp_deep_" + profile;
  let deepRun = null;
  function renderDeep() {
    const box = $("deepBox"); if (!box) return;
    const d = NL.store.get(deepKey, null);
    const left = NL.usage.left();
    const result = d ? `<div class="deep-result"><p><b>${d.ok}</b> of ${d.n} analyzed${d.failed ? `, ${d.failed} skipped` : ""} (${NL.fmtDate(d.at)}).</p>
        <p>By emotional tone: <b>${d.levels.calm}</b> calm, <b>${d.levels.watch}</b> worth a look, <b>${d.levels.high}</b> high concern. Most common feeling: <b>${d.top ? NL.moodEmoji(d.top) + " " + NL.cap(d.top) : "–"}</b>.</p>
        ${d.capHeavy != null ? `<p class="muted" style="font-size:13px">The caption-based estimate said ${pct(d.capHeavy)}% heavier-toned. The video check found ${d.ok ? Math.round(((d.levels.watch + d.levels.high) / d.ok) * 100) : 0}% in this sample.</p>` : ""}
        <p><a class="link-arrow" href="history.html">See them in your history <i data-icon="arrow" data-size="16"></i></a></p></div>` : "";
    box.innerHTML = `<section class="card deep-card"><div class="card-head"><h3 class="h-card">Check the videos themselves</h3><span class="muted" style="font-size:12.5px">optional</span></div>
      <p>Runs the video analyzer on a sample of the most recent liked, saved and watched links to compare what the captions suggest with what the videos actually feel like. Each one counts toward your monthly analyses (${left} left). Links are sent to our server for this step only.</p>
      <div class="chips no-print" style="margin:14px 0" role="group" aria-label="Sample size">${[5, 10, 20].map((n) => `<button class="chip" data-deep-n="${n}" aria-pressed="${n === (deepRun ? deepRun.n : 10)}">${n} items</button>`).join("")}</div>
      <div id="deepControls"><button class="btn primary" id="deepStart"><i data-icon="film" data-size="16"></i>Check a sample</button></div>
      <div id="deepProg" hidden><div class="progress" role="progressbar" aria-label="Video check progress" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><i id="deepBar"></i></div><p id="deepStage" aria-live="polite" style="margin-top:8px"></p><button class="btn sm" id="deepCancel">Stop</button></div>
      ${result}</section>`;
    NL.hydrateIcons(box);
    let nSel = 10;
    box.querySelectorAll("[data-deep-n]").forEach((b) => (b.onclick = () => { nSel = Number(b.dataset.deepN); box.querySelectorAll("[data-deep-n]").forEach((x) => x.setAttribute("aria-pressed", String(x === b))); }));
    $("deepStart").onclick = () => runDeep(nSel);
  }
  async function runDeep(n) {
    const left = NL.usage.left();
    if (left <= 0) return NL.upgradeModal(`You've used all ${NL.plan.get().quota} analyses on the ${NL.plan.get().name} plan this month.`);
    n = Math.min(n, left);
    const ev = await loadEvents();
    const ok = (e) => ["like", "save", "view"].includes(e.act) && ((e.src === "ig" && /instagram\.com\/(reel|reels|p)\//i.test(e.url)) || (e.src === "yt" && /youtube\.com\/watch\?v=/i.test(e.url)));
    const seen = new Set(), picks = [];
    const pools = [ev.ig.filter(ok), ev.yt.filter(ok)].map((a) => a.sort((x, y) => y.t - x.t));
    for (let i = 0; picks.length < n && (pools[0].length || pools[1].length); i++) {
      const e = pools[i % 2].shift(); if (!e) { if (!pools[0].length && !pools[1].length) break; continue; }
      if (!seen.has(e.url)) { seen.add(e.url); picks.push(e); }
    }
    if (!picks.length) return NL.toast("No analyzable links found in this import");
    deepRun = { n: picks.length, cancel: false };
    $("deepControls").hidden = true; $("deepProg").hidden = false;
    $("deepCancel").onclick = () => { deepRun.cancel = true; $("deepStage").textContent = "Stopping after the current item…"; };
    const levels = { calm: 0, watch: 0, high: 0 }, moods = {}; let okN = 0, failed = 0, first = null;
    for (let i = 0; i < picks.length && !deepRun.cancel; i++) {
      const e = picks[i];
      $("deepStage").textContent = `Analyzing ${i + 1} of ${picks.length}…`;
      $("deepBar").style.width = Math.round((i / picks.length) * 100) + "%"; $("deepProg").querySelector("[role=progressbar]").setAttribute("aria-valuenow", String(Math.round((i / picks.length) * 100)));
      try {
        const jobId = await NL.api.analyzeLink(e.url);
        const result = await NL.api.waitForJob(jobId, (st, p) => { $("deepStage").textContent = `Analyzing ${i + 1} of ${picks.length}: ${st || "working"}…`; });
        NL.usage.record();
        NL.history.add({ id: jobId, createdAt: Date.now(), profileId: profile, title: (result.source && result.source.title) || (e.text || "").slice(0, 60) || "Imported item", source: { kind: "link", url: e.url }, result });
        okN++; levels[NL.wellbeing.assess(result).level.key]++; moods[result.dominant_mood] = (moods[result.dominant_mood] || 0) + 1;
      } catch (err) { failed++; if (/reach the analysis service/i.test(err.message)) { first = err.message; break; } }
    }
    const top = Object.entries(moods).sort((a, b) => b[1] - a[1])[0];
    NL.store.set(deepKey, { n: picks.length, ok: okN, failed, levels, top: top && top[0], at: Date.now(), capHeavy: (report.platforms[cState.platform].content || {}).heavyShare });
    deepRun = null;
    announce(`Video check finished: ${okN} analyzed, ${failed} failed.`);
    renderDeep();
    if (first) NL.toast(first);
  }

  /* ================= BROWSE ================= */
  const bState = { platform: "all", kind: "all", act: "all", q: "", page: 0 };
  const PAGE = 25;
  async function renderBrowse() {
    const box = $("panel-browse");
    box.innerHTML = `<p class="muted">Loading your items…</p>`;
    const ev = await loadEvents();
    const all = [...ev.ig, ...ev.yt].filter((e) => e.url && !["profile", "search"].includes(e.kind) && e.act !== "hide").sort((a, b) => b.t - a.t);
    if (!all.length) { box.innerHTML = `<div class="card empty"><h2 class="h3">No browsable items</h2><p>Re-import to list your items here.</p></div>`; return; }
    const kinds = [...new Set(all.map((e) => e.kind))], acts = [...new Set(all.map((e) => e.act))];
    const draw = () => {
      const q = bState.q.trim().toLowerCase();
      const rows = all.filter((e) => (bState.platform === "all" || e.src === bState.platform) && (bState.kind === "all" || e.kind === bState.kind) && (bState.act === "all" || e.act === bState.act) && (!q || (e.text || "").toLowerCase().includes(q) || (e.by || "").toLowerCase().includes(q)));
      const pages = Math.max(1, Math.ceil(rows.length / PAGE)); bState.page = Math.min(bState.page, pages - 1);
      const slice = rows.slice(bState.page * PAGE, bState.page * PAGE + PAGE);
      $("browseList").innerHTML = slice.map((e) => {
        const id = e.src === "yt" ? NL.imp.parse.ytId(e.url) : "";
        const img = id ? `<img src="https://i.ytimg.com/vi/${id}/mqdefault.jpg" alt="" loading="lazy" decoding="async" onerror="this.remove()">` : "";
        const title = e.text ? e.text.replace(/\s+/g, " ").slice(0, 120) : "(no caption)";
        return `<div class="item-row"><div class="th" aria-hidden="true"><span class="th-emoji">${kindEmoji[e.kind] || "•"}</span>${img}</div>
          <div style="min-width:0"><b>${esc(title)}</b><small>${PLAT[e.src]} · ${esc(e.kind)} · ${esc(e.act)} · ${new Date(e.t * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" })}${e.by ? " · " + esc(e.by) : ""}</small></div>
          <div class="row-actions"><a class="btn sm ghost" href="${esc(e.url)}" target="_blank" rel="noopener noreferrer" aria-label="Open the original ${esc(e.kind)}: ${esc(title.slice(0, 40))} (opens in a new tab)">${NL.icon("external", 15)}Open</a></div></div>`;
      }).join("") || `<p class="muted">Nothing matches those filters.</p>`;
      $("browseCount").textContent = `${rows.length.toLocaleString()} item${rows.length === 1 ? "" : "s"}`;
      $("pgInfo").textContent = `Page ${bState.page + 1} of ${pages}`;
      $("pgPrev").disabled = bState.page === 0; $("pgNext").disabled = bState.page >= pages - 1;
      NL.hydrateIcons($("browseList"));
    };
    const opt = (vals, cur, fmt = (x) => x, all = "All") => ["all", ...vals].map((v) => `<option value="${esc(v)}"${v === cur ? " selected" : ""}>${v === "all" ? all : esc(fmt(v))}</option>`).join("");
    box.innerHTML = `<div class="series-head"><h2 class="h3" style="font-size:20px">Browse your items</h2><p class="coverage" id="browseCount"></p></div>
      <div class="browse-tools no-print"><label class="sr-only" for="bq">Search captions and titles</label><input class="input" id="bq" type="search" placeholder="Search captions, titles, channels…" value="${esc(bState.q)}">
        <label class="sr-only" for="bp">Platform</label><select class="input sm" id="bp">${opt(plats, bState.platform, (v) => PLAT[v], "All platforms")}</select>
        <label class="sr-only" for="bk">Type</label><select class="input sm" id="bk">${opt(kinds, bState.kind, NL.cap, "All types")}</select>
        <label class="sr-only" for="ba">Action</label><select class="input sm" id="ba">${opt(acts, bState.act, NL.cap, "All actions")}</select></div>
      <section class="card"><div id="browseList"></div></section>
      <div class="pager no-print"><button class="btn sm" id="pgPrev">Previous</button><span id="pgInfo" aria-live="polite"></span><button class="btn sm" id="pgNext">Next</button></div>`;
    $("bq").oninput = (e) => { bState.q = e.target.value; bState.page = 0; draw(); };
    $("bp").onchange = (e) => { bState.platform = e.target.value; bState.page = 0; draw(); };
    $("bk").onchange = (e) => { bState.kind = e.target.value; bState.page = 0; draw(); };
    $("ba").onchange = (e) => { bState.act = e.target.value; bState.page = 0; draw(); };
    $("pgPrev").onclick = () => { bState.page--; draw(); $("browseList").scrollIntoView({ block: "start" }); };
    $("pgNext").onclick = () => { bState.page++; draw(); $("browseList").scrollIntoView({ block: "start" }); };
    draw();
  }

  /* ================= tabs ================= */
  const TABS = [["overview", "Overview", "chart"], ...plats.map((p) => [p, PLAT[p], p === "ig" ? "instagram" : "play"]), ["content", "Content", "brain"], ["browse", "Browse items", "film"]];
  let current = TABS.some(([k]) => k === params.get("tab")) ? params.get("tab") : "overview";
  const rendered = new Set();
  const renderers = { overview: renderOverview, ig: () => renderPlatform("ig"), yt: () => renderPlatform("yt"), content: renderContent, browse: renderBrowse };

  $("hbTabs").innerHTML = TABS.map(([k, l, i]) => `<button class="hb-tab" role="tab" id="tab-${k}" aria-controls="panel-${k}" aria-selected="${k === current}" tabindex="${k === current ? 0 : -1}">${NL.icon(i, 16)}${l}</button>`).join("");
  function show(k, focus) {
    current = k;
    TABS.forEach(([t]) => { const b = $("tab-" + t); b.setAttribute("aria-selected", String(t === k)); b.tabIndex = t === k ? 0 : -1; $("panel-" + t).hidden = t !== k; });
    if (!rendered.has(k)) { rendered.add(k); renderers[k](); }
    { const bar = $("hbTabs"), t = $("tab-" + k); bar.scrollLeft = t.offsetLeft - (bar.clientWidth - t.offsetWidth) / 2; }
    if (focus) $("tab-" + k).focus();
    announce(`Showing ${TABS.find(([t]) => t === k)[1]}`);
    const u = new URL(location.href); u.searchParams.set("tab", k); history.replaceState(null, "", u);
  }
  $("hbTabs").addEventListener("click", (e) => { const b = e.target.closest("[role=tab]"); if (b) show(b.id.slice(4)); });
  $("hbTabs").addEventListener("keydown", (e) => {
    const keys = TABS.map(([k]) => k), i = keys.indexOf(current);
    const to = e.key === "ArrowRight" ? keys[(i + 1) % keys.length] : e.key === "ArrowLeft" ? keys[(i - 1 + keys.length) % keys.length] : e.key === "Home" ? keys[0] : e.key === "End" ? keys[keys.length - 1] : null;
    if (to) { e.preventDefault(); show(to, true); }
  });
  // chip clicks inside panels (series / platform pickers)
  document.addEventListener("click", (e) => {
    const s = e.target.closest("[data-series]"); if (s) { const p = s.closest(".hb-panel").id.slice(6); sel[p] = s.dataset.series; renderPlatform(p); $("panel-" + p).querySelector(`[data-series="${sel[p]}"]`).focus(); }
    const c = e.target.closest("[data-cplat]"); if (c) { cState.platform = c.dataset.cplat; renderContent(); $("panel-content").querySelector(`[data-cplat="${cState.platform}"]`).focus(); }
  });

  /* ================= actions ================= */
  function csvText() {
    const rows = [["section", "platform", "series", "key", "value"]];
    rows.push(["overall", "", "", "score", report.overall.score ?? ""], ["overall", "", "", "label", report.overall.label]);
    for (const [p, P] of Object.entries(report.platforms)) {
      rows.push(["verdict", PLAT[p], "", "score", P.verdict.score]);
      P.verdict.findings.forEach((f) => rows.push(["finding", PLAT[p], "", f.title, f.text]));
      for (const [k, s] of Object.entries(P.series)) {
        if (!s) continue;
        [["items", s.n], ["active_days", s.activeDays], ["days_covered", s.days], ["typical_per_active_day", s.perActiveDay], ["busiest_day", s.maxDay], ["night_share", s.nightShare.toFixed(4)], ["peak_hour", s.peakHour], ["sessions", s.sessions.count]].forEach(([a, b]) => rows.push(["series", PLAT[p], k, a, b]));
        s.byHour.forEach((v, h) => rows.push(["by_hour", PLAT[p], k, h, v]));
        s.byWeekday.forEach((v, d) => rows.push(["by_weekday", PLAT[p], k, H.WD[d], v]));
        Object.entries(s.monthly).sort().forEach(([m, v]) => rows.push(["by_month", PLAT[p], k, m, v]));
      }
      if (P.content) P.content.themes.forEach((t) => rows.push(["theme", PLAT[p], "", t.label, t.share.toFixed(1)]));
    }
    return rows.map((r) => r.map((c) => `"${String(c ?? "").replace(/"/g, '""')}"`).join(",")).join("\n");
  }
  $("csvBtn").onclick = () => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csvText()], { type: "text/csv" }));
    a.download = `neurolens-habits-${new Date().toISOString().slice(0, 10)}.csv`; a.click(); URL.revokeObjectURL(a.href);
    NL.toast("Summary exported");
  };
  const renderAll = () => TABS.forEach(([k]) => { if (!rendered.has(k) && k !== "browse") { rendered.add(k); renderers[k](); } });
  $("printBtn").onclick = () => { renderAll(); setTimeout(() => window.print(), 150); };
  addEventListener("beforeprint", renderAll);
  $("deleteBtn").onclick = async () => {
    if (!confirm("Delete this imported data and report from this browser? Your video analyses in History are not affected.")) return;
    await S.remove(profile); NL.store.del(deepKey); location.href = "import.html";
  };

  /* redraw charts when the width changes (rotation / resize) */
  let lastW = innerWidth, rt;
  addEventListener("resize", () => { clearTimeout(rt); rt = setTimeout(() => { if (Math.abs(innerWidth - lastW) > 30) { lastW = innerWidth; rendered.clear(); rendered.add(current); renderers[current](); } }, 250); });

  show(current);
  NL.hydrateIcons();
})();
