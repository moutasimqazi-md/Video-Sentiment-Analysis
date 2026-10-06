/* Analyze page: pick a file or link, enforce plan limits, run the job, save to history. */
(() => {
  const $ = (id) => document.getElementById(id);
  const ALLOWED = [".mp4", ".mov", ".avi", ".mkv", ".webm"];
  const MAX_BYTES = 300 * 1024 * 1024;

  let mode = "link";
  let file = null;
  let thumb = null;
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

  async function setFile(f) {
    showError("");
    const ext = "." + (f.name.split(".").pop() || "").toLowerCase();
    if (!ALLOWED.includes(ext)) return showError(`Unsupported file type ${ext}. Use ${ALLOWED.join(", ")}.`);
    if (f.size > MAX_BYTES) return showError("That file is over 300 MB.");
    file = f;
    $("fileName").textContent = f.name;
    $("fileMeta").textContent = `${(f.size / 1048576).toFixed(1)} MB`;
    $("fileThumb").removeAttribute("src");
    $("fileChip").hidden = false;
    $("dropzone").hidden = true;
    thumb = await grabThumbnail(f);
    if (thumb) $("fileThumb").src = thumb;
  }

  const clearFile = () => { file = null; thumb = null; $("videoInput").value = ""; $("fileChip").hidden = true; $("dropzone").hidden = false; };
  $("fileClear").onclick = clearFile;
  $("videoInput").onchange = (e) => e.target.files[0] && setFile(e.target.files[0]);

  const dz = $("dropzone");
  ["dragenter", "dragover"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.add("over"); }));
  ["dragleave", "drop"].forEach((t) => dz.addEventListener(t, (e) => { e.preventDefault(); dz.classList.remove("over"); }));
  dz.addEventListener("drop", (e) => e.dataTransfer.files[0] && setFile(e.dataTransfer.files[0]));

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

  $("analyzeBtn").onclick = async () => {
    if (busy) return;
    showError("");
    const plan = NL.plan.get();

    if (NL.usage.left() <= 0) return NL.upgradeModal(`You've used all ${plan.quota} analyses on the ${plan.name} plan this month.`);
    if (mode === "file" && !file) return showError("Choose a video file first.");
    let link = "";
    if (mode === "link") {
      link = $("linkInput").value.trim();
      if (!/^https?:\/\//i.test(link)) return showError("Paste a full link starting with https://");
    }

    setRunning(true);
    progress("Starting…", 0);
    try {
      let jobId;
      if (mode === "file") {
        progress("Uploading video", 0);
        jobId = await NL.api.uploadFile(file, (f) => progress("Uploading video", f * 0.1));
      } else {
        jobId = await NL.api.analyzeLink(link);
      }
      const result = await NL.api.waitForJob(jobId, (stage, p) => progress(stage, Math.max(p, mode === "file" ? 0.1 : 0)));

      NL.usage.record();
      NL.history.add({
        id: jobId, createdAt: Date.now(), result, thumb,
        profileId: sel.value === "__new" ? "me" : sel.value,
        title: mode === "file" ? file.name : (result.source && result.source.title) || link,
        source: mode === "file" ? { kind: "upload" } : { kind: "link", url: link },
      });
      progress("Done", 1);
      location.href = `results.html?id=${encodeURIComponent(jobId)}`;
    } catch (e) {
      setRunning(false);
      showError(e.message);
    }
  };
})();
