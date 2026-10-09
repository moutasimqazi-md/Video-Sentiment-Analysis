/* The private browser, shown inside the page. Frames arrive over a WebSocket and are drawn on a canvas; clicks, scrolling and typing
   go back the same way. Nothing opens on the computer running NeuroLens. */
window.NL = window.NL || {};

NL.browserView = (() => {
  const VIEW_W = 440, VIEW_H = 780; // the remote page's logical size (must match backend/neurolens/live.py)
  const $ = (id) => document.getElementById(id);
  const SPECIAL = new Set(["Backspace", "Enter", "Tab", "Escape", "Delete", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown"]);
  let ws = null, closing = false, attempts = 0, handlers = {}, pid = null, lastMove = 0, drag = null;

  const canvas = () => $("rbCanvas");
  function wsUrl(token) {
    const u = new URL(`${NL.api.base}api/sessions/${pid}/view?t=${encodeURIComponent(token)}`, location.href);
    u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
    return u.href;
  }
  const send = (m) => { if (ws && ws.readyState === 1) ws.send(JSON.stringify(m)); };
  const pos = (e) => {
    const r = canvas().getBoundingClientRect();
    return { x: Math.max(0, Math.min(VIEW_W, ((e.clientX - r.left) * VIEW_W) / r.width)), y: Math.max(0, Math.min(VIEW_H, ((e.clientY - r.top) * VIEW_H) / r.height)) };
  };
  const focusKeys = () => $("rbKeys").focus({ preventScroll: true });

  async function draw(blob) {
    try {
      const bmp = await createImageBitmap(blob);
      const c = canvas();
      if (c.width !== bmp.width || c.height !== bmp.height) { c.width = bmp.width; c.height = bmp.height; }
      c.getContext("2d").drawImage(bmp, 0, 0);
      bmp.close && bmp.close();
      $("rbOverlay").hidden = true;
    } catch (e) { /* skip a bad frame */ }
  }

  async function connect() {
    let token;
    try { token = (await NL.owner.call("POST", `api/sessions/${pid}/view-token`)).token; }
    catch (e) { return handlers.onState && handlers.onState({ state: "error", error: e.message }); }
    ws = new WebSocket(wsUrl(token));
    ws.binaryType = "blob";
    ws.onopen = () => { attempts = 0; };
    ws.onmessage = (ev) => {
      if (typeof ev.data !== "string") return draw(ev.data);
      const m = JSON.parse(ev.data);
      if (m.type === "url") { $("rbHost").textContent = m.host || "instagram.com"; handlers.onHost && handlers.onHost(m.host); }
      if (m.type === "hint" && $("rbHint")) { $("rbHint").textContent = m.text || ""; $("rbHint").hidden = !m.text; }
      if (m.type === "state") {
        const o = $("rbOverlayText");
        if (m.state === "finishing") { $("rbOverlay").hidden = false; o.textContent = "Signed in. Saving your session…"; }
        if (m.state === "starting") { $("rbOverlay").hidden = false; o.textContent = "Starting the private browser…"; }
        handlers.onState && handlers.onState(m);
        if (["connected", "closed", "error"].includes(m.state)) { closing = true; }
      }
    };
    ws.onclose = () => {
      if (closing) return;
      // dropped mid-sign-in: try again with a fresh single-use key
      if (++attempts <= 3) { $("rbOverlay").hidden = false; $("rbOverlayText").textContent = "Reconnecting…"; setTimeout(connect, 1200); }
      else handlers.onState && handlers.onState({ state: "error", error: "The connection to the private browser was lost." });
    };
  }

  /* ---- input ---- */
  function wire() {
    const c = canvas(), keys = $("rbKeys");
    if (c.dataset.wired) return;
    c.dataset.wired = "1";
    c.addEventListener("contextmenu", (e) => e.preventDefault());
    c.addEventListener("pointerdown", (e) => {
      e.preventDefault(); focusKeys();
      c.setPointerCapture(e.pointerId);
      const p = pos(e);
      drag = { id: e.pointerId, touch: e.pointerType === "touch", x0: e.clientX, y0: e.clientY, lx: e.clientX, ly: e.clientY, moved: false, p };
      if (!drag.touch) send({ t: "mouse", type: "down", ...p, button: e.button === 2 ? "right" : "left", clicks: e.detail || 1 });
    });
    c.addEventListener("pointermove", (e) => {
      const now = performance.now();
      if (drag && drag.touch) {  // dragging a finger scrolls the page, like on a phone
        const dy = drag.ly - e.clientY, dx = drag.lx - e.clientX;
        if (Math.abs(e.clientY - drag.y0) + Math.abs(e.clientX - drag.x0) > 8) drag.moved = true;
        if (drag.moved) { send({ t: "mouse", type: "wheel", ...pos(e), dx, dy: dy * (VIEW_H / c.getBoundingClientRect().height) }); }
        drag.lx = e.clientX; drag.ly = e.clientY; return;
      }
      if (now - lastMove < 40) return;
      lastMove = now;
      send({ t: "mouse", type: "move", ...pos(e) });
    });
    c.addEventListener("pointerup", (e) => {
      const p = pos(e);
      if (drag && drag.touch) {
        if (!drag.moved) { send({ t: "mouse", type: "down", ...drag.p, button: "left", clicks: 1 }); send({ t: "mouse", type: "up", ...drag.p, button: "left", clicks: 1 }); }
      } else send({ t: "mouse", type: "up", ...p, button: e.button === 2 ? "right" : "left", clicks: e.detail || 1 });
      drag = null;
    });
    c.addEventListener("wheel", (e) => { e.preventDefault(); send({ t: "mouse", type: "wheel", ...pos(e), dx: e.deltaX, dy: e.deltaY }); }, { passive: false });
    c.addEventListener("focus", focusKeys);
    keys.addEventListener("keydown", (e) => {
      if (SPECIAL.has(e.key) && !e.ctrlKey && !e.metaKey) { e.preventDefault(); send({ t: "key", key: e.key }); }
    });
    keys.addEventListener("input", () => {
      const text = keys.value.replace(/\r?\n/g, "");
      keys.value = "";
      if (text) send({ t: "text", text });
    });
  }

  /** Show the viewer for a profile; resolves once the socket is requested. handlers: onState({state,error}), onHost(host) */
  function open(profileId, h) {
    pid = profileId; handlers = h || {}; closing = false; attempts = 0;
    $("rbOverlay").hidden = false; $("rbOverlayText").textContent = "Starting the private browser…";
    $("rbHost").textContent = "instagram.com";
    wire();
    return connect();
  }
  function close() { closing = true; if (ws) { try { ws.close(); } catch (e) { /* already closed */ } } ws = null; drag = null; }

  return { open, close, focus: focusKeys };
})();
