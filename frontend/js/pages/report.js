/* Printable report: a single analysis (?id=) or a period summary for a profile (?profile=&days=). */
(() => {
  const $ = (id) => document.getElementById(id);
  const q = new URLSearchParams(location.search);
  $("rBrand").innerHTML = NL.BRAND;
  $("printBtn").innerHTML = NL.icon("print", 18) + "Print / Save as PDF";
  $("printBtn").onclick = () => window.print();

  let entries = [];
  let title, sub, profileId = "me";

  if (q.get("id")) {
    const e = q.get("id") === "sample" ? NL.SAMPLE : NL.history.get(q.get("id"));
    if (e) { entries = [e]; profileId = e.profileId || "me"; title = e.title || "Reel analysis"; sub = `${NL.fmtDate(e.createdAt)} · ${NL.profiles.name(profileId)}`; }
  } else {
    profileId = q.get("profile") || "me";
    const days = Number(q.get("days")) || 7;
    const since = Date.now() - days * 864e5;
    entries = NL.history.list().filter((h) => (h.profileId || "me") === profileId && h.createdAt >= since);
    const who = NL.profiles.name(profileId);
    title = profileId === "me" ? `My ${days}-day Reels report` : `${who}'s ${days}-day Reels report`;
    sub = `${NL.fmtDate(since)} – ${NL.fmtDate(Date.now())}`;
  }

  if (!entries.length) { $("rEmpty").hidden = false; return; }
  $("rBody").hidden = false;
  $("rTitle").textContent = title;
  $("rSub").textContent = sub;
  document.title = `${title} — NeuroLens`;

  const agg = NL.wellbeing.aggregate(entries);
  const forChild = profileId !== "me";

  $("rLevel").innerHTML = `<div class="alert-banner ${agg.overall.key}" style="margin:0 0 18px"><div class="ico">${NL.wellbeing.iconSvg(agg.overall)}</div>
    <div><b>Overall: ${agg.overall.label}</b><p>${agg.count} Reel${agg.count > 1 ? "s" : ""} reviewed · ${agg.heavyShare}% had a heavier emotional tone.</p></div></div>`;

  const topMood = agg.mix[0];
  $("rStats").innerHTML = [
    ["Reels reviewed", agg.count],
    ["Top emotion", `${NL.moodEmoji(topMood[0])} ${NL.cap(topMood[0])}`],
    ["Worth a look", agg.levels.watch],
    ["High concern", agg.levels.high],
  ].map(([k, v]) => `<div class="stat"><small>${k}</small><b>${v}</b></div>`).join("");

  $("rBars").innerHTML = agg.mix.slice(0, 8).map(([m, v], i) => `
    <div class="bar-row ${i === 0 ? "top" : ""}"><span class="emo" aria-hidden="true">${NL.moodEmoji(m)}</span><span class="name">${NL.cap(m)}</span>
    <span class="track"><i style="width:${Math.min(v, 100)}%"></i></span><span class="pct">${v.toFixed(1)}%</span></div>`).join("");

  if (agg.flagged.length) {
    $("rFlags").innerHTML = agg.flagged.map(({ entry, assessment }) => `<div class="insight"><div class="ico">${NL.wellbeing.iconSvg(assessment.level)}</div>
      <div><b>${NL.esc(entry.title || "Untitled")} · ${NL.fmtDate(entry.createdAt)}</b><span>${NL.esc(assessment.summary)}</span>${NL.sourceUrl(entry) ? `<span class="src-link">Source: <a href="${NL.esc(NL.sourceUrl(entry))}" target="_blank" rel="noopener noreferrer">${NL.esc(NL.sourceUrl(entry))}<span class="sr-only"> (opens in a new tab)</span></a></span>` : ""}</div></div>`).join("");
  } else {
    $("rFlags").innerHTML = `<p class="muted">Nothing flagged in this period.</p>`;
  }

  const tips = forChild ? NL.wellbeing.TIPS : [
    "Lean into your strongest emotion: your clearest Reels are the ones where one feeling dominates.",
    "Check pacing: fast cuts raise energy, slower cuts feel calmer.",
    "If your feed leaves you drained, balance it with lighter or more peaceful content.",
  ];
  $("rTipsH").textContent = forChild ? "Talking with your child" : "Suggestions";
  $("rTips").innerHTML = tips.map((t) => `<li>${NL.esc(t)}</li>`).join("");
})();
