/* Analyze page: add links, videos or images, enforce plan limits, and hand them to the background queue (NL.jobs).
   One item: follow it here and open the results. Several: they queue up and the header tray tracks them. */
(() => {
  const $ = (id) => document.getElementById(id);
  const VIDEO = [".mp4", ".mov", ".avi", ".mkv", ".webm"], IMAGE = [".jpg", ".jpeg", ".png", ".webp"];
  const ALLOWED = [...VIDEO, ...IMAGE];
  const MAX_BYTES = 300 * 1024 * 1024;
  const MAX_ITEMS = 10;

  let mode = "link";
  let files = [];
  let busy = false;

  function refreshQuota() {
    const plan = NL.plan.get();
    $("planName").textContent = plan.name;
    $("quotaText").innerHTML = `<b>${NL.usage.left()}</b> of ${plan.quota} analyses left this month`;
  }
  refreshQuota();
  NL.hydrateIcons();

  /* ---- who is this for ---- */
  const sel = $("profileSel");
  const kids = NL.profiles.children();
  sel.innerHTML = `<option value="me">Me (my own content)</option>` +
    kids.map((c) => `<option value="${NL.esc(c.id)}">${NL.esc(c.name)}${c.age ? " (" + c.age + ")" : ""} — child profile</option>`).join("") +
    `<option value="__new">+ Add a child profile…</option>`;
  const wanted = new URLSearchParams(location.search).get("profile") || NL.profiles.active();
  if ([...sel.options].some((o) => o.value === wanted)) sel.value = wanted;
  sel.onchange = () => {
    if (sel.value === "__new") { location.href = "family.html?add=1"; return; }
    NL.profiles.setActive(sel.value);
  };

  const showError = (msg) => { $("errBox").textContent = msg; $("errBox").hidden = !msg; };

  /* ---- tabs ---- */
  document.querySelectorAll(".tab").forEach((t) => (t.onclick = () => {
    mode = t.dataset.tab;
    document.querySelectorAll(".tab").forEach((x) => { x.classList.toggle("active", x === t); x.setAttribute("aria-selected", String(x === t)); });
    $("tabFile").hidden = mode !== "file";
    $("tabLink").hidden = mode !== "link";
    showError("");
  }));

  /* ---- file selection ---- */
  function grabThumbnail(f) {
    if (/^image\//.test(f.type)) {
      return new Promise((resolve) => {
        const url = URL.createObjectURL(f), im = new Image();
        im.onload = () => {
          const c = document.createElement("canvas"), k = Math.min(160 / Math.min(im.width, im.height), 1);
          c.width = Math.round(im.width * k); c.height = Math.round(im.height * k);
          c.getContext("2d").drawImage(im, 0, 0, c.width, c.height);
          URL.revokeObjectURL(url); resolve(c.toDataURL("image/jpeg", 0.7));
        };
        im.onerror = () => { URL.revokeObjectURL(url); resolve(null); };
        im.src = url;
      });
    }
    return new Promise((resolve) => {
      const url = URL.createObjectURL(f);
      const v = document.createElement("video");
      const done = (val) => { URL.revokeObjectURL(url); resolve(val); };
      const timer = setTimeout(() => done(null), 4000);
      v.muted = true; v.preload = "metadata"; v.src = url;
      v.onloadeddata = () => { v.currentTime = Math.min(1, (v.duration || 2) / 2); };
      v.onseeked = () => {
        try {
          const c = document.createElement("canvas");
          const s = 160 / Math.min(v.videoWidth, v.videoHeight);
          c.width = Math.round(v.videoWidth * s); c.height = Math.round(v.videoHeight * s);
          c.getContext("2d").drawImage(v, 0, 0, c.width, c.height);
          clearTimeout(timer); done(c.toDataURL("image/jpeg", 0.7));
        } catch (e) { clearTimeout(timer); done(null); }
      };
      v.onerror = () => { clearTimeout(timer); done(null); };
    });
  }

  const extOf = (f) => "." + (f.name.split(".").pop() || "").toLowerCase();
  function renderFiles() {
    const list = $("fileList");
    list.hidden = !files.length;
    $("dropzone").hidden = files.length >= MAX_ITEMS;
    list.innerHTML = files.map((x, i) => `<div class="file-chip"><img alt="" ${x.thumb ? `src="${x.thumb}"` : ""}>
      <div class="meta"><b>${NL.esc(x.file.name)}</b><span>${x.isImage ? "Image" : "Video"} · ${(x.file.size / 1048576).toFixed(1)} MB</span></div>
      <button class="btn sm" type="button" data-rm="${i}" aria-label="Remove ${NL.esc(x.file.name)}">Remove</button></div>`).join("");
  }
  async function addFiles(picked) {
    showError("");
    const problems = [];
    for (const f of picked) {
      if (files.length >= MAX_ITEMS) { problems.push(`You can add up to ${MAX_ITEMS} at a time.`); break; }
      if (!ALLOWED.includes(extOf(f))) { problems.push(`${f.name}: unsupported type. Use ${ALLOWED.join(", ")}.`); continue; }
      if (f.size > MAX_BYTES) { problems.push(`${f.name} is over 300 MB.`); continue; }
      files.push({ file: f, thumb: null, isImage: IMAGE.includes(extOf(f)) });
    }
    if (problems.length) showError([...new Set(problems)].join(" "));
    renderFiles();
    for (const x of files.filter((y) => !y.tried)) { x.tried = true; x.thumb = await grabThumbnail(x.file); renderFiles(); }
  }
  $("fileList").addEventListener("click", (e) => { const b = e.target.closest("[data-rm]"); if (b) { files.splice(+b.dataset.rm, 1); renderFiles(); } });
  $("videoInput").onchange = (e) => { addFiles([...e.target.files]); e.target.value = ""; };

  const dz = $("dropzone");
  ["dragenter", "dragover"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.remove("over"); }));
  dz.addEventListener("drop", (e) => addFiles([...e.dataTransfer.files]));

  /* ---- run ---- */
  function setRunning(on) {
    busy = on;
    $("runState").classList.toggle("show", on);
    $("analyzeBtn").hidden = on;
    $("tabFile").style.opacity = $("tabLink").style.opacity = on ? ".4" : "";
  }
  function progress(stage, frac) {
    $("stageText").textContent = stage;
    $("progBar").style.width = Math.round(frac * 100) + "%";
    $("progWrap").setAttribute("aria-valuenow", String(Math.round(frac * 100)));
    $("progText").textContent = Math.round(frac * 100) + "%";
  }

  const parseLinks = () => [...new Set($("linkInput").value.split(/[\s,]+/).map((x) => x.trim()).filter(Boolean))];

  $("analyzeBtn").onclick = async () => {
    if (busy) return;
    showError("");
    $("queuedMsg").hidden = true;
    const plan = NL.plan.get();
    const profileId = sel.value === "__new" ? "me" : sel.value;

    let links = [];
    if (mode === "link") {
      links = parseLinks();
      if (!links.length) return showError("Paste a link first.");
      if (links.some((l) => !/^https?:\/\//i.test(l))) return showError("Paste full links starting with https://");
      if (links.length > MAX_ITEMS) return showError(`Add up to ${MAX_ITEMS} links at a time.`);
    } else if (!files.length) return showError("Choose a video or image first.");

    const count = mode === "link" ? links.length : files.length;
    if (NL.usage.left() <= 0) return NL.upgradeModal(`You've used all ${plan.quota} analyses on the ${plan.name} plan this month.`);
    if (count > NL.usage.left()) return showError(`You have ${NL.usage.left()} ${NL.usage.left() === 1 ? "analysis" : "analyses"} left this month, but added ${count}. Remove some or upgrade.`);

    const start = (i) => mode === "link"
      ? NL.jobs.startLink(links[i], { profileId })
      : NL.jobs.startFile(files[i].file, { profileId, thumb: files[i].thumb });

    if (count === 1) {
      // follow the single job here and open its results
      document.body.dataset.jobsQuiet = "1";
      setRunning(true); progress("Starting…", 0);
      const j = await start(0);
      const follow = () => {
        const cur = NL.jobs.get(j.id);
        if (!cur) return;
        progress(cur.stage || "Working", cur.progress || 0);
        if (cur.status === "done") { progress("Done", 1); location.href = `results.html?id=${encodeURIComponent(cur.entryId)}`; }
        else if (cur.status === "error") { setRunning(false); delete document.body.dataset.jobsQuiet; showError(cur.error || "Analysis failed"); NL.jobs.remove(cur.id); }
      };
      NL.jobs.on("change", follow); follow();
      return;
    }

    // several: queue them all; they run one after another in the background
    busy = true; $("analyzeBtn").disabled = true;
    $("runState").classList.add("show");
    for (let i = 0; i < count; i++) {
      progress(`Adding ${i + 1} of ${count}…`, (i + 1) / count);
      await start(i); // each upload finishes before the next starts so the connection isn't saturated
    }
    busy = false; $("analyzeBtn").disabled = false; $("runState").classList.remove("show");
    $("linkInput").value = ""; files = []; renderFiles();
    $("queuedMsg").hidden = false;
    $("queuedText").textContent = `${count} analyses added. They run one after another in the background, so you can leave this page. Follow progress from the lightning icon in the header.`;
    if (NL.jobTray) NL.jobTray.open();
  };
})();
