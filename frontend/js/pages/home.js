/* Landing page: mood cloud + plan teasers */
(() => {
  document.getElementById("moodCloud").innerHTML = Object.entries(NL.MOODS)
    .map(([k, m]) => `<span class="mood-pill"><span class="emo">${m.emoji}</span>${NL.cap(k)}</span>`).join("");

  document.getElementById("planTeasers").innerHTML = Object.values(NL.PLANS).map((p, i) => `
    <article class="card hover reveal d${i} ${p.featured ? "featured-teaser" : ""}" style="${p.featured ? "border:2px solid var(--coral);box-shadow:0 18px 44px rgba(244,104,95,.16)" : ""}">
      ${p.featured ? '<span class="badge coral" style="margin-bottom:12px">Most popular</span>' : ""}
      <h3 style="font-size:20px">${NL.esc(p.name)}</h3>
      <div style="font:800 40px/1 var(--font-display);letter-spacing:-.04em;margin:14px 0 10px">${p.monthly ? "$" + p.monthly : "Free"}<small style="font:500 14px var(--font);color:var(--muted);letter-spacing:0">${p.monthly ? " / month" : ""}</small></div>
      <p>${NL.esc(p.blurb)}</p>
      <ul style="list-style:none;padding:0;margin:16px 0 0;display:grid;gap:8px;font-size:14px;color:var(--muted)">
        ${p.features.slice(0, 3).map((f) => `<li style="display:flex;gap:8px">${NL.icon("check", 16)}<span>${NL.esc(f)}</span></li>`).join("")}
      </ul>
    </article>`).join("");

  NL.hydrateIcons();
  NL.observeReveal();
})();
