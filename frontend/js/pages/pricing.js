/* Pricing page: billing toggle, plan cards, comparison table. */
(() => {
  const $ = (id) => document.getElementById(id);
  let cycle = NL.plan.cycle();
  const current = NL.plan.id();

  const price = (p) => (cycle === "yearly" ? p.yearly : p.monthly);

  function render() {
    document.querySelectorAll("#billing button").forEach((b) => { b.classList.toggle("active", b.dataset.cycle === cycle); b.setAttribute("aria-pressed", String(b.dataset.cycle === cycle)); });

    $("plans").innerHTML = Object.values(NL.PLANS).map((p) => {
      const isCurrent = p.id === current;
      const sub = p.monthly === 0 ? "Free forever" : cycle === "yearly" ? `Billed $${p.yearly * 12} per year` : "Billed monthly";
      return `<article class="card plan ${p.featured ? "featured" : ""}">
        ${p.featured ? '<span class="ribbon">Most popular</span>' : ""}
        <h2 class="h3">${NL.esc(p.name)}</h2><p class="muted" style="font-size:14px">${NL.esc(p.blurb)}</p>
        <div class="price">${price(p) ? "$" + price(p) : "$0"}<small> / month</small></div>
        <div class="sub">${sub}</div>
        <ul>${p.features.map((f) => `<li>${NL.esc(f)}</li>`).join("")}${p.off.map((f) => `<li class="off">${NL.esc(f)}</li>`).join("")}</ul>
        ${isCurrent ? `<button class="btn full" disabled>Your current plan</button>`
          : p.id === "free" ? `<button class="btn full" data-pick="free">Switch to Starter</button>`
          : `<a class="btn ${p.featured ? "primary" : "dark"} full" href="checkout.html?plan=${p.id}&cycle=${cycle}">Choose ${NL.esc(p.name)}</a>`}
      </article>`;
    }).join("");
  }

  document.querySelectorAll("#billing button").forEach((b) => (b.onclick = () => { cycle = b.dataset.cycle; render(); }));
  $("plans").addEventListener("click", (e) => {
    if (e.target.dataset.pick === "free") { NL.plan.set("free"); NL.toast("Switched to Starter"); setTimeout(() => location.reload(), 600); }
  });

  const ps = Object.values(NL.PLANS);
  const rows = [
    ["Analyses per month", (p) => p.quota],
    ["Visual + audio emotion scores", () => "✓"],
    ["Emotion timeline", () => "✓"],
    ["Paste Instagram Reel links", (p) => (p.link ? "✓" : "–")],
    ["Download & print reports", (p) => (p.export ? "✓" : "–")],
    ["Wellbeing signal", () => "✓"],
    ["Child monitoring profiles", (p) => p.children || "–"],
    ["Weekly summary reports", (p) => (p.weekly ? "✓" : "–")],
    ["Saved history", (p) => p.history],
    ["Team seats", (p) => p.seats],
  ];
  $("compare").innerHTML = `<caption class="sr-only">Plan comparison</caption><thead><tr><th scope="col"><span class="sr-only">Feature</span></th>${ps.map((p) => `<th scope="col">${NL.esc(p.name)}</th>`).join("")}</tr></thead>
    <tbody>${rows.map(([n, f]) => `<tr><td>${n}</td>${ps.map((p) => `<td>${(() => { const v = f(p); return v === "✓" ? `<span class="yes">✓</span>` : v === "–" ? `<span class="no">–</span>` : v; })()}</td>`).join("")}</tr>`).join("")}</tbody>`;

  render();
})();
