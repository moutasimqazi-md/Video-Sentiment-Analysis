/* Inline SVG icon set (24px grid, 1.8 stroke). Usage: <i data-icon="upload"></i>  or  NL.icon("upload", 20) */
window.NL = window.NL || {};

NL.ICONS = {
  upload: '<path d="M12 16V4m0 0L7 9m5-5 5 5M4 16v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/>',
  link: '<path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1M14 10a4 4 0 0 0-5.7 0l-3 3A4 4 0 0 0 11 18.7l1-1"/>',
  brain: '<path d="M9 4a3 3 0 0 0-3 3 3 3 0 0 0-2 2.8A3 3 0 0 0 5 14a3 3 0 0 0 4 3.5V4Zm6 0a3 3 0 0 1 3 3 3 3 0 0 1 2 2.8 3 3 0 0 1-1 4.2 3 3 0 0 1-4 3.5V4Z"/>',
  chart: '<path d="M4 20V10m6 10V4m6 16v-7m4 7H2"/>',
  trend: '<path d="m3 17 6-6 4 4 8-8m0 0h-5m5 0v5"/>',
  shield: '<path d="M12 3 5 6v5c0 4.5 3 8 7 10 4-2 7-5.500 7-10V6l-7-3Z"/><path d="m9 12 2 2 4-4"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.500 20a6.500 6.500 0 0 1 13 0M16 4.500a3.500 3.500 0 0 1 0 7M18 14.500a6.500 6.500 0 0 1 3.500 5.500"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  file: '<path d="M14 3H7a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8l-5-5Z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  check: '<path d="m5 12.500 4.500 4.500L19 7.500"/>',
  alert: '<path d="M12 3 2 20h20L12 3Z"/><path d="M12 10v4m0 3h.01"/>',
  heart: '<path d="M12 20s-8-4.800-8-11a4.500 4.500 0 0 1 8-2.800A4.500 4.500 0 0 1 20 9c0 6.200-8 11-8 11Z"/>',
  play: '<path d="M7 4.500v15L19 12 7 4.500Z"/>',
  sparkle: '<path d="M12 3v4m0 10v4M3 12h4m10 0h4M6 6l2.500 2.500M15.500 15.500 18 18M18 6l-2.500 2.500M8.500 15.500 6 18"/>',
  bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7l1-8Z"/>',
  music: '<path d="M9 18V6l11-2v12"/><circle cx="6.500" cy="18" r="2.500"/><circle cx="17.500" cy="16" r="2.500"/>',
  palette: '<path d="M12 3a9 9 0 1 0 0 18c1.500 0 2-1 1.500-2-.600-1.200.200-2.500 1.700-2.500H18a3 3 0 0 0 3-3C21 7 17 3 12 3Z"/><circle cx="7.500" cy="11" r="1"/><circle cx="10" cy="7" r="1"/><circle cx="15" cy="7" r="1"/>',
  target: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1"/>',
  lock: '<rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
  eye: '<path d="M2 12s3.500-7 10-7 10 7 10 7-3.500 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  download: '<path d="M12 4v12m0 0 5-5m-5 5-5-5M4 20h16"/>',
  copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
  trash: '<path d="M4 7h16M10 11v6m4-6v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.900 4.900l1.400 1.400m11.400 11.400 1.400 1.400M2 12h2m16 0h2M4.900 19.100l1.400-1.400M17.700 6.300l1.400-1.400"/>',
  moon: '<path d="M20 14.500A8 8 0 0 1 9.500 4 8 8 0 1 0 20 14.500Z"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  close: '<path d="m6 6 12 12M18 6 6 18"/>',
  back: '<path d="M19 12H5m0 0 6-6m-6 6 6 6"/>',
  external: '<path d="M14 4h6v6m0-6-9 9M18 14v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4"/>',
  arrow: '<path d="M5 12h14m0 0-6-6m6 6-6 6"/>',
  film: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M7 4v16M17 4v16M3 9h4m10 0h4M3 15h4m10 0h4"/>',
  history: '<path d="M3 12a9 9 0 1 0 3-6.700L3 8m0-4v4h4"/><path d="M12 7v5l3 2"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0m-7 7v3"/>',
  bell: '<path d="M6 16V11a6 6 0 0 1 12 0v5l2 2H4l2-2Zm4 4a2 2 0 0 0 4 0"/>',
  star: '<path d="m12 3 2.700 5.600 6.100.9-4.400 4.300 1 6.100L12 17l-5.400 2.900 1-6.100L3.200 9.500l6.100-.9L12 3Z"/>',
  gauge: '<path d="M4 17a8 8 0 1 1 16 0"/><path d="m12 17 4-5"/>',
  thumbup: '<path d="M7 11v9H4v-9h3Zm0 0 4-8a2 2 0 0 1 2 2v4h6a2 2 0 0 1 2 2.300l-1.200 6A2 2 0 0 1 17.800 20H7"/>',
  thumbdown: '<path d="M7 13V4H4v9h3Zm0 0 4 8a2 2 0 0 0 2-2v-4h6a2 2 0 0 0 2-2.300l-1.200-6A2 2 0 0 0 17.800 4H7"/>',
  print: '<path d="M7 9V3h10v6M7 17H5a2 2 0 0 1-2-2v-4a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v4a2 2 0 0 1-2 2h-2"/><rect x="7" y="14" width="10" height="7"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.400 15a1.700 1.700 0 0 0 .3 1.800l.1.1a2 2 0 1 1-2.800 2.800l-.1-.1a1.700 1.700 0 0 0-1.800-.3 1.700 1.700 0 0 0-1 1.500V21a2 2 0 1 1-4 0v-.1a1.700 1.700 0 0 0-1.100-1.500 1.700 1.700 0 0 0-1.800.3l-.1.1a2 2 0 1 1-2.800-2.800l.1-.1a1.700 1.700 0 0 0 .3-1.800 1.700 1.700 0 0 0-1.500-1H3a2 2 0 1 1 0-4h.1a1.700 1.700 0 0 0 1.500-1.100 1.700 1.700 0 0 0-.3-1.800l-.1-.1a2 2 0 1 1 2.800-2.800l.1.1a1.700 1.700 0 0 0 1.800.3h.1a1.700 1.700 0 0 0 1-1.500V3a2 2 0 1 1 4 0v.1a1.700 1.700 0 0 0 1 1.500 1.700 1.700 0 0 0 1.800-.3l.1-.1a2 2 0 1 1 2.800 2.800l-.1.1a1.700 1.700 0 0 0-.3 1.800v.1a1.700 1.700 0 0 0 1.500 1H21a2 2 0 1 1 0 4h-.1a1.700 1.700 0 0 0-1.500 1Z"/>',
  instagram: '<rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.200" cy="6.800" r=".8" fill="currentColor"/>',
};

NL.icon = (name, size = 20, cls = "", style = "") =>
  `<svg class="ico-svg ${cls}" ${style ? `style="${style}"` : ""} width="${size}" height="${size}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${NL.ICONS[name] || ""}</svg>`;

/** Replace every <i data-icon="name" data-size="20"> inside `root` with its SVG. Safe to call repeatedly. */
NL.hydrateIcons = (root = document) => {
  root.querySelectorAll("i[data-icon]").forEach((el) => {
    el.outerHTML = NL.icon(el.dataset.icon, Number(el.dataset.size) || 20, el.className, el.getAttribute("style") || "");
  });
};
