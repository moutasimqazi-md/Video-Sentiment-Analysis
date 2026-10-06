/* Minimal streaming ZIP reader for big exports: reads the central directory, then slices out and inflates ONLY the
   entries you ask for (stored or deflate; ZIP64 supported). Nothing is uploaded — everything happens in the browser. */
window.NL = window.NL || {};

NL.zip = (() => {
  const u16 = (d, o) => d[o] | (d[o + 1] << 8);
  const u32 = (d, o) => (d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24)) >>> 0;
  const u64 = (d, o) => u32(d, o) + u32(d, o + 4) * 4294967296;
  const bytes = async (file, a, b) => new Uint8Array(await file.slice(a, b).arrayBuffer());
  const utf8 = new TextDecoder("utf-8");

  async function open(file) {
    const size = file.size;
    if (size < 22) throw new Error("That file is too small to be a ZIP archive.");
    const tailLen = Math.min(size, 65535 + 22 + 20);
    const tail = await bytes(file, size - tailLen, size);
    let eocd = -1;
    for (let i = tail.length - 22; i >= 0; i--) {
      if (tail[i] === 0x50 && tail[i + 1] === 0x4b && tail[i + 2] === 5 && tail[i + 3] === 6) { eocd = i; break; }
    }
    if (eocd < 0) throw new Error("This doesn't look like a ZIP file (or it's incomplete).");

    let total = u16(tail, eocd + 10), cdSize = u32(tail, eocd + 12), cdOff = u32(tail, eocd + 16);
    if (total === 0xffff || cdSize === 0xffffffff || cdOff === 0xffffffff) {           // ZIP64
      const loc = eocd - 20;
      if (loc < 0 || u32(tail, loc) !== 0x07064b50) throw new Error("Unsupported ZIP layout.");
      const z64 = u64(tail, loc + 8);
      const z = await bytes(file, z64, z64 + 56);
      if (u32(z, 0) !== 0x06064b50) throw new Error("Unsupported ZIP64 layout.");
      total = u64(z, 32); cdSize = u64(z, 40); cdOff = u64(z, 48);
    }

    const cd = await bytes(file, cdOff, cdOff + cdSize);
    const entries = [];
    let p = 0;
    while (p + 46 <= cd.length && u32(cd, p) === 0x02014b50) {
      const method = u16(cd, p + 10);
      let csize = u32(cd, p + 20), usize = u32(cd, p + 24);
      const nl = u16(cd, p + 28), el = u16(cd, p + 30), cl = u16(cd, p + 32);
      let off = u32(cd, p + 42);
      const name = utf8.decode(cd.subarray(p + 46, p + 46 + nl));
      let q = p + 46 + nl;
      const end = q + el;
      while (q + 4 <= end) {                                                        // ZIP64 extra field
        const id = u16(cd, q), sz = u16(cd, q + 2);
        if (id === 1) {
          let r = q + 4;
          if (usize === 0xffffffff) { usize = u64(cd, r); r += 8; }
          if (csize === 0xffffffff) { csize = u64(cd, r); r += 8; }
          if (off === 0xffffffff) { off = u64(cd, r); r += 8; }
        }
        q += 4 + sz;
      }
      entries.push({ name, method, csize, usize, off, dir: name.endsWith("/") });
      p += 46 + nl + el + cl;
    }

    /** Text content of one entry (UTF-8). maxBytes guards against absurd entries. */
    async function text(e, maxBytes = 400 * 1024 * 1024) {
      if (e.usize > maxBytes) throw new Error(`${e.name} is too large to read in the browser.`);
      const h = await bytes(file, e.off, e.off + 30);
      if (u32(h, 0) !== 0x04034b50) throw new Error("Corrupt ZIP entry.");
      const start = e.off + 30 + u16(h, 26) + u16(h, 28);
      const blob = file.slice(start, start + e.csize);
      if (e.method === 0) return utf8.decode(new Uint8Array(await blob.arrayBuffer()));
      if (e.method !== 8) throw new Error("Unsupported compression in ZIP.");
      if (typeof DecompressionStream === "undefined") throw new Error("This browser is too old to unzip files. Please use a current Chrome, Edge, Firefox or Safari.");
      const stream = blob.stream().pipeThrough(new DecompressionStream("deflate-raw"));
      return utf8.decode(new Uint8Array(await new Response(stream).arrayBuffer()));
    }
    return { entries, text };
  }

  return { open };
})();
