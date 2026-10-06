/* Import: intake (ZIPs, folders, loose files) + adapters for Instagram "Download your information" and Google Takeout (YouTube).
   Everything runs in the browser; only an allowlist of history files is ever read (never messages or personal details).

   Every adapter yields events in ONE shape:
     { src: "ig" | "yt", kind: "reel"|"post"|"story"|"video"|"short"|"music"|"search"|"profile"|"comment",
       act: "view"|"like"|"save"|"comment"|"search"|"follow"|"sub"|"ad"|"hide",
       t: epoch seconds, url, text (caption / title / query), by (channel or author) }                                           */
window.NL = window.NL || {};
NL.imp = NL.imp || {};

NL.imp.parse = (() => {
  /* ======================= text helpers ======================= */
  // Instagram's JSON is UTF-8 that was mis-decoded as Latin-1 ("ð\u009f˜\u0080"); undo that when it looks like it.
  const fix = (s) => {
    if (typeof s !== "string" || !/[Â-ô][\u0080-¿]/.test(s)) return s || "";
    try {
      const b = Uint8Array.from(s, (c) => { const k = c.charCodeAt(0); if (k > 255) throw 0; return k; });
      return new TextDecoder("utf-8", { fatal: true }).decode(b);
    } catch (e) { return s; }
  };
  const secs = (t) => (t && t > 1e12 ? Math.round(t / 1000) : t || 0);
  const ytId = (u) => { const m = /(?:v=|youtu\.be\/|shorts\/|embed\/)([A-Za-z0-9_-]{11})/.exec(u || ""); return m ? m[1] : ""; };
  const unesc = (s) => s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'").replace(/&nbsp;/g, " ");

  function csv(text) {                                                  // small RFC-4180 parser -> array of objects
    const rows = []; let row = [], cur = "", q = false;
    for (let i = 0; i < text.length; i++) {
      const c = text[i];
      if (q) { if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; } else cur += c; }
      else if (c === '"') q = true;
      else if (c === ",") { row.push(cur); cur = ""; }
      else if (c === "\n" || c === "\r") { if (c === "\r" && text[i + 1] === "\n") i++; row.push(cur); cur = ""; if (row.length > 1 || row[0] !== "") rows.push(row); row = []; }
      else cur += c;
    }
    if (cur || row.length) { row.push(cur); rows.push(row); }
    if (!rows.length) return [];
    const head = rows[0].map((h) => h.replace(/^﻿/, "").trim());
    return rows.slice(1).map((r) => Object.fromEntries(head.map((h, i) => [h, (r[i] || "").trim()])));
  }

  /* ======================= which files we read (allowlist) ======================= */
  const IG = [
    ["igVideosWatched", /(^|\/)videos_watched\.json$/i, "Reels watched"],
    ["igPostsViewed", /(^|\/)posts_viewed\.json$/i, "Posts viewed"],
    ["igLikes", /(^|\/)liked_posts\.json$/i, "Likes"],
    ["igSaved", /(^|\/)saved_posts\.json$/i, "Saved"],
    ["igStories", /(^|\/)stories_viewed\.json$/i, "Stories viewed"],
    ["igComments", /(^|\/)(post_comments[^/]*|reels_comments[^/]*)\.json$/i, "Comments"],
    ["igFollowing", /(^|\/)followers_and_following\/following\.json$/i, "Accounts followed"],
    ["igSearchWords", /(^|\/)word_or_phrase_searches\.json$/i, "Keyword searches"],
    ["igSearchRecent", /(^|\/)recent_searches\.json$/i, "Recent searches"],
    ["igSearchProfiles", /(^|\/)(profile_searches|account_searches)\.json$/i, "Profile searches"],
    ["igNotInterested", /(^|\/)posts_you'?re_not_interested_in\.json$/i, "Marked not interested"],
    ["igSeeLess", /(^|\/)see_less_topics\.json$/i, "Topics hidden"],
    ["igAds", /(^|\/)ads_viewed\.json$/i, "Ads seen"],
  ];
  const YT = [
    ["ytWatch", /(^|\/)watch-history\.(json|html)$/i, "Videos watched"],
    ["ytSearch", /(^|\/)search-history\.(json|html)$/i, "Searches"],
    ["ytSubs", /(^|\/)subscriptions\/[^/]*\.csv$/i, "Subscriptions"],
    ["ytLiked", /(^|\/)liked videos\.csv$/i, "Liked videos"],
  ];
  const LABELS = Object.fromEntries([...IG, ...YT].map(([k, , l]) => [k, l]));
  const norm = (n) => n.replace(/\\/g, "/");
  const categorize = (name) => { const n = norm(name); for (const [k, re] of [...IG, ...YT]) if (re.test(n)) return k; return null; };
  const isPrivate = (name) => /(^|\/)(messages|inbox|message_requests|personal_information|security_and_login_information)\//i.test(norm(name));

  /* ======================= intake: ZIPs, folders, loose files ======================= */
  async function walkEntry(entry, out, base = "") {                      // dropped folders (webkitGetAsEntry)
    if (entry.isFile) await new Promise((res) => entry.file((f) => { out.push({ file: f, path: base + f.name }); res(); }, res));
    else if (entry.isDirectory) {
      const reader = entry.createReader();
      for (;;) {
        const batch = await new Promise((res) => reader.readEntries(res, () => res([])));
        if (!batch.length) break;
        for (const e of batch) await walkEntry(e, out, base + entry.name + "/");
      }
    }
  }
  /** FileList | DataTransfer -> [{file, path}] */
  async function collect(input) {
    const out = [];
    if (input && input.items && input.items.length && input.items[0].webkitGetAsEntry) {
      const entries = [...input.items].map((i) => i.webkitGetAsEntry && i.webkitGetAsEntry()).filter(Boolean);
      for (const e of entries) await walkEntry(e, out);
      if (out.length) return out;
    }
    return [...(input.files || input)].map((f) => ({ file: f, path: f.webkitRelativePath || f.name }));
  }

  const IG_HTML = /(videos_watched|liked_posts|posts_viewed|stories_viewed|saved_posts)\.html?$/i;
  /** -> { sources:[{name, read()}], ignoredPrivate, archives, files, igHtml } */
  async function intake(input, onProgress) {
    const picked = await collect(input);
    const sources = []; let ignoredPrivate = 0, archives = 0, totalEntries = 0, igHtml = 0;
    for (const { file, path } of picked) {
      if (/\.zip$/i.test(file.name)) {
        archives++;
        onProgress && onProgress(`Opening ${file.name}`);
        const z = await NL.zip.open(file);
        for (const e of z.entries) {
          if (e.dir) continue;
          totalEntries++;
          if (isPrivate(e.name)) { ignoredPrivate++; continue; }          // never even listed as a candidate
          if (categorize(e.name)) sources.push({ name: norm(e.name), size: e.usize, read: () => z.text(e) });
          else if (IG_HTML.test(norm(e.name))) igHtml++;
        }
      } else {
        totalEntries++;
        const name = norm(path);
        if (isPrivate(name)) { ignoredPrivate++; continue; }
        if (categorize(name)) sources.push({ name, size: file.size, read: () => file.text() });
        else if (IG_HTML.test(name)) igHtml++;
      }
    }
    return { sources, ignoredPrivate, archives, files: picked.length, totalEntries, igHtml };
  }

  /* ======================= Instagram adapter ======================= */
  // New exports: item = { timestamp, label_values:[{label,value,href,timestamp_value}] }.  Old exports: string_map_data / string_list_data.
  function igFields(item) {
    const m = {};
    for (const lv of item.label_values || []) if (lv && lv.label) m[lv.label] = lv;
    const smd = item.string_map_data || {}, sld = (item.string_list_data || [])[0] || {};
    const deepTs = (o, d = 0) => { if (!o || typeof o !== "object" || d > 4) return 0; if (typeof o.timestamp === "number") return o.timestamp; for (const k in o) { const r = deepTs(o[k], d + 1); if (r) return r; } return 0; };
    const t = secs(item.timestamp || (m["Update time"] && m["Update time"].timestamp_value) || sld.timestamp || deepTs(smd) || 0);
    const url = (m.URL && (m.URL.href || m.URL.value)) || sld.href || (smd["Saved on"] && smd["Saved on"].href) || "";
    const text = fix((m.Caption && m.Caption.value) || (m["Search query"] && m["Search query"].value) || (smd.Comment && smd.Comment.value) || (smd.Search && smd.Search.value) || (sld.value) || "");
    const by = fix((m.Title && m.Title.value) || (smd["Media Owner"] && smd["Media Owner"].value) || item.title || "");
    return { t, url, text: text.trim(), by: by.trim().replace(/^@/, ""), m };
  }
  const igKind = (url, fallback) => (/\/(reel|reels|tv)\//i.test(url) ? "reel" : /\/stories\//i.test(url) ? "story" : /\/p\//i.test(url) ? "post" : fallback);
  const listOf = (j) => { if (Array.isArray(j)) return j; if (j && typeof j === "object") for (const k of Object.keys(j)) if (Array.isArray(j[k])) return j[k]; return []; };

  function igEvents(cat, json) {
    const out = []; const list = listOf(json).filter((x) => x && typeof x === "object");
    for (const it of list) {
      const f = igFields(it);
      const ev = { src: "ig", t: f.t, url: f.url, text: f.text, by: f.by };
      switch (cat) {
        case "igVideosWatched": Object.assign(ev, { kind: igKind(f.url, "reel"), act: "view" }); break;
        case "igPostsViewed": Object.assign(ev, { kind: igKind(f.url, "post"), act: "view" }); break;
        case "igLikes": Object.assign(ev, { kind: igKind(f.url, "post"), act: "like" }); break;
        case "igSaved": Object.assign(ev, { kind: igKind(f.url, "post"), act: "save" }); break;
        case "igStories": Object.assign(ev, { kind: "story", act: "view" }); break;
        case "igComments": Object.assign(ev, { kind: "comment", act: "comment" }); break;
        case "igFollowing": Object.assign(ev, { kind: "profile", act: "follow", text: "", by: f.by }); break;
        case "igSearchWords": case "igSearchRecent": Object.assign(ev, { kind: "search", act: "search" }); break;
        case "igSearchProfiles": Object.assign(ev, { kind: "search", act: "search", text: f.by }); break;
        case "igNotInterested": Object.assign(ev, { kind: "post", act: "hide", text: "" }); break;
        case "igSeeLess": { const lab = (it.label_values || []).map((l) => l.label).find(Boolean); Object.assign(ev, { kind: "profile", act: "hide", text: fix(lab || ""), t: secs(it.timestamp) }); break; }
        case "igAds": Object.assign(ev, { kind: "post", act: "ad", text: "" }); break;
        default: continue;
      }
      if (ev.t || cat === "igSeeLess") out.push(ev);
    }
    return out;
  }

  /* ======================= YouTube (Google Takeout) adapter ======================= */
  const WATCH_PREFIX = /^(watched|viewed|listened to|visto|vu|angesehen|assistido|guardado)\s+/i;
  function ytFromJson(cat, json) {
    const out = []; let skippedAds = 0;
    for (const it of Array.isArray(json) ? json : []) {
      if (!it || !it.time) continue;
      const t = Math.round(Date.parse(it.time) / 1000); if (!t) continue;
      if ((it.details || []).some((d) => /google ads/i.test(d.name || ""))) { skippedAds++; continue; }
      const url = it.titleUrl || "";
      let title = fix(it.title || "");
      if (cat === "ytWatch") {
        if (!url) continue;                                             // "Watched a video that has been removed"
        title = title.replace(WATCH_PREFIX, "");
        const music = (it.products || []).some((p) => /music/i.test(p)) || /music\.youtube/i.test(url);
        out.push({ src: "yt", kind: music ? "music" : /\/shorts\//i.test(url) ? "short" : "video", act: "view", t, url, text: title, by: fix((it.subtitles && it.subtitles[0] && it.subtitles[0].name) || "") });
      } else {
        out.push({ src: "yt", kind: "search", act: "search", t, url, text: title.replace(/^(searched for|searched|buscaste|recherché)\s+/i, ""), by: "" });
      }
    }
    return { events: out, skippedAds };
  }
  function ytFromHtml(cat, html) {                                      // best-effort: Takeout's default format is HTML, dates are localised
    const out = []; let bad = 0;
    const cells = html.match(/<div class="content-cell mdl-cell mdl-cell--6-col mdl-typography--body-1">[\s\S]*?<\/div>/g) || [];
    for (const c of cells) {
      const anchors = [...c.matchAll(/<a href="([^"]+)">([\s\S]*?)<\/a>/g)];
      const tail = unesc(c.replace(/<[^>]+>/g, "\n").split("\n").map((x) => x.trim()).filter(Boolean).slice(-1)[0] || "");
      if (!anchors.length) continue;
      // Only the strict English format is trusted ("Oct 1, 2026, 11:42:10 PM GMT+05:00"). Other locales write day/month in other orders and
      // JavaScript's lenient parser would silently misread them, so those are rejected and the user is told to export JSON instead.
      if (!/^[A-Za-z]{3,9}\.? \d{1,2}, \d{4},? \d{1,2}:\d{2}:\d{2}(\s?[AP]M)?/.test(tail)) { bad++; continue; }
      const d = tail.replace(/,\s(\d{1,2}:\d{2}:\d{2})/, " $1").replace(/\sGMT([+-])(\d{2}):?(\d{2})/, " GMT$1$2$3").replace(/ /g, " ");
      const t = Math.round(Date.parse(d) / 1000);
      if (!t) { bad++; continue; }
      const url = unesc(anchors[0][1]); const title = unesc(anchors[0][2].replace(/<[^>]+>/g, ""));
      if (cat === "ytWatch") out.push({ src: "yt", kind: /\/shorts\//i.test(url) ? "short" : /music\.youtube/i.test(url) ? "music" : "video", act: "view", t, url, text: title, by: anchors[1] ? unesc(anchors[1][2].replace(/<[^>]+>/g, "")) : "" });
      else out.push({ src: "yt", kind: "search", act: "search", t, url, text: title, by: "" });
    }
    return { events: out, badDates: bad, cells: cells.length };
  }
  function ytFromCsv(cat, text) {
    const rows = csv(text);
    if (cat === "ytSubs") return rows.map((r) => ({ src: "yt", kind: "profile", act: "sub", t: 0, url: r["Channel URL"] || r["Channel Url"] || "", text: r["Channel title"] || r["Channel Title"] || "", by: r["Channel title"] || "" }));
    return rows.map((r) => {
      const id = r["Video ID"] || r["Video Id"] || "";
      const t = Math.round(Date.parse(r["Playlist video creation timestamp"] || r["Playlist Video Creation Timestamp"] || "") / 1000) || 0;
      return { src: "yt", kind: "video", act: "like", t, url: id ? `https://www.youtube.com/watch?v=${id}` : "", text: "", by: "" };
    }).filter((e) => e.url);
  }

  /* ======================= main entry ======================= */
  async function run(sources, onProgress) {
    const events = { ig: [], yt: [] };
    const recognized = {}, ranges = {}; const problems = [];
    let done = 0, htmlDateProblems = 0, adsSkipped = 0;
    for (const s of sources) {
      const cat = categorize(s.name);
      onProgress && onProgress({ stage: `Reading ${(LABELS[cat] || cat).toLowerCase()}`, done, total: sources.length });
      try {
        const text = await s.read();
        let evs = [];
        if (cat.startsWith("ig")) evs = igEvents(cat, JSON.parse(text));
        else if (/\.csv$/i.test(s.name)) evs = ytFromCsv(cat, text);
        else if (/\.json$/i.test(s.name)) { const r = ytFromJson(cat, JSON.parse(text)); evs = r.events; adsSkipped += r.skippedAds; }
        else { const r = ytFromHtml(cat, text); evs = r.events; htmlDateProblems += r.badDates; if (!evs.length && r.cells) problems.push(`${s.name}: couldn't read the dates in this HTML file. Re-export from Google Takeout and choose JSON as the format.`); }
        const bucket = cat.startsWith("ig") ? "ig" : "yt";
        for (const e of evs) events[bucket].push(e);
        recognized[cat] = (recognized[cat] || 0) + evs.length;
        const ts = evs.map((e) => e.t).filter(Boolean);
        const r = (ranges[cat] = ranges[cat] || { n: 0, from: 0, to: 0 });
        r.n += evs.length;
        if (ts.length) { const a = Math.min(...ts), b = Math.max(...ts); r.from = r.from ? Math.min(r.from, a) : a; r.to = Math.max(r.to, b); }
      } catch (e) { problems.push(`${s.name}: ${e.message || "couldn't be read"}`); }
      done++;
      await new Promise((r) => setTimeout(r, 0));                       // let the UI breathe
    }
    onProgress && onProgress({ stage: "Done reading", done, total: sources.length });
    return { events, recognized, ranges, problems, adsSkipped, htmlDateProblems };
  }

  return { intake, run, categorize, isPrivate, LABELS, fix, csv, ytId, _ig: igEvents, _yt: { json: ytFromJson, html: ytFromHtml, csv: ytFromCsv } };
})();
