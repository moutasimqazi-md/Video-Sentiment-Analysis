/* Client for the FastAPI backend (backend/neurolens/main.py). */
window.NL = window.NL || {};

NL.api = (() => {
  // Served by the backend → same origin. Opened straight from disk → talk to the local server.
  const base = location.protocol === "file:" ? "http://localhost:8000/" : "/";

  const H = { "ngrok-skip-browser-warning": "1" };

  async function json(res) {
    let body = null;
    try { body = await res.json(); } catch (e) { /* non-JSON error */ }
    if (!res.ok) throw new Error((body && body.detail) || `Request failed (${res.status})`);
    return body;
  }

  const networkError = () => new Error("We can't reach the analysis service right now. Please try again in a moment.");

  function uploadFile(file, onProgress) {
    return new Promise((resolve, reject) => {
      const fd = new FormData();
      fd.append("file", file);
      const xhr = new XMLHttpRequest();
      xhr.open("POST", base + "api/analyze");
      xhr.setRequestHeader("ngrok-skip-browser-warning", "1");
      xhr.upload.onprogress = (e) => e.lengthComputable && onProgress && onProgress(e.loaded / e.total);
      xhr.onerror = () => reject(networkError());
      xhr.onload = () => {
        let body = null;
        try { body = JSON.parse(xhr.responseText); } catch (e) { /* ignore */ }
        if (xhr.status >= 200 && xhr.status < 300) resolve(body.job_id);
        else reject(new Error((body && body.detail) || `Upload failed (${xhr.status})`));
      };
      xhr.send(fd);
    });
  }

  async function analyzeLink(url) {
    try {
      const res = await fetch(base + "api/analyze-link", {
        method: "POST", headers: { ...H, "Content-Type": "application/json" }, body: JSON.stringify({ url }),
      });
      return (await json(res)).job_id;
    } catch (e) {
      throw e instanceof TypeError ? networkError() : e;
    }
  }

  /** Polls until the job finishes. onUpdate(stage, progress 0..1). Resolves with the result object. */
  async function waitForJob(jobId, onUpdate) {
    for (;;) {
      let job;
      try { job = await json(await fetch(base + "api/jobs/" + jobId, { headers: H })); }
      catch (e) { throw e instanceof TypeError ? networkError() : e; }
      onUpdate && onUpdate(job.stage, job.progress);
      if (job.status === "done") return job.result;
      if (job.status === "error") throw new Error(job.error || "Analysis failed");
      await new Promise((r) => setTimeout(r, 1200));
    }
  }

  async function sendFeedback(jobId, rating, correctedMood, note) {
    const res = await fetch(base + "api/feedback/" + jobId, {
      method: "POST", headers: { ...H, "Content-Type": "application/json" },
      body: JSON.stringify({ rating, corrected_mood: correctedMood || null, note: note || null }),
    });
    return json(res);
  }

  return { base, uploadFile, analyzeLink, waitForJob, sendFeedback };
})();
