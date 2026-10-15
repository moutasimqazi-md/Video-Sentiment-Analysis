#!/usr/bin/env node
/* Keeps the three copies of the taxonomy in step. shared/taxonomy.json is the only file to edit.
     node shared/sync.js          write frontend/js/data/taxonomy.js and flutter/assets/taxonomy.json
     node shared/sync.js --check  exit 1 if either copy is out of date, or the data is inconsistent (used by the tests) */
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const src = path.join(__dirname, "taxonomy.json");
const outJs = path.join(root, "frontend", "js", "data", "taxonomy.js");
const outJson = path.join(root, "flutter", "assets", "taxonomy.json");

const data = JSON.parse(fs.readFileSync(src, "utf8"));

function problems(d) {
  const out = [];
  const topics = Object.keys(d.topics);
  for (const [k, t] of Object.entries(d.topics)) {
    if (!t.label) out.push(`topic ${k} has no label`);
    if (!(t.tags || []).length && !(t.words || []).length) out.push(`topic ${k} has no keywords`);
    for (const w of [...(t.tags || []), ...(t.words || [])]) if (w !== w.toLowerCase()) out.push(`topic ${k}: "${w}" is not lowercase`);
    for (const h of t.tags || []) if (/[\s#]/.test(h)) out.push(`topic ${k}: tag "${h}" must have no spaces or #`);
  }
  const ids = new Set();
  for (const g of d.goals) {
    if (ids.has(g.id)) out.push(`duplicate goal ${g.id}`);
    ids.add(g.id);
    for (const t of [...g.supports, ...g.avoid]) if (!topics.includes(t)) out.push(`goal ${g.id} names unknown topic ${t}`);
    for (const t of g.supports) if (g.avoid.includes(t)) out.push(`goal ${g.id} both supports and avoids ${t}`);
  }
  return out;
}

const js =
  "/* GENERATED from shared/taxonomy.json by shared/sync.js. Do not edit here. */\n" +
  "window.NL = window.NL || {};\n" +
  "NL.TAXONOMY = " + JSON.stringify(data, null, 1) + ";\n";
const json = JSON.stringify(data);

const bad = problems(data);
if (bad.length) {
  console.error("taxonomy problems:\n - " + bad.join("\n - "));
  process.exit(1);
}

if (process.argv.includes("--check")) {
  const stale = [];
  if (!fs.existsSync(outJs) || fs.readFileSync(outJs, "utf8") !== js) stale.push(path.relative(root, outJs));
  if (!fs.existsSync(outJson) || fs.readFileSync(outJson, "utf8") !== json) stale.push(path.relative(root, outJson));
  if (stale.length) {
    console.error("out of date (run: node shared/sync.js): " + stale.join(", "));
    process.exit(1);
  }
  console.log("taxonomy copies are in sync");
} else {
  fs.writeFileSync(outJs, js);
  fs.writeFileSync(outJson, json);
  console.log(`wrote ${path.relative(root, outJs)} and ${path.relative(root, outJson)} (${Object.keys(data.topics).length} topics, ${data.goals.length} goals)`);
}
