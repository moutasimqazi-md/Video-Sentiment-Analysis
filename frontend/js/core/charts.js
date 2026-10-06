/* Dependency-free SVG chart helpers. Every function returns an SVG/HTML string; hover tooltips come from data-tip attributes. */
window.NL = window.NL || {};

NL.charts = (() => {
  const PALETTE = ["#f4685f", "#4a7cf0", "#1f9d6f", "#e9a23b", "#8b6cf0", "#19a7b5", "#e0559f", "#7a8aa8"];
  const moodColor = (m) => {
    const keys = Object.keys(NL.MOODS);
    const i = Math.max(0, keys.indexOf(m));
    return `hsl(${Math.round((i * 360) / keys.length + 8)} 62% 56%)`;
  };
  const esc = (s) => NL.esc(s);
  const tip = (t) => `data-tip="${esc(t)}"`;

  const niceMax = (v) => {
    if (v <= 0) return 1;
    const p = Math.pow(10, Math.floor(Math.log10(v)));
    const n = v / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p;
  };
  const thin = (arr, max) => (arr.length <= max ? arr.map((_, i) => i) : arr.map((_, i) => i).filter((i) => i % Math.ceil(arr.length / max) === 0));

  /* ---------- line / area ---------- */
  function line({ labels, series, yMax, yFmt = (v) => v, area = true, height = 240, unit = "", width = 640 }) {
    const W = width, H = height, pl = 40, pr = 12, pt = 12, pb = 28;
    const max = yMax || niceMax(Math.max(1, ...series.flatMap((s) => s.values.filter((v) => v != null))));
    const n = labels.length;
    const x = (i) => pl + (n <= 1 ? (W - pl - pr) / 2 : (i / (n - 1)) * (W - pl - pr));
    const y = (v) => pt + (1 - v / max) * (H - pt - pb);
    const grid = [0, 0.25, 0.5, 0.75, 1].map((k) => `<line x1="${pl}" x2="${W - pr}" y1="${y(max * k)}" y2="${y(max * k)}" stroke="var(--border)" stroke-dasharray="${k ? "3 4" : ""}"/><text x="${pl - 8}" y="${y(max * k) + 3}" text-anchor="end">${yFmt(Math.round(max * k * 10) / 10)}</text>`).join("");
    const xl = thin(labels, Math.max(2, Math.floor(W / 80))).map((i) => `<text x="${x(i)}" y="${H - 8}" text-anchor="middle">${esc(labels[i])}</text>`).join("");
    let body = "";
    series.forEach((s, si) => {
      const pts = s.values.map((v, i) => (v == null ? null : [x(i), y(v)])).filter(Boolean);
      if (!pts.length) return;
      const d = pts.map((p, i) => (i ? "L" : "M") + p[0].toFixed(1) + " " + p[1].toFixed(1)).join(" ");
      if (area && si === 0 || area && series.length <= 2) {
        body += `<path d="${d} L${pts[pts.length - 1][0]} ${y(0)} L${pts[0][0]} ${y(0)}Z" fill="${s.color}" opacity=".10"/>`;
      }
      body += `<path d="${d}" fill="none" stroke="${s.color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`;
      s.values.forEach((v, i) => { if (v != null) body += `<circle cx="${x(i)}" cy="${y(v)}" r="${n > 30 ? 2.5 : 4}" fill="var(--surface)" stroke="${s.color}" stroke-width="2" ${tip(`${s.name} · ${labels[i]}: ${yFmt(Math.round(v * 10) / 10)}${unit}`)}/>`; });
    });
    return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img">${grid}${xl}${body}</svg>${legend(series)}`;
  }

  const legend = (series) => `<div class="legend">${series.map((s) => `<span><i style="background:${s.color}"></i>${esc(s.name)}</span>`).join("")}</div>`;

  /* ---------- donut ---------- */
  function donut({ items, centerBig, centerSmall }) {
    const total = items.reduce((a, b) => a + b.value, 0) || 1;
    const R = 70, C = 2 * Math.PI * R;
    let off = 0;
    const arcs = items.map((it) => {
      const len = (it.value / total) * C;
      const a = `<circle cx="100" cy="100" r="${R}" fill="none" stroke="${it.color}" stroke-width="26" stroke-dasharray="${len} ${C - len}" stroke-dashoffset="${-off}" transform="rotate(-90 100 100)" ${tip(`${it.label}: ${it.value} (${Math.round((it.value / total) * 100)}%)`)}/>`;
      off += len;
      return a;
    }).join("");
    const lg = items.map((it) => `<li><i style="background:${it.color}"></i><span>${esc(it.label)}</span><b>${Math.round((it.value / total) * 100)}%</b></li>`).join("");
    return `<div class="donut-wrap"><svg viewBox="0 0 200 200" class="donut" role="img"><circle cx="100" cy="100" r="${R}" fill="none" stroke="var(--surface-2)" stroke-width="26"/>${arcs}
      <text x="100" y="98" text-anchor="middle" class="d-big">${esc(centerBig)}</text><text x="100" y="118" text-anchor="middle" class="d-small">${esc(centerSmall)}</text></svg><ul class="donut-legend">${lg}</ul></div>`;
  }

  /* ---------- radar ---------- */
  function radar({ axes, values, max, color = "#f4685f" }) {
    const S = 360, cx = S / 2, cy = S / 2, R = 118, n = axes.length;
    const ang = (i) => (Math.PI * 2 * i) / n - Math.PI / 2;
    const pt = (i, r) => [cx + Math.cos(ang(i)) * r, cy + Math.sin(ang(i)) * r];
    const rings = [0.25, 0.5, 0.75, 1].map((k) => `<polygon points="${axes.map((_, i) => pt(i, R * k).join(",")).join(" ")}" fill="none" stroke="var(--border)"/>`).join("");
    const spokes = axes.map((_, i) => `<line x1="${cx}" y1="${cy}" x2="${pt(i, R)[0]}" y2="${pt(i, R)[1]}" stroke="var(--border)"/>`).join("");
    const poly = values.map((v, i) => pt(i, R * Math.min(1, v / max)).join(",")).join(" ");
    const dots = values.map((v, i) => { const [px, py] = pt(i, R * Math.min(1, v / max)); return `<circle cx="${px}" cy="${py}" r="4" fill="${color}" stroke="var(--surface)" stroke-width="2" ${tip(`${axes[i].label}: ${Math.round(v * 10) / 10}%`)}/>`; }).join("");
    const labs = axes.map((a, i) => { const [lx, ly] = pt(i, R + 22); return `<text x="${lx}" y="${ly + 4}" text-anchor="middle" class="r-lab">${a.emoji}</text>`; }).join("");
    return `<svg viewBox="0 0 ${S} ${S}" class="radar" role="img">${rings}${spokes}<polygon points="${poly}" fill="${color}" fill-opacity=".18" stroke="${color}" stroke-width="2.5" stroke-linejoin="round"/>${dots}${labs}</svg>`;
  }

  /* ---------- horizontal grouped bars ---------- */
  function hbars({ rows, series, max }) {
    const m = max || niceMax(Math.max(1, ...rows.flatMap((r) => r.values)));
    return `<div class="hbars">${rows.map((r) => `<div class="hb-row"><span class="hb-lab">${r.emoji ? `<span class="emo" aria-hidden="true">${r.emoji}</span>` : ""}${esc(r.label)}</span>
      <span class="hb-val">${r.values.map((v) => Math.round(v) + "%").join(" / ")}</span>
      <div class="hb-tracks">${r.values.map((v, i) => `<div class="hb-track" ${tip(`${series[i].name} · ${r.label}: ${Math.round(v * 10) / 10}%`)}><i style="width:${Math.min(100, (v / m) * 100)}%;background:${series[i].color}"></i></div>`).join("")}</div></div>`).join("")}</div>${series.length > 1 ? legend(series) : ""}`;
  }

  /* ---------- scatter ---------- */
  function scatter({ points, xLabel, yLabel, xMax, yMax = 100, width = 640, height = 260 }) {
    const W = width, H = height, pl = 56, pr = 14, pt = 12, pb = 40;
    const xm = xMax || niceMax(Math.max(10, ...points.map((p) => p.x)));
    const x = (v) => pl + (v / xm) * (W - pl - pr);
    const y = (v) => pt + (1 - v / yMax) * (H - pt - pb);
    const gy = [0, 0.5, 1].map((k) => `<line x1="${pl}" x2="${W - pr}" y1="${y(yMax * k)}" y2="${y(yMax * k)}" stroke="var(--border)"/><text x="${pl - 8}" y="${y(yMax * k) + 3}" text-anchor="end">${Math.round(yMax * k)}%</text>`).join("");
    const gx = [0, 0.5, 1].map((k) => `<text x="${x(xm * k)}" y="${H - 22}" text-anchor="middle">${Math.round(xm * k)}</text>`).join("");
    const dots = points.map((p) => `<circle cx="${x(p.x)}" cy="${y(p.y)}" r="7" fill="${p.color}" fill-opacity=".75" stroke="var(--surface)" stroke-width="2" ${tip(p.tip)}/>`).join("");
    return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img">${gy}${gx}${dots}<text x="${(W + pl) / 2}" y="${H - 4}" text-anchor="middle">${esc(xLabel)}</text><text x="12" y="${H / 2}" transform="rotate(-90 12 ${H / 2})" text-anchor="middle">${esc(yLabel)}</text></svg>`;
  }

  /* ---------- stacked bars ---------- */
  function stacked({ labels, series, height = 220, width = 640 }) {
    const W = width, H = height, pl = 34, pr = 10, pt = 10, pb = 28;
    const totals = labels.map((_, i) => series.reduce((a, s) => a + s.values[i], 0));
    const max = niceMax(Math.max(1, ...totals));
    const bw = Math.min(46, ((W - pl - pr) / labels.length) * 0.62);
    const step = (W - pl - pr) / labels.length;
    const y = (v) => pt + (1 - v / max) * (H - pt - pb);
    let bars = "";
    labels.forEach((lab, i) => {
      let acc = 0;
      const bx = pl + step * i + (step - bw) / 2;
      series.forEach((s) => {
        const v = s.values[i]; if (!v) return;
        bars += `<rect x="${bx}" y="${y(acc + v)}" width="${bw}" height="${y(acc) - y(acc + v)}" rx="3" fill="${s.color}" ${tip(`${lab} · ${s.name}: ${v}`)}/>`;
        acc += v;
      });
    });
    const xl = thin(labels, Math.max(2, Math.floor(W / 80))).map((i) => `<text x="${pl + step * i + step / 2}" y="${H - 8}" text-anchor="middle">${esc(labels[i])}</text>`).join("");
    const ticks = max <= 4 ? Array.from({ length: max + 1 }, (_, i) => i / max) : [0, 0.5, 1];   // whole numbers for small counts
    const gy = ticks.map((k) => `<line x1="${pl}" x2="${W - pr}" y1="${y(max * k)}" y2="${y(max * k)}" stroke="var(--border)"/><text x="${pl - 8}" y="${y(max * k) + 3}" text-anchor="end">${Math.round(max * k)}</text>`).join("");
    return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img">${gy}${bars}${xl}</svg>${legend(series)}`;
  }

  /* ---------- activity heatmap (weeks x 7 days) ---------- */
  function heatmap({ counts, weeks = 14 }) {
    const today = new Date(); today.setHours(0, 0, 0, 0);
    const start = new Date(today); start.setDate(start.getDate() - (weeks * 7 - 1) - ((today.getDay() + 6) % 7 === 0 ? 0 : 0));
    const cell = 20, gap = 3, pl = 28, pt = 18;
    const max = Math.max(1, ...Object.values(counts));
    let out = "", lastMonth = -1;
    for (let w = 0; w < weeks; w++) {
      for (let d = 0; d < 7; d++) {
        const dt = new Date(start); dt.setDate(start.getDate() + w * 7 + d);
        if (dt > today) continue;
        const key = dt.toISOString().slice(0, 10);
        const c = counts[key] || 0;
        const a = c ? 0.25 + 0.75 * (c / max) : 0;
        if (d === 0 && dt.getMonth() !== lastMonth) { out += `<text x="${pl + w * (cell + gap)}" y="11">${dt.toLocaleString(undefined, { month: "short" })}</text>`; lastMonth = dt.getMonth(); }
        out += `<rect x="${pl + w * (cell + gap)}" y="${pt + d * (cell + gap)}" width="${cell}" height="${cell}" rx="5" fill="${c ? "var(--coral)" : "var(--surface-2)"}" ${c ? `fill-opacity="${a}"` : ""} ${tip(`${dt.toLocaleDateString(undefined, { month: "short", day: "numeric" })}: ${c} ${c === 1 ? "analysis" : "analyses"}`)}/>`;
      }
    }
    const days = ["Mon", "", "Wed", "", "Fri", "", "Sun"].map((t, i) => `<text x="0" y="${pt + i * (cell + gap) + 13}">${t}</text>`).join("");
    const W = pl + weeks * (cell + gap), H = pt + 7 * (cell + gap);
    return `<svg class="chart heat" viewBox="0 0 ${W} ${H}" role="img">${days}${out}</svg>`;
  }

  /* ---------- sparkline for KPI cards ---------- */
  function spark(values, color = "#f4685f") {
    if (values.length < 2) return "";
    const W = 110, H = 34, max = Math.max(...values, 1), min = Math.min(...values, 0);
    const x = (i) => (i / (values.length - 1)) * W;
    const y = (v) => 3 + (1 - (v - min) / (max - min || 1)) * (H - 6);
    const d = values.map((v, i) => `${i ? "L" : "M"}${x(i).toFixed(1)} ${y(v).toFixed(1)}`).join(" ");
    return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><path d="${d} L${W} ${H} L0 ${H}Z" fill="${color}" opacity=".12"/><path d="${d}" fill="none" stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }

  /* ---------- shared tooltip ---------- */
  let tipEl;
  document.addEventListener("mouseover", (e) => {
    const t = e.target.closest && e.target.closest("[data-tip]");
    if (!t) return;
    if (!tipEl) { tipEl = document.createElement("div"); tipEl.className = "chart-tip"; document.body.appendChild(tipEl); }
    tipEl.textContent = t.getAttribute("data-tip");
    tipEl.style.display = "block";
  });
  document.addEventListener("mousemove", (e) => {
    if (!tipEl || tipEl.style.display !== "block") return;
    tipEl.style.left = Math.min(e.clientX + 14, innerWidth - tipEl.offsetWidth - 8) + "px";
    tipEl.style.top = e.clientY + 16 + "px";
  });
  document.addEventListener("mouseout", (e) => { if (tipEl && e.target.closest && e.target.closest("[data-tip]")) tipEl.style.display = "none"; });

  /* ---------- weekday x hour heatmap ("when does it happen") ---------- */
  function hourGrid({ grid, width = 600, unit = "items" }) {
    const WDN = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], WDF = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
    const pl = 34, pt = 20, gap = 2, cw = Math.max(8, (width - pl) / 24), ch = Math.max(14, Math.min(cw, 26));
    const H = pt + 7 * ch + 22, max = Math.max(1, ...grid.flat());
    const hl = (h) => `${h % 12 === 0 ? 12 : h % 12}${h < 12 ? "a" : "p"}`;
    let cells = "";
    for (let d = 0; d < 7; d++) for (let h = 0; h < 24; h++) {
      const v = grid[d][h], a = v ? 0.12 + 0.88 * Math.sqrt(v / max) : 0;
      cells += `<rect x="${pl + h * cw}" y="${pt + d * ch}" width="${cw - gap}" height="${ch - gap}" rx="3" fill="${v ? "var(--coral)" : "var(--surface-2)"}" ${v ? `fill-opacity="${a.toFixed(2)}"` : ""} ${tip(`${WDF[d]} ${hl(h)}: ${v.toLocaleString()} ${unit}`)}/>`;
    }
    const hours = [0, 3, 6, 9, 12, 15, 18, 21].map((h) => `<text x="${pl + h * cw}" y="12">${hl(h)}</text>`).join("");
    const days = WDN.map((n, d) => `<text x="0" y="${pt + d * ch + ch / 2 + 3}">${n}</text>`).join("");
    const night = `<rect x="${pl}" y="${pt - 3}" width="${5 * cw - gap}" height="${7 * ch + 3}" rx="4" fill="none" stroke="var(--blue)" stroke-width="1.5" stroke-dasharray="4 3" opacity=".8"/><text x="${pl + 2.5 * cw}" y="${H - 6}" text-anchor="middle" style="fill:var(--blue-ink)">midnight–5am</text>`;
    return `<svg class="chart heat" viewBox="0 0 ${width} ${H}" role="img">${hours}${days}${cells}${night}</svg>`;
  }

  /* ---------- shared a11y helpers (text alternative + data table fallback) ---------- */
  const table = (caption, headers, rows) =>
    `<div class="table-wrap" tabindex="0" role="region" aria-label="${esc(caption)} (scrolls sideways on small screens)"><table class="data-table"><caption class="sr-only">${esc(caption)}</caption><thead><tr>${headers.map((h) => `<th scope="col">${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c, i) => (i === 0 ? `<th scope="row">${esc(c)}</th>` : `<td>${esc(c)}</td>`)).join("")}</tr>`).join("")}</tbody></table></div>`;
  function describe(box, label, tableHtml) {
    const svg = box.querySelector("svg");
    if (svg) { svg.setAttribute("role", "img"); svg.setAttribute("aria-label", label); }
    else { box.setAttribute("role", "group"); box.setAttribute("aria-label", label); }
    if (tableHtml) box.insertAdjacentHTML("beforeend", `<details class="chart-data"><summary>View data as a table</summary>${tableHtml}</details>`);
  }

  return { PALETTE, moodColor, line, donut, radar, hbars, scatter, stacked, heatmap, spark, niceMax, hourGrid, table, describe };
})();
