/* engine.js — the WxDash dashboard, client side.
 *
 * Renders the site 09_build_dashboard.R assembles: the question and map data
 * 09_statistics.R computed, plus a config.json of presentation content. Nothing
 * here computes a statistic — every percentage, CI, rank, percentile and
 * median was precomputed upstream, so this file only ever picks a slice and
 * draws it. That is what lets the site run with no server.
 *
 * Components (registered on the `components` object): explore (the survey
 * question explorer), wx_map_explorer, wx_landing, wx_quiz, static_page.
 * Each receives (pageConfig, container) and renders itself from the files it
 * references.
 */

"use strict";

window.WX_ENGINE_LOADED = true; // watchdog diagnostics: proves this file executed

const BUNDLE = (() => {
  // A page served from a subdirectory sets window.WX_BUNDLE (e.g. "../../")
  // so fetches resolve to the bundle root; ?bundle= does the same.
  const p = window.WX_BUNDLE ||
    new URLSearchParams(location.search).get("bundle") || "./";
  return p.endsWith("/") ? p : p + "/";
})();

let CONFIG = null;
const jsonCache = new Map();

async function fetchJSON(rel) {
  if (jsonCache.has(rel)) return jsonCache.get(rel);
  // Build stamp (set by the bundle's index.html) busts long-lived host
  // caches on every deploy.
  const bust = window.WX_BUILD
    ? (rel.includes("?") ? "&" : "?") + "v=" + window.WX_BUILD : "";
  const res = await fetch(BUNDLE + rel + bust);
  if (!res.ok) throw new Error(`Failed to load ${rel}: ${res.status}`);
  const data = await res.json();
  jsonCache.set(rel, data);
  return data;
}

/* ---------------------------------------------------------------- utils -- */

const esc = (s) => String(s ?? "")
  .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") node.className = v;
    else if (k === "html") node.innerHTML = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children) {
    if (c == null) continue;
    node.append(c instanceof Node ? c : document.createTextNode(c));
  }
  return node;
}

// Display token for missing groups/categories — mirrors R's rendering of NA.
const naLabel = (v) => (v == null ? "NA" : v);

/* Flagging ------------------------------------------------------------------
 * A triage tool, not a reader feature: ?flag=1 puts a flag beside the question
 * heading and a panel at the foot of the explorer. What it collects is the
 * input to hidden_questions.csv, which the build reads to drop a question, so
 * the judgement is made where the problem is visible rather than against a
 * list of variable names.
 *
 * Kept in localStorage because the site is plain files on a host with nothing
 * to POST to. That makes the list per-browser and per-origin: flags made
 * against a local preview do not follow you to the deployed site, so export
 * before switching. Every access is guarded — a browser set to block site data
 * throws on the accessor itself rather than returning empty. */
const FLAGS_KEY = "wxdash-flags";
const flaggingOn = () => new URLSearchParams(location.search).get("flag") === "1";

function readFlags() {
  try {
    return JSON.parse(localStorage.getItem(FLAGS_KEY) || "{}");
  } catch { return {}; }
}

function writeFlags(f) {
  try { localStorage.setItem(FLAGS_KEY, JSON.stringify(f)); } catch { /* no store */ }
}

// Same columns the build reads, so an export can be dropped straight in;
// every row is `hide`, and a different disposition or a note is set in the
// file itself.
function flagsToCSV(flags) {
  const q = (v) => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`;
  const rows = Object.entries(flags).map(([id, f]) =>
    [id, f.disposition || "hide", f.note || "", f.question || ""].map(q).join(","));
  return ["id,disposition,note,question", ...rows].join("\n") + "\n";
}

/* Saved questions ------------------------------------------------------------
 * A reader's own list, for keeping track of questions while browsing: "Save"
 * beside the question heading, and a panel at the foot of the explorer that
 * appears once something is saved. Kept apart from the flags above, so saving
 * a question to read later never feeds the hide list. In localStorage for
 * the same reason the flags are, which makes it per-browser; the panel says
 * so, and the download is how a list is kept. Guarded the same way. */
const SAVED_KEY = "wxdash-saved";

function readSaved() {
  try {
    const list = JSON.parse(localStorage.getItem(SAVED_KEY) || "[]");
    return Array.isArray(list) ? list : [];
  } catch { return []; }
}

function writeSaved(list) {
  try { localStorage.setItem(SAVED_KEY, JSON.stringify(list)); } catch { /* no store */ }
}

// What a reader needs to find each question again in the released data.
function savedToCSV(list) {
  const q = (v) => `"${String(v == null ? "" : v).replace(/"/g, '""')}"`;
  const rows = list.map(x =>
    [x.survey, x.years, x.question, x.variable].map(q).join(","));
  return ["survey,years,question,variable", ...rows].join("\n") + "\n";
}

/* A split-sample question nests its splits and summaries one level deeper,
 * under the version the respondent read; every other question does not.
 * `arms` being present is the signal, and this is the one place that knows it,
 * so a component that charts a question need not care which shape it got.
 * There is no pooled option: pooling the versions would average across the
 * difference the experiment was testing. */
function questionSlice(v, armId) {
  const arms = Array.isArray(v.arms) ? v.arms : [];
  if (arms.length === 0) {
    return { armed: false, armKey: null,
             splits: v.splits || {}, summaries: v.summaries || {} };
  }
  const armKey = arms.some(a => a.id === armId) ? armId : arms[0].id;
  return { armed: true, armKey,
           splits: (v.splits || {})[armKey] || {},
           summaries: (v.summaries || {})[armKey] || {} };
}

// Optional deep-link: ?grouping=Gender preselects the demographic grouping.
const urlGrouping = () => {
  const g = new URLSearchParams(location.search).get("grouping");
  return g && CONFIG.groupings.some(x => x.id === g) ? g : null;
};

// "Snow\nIce" → ["Snow", "Ice"] for multi-line Chart.js tick labels.
const tickLines = (label) => String(label).split("\n");

/* ---- viridis (matches ggplot2 scale_fill_viridis discrete sampling) ------ */
// 32 anchor stops of the viridis colormap; discrete palette of n colors =
// n evenly spaced samples over [0,1] with linear interpolation, like
// viridisLite::viridis(n).
const VIRIDIS_STOPS = [
  [68,1,84],[71,13,96],[72,24,106],[72,35,116],[71,45,123],[69,55,129],
  [66,64,134],[62,73,137],[58,82,139],[54,90,140],[50,98,142],[47,106,142],
  [43,113,142],[40,121,142],[37,128,142],[34,136,142],[31,143,141],[29,151,140],
  [27,158,138],[27,166,135],[30,173,131],[37,180,126],[47,187,119],[61,194,111],
  [77,200,101],[95,206,90],[114,212,77],[135,217,63],[157,221,48],[180,224,33],
  [203,226,25],[253,231,37]
];
function viridis(n) {
  if (n === 1) return ["rgb(68,1,84)"];
  const out = [];
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1) * (VIRIDIS_STOPS.length - 1);
    const lo = Math.floor(t), hi = Math.min(lo + 1, VIRIDIS_STOPS.length - 1);
    const f = t - lo;
    const c = [0, 1, 2].map(k => Math.round(VIRIDIS_STOPS[lo][k] * (1 - f) + VIRIDIS_STOPS[hi][k] * f));
    out.push(`rgb(${c[0]},${c[1]},${c[2]})`);
  }
  return out;
}

// cividis (viridisLite option "cividis").
const CIVIDIS_STOPS = [
  [0,32,76],[0,36,86],[0,40,97],[0,44,108],[0,48,115],[9,53,116],[26,57,117],
  [37,62,117],[46,66,117],[54,71,118],[61,75,118],[68,80,119],[74,84,120],
  [80,89,121],[86,93,122],[92,98,123],[97,102,125],[103,107,126],[108,112,128],
  [113,116,129],[119,121,131],[124,126,133],[129,130,135],[135,135,136],
  [140,140,137],[146,144,137],[152,149,136],[158,154,135],[164,159,134],
  [171,164,132],[177,169,130],[184,174,127],[191,179,124],[198,184,120],
  [205,190,116],[212,195,111],[220,200,105],[227,206,98],[235,211,90],
  [243,217,80],[252,222,68],[255,230,66]
];

// ColorBrewer Greys — greyscale theme's map ramp (see dataStops).
const GREYS_STOPS = [
  [247,247,247],[217,217,217],[189,189,189],[150,150,150],
  [115,115,115],[82,82,82],[37,37,37]
];

// In the greyscale accessibility theme the maps repaint in greys, so one
// theme switch covers them; every other theme keeps the chosen color scheme.
// Charts are untouched: this applies to choropleth ramps only.
function dataStops(stops) {
  return document.documentElement.dataset.theme === "greyscale" ? GREYS_STOPS : stops;
}

// Continuous colour ramp over stop array; t clamped to [0,1]. Used by the
// choropleth components (clamping is a deliberate deviation from R
// colorNumeric, which paints out-of-domain values grey).
function rampColor(stops, t) {
  t = Math.max(0, Math.min(1, t));
  const x = t * (stops.length - 1);
  const lo = Math.floor(x), hi = Math.min(lo + 1, stops.length - 1), f = x - lo;
  const c = [0, 1, 2].map(k => Math.round(stops[lo][k] * (1 - f) + stops[hi][k] * f));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

/* ---- user-facing data-color schemes -------------------------------------
 * The two explore pages open in blue and offer viridis and print-safe grey
 * as viewer choices. Blue is the default without being first in the menu,
 * which is why the default lives here rather than in the scheme list order.
 * The greyscale accessibility theme still overrides map ramps via
 * dataStops(). */
const BLUES_STOPS = [
  [239,243,255],[198,219,239],[158,202,225],[107,174,214],
  [66,146,198],[33,113,181],[8,69,148]
];
const COLOR_SCHEMES = [
  { id: "viridis", label: "Viridis (multiple hues)", stops: VIRIDIS_STOPS },
  { id: "blue", label: "Blue (one hue)", stops: BLUES_STOPS },
  { id: "grey", label: "Grey (print safe)", stops: GREYS_STOPS }
];
const DEFAULT_SCHEME = "blue";
const urlScheme = () => {
  const s = getParam("scheme");
  return COLOR_SCHEMES.some(x => x.id === s) ? s : DEFAULT_SCHEME;
};
const schemeStops = (id) =>
  (COLOR_SCHEMES.find(x => x.id === id)
   || COLOR_SCHEMES.find(x => x.id === DEFAULT_SCHEME)).stops;
// Discrete series colors. Viridis keeps its ggplot sampling; the sequential
// ramps sample dark→light so a single series is always the dark end.
function schemeSeriesColors(id, n) {
  if (id === "viridis") return viridis(n);
  const stops = schemeStops(id);
  const out = [];
  for (let i = 0; i < n; i++) out.push(rampColor(stops, n === 1 ? 1 : 1 - (i / (n - 1)) * 0.8));
  return out;
}
function schemeSelect(current, onChange) {
  const wrap = el("div");
  wrap.append(el("label", { class: "field-label", for: "scheme-sel" }, "Change color scheme"));
  const sel = el("select", { class: "grouping", id: "scheme-sel", onchange: () => onChange(sel.value) });
  for (const sc of COLOR_SCHEMES) sel.append(el("option", { value: sc.id }, sc.label));
  sel.value = current;
  wrap.append(sel);
  return wrap;
}

/* ---- PDF export (jsPDF vendored with the site) -------------------------- */
// Crop the flat backdrop off a snapshot, so what lands in a document is the
// map rather than the map plus the empty frame around it. The frame is a
// fixed-size container the CONUS floats in; left in, it shrinks the plot and
// leaves a legend anchored to the image sitting well left of the coastline.
function trimCanvas(src, bg) {
  const W = src.width, H = src.height;
  const data = src.getContext("2d").getImageData(0, 0, W, H).data;
  const rgb = (String(bg).match(/\d+(\.\d+)?/g) || [255, 255, 255])
    .slice(0, 3).map(Number);
  const tol = 10;
  let x0 = W, y0 = H, x1 = -1, y1 = -1;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      if (data[i + 3] < 8) continue;
      if (Math.abs(data[i] - rgb[0]) <= tol &&
          Math.abs(data[i + 1] - rgb[1]) <= tol &&
          Math.abs(data[i + 2] - rgb[2]) <= tol) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) return src;                       // nothing drawn — leave it be
  const pad = 8;
  x0 = Math.max(0, x0 - pad); y0 = Math.max(0, y0 - pad);
  x1 = Math.min(W - 1, x1 + pad); y1 = Math.min(H - 1, y1 + pad);
  const out = document.createElement("canvas");
  out.width = x1 - x0 + 1; out.height = y1 - y0 + 1;
  const ctx = out.getContext("2d");
  ctx.fillStyle = bg;
  ctx.fillRect(0, 0, out.width, out.height);
  ctx.drawImage(src, x0, y0, out.width, out.height, 0, 0, out.width, out.height);
  return out;
}

/* A figure to take away - a chart or a map - drawn once for both downloads,
 * so the PNG and the PDF are the same picture in two formats, and drawn the
 * same way on every page. A fixed 1200px layout at four times the pixel
 * density, 4800px across, holds up full-width on a slide. Above the figure:
 * a small label, an optional stem, the title. Below it: the page's own
 * caption lines and a source line, so it still says what it shows once it
 * has left the page. On the page's own background, so a dark theme exports
 * legibly.
 *
 * `body` is { height, draw(ctx, x, y, width) }, drawn into a context already
 * scaled to the figure's density. */
const FIGURE = { S: 4, W: 1200, pad: 48 };
// Every download names its source in the same first sentence; each page adds
// one sentence on method.
const FIGURE_SOURCE = "Source: Extreme Weather and Society Survey, University " +
  "of Oklahoma Institute for Public Policy Research and Analysis.";
function figureImage({ label, stem, title, body, lines = [], source }) {
  const { S, W, pad } = FIGURE, inner = W - pad * 2;
  const css = getComputedStyle(document.body);
  const tok = (n, d) => css.getPropertyValue(n).trim() || d;
  const bg = tok("--panel", "#ffffff"), ink = tok("--text", "#1f1d2b");
  const muted = tok("--text-muted", "#5f5a73"), accent = tok("--accent", "#443a83");
  const family = css.fontFamily, mono = tok("--mono", "monospace");

  const measure = document.createElement("canvas").getContext("2d");
  const wrapText = (text, font) => {
    measure.font = font;
    const words = String(text || "").split(/\s+/).filter(Boolean);
    const out = []; let line = "";
    for (const w of words) {
      const t = line ? line + " " + w : w;
      if (line && measure.measureText(t).width > inner) { out.push(line); line = w; }
      else line = t;
    }
    if (line) out.push(line);
    return out;
  };
  const block = (text, size, weight, color, lead, gap, face = family) => {
    if (!text) return null;
    const font = `${weight} ${size}px ${face}`;
    return { lines: wrapText(text, font), font, color, lead, gap };
  };
  const head = [
    block(label && String(label).toUpperCase(), 13, 600, accent, 18, 12, mono),
    block(stem, 17, 400, muted, 25, 8),
    block(title, 30, 700, ink, 38, 22)
  ].filter(Boolean);
  const foot = [
    ...lines.map((l, i) => block(l.text, 15, l.strong ? 600 : 400,
      l.strong ? ink : muted, 22, i === lines.length - 1 ? 6 : 4)),
    block(source, 13, 400, muted, 19, 0)
  ].filter(Boolean);
  const heightOf = (bs) => bs.reduce((t, b) => t + b.lines.length * b.lead + b.gap, 0);
  const H = pad + heightOf(head) + body.height + 22 + heightOf(foot) + pad;

  const out = document.createElement("canvas");
  out.width = W * S; out.height = Math.ceil(H * S);
  const ctx = out.getContext("2d");
  ctx.scale(S, S);
  ctx.fillStyle = bg; ctx.fillRect(0, 0, W, H);
  ctx.textBaseline = "alphabetic";
  let y = pad;
  const paint = (bs) => {
    for (const b of bs) {
      ctx.font = b.font; ctx.fillStyle = b.color;
      for (const ln of b.lines) { y += b.lead; ctx.fillText(ln, pad, y - b.lead * 0.25); }
      y += b.gap;
    }
  };
  paint(head);
  ctx.save(); body.draw(ctx, pad, y, inner, { ink, muted, accent, family, mono }); ctx.restore();
  y += body.height + 22;
  paint(foot);
  return { canvas: out, width: W, height: H };
}

// Saves a figure as a PNG, or as a PDF page 11 inches wide cut to the
// figure's height so nothing is letterboxed or cropped.
function saveFigure(img, name, kind) {
  if (!img) return;
  if (kind === "pdf") {
    if (!window.jspdf) { alert("The PDF library did not load - try reloading the page."); return; }
    const w = 792, h = w * img.height / img.width;
    const doc = new window.jspdf.jsPDF({
      orientation: w > h ? "l" : "p", unit: "pt", format: [w, h] });
    doc.addImage(img.canvas, "PNG", 0, 0, w, h, undefined, "FAST");
    doc.save(name);
    return;
  }
  img.canvas.toBlob((blob) => {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const a = el("a", { href: url, download: name });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }, "image/png");
}

/* A Leaflet map redrawn as vectors at the figure's density. Leaflet paints
 * its canvas at screen resolution, which pixelates on a slide, so the paths
 * are drawn again from the positions and styles Leaflet has already worked
 * out: the same frame, colors, borders and outline as on screen, sharp at
 * any size. Layers go in the order they were added, which is the order
 * Leaflet stacks them. */
function vectorMap(lmap, S, bg) {
  const size = lmap.getSize();
  const cv = document.createElement("canvas");
  cv.width = Math.round(size.x * S); cv.height = Math.round(size.y * S);
  const ctx = cv.getContext("2d");
  ctx.fillStyle = bg; ctx.fillRect(0, 0, cv.width, cv.height);
  ctx.scale(S, S);
  ctx.lineJoin = "round";
  const layers = [];
  lmap.eachLayer(l => { if (l instanceof L.Polyline) layers.push(l); });
  layers.sort((a, b) => L.stamp(a) - L.stamp(b));
  for (const l of layers) {
    const o = l.options, isPoly = l instanceof L.Polygon;
    ctx.beginPath();
    const walk = (a) => {
      if (!a.length) return;
      if (a[0].lat !== undefined) {
        a.forEach((p, i) => {
          const q = lmap.latLngToContainerPoint(p);
          if (i) ctx.lineTo(q.x, q.y); else ctx.moveTo(q.x, q.y);
        });
        if (isPoly) ctx.closePath();
      } else a.forEach(walk);
    };
    walk(l.getLatLngs());
    if (isPoly && o.fill !== false) {
      ctx.globalAlpha = o.fillOpacity == null ? 0.2 : o.fillOpacity;
      ctx.fillStyle = o.fillColor || o.color;
      ctx.fill("evenodd");
    }
    if (o.stroke !== false && o.weight > 0) {
      ctx.globalAlpha = o.opacity == null ? 1 : o.opacity;
      ctx.strokeStyle = o.color; ctx.lineWidth = o.weight;
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
  return trimCanvas(cv, bg);
}

function pdfButton(label, onClick) {
  return el("button", { class: "wx-pdf-btn", onclick: onClick }, label);
}

// Charts owned by the current page (a page can hold several); destroyed on
// navigation alongside activeChart, the one renderGroupedBar keeps.
let pageCharts = [];
function trackChart(c) { pageCharts.push(c); return c; }

// Error bars for Chart.js (CIs) — reads dataset.errorLow / dataset.errorHigh
// arrays parallel to data. Draws along the value axis with a cap at each end:
// vertical normally, horizontal when the chart uses indexAxis "y" (flipped
// bars), where the caps come out as short vertical ticks.
const ErrorBarsPlugin = {
  id: "wxErrorBars",
  afterDatasetsDraw(chart) {
    const { ctx } = chart;
    const flipped = chart.options.indexAxis === "y";
    chart.data.datasets.forEach((ds, di) => {
      if (!ds.errorLow) return;
      const meta = chart.getDatasetMeta(di);
      if (meta.hidden) return;
      ctx.save();
      ctx.strokeStyle = ds.borderColor || "#000";
      ctx.lineWidth = 2;
      meta.data.forEach((pt, i) => {
        const lo = ds.errorLow[i], hi = ds.errorHigh[i];
        if (lo == null || hi == null) return;
        const scale = flipped ? chart.scales.x : chart.scales.y;
        const p1 = scale.getPixelForValue(lo);
        const p2 = scale.getPixelForValue(hi);
        // Capped at both ends, across the bar rather than along it: on the
        // horizontal explorer bars a bare line reads as part of the bar, and
        // the caps are what make the interval's ends findable. Sized off the
        // bar so they stay proportional as the canvas grows with the group
        // count, and clamped so thin bars still get a visible tick.
        const half = Math.max(3, Math.min(7,
          (flipped ? pt.height : pt.width) * 0.35)) / 2;
        ctx.beginPath();
        if (flipped) {
          ctx.moveTo(p1, pt.y); ctx.lineTo(p2, pt.y);
          ctx.moveTo(p1, pt.y - half); ctx.lineTo(p1, pt.y + half);
          ctx.moveTo(p2, pt.y - half); ctx.lineTo(p2, pt.y + half);
        } else {
          ctx.moveTo(pt.x, p1); ctx.lineTo(pt.x, p2);
          ctx.moveTo(pt.x - half, p1); ctx.lineTo(pt.x + half, p1);
          ctx.moveTo(pt.x - half, p2); ctx.lineTo(pt.x + half, p2);
        }
        ctx.stroke();
      });
      ctx.restore();
    });
  }
};

// URL state helpers — page id stays in the hash, per-page state lives in the
// query string (merged, so dev's ?bundle= survives).
function getParam(k) { return new URLSearchParams(location.search).get(k); }
// `push` makes the change a step in the browser's history, for a reader's own
// choices (a question, a comparison, a version, a measure, an area), so Back
// undoes it; housekeeping replaces the entry it is tidying.
function setParams(obj, push = false) {
  const q = new URLSearchParams(location.search);
  for (const [k, v] of Object.entries(obj)) {
    if (v == null || v === "") q.delete(k); else q.set(k, v);
  }
  const url = location.pathname + "?" + q.toString() + location.hash;
  if (url === location.pathname + location.search + location.hash) return;
  history[push ? "pushState" : "replaceState"](null, "", url);
}

// A link to another page carrying exactly the state it names. The reader's
// theme and color scheme come along; anything else in the address (a version,
// an area, a split left from an earlier page) is left behind. The full
// address is the href, so the link works opened in a new tab or copied as
// well as clicked; a plain click moves in place without reloading.
const CARRIED_PARAMS = ["theme", "scheme", "flag"];
function pageLink(hash, params, attrs, label) {
  const query = () => {
    const now = new URLSearchParams(location.search);
    const q = new URLSearchParams();
    for (const k of CARRIED_PARAMS) if (now.get(k)) q.set(k, now.get(k));
    for (const [k, v] of Object.entries(params || {}))
      if (v != null && v !== "") q.set(k, v);
    return q.toString();
  };
  const a = el("a", Object.assign({}, attrs, { href: "?" + query() + hash }), label);
  a.addEventListener("click", (e) => {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return;
    e.preventDefault();
    history.replaceState(null, "", location.pathname + "?" + query() + location.hash);
    location.hash = hash;
  });
  // Kept current for a copy made after the theme or scheme changes.
  a.addEventListener("mouseenter", () => { a.href = "?" + query() + hash; });
  a.addEventListener("focus", () => { a.href = "?" + query() + hash; });
  return a;
}

/* ------------------------------------------------------ shared widgets -- */

function groupingSelect(onChange, initial, labelText = "Select a grouping") {
  const wrap = el("div");
  wrap.append(el("label", { class: "field-label", for: "grouping-sel" }, labelText));
  const sel = el("select", { class: "grouping", id: "grouping-sel", onchange: () => onChange(sel.value) });
  for (const g of CONFIG.groupings) {
    sel.append(el("option", { value: g.id }, g.label));
  }
  sel.value = initial || CONFIG.groupings[0].id;
  wrap.append(sel);
  return wrap;
}

/* Grouped bar chart from long rows [{group, category, value, label}].
   Category axis order + series (group) order = first-appearance order in the
   data (which preserves R's factor-level ordering from the compiler), unless
   an explicit categoryOrder is supplied by config. */
let activeChart = null;
function groupedBarChart(canvas, rows, { title = "", xLabel = "", yLabel = "", categoryOrder = null, showCI = false, horizontal = false, colors = null, legend = true, legendTitle = "Group", standalone = false, pixelRatio = null, labelSize = null, highlight = null, altTitle = "", alongside = false }) {
  const groupsSeen = [], catsSeen = [];
  for (const r of rows) {
    const g = naLabel(r.group), c = naLabel(r.category);
    if (!groupsSeen.includes(g)) groupsSeen.push(g);
    if (!catsSeen.includes(c)) catsSeen.push(c);
  }
  let cats = catsSeen;
  if (categoryOrder) {
    const order = categoryOrder.map(naLabel);
    cats = order.filter(c => catsSeen.includes(c))
      .concat(catsSeen.filter(c => !order.includes(c))); // unknowns (e.g. NA) go last
  }
  const lookup = new Map(rows.map(r => [naLabel(r.group) + "\x1F" + naLabel(r.category), r]));
  colors = colors || viridis(groupsSeen.length);
  // `highlight` ({ categories, group }) keeps the named bars at full color and
  // fades the rest, so a chart can show which bars an answer is made of.
  const lit = (g, c) => !highlight ||
    ((!highlight.categories || highlight.categories.has(c)) &&
     (!highlight.group || highlight.group === g));
  // On a chart split by group a highlighted bar also takes an outline in the
  // theme's ink: the group an answer names can have the palest color in the
  // ramp, and fading the others alone would leave it no darker than them.
  const ink = getComputedStyle(document.body).getPropertyValue("--text").trim() || "#000";
  const outline = highlight && highlight.group && groupsSeen.length > 1;
  const datasets = groupsSeen.map((g, i) => ({
    label: g,
    backgroundColor: highlight
      ? cats.map(c => lit(g, c) ? colors[i] : fadeColor(colors[i], outline ? 0.14 : 0.22))
      : colors[i],
    ...(outline && !showCI ? {
      borderColor: cats.map(c => lit(g, c) ? ink : "rgba(0,0,0,0)"),
      borderWidth: cats.map(c => lit(g, c) ? 1.5 : 0)
    } : {}),
    data: cats.map(c => {
      const r = lookup.get(g + "\x1F" + c);
      return r ? r.value : null;
    }),
    barLabels: cats.map(c => {
      const r = lookup.get(g + "\x1F" + c);
      return r ? String(r.label ?? "") : "";
    }),
    // CI whiskers (opt-in): stroked by ErrorBarsPlugin in the theme's ink —
    // a same-color whisker would vanish where it overlaps its own bar.
    ...(showCI ? {
      borderColor: getComputedStyle(document.body).getPropertyValue("--text").trim() || "#000",
      errorLow: cats.map(c => { const r = lookup.get(g + "\x1F" + c); return r && r.low != null ? r.low : null; }),
      errorHigh: cats.map(c => { const r = lookup.get(g + "\x1F" + c); return r && r.upp != null ? r.upp : null; })
    } : {})
  }));

  // A standalone chart is drawn for export: fixed size, no animation, at the
  // pixel ratio asked for, and it leaves the chart on screen alone.
  // A chart drawn `alongside` the page's main one (a second office in the
  // quiz) leaves it standing and is cleared with the page instead.
  if (!standalone && !alongside && activeChart) { activeChart.destroy(); activeChart = null; }
  const chart = new Chart(canvas, {
    type: "bar",
    data: { labels: cats.map(tickLines), datasets },
    options: {
      responsive: !standalone,
      maintainAspectRatio: false,
      ...(standalone ? { animation: false, devicePixelRatio: pixelRatio || 1 } : {}),
      // horizontal: categories run down the y-axis
      indexAxis: horizontal ? "y" : "x",
      interaction: { mode: "nearest", intersect: false, axis: horizontal ? "y" : "x" },
      layout: { padding: horizontal ? { right: 48 } : { top: 24 } },
      plugins: {
        title: title ? { display: true, text: title, align: "start",
          font: { size: 15, weight: "600" }, padding: { bottom: 16 } } : { display: false },
        // legend:false for single-group charts (quiz reveal) — a one-entry
        // "Group: All" legend is noise.
        legend: legend ? { position: "bottom",
                           title: { display: !!legendTitle, text: legendTitle },
                           // A highlight fades bars, not the key: each group
                           // keeps its full color there.
                           ...(highlight ? { labels: { generateLabels: (ch) =>
                             Chart.defaults.plugins.legend.labels.generateLabels(ch)
                               .map((it, i) => Object.assign(it, {
                                 fillStyle: colors[i], strokeStyle: colors[i],
                                 lineWidth: 0 })) } } : {}) }
          : { display: false },
        datalabels: showCI ? { display: false } : {
          anchor: "end", align: "end", offset: 0, clip: false,
          color: getComputedStyle(document.body).getPropertyValue("--text").trim() || "#000",
          font: { size: labelSize
            ? (groupsSeen.length > 8 ? labelSize - 3 : labelSize)
            : (groupsSeen.length > 8 ? 9 : 11) },
          formatter: (v, ctx) => ctx.dataset.barLabels[ctx.dataIndex]
        },
        tooltip: {
          callbacks: {
            label: (ctx) => {
              const base = `${ctx.dataset.label}: ${ctx.dataset.barLabels[ctx.dataIndex]}`;
              const lo = ctx.dataset.errorLow && ctx.dataset.errorLow[ctx.dataIndex];
              const hi = ctx.dataset.errorHigh && ctx.dataset.errorHigh[ctx.dataIndex];
              return lo != null && hi != null
                ? `${base} (95% CI ${lo.toFixed(1)}–${hi.toFixed(1)})` : base;
            }
          }
        }
      },
      scales: horizontal ? {   // xLabel/yLabel keep their meaning: category / value
        // Every category keeps its label: Chart.js drops alternate ones when
        // they crowd, which leaves a bar with nothing to say what it is.
        y: { title: { display: !!xLabel, text: xLabel }, grid: { display: false },
             ticks: { autoSkip: false } },
        x: { title: { display: !!yLabel, text: yLabel }, beginAtZero: true, grace: "15%" }
      } : {
        x: { title: { display: !!xLabel, text: xLabel }, grid: { display: false },
             ticks: { autoSkip: false } },
        y: { title: { display: !!yLabel, text: yLabel }, beginAtZero: true, grace: "15%" }
      }
    },
    plugins: [ChartDataLabels, ErrorBarsPlugin]   // ErrorBarsPlugin no-ops without errorLow
  });
  if (!standalone) {
    if (alongside) trackChart(chart); else activeChart = chart;
    // altTitle names what the chart answers (the question) for the spoken
    // label, where the drawn chart has no title of its own.
    chartAlt(canvas, { cats, groups: groupsSeen, lookup, valueLabel: yLabel,
      title: altTitle || title, highlight: highlight ? lit : null,
      ci: showCI });
  }
  return chart;
}

/* Question wording with its survey placeholders made readable. The
   instruments pipe text into questions ("[rand_evnt_snow]", "[lead_time: 15 |
   30 | 60]", "rand_timeline"); a reader should see what was shown, not a
   variable name. A split-sample question's own variable becomes the version
   selected, in bold; a placeholder carrying its values becomes that list
   ("[15, 30, or 60]", "[5 to 100]"); a known one takes its words from the
   config; anything else reads "[varied between respondents]". Returns DOM
   nodes, the plain text, and the variable names that varied (for the note). */
function readableWording(text, id, armLabel = null, armId = null) {
  const words = CONFIG.placeholders || {};
  const armVar = (CONFIG.arm_variables || {})[id];
  const nodes = [], varied = [];
  let plain = "", last = 0, m;
  const re = /\[([a-z][a-z0-9_]*)(?::\s*([^\]]*))?\]|\b(rand_[a-z0-9_]+)\b/g;
  const push = (t) => { if (t) { nodes.push(t); plain += t; } };
  const listOf = (spec) => {
    // A value that depends on another placeholder ("2 and 6 if
    // amount_format_rand1 = 4, or 10 and 14 if ...") keeps its alternatives
    // and drops the conditions, which only name variables.
    if (/\sif\s/.test(spec)) {
      return spec.replace(/\s+if\s+[a-z][a-z0-9_]*\s*=\s*[^,\]]+/g, "").trim();
    }
    const range = spec.match(/^\s*(\d+)\s*:\s*(\d+)\s*$/);
    if (range) return `${range[1]} to ${range[2]}`;
    const items = spec.split(spec.includes("|") ? "|" : ",").map(x => x.trim()).filter(Boolean);
    return items.length > 1
      ? items.slice(0, -1).join(", ") + (items.length > 2 ? "," : "") + " or " + items[items.length - 1]
      : items.join("");
  };
  // With no version chosen, the slot names the versions: a run of numbers or
  // times as its two ends ("1:00 AM to 9:00 AM"), a few short words as a list,
  // and anything longer as a count, since a list of sentences is not wording.
  const versionsOf = (v) => {
    const all = ((CONFIG.arm_versions || {})[v] || []).map(String);
    const xs = all.filter(Boolean);
    if (xs.length < 2) return null;
    if (xs.some(x => x.length > 40) || xs.length < all.length)
      return `one of ${all.length} versions`;
    if (xs.length > 4 && xs.every(x => /^\d/.test(x)))
      return `${xs[0]} to ${xs[xs.length - 1]}`;
    return xs.slice(0, -1).join(", ") + (xs.length > 2 ? "," : "") +
      " or " + xs[xs.length - 1];
  };
  const pickFor = (spec) => {
    if (!/\sif\s/.test(spec)) return null;
    const alts = [...spec.matchAll(
      /(?:^|,)\s*(?:or\s+)?(.+?)\s+if\s+([a-z][a-z0-9_]*)\s*=\s*([^,]+)/g)];
    const hit = alts.find(a => a[2] === armVar && a[3].trim() === String(armId));
    return hit ? hit[1].trim() : null;
  };
  text = String(text || "");
  while ((m = re.exec(text))) {
    push(text.slice(last, m.index));
    const name = m[1] || m[3];
    if (armVar && name === armVar && armLabel == null && versionsOf(armVar)) {
      push("[" + versionsOf(armVar) + "]");
    } else if (armVar && name === armVar && armLabel != null) {
      if (armLabel) { nodes.push(el("strong", {}, armLabel)); plain += armLabel; }
    } else if (m[2] && armVar && armId != null && pickFor(m[2]) != null) {
      // A value keyed to the version shown ("10 and 14 if
      // amount_format_rand1 = 12") is the one that version read.
      const pick = pickFor(m[2]);
      nodes.push(el("strong", {}, pick)); plain += pick;
    } else {
      if (name !== armVar && !varied.includes(name)) varied.push(name);
      push("[" + (m[2] ? listOf(m[2]) : (words[name] || words[".default"] || "varied")) + "]");
    }
    last = re.lastIndex;
  }
  push(text.slice(last));
  return { nodes, text: plain, varied };
}

/* A question file with its response labels put into words, since options
   carry placeholders as often as the wording does ("[amount_format_rand1: 4
   or 12] inches"). Every chart reads its labels from here. */
async function fetchQuestion(id) {
  const v = await fetchJSON(`data/q/${id}.json`);
  if (v && v.options) {
    const varied = new Set();
    v.options = v.options.map(o => {
      const w = readableWording(String(o.label ?? ""), v.id);
      w.varied.forEach(n => varied.add(n));
      return { ...o, raw: o.label, label: w.text };
    });
    // Named in the note like the wording's own placeholders.
    v.options_varied = [...varied];
  }
  return v;
}

/* A chart drawn on a canvas says nothing to a screen reader, so every bar
   chart on the page carries a text alternative: a short spoken label on the
   canvas and, beside it, a table of the same numbers that is hidden on
   screen. Nothing is computed here - the table repeats the bars' own labels.
   Redrawing the chart replaces its table. */
function chartAlt(canvas, { cats, groups, lookup, valueLabel, title, highlight, ci = false }) {
  const clean = (t) => String(t).replace(/\n/g, " ");
  const multi = groups.length > 1;
  canvas.setAttribute("role", "img");
  // In sentences, so a title ending in its own punctuation reads cleanly.
  const sentence = (t) => { t = clean(t).trim(); return /[.?!]$/.test(t) ? t : t + "."; };
  canvas.setAttribute("aria-label", ["Bar chart.",
    title ? sentence(title) : "",
    valueLabel ? sentence("Values: " + valueLabel) : "",
    `${cats.length} categories${multi ? `, ${groups.length} groups` : ""}.`,
    "The values are in the table that follows."].filter(Boolean).join(" "));
  if (canvas._altTable) canvas._altTable.remove();
  const cell = (g, c) => {
    const r = lookup.get(g + "\x1F" + c);
    let v = r ? (r.label != null ? String(r.label) : String(r.value)) : "\u2014";
    // The interval the chart draws, when it draws one.
    if (ci && r && r.low != null && r.upp != null)
      v += ` (95% CI ${Number(r.low).toFixed(1)}\u2013${Number(r.upp).toFixed(1)})`;
    return highlight && r && highlight(g, c) ? v + " (highlighted)" : v;
  };
  const table = el("table", {},
    el("caption", {}, clean(title || valueLabel || "Chart values")),
    el("thead", {}, el("tr", {},
      el("th", { scope: "col" }, "Category"),
      ...(multi ? groups.map(g => el("th", { scope: "col" }, clean(g)))
                : [el("th", { scope: "col" }, clean(valueLabel || "Value"))]))),
    el("tbody", {}, ...cats.map(c => el("tr", {},
      el("th", { scope: "row" }, clean(c)),
      ...groups.map(g => el("td", {}, cell(g, c)))))));
  // Hidden by its wrapper rather than by its own class: a table will not
  // shrink to the one-pixel box that hides it, and on a phone its full width
  // would widen the page.
  const hidden = el("div", { class: "wx-sr-only" }, table);
  canvas.insertAdjacentElement("afterend", hidden);
  canvas._altTable = hidden;
}

// A color at reduced opacity, for bars a highlight leaves in the background.
function fadeColor(color, alpha) {
  const c = String(color || "").trim();
  const hex = c.match(/^#([0-9a-f]{3}|[0-9a-f]{6})$/i);
  if (hex) {
    let h = hex[1];
    if (h.length === 3) h = h.split("").map(x => x + x).join("");
    const n = parseInt(h, 16);
    return `rgba(${n >> 16 & 255}, ${n >> 8 & 255}, ${n & 255}, ${alpha})`;
  }
  const rgb = c.match(/^rgba?\(([^)]+)\)$/i);
  if (rgb) {
    const [r, g, b] = rgb[1].split(",").map(x => x.trim());
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }
  return c;
}

/* ------------------------------------------------------------ components -- */

const components = {};

/* Explore: a search over every question, the selected question as a
 * heading, the split control (color and intervals under "Chart options"),
 * the full-width chart card with its caption and downloads, and the question
 * browser below.
 *
 * Bars carry the instrument's own response labels, from the question file's
 * `options`, and its `summaries` (per-split respondent counts) fill the
 * `explore_caption` templates in config, so the caption rewrites itself
 * for the selected split ("… the weighted percentage of each age group
 * giving each answer. The smallest group, X, has N respondents."). */

// SVG/Chart.js tick labels don't wrap on their own; response labels are
// sentences ("I would trust forecasts generated by machine learning…"), so
// they are broken into tick lines at word boundaries instead of trimmed.
function wrapTickLabel(text, width = 26, maxLines = 3) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let line = "";
  for (const w of words) {
    if (line && (line + " " + w).length > width) { lines.push(line); line = w; }
    else line = line ? line + " " + w : w;
    if (lines.length === maxLines) break;
  }
  if (lines.length < maxLines && line) lines.push(line);
  else if (line) lines[maxLines - 1] += "…";
  return lines.join("\n");
}

/* Tick labels for a question's options. The chart keys bars by label, so
   two options that read the same once cut (formats that differ only in a
   last sentence) would share one bar and the other response would vanish;
   those are wrapped in full instead of cut. */
function tickLabeller(labels) {
  const cut = labels.map(l => wrapTickLabel(l));
  const clash = new Set(cut.filter((c, i) => cut.indexOf(c) !== i));
  const map = new Map(labels.map((l, i) =>
    [l, clash.has(cut[i]) ? wrapTickLabel(l, 26, Infinity) : cut[i]]));
  return (l) => map.get(l) ?? wrapTickLabel(l);
}

components.explore = async function (page, container) {
  const questions = await fetchJSON(page.questions.replace(/^data\//, "data/"));
  let grouping = urlGrouping() || page.default_grouping || "All";
  let showCI = getParam("ci") === "1";   // ?ci=1 deep-links the CI view
  let currentArm = getParam("arm");      // ?arm= deep-links a split-sample version
  let scheme = urlScheme();              // ?scheme= deep-links a color scheme
  let currentQuestionText = "";          // for the flag list
  // Question files are keyed by `id` — hazard code + variable, because two
  // surveys can share a variable name (alert_und is asked in all four).
  const keyOf = (r) => r.id;
  // ?q=<id> deep-links a question; else row 1.
  const urlQ = getParam("q");
  let currentKey = (urlQ && questions.some(x => keyOf(x) === urlQ))
    ? urlQ : (questions[0] && keyOf(questions[0]));

  // The selected question leads the section and is set on the page rather
  // than in a card: the survey as a small label, then the stem it shares
  // with the rest of its battery, quiet, and the item large beneath it.
  const resultHead = el("div", { class: "wx-result-head" });
  const qSurvey = el("p", { class: "wx-result-survey" }, "");
  const chartCard = el("div", { class: "card wx-result-chart" });
  const wrap = el("div", { class: "chart-wrap" });
  const canvas = el("canvas");
  wrap.append(canvas);

  // Chrome created up front so draw() can update it.
  // The stem a battery of items shares, above the item itself. Quieter,
  // because it is the same sentence on every item in the battery and the item
  // is what changes.
  const qIntro = el("p", { class: "wx-question-intro wx-result-stem" }, "");
  // Text a version showed ahead of the question, for experiments where the
  // question itself reads the same in every version.
  const qShown = el("div", { class: "wx-arm-shown" });
  const qHead = el("h2", { class: "wx-question-head wx-result-item" }, "");
  // The version menu, inside the chart card rather than the toolbar above it:
  // it belongs to this question, not to the page, and it disappears with the
  // question. Only split-sample items have one.
  const armBox = el("div", { class: "wx-arm-pick" });
  const flagBtn = flaggingOn()
    ? el("button", { class: "wx-flag-btn", type: "button" }, "\u2691 Flag")
    : null;
  const flagPanel = flaggingOn() ? el("div", { class: "card wx-flag-panel" }) : null;
  const saveBtn = el("button", { class: "wx-save-btn", type: "button" }, "\u2606 Save question");
  const savedPanel = el("section", { class: "card wx-saved" });
  let currentSave = null;   // the question on screen, as a saved entry
  let shownStem = "", shownItem = "", shownQuestion = "";

  function syncSaveBtn() {
    const on = readSaved().some(x => x.id === currentKey);
    saveBtn.textContent = on ? "\u2605 Saved" : "\u2606 Save question";
    saveBtn.classList.toggle("is-on", on);
    saveBtn.setAttribute("aria-pressed", on ? "true" : "false");
  }

  saveBtn.onclick = () => {
    if (!currentSave) return;
    const list = readSaved();
    const at = list.findIndex(x => x.id === currentSave.id);
    if (at >= 0) list.splice(at, 1); else list.push(currentSave);
    writeSaved(list);
    syncSaveBtn();
    renderSaved();
  };

  // A quiet way down to the list from the search, shown once something is
  // saved, so a reader with a list does not have to scroll the browser to
  // find it.
  const savedJump = el("a", { class: "wx-saved-jump", href: "#",
    onclick: (e) => {
      e.preventDefault();
      savedPanel.scrollIntoView({ behavior: "smooth", block: "start" });
    } });

  function renderSaved() {
    const list = readSaved();
    savedJump.textContent = `Saved questions (${list.length}) \u2193`;
    savedJump.style.display = list.length ? "" : "none";
    savedPanel.textContent = "";
    savedPanel.style.display = list.length ? "" : "none";
    if (!list.length) return;
    savedPanel.append(
      el("h2", { class: "wx-saved-title" }, `Saved questions (${list.length})`),
      el("p", { class: "wx-saved-lede" },
        "Saved in this browser only. Download the list to keep it."));
    const ul = el("ul", { class: "wx-saved-list" });
    for (const x of list) {
      // A question taken off the list since it was saved still shows, so the
      // reader knows what they had, but it no longer opens.
      const listed = questions.some(r => keyOf(r) === x.id);
      const text = [
        el("span", { class: "wx-saved-meta" },
          [x.survey, x.years].filter(Boolean).join(" \u00b7 ")),
        el("span", { class: "wx-saved-q" }, x.question)];
      const open = listed
        ? el("button", { class: "wx-saved-open", type: "button", onclick: () => {
            currentKey = x.id;
            currentArm = null;
            setParams({ q: currentKey, arm: null }, true);
            qTable.selectRow(r => keyOf(r) === currentKey);
            resultSection.scrollIntoView({ behavior: "smooth", block: "start" });
            draw();
          } }, ...text)
        : el("div", { class: "wx-saved-open is-gone" }, ...text);
      const drop = el("button", { class: "wx-saved-drop", type: "button",
        "aria-label": "Remove from saved questions", title: "Remove",
        onclick: () => {
          writeSaved(readSaved().filter(y => y.id !== x.id));
          syncSaveBtn();
          renderSaved();
        } }, "\u00d7");
      ul.append(el("li", { class: "wx-saved-row" }, open, drop));
    }
    savedPanel.append(ul, el("div", { class: "wx-saved-actions" },
      pdfButton("Download list (CSV)", () => {
        const url = URL.createObjectURL(
          new Blob([savedToCSV(readSaved())], { type: "text/csv" }));
        const a = el("a", { href: url, download: "wxdash_saved_questions.csv" });
        document.body.append(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      })));
  }

  function renderFlagPanel() {
    if (!flagPanel) return;
    const flags = readFlags();
    const ids = Object.keys(flags).sort();
    flagPanel.textContent = "";
    flagPanel.append(el("h3", {}, `Flagged questions (${ids.length})`));
    if (ids.length === 0) {
      flagPanel.append(el("p", { class: "wx-flag-empty" },
        "Nothing flagged yet. Open a question and use the flag beside its heading."));
      return;
    }
    for (const id of ids) {
      const f = flags[id];
      const row = el("div", { class: "wx-flag-row" });
      row.append(
        el("button", { class: "wx-flag-drop", type: "button", onclick: () => {
          const all = readFlags(); delete all[id]; writeFlags(all);
          renderFlagPanel();
          syncFlagBtn();
          if (qTable && qTable.rerender) qTable.rerender();
        } }, "\u00d7"),
        el("code", { class: "wx-flag-id" }, id),
        el("span", { class: "wx-flag-question" }, f.question || ""));
      flagPanel.append(row);
    }
    const csv = () => flagsToCSV(readFlags());
    flagPanel.append(el("div", { class: "wx-flag-actions" },
      pdfButton("Download hidden_questions.csv", () => {
        const url = URL.createObjectURL(new Blob([csv()], { type: "text/csv" }));
        const a = el("a", { href: url, download: "hidden_questions.csv" });
        document.body.append(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }),
      pdfButton("Copy to clipboard", () => {
        navigator.clipboard && navigator.clipboard.writeText(csv());
      })));
  }

  // One toggle behind both affordances, so the flag beside the heading and the
  // one in the table row cannot disagree about what is flagged.
  function toggleFlag(id, question) {
    const all = readFlags();
    if (all[id]) delete all[id];
    else all[id] = { disposition: "hide", note: "", question: question || "" };
    writeFlags(all);
    renderFlagPanel();
    syncFlagBtn();
  }

  function flagCell(r) {
    const on = Object.prototype.hasOwnProperty.call(readFlags(), r.id);
    const b = el("button", {
      class: "wx-flag-cell" + (on ? " is-on" : ""), type: "button",
      title: on ? "Flagged" : "Flag this question",
      // The row itself loads the question; flagging is not that, so the click
      // stops here rather than opening what you were only triaging.
      onclick: (e) => {
        e.stopPropagation();
        toggleFlag(r.id, r.question_text || r.question);
        b.classList.toggle("is-on");
        b.textContent = b.classList.contains("is-on") ? "\u2691" : "\u2690";
      }
    }, on ? "\u2691" : "\u2690");
    return b;
  }

  function syncFlagBtn() {
    if (!flagBtn) return;
    const on = Object.prototype.hasOwnProperty.call(readFlags(), currentKey);
    flagBtn.textContent = on ? "\u2691 Flagged" : "\u2691 Flag";
    flagBtn.classList.toggle("is-on", on);
  }

  if (flagBtn) {
    flagBtn.onclick = () => {
      toggleFlag(currentKey, currentQuestionText);
      if (qTable && qTable.rerender) qTable.rerender();
    };
  }
  const caption = el("div", { class: "wx-caption wx-explore-caption" });
  const ciBox = el("input", { type: "checkbox", id: "ci-toggle" });
  ciBox.checked = showCI;
  ciBox.onchange = () => { showCI = ciBox.checked; setParams({ ci: showCI ? "1" : null }); draw(); };
  const headRow = el("div", { class: "wx-question-headrow" }, qHead);
  if (flagBtn) headRow.append(flagBtn);
  resultHead.append(qSurvey, qShown, qIntro, headRow, armBox);
  chartCard.append(wrap, caption);

  function renderArmPicker(v, armKey) {
    armBox.textContent = "";
    const arms = v.arms;
    armBox.style.display = arms ? "" : "none";
    if (!arms) return;
    const sel = el("select", { class: "wx-arm-select", onchange: () => {
      currentArm = sel.value;
      setParams({ arm: currentArm }, true);   // keep the URL shareable
      draw();
    } });
    for (const a of arms) sel.append(el("option", { value: a.id }, a.label));
    sel.value = armKey;
    armBox.append(
      el("span", { class: "wx-arm-label" },
         (v.arm_prompt || "Version") + ":"),
      sel,
      infoTip("Respondents did not all read the same thing. Each version is " +
              "estimated on its own — pooling them would average across the " +
              "difference being tested."));
  }
  // The R that rebuilds this exact chart is generated by 09_statistics.R, the
  // script that computed the numbers, and downloaded from the foot of the
  // chart. Assigned with the downloads below; declared here so draw() can
  // hide it for a bundle whose question files carry no scripts.
  let lastCodeArgs = null;
  let rcodeBtn = null;
  let lastChart = null;   // what draw() last drew, for the PNG to redraw

  /* The chart as a figure (figureImage): redrawn off screen at the figure's
   * density with slide-sized type, under the survey, stem and item, over the
   * caption's facts line and bars sentence. */
  function chartImage() {
    if (!lastChart) return null;
    const inner = FIGURE.W - FIGURE.pad * 2;
    // The chart keeps the proportions it has on screen.
    const ratio = wrap.clientHeight / Math.max(1, wrap.clientWidth);
    const chartH = Math.round(Math.max(460, Math.min(1400, inner * ratio * 1.1)));
    const host = el("div", { style:
      `position:fixed;left:-30000px;top:0;width:${inner}px;height:${chartH}px` });
    const cv = el("canvas");
    cv.style.width = inner + "px"; cv.style.height = chartH + "px";
    cv.width = inner; cv.height = chartH;
    host.append(cv); document.body.append(host);
    const saved = Chart.defaults.font.size;
    Chart.defaults.font.size = 15;   // slide-sized type, not screen-sized
    let chart;
    try {
      chart = groupedBarChart(cv, lastChart.rows,
        { ...lastChart.opts, standalone: true, pixelRatio: FIGURE.S, labelSize: 14 });
    } finally { Chart.defaults.font.size = saved; }
    const capLine = (cls) => (caption.querySelector(cls) || {}).textContent || "";
    const img = figureImage({
      label: lastChart.survey, stem: lastChart.stem, title: lastChart.item,
      body: { height: chartH,
              draw: (ctx, x, y, w) => ctx.drawImage(cv, x, y, w, chartH) },
      lines: [{ text: capLine(".wx-caption-meta"), strong: true },
              { text: capLine(".wx-caption-bars") }],
      source: FIGURE_SOURCE + " Survey weights adjust each wave to American " +
              "Community Survey benchmarks."
    });
    chart.destroy(); host.remove();
    return img;
  }

  const exportName = (ext) => {
    const g = lastChart && lastChart.g;
    return `wxdash-${currentKey}${g && g !== "All" ? "-" + g : ""}.${ext}`;
  };

  /* The scripts live in their own file, fetched the first time a reader asks
   * for one and kept after: one question carries thirteen splits, and code
   * nobody wanted has no business loading with the chart. 09_statistics.R
   * writes one concrete script per split, so this is a lookup: the engine
   * composes nothing. */
  const rcodeCache = new Map();

  async function rcodeFor(id, g, armKey) {
    let all = rcodeCache.get(id);
    if (!all) {
      all = await fetchJSON(`data/rcode/${id}.json`);
      rcodeCache.set(id, all);
    }
    // Nested under the version for a split-sample question, flat for the rest
    // — the same shape the question file uses.
    return (armKey ? (all[armKey] || {})[g] : all[g]) || "";
  }

  function downloadRCode(text, id, g, armKey) {
    // A version id can be an instrument's own spelling — "10:00:00", "1/4 inch
    // of freezing rain or ice" — and neither belongs in a filename.
    const safe = (v) => String(v).replace(/[^A-Za-z0-9]+/g, "-")
                                 .replace(/^-|-$/g, "");
    const name = armKey ? `wxdash-${id}-${safe(armKey)}-${g}.R`
                        : `wxdash-${id}-${g}.R`;
    const url = URL.createObjectURL(new Blob([text], { type: "text/plain" }));
    const a = el("a", { href: url, download: name });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  let groupingSel = null;   // set below; draw() updates it on split fallback

  // The note under the chart (templates in config.explore_caption): a line
  // of facts, what the bars are for the chosen split, where the data come
  // from, then the variable and the data link.
  function renderCaption2(v, g, summaries, varied = []) {
    const tpl = CONFIG.explore_caption;
    const s = summaries && summaries[g];
    caption.textContent = "";
    if (!s) return;
    const survey = String(v.hazard || "").replace(/\s*\([A-Z]+\)$/, "");
    const years = String(s.years || "").replace(/-/g, "\u2013");
    caption.append(el("p", { class: "wx-caption-meta" }, fillTpl(tpl.meta, {
      who: countedAs(s.years), n: Number(s.n).toLocaleString(), survey, years })));
    const gcfg = CONFIG.groupings.find(x => x.id === g);
    let bars = g === "All" ? tpl.bars
      : fillTpl(tpl.bars_split, { group_phrase: (gcfg && gcfg.phrase) || "group" });
    if (g !== "All") bars += fillTpl(tpl.smallest, {
      smallest: s.smallest, smallest_n: Number(s.smallest_n).toLocaleString() });
    // A split-sample question says its versions were randomized, and one
    // whose wording carries other piped-in text says that varied; the
    // survey variables behind either are named in the reference line.
    const armVar = (CONFIG.arm_variables || {})[v.id];
    if (v.arms) bars += tpl.randomized || "";
    else if (varied.length) bars += tpl.varied || "";
    if (g !== "survey_year" && countedAs(s.years) === "responses")
      bars += fillTpl(tpl.pooled || "", { years });
    if (showCI) bars += tpl.ci || "";
    caption.append(el("p", { class: "wx-caption-bars" }, bars));
    caption.append(el("p", { class: "wx-caption-provenance", html: tpl.provenance }));
    const others = varied.filter(x => x !== armVar)
      .filter((x, i, a) => a.indexOf(x) === i);
    const refExtra =
      (v.arms && armVar ? fillTpl(tpl.randomization || "", { names: esc(armVar) }) : "") +
      (others.length ? fillTpl(tpl.piped || "", { names: others.map(esc).join(", ") }) : "");
    caption.append(el("p", { class: "wx-caption-ref",
      html: fillTpl(tpl.reference, { variable: esc(v.variable),
        randomization: refExtra }) }));
  }

  async function draw() {
    if (!currentKey) return;
    const v = await fetchQuestion(currentKey);
    // A split-sample question nests its splits one level deeper, under the
    // version. `arms` being present is what says so — there is no pooled
    // option, because pooling averages across the treatment.
    const { armKey, splits, summaries } = questionSlice(v, currentArm);
    renderArmPicker(v, armKey);
    // A question is not asked under every split — fall back to Everyone
    // rather than drawing an empty panel, and show the select doing it.
    let g = grouping;
    if (!(splits[g] && splits[g].length)) g = "All";
    if (groupingSel) groupingSel.value = g;
    const labelFor = (resp) => {
      const hit = (v.options || []).find(o => String(o.value) === String(resp));
      // An unlabelled value is shown as itself rather than dropped: it means
      // the data carries a code the instrument does not document.
      return hit ? hit.label : String(resp);
    };
    currentQuestionText = v.question || currentKey;
    qSurvey.textContent = String(v.hazard || "").replace(/\s*\([A-Z]+\)$/, "");
    // Placeholders in the wording read as the version shown (in bold) or in
    // plain words, never as survey variable names.
    // The roster's wording where it has one, which may be empty (a version
    // that added nothing); otherwise the survey's own value where it is the
    // text respondents read ("flooding event"), and the label where the value
    // is a code (a number, a time, or a name with underscores).
    const arm = v.arms ? (v.arms.find(a => a.id === armKey) || {}) : {};
    const worded = (CONFIG.arm_wording || {})[(CONFIG.arm_variables || {})[v.id]];
    const armId = String(arm.id ?? "");
    const armLabel = !armId ? null
      : worded ? (worded[armId] ?? "")
      : /[a-z]/i.test(armId) && !/_/.test(armId) ? armId : (arm.label || "");
    // Options carry placeholders too; on a version, they read its numbers.
    if (armId && v.options) {
      const varied = new Set();
      v.options = v.options.map(o => {
        const w = readableWording(String(o.raw ?? o.label), v.id, armLabel, armId);
        w.varied.forEach(n => varied.add(n));
        return { ...o, label: w.text };
      });
      v.options_varied = [...varied];
    }
    const wi = readableWording(v.question_intro || "", v.id, armLabel);
    const wt = readableWording(v.question_text || v.question || currentKey, v.id, armLabel);
    const shown = ((CONFIG.arm_shown || {})[(CONFIG.arm_variables || {})[v.id]] || {})[armId];
    qShown.textContent = "";
    if (shown) {
      qShown.append(el("p", { class: "wx-arm-shown-label" }, CONFIG.arm_shown_label || ""),
        el("blockquote", { class: "wx-quiz-quote" }, shown));
    }
    qShown.style.display = shown ? "" : "none";
    qIntro.textContent = ""; qIntro.append(...wi.nodes);
    qIntro.style.display = v.question_intro ? "" : "none";
    qHead.textContent = ""; qHead.append(...wt.nodes);
    // The wording as shown, for everything that repeats it off the page: the
    // chart's spoken label and the downloaded figure.
    shownStem = v.question_intro ? wi.text : "";
    shownItem = wt.text;
    shownQuestion = [shownStem, shownItem].filter(Boolean).join(" ");
    renderCaption2(v, g, summaries,
      [...new Set(wi.varied.concat(wt.varied, v.options_varied || []))]);
    syncFlagBtn();
    currentSave = {
      id: currentKey,
      survey: qSurvey.textContent + " Survey",
      years: (summaries && summaries.All && summaries.All.years) || "",
      question: readableWording(v.question || "", v.id).text,
      variable: v.variable || ""
    };
    syncSaveBtn();
    lastCodeArgs = [currentKey, g, armKey];
    if (rcodeBtn) rcodeBtn.style.display = v.has_r_code ? "" : "none";
    const tick = tickLabeller((v.options || []).map(o => o.label));
    const rows = (splits[g] || []).map(r => ({
      group: r.group, category: tick(labelFor(r.resp)),
      value: r.p, label: Math.round(r.p) + "%", low: r.p_low, upp: r.p_upp
    }));
    // Horizontal bars need vertical room proportional to bar count —
    // grow the canvas instead of cramming (long scales × many groups).
    const nCats = new Set(rows.map(r => naLabel(r.category))).size;
    const nGroups = new Set(rows.map(r => naLabel(r.group))).size;
    const tickLines = Math.max(1, ...rows.map(r => String(r.category).split("\n").length));
    wrap.style.height = Math.max(380, Math.min(1000,
      110 + nCats * Math.max(44, nGroups * 20, tickLines * 18))) + "px";
    // One series needs no key; several are keyed by what they split on, so
    // the legend reads "Age" rather than "Group".
    const gLabel = (CONFIG.groupings.find(x => x.id === g) || {}).label;
    const chartOpts = {
      title: "",
      altTitle: shownQuestion,
      xLabel: page.chart.x_label, yLabel: page.chart.y_label,
      showCI,
      legend: nGroups > 1, legendTitle: gLabel || "Group",
      horizontal: true,
      colors: schemeSeriesColors(scheme, new Set(rows.map(r => naLabel(r.group))).size)
    };
    groupedBarChart(canvas, rows, chartOpts);
    lastChart = { rows, opts: chartOpts, g,
                  survey: qSurvey.textContent, stem: shownStem,
                  item: shownItem };
  }

  const tableCard = el("section", { class: "card wx-browse" });
  tableCard.append(el("h2", { class: "wx-browse-title" }, "Browse Survey Questions"),
    el("p", { class: "wx-browse-lede" },
      "Browse all survey questions or use the filters below to narrow the list."));
  const qTable = questionBrowser(questions, {
    flagCell: flaggingOn() ? flagCell : null,
    onPick: (r) => {
      currentKey = keyOf(r);
      currentArm = null;
      setParams({ q: currentKey, arm: null }, true);   // keep the URL shareable
      // The chart sits well above the list: bring it into view so the click
      // visibly loads the new question.
      resultSection.scrollIntoView({ behavior: "smooth", block: "start" });
      draw();
    }
  });
  if (currentKey === urlQ) qTable.selectRow(r => keyOf(r) === urlQ);
  else qTable.selectFirst();
  tableCard.append(qTable);

  const intro = pageHead(page,
    "Click a survey question in the table below to see the weighted distribution of responses, split by the group you choose.");
  // The way in for someone who arrives with a question in mind: pick a match
  // and it loads exactly as a click in the table does, with the table paged
  // to it so the two never disagree about which question is showing.
  const search = questionSearch(questions, (r) => {
    currentKey = keyOf(r);
    currentArm = null;
    setParams({ q: currentKey, arm: null }, true);
    qTable.selectRow(x => keyOf(x) === currentKey);
    draw();
  });
  // The comparison is the control that matters, so it stands alone; color
  // and intervals sit behind "Chart options", open from the start only when
  // a link has already set one of them, so a shared view shows its settings.
  const bar = el("div", { class: "wx-result-controls" });
  const resultSection = el("section", { class: "wx-result" });
  // The URL carries the comparison, so a reload or a copied link shows the
  // same split, and a link that arrived with one does not keep it stale.
  const gWrap = groupingSelect(g => {
    grouping = g;
    setParams({ grouping: g === "All" ? null : g }, true);
    draw();
  }, grouping, "Compare responses by");
  gWrap.classList.add("wx-compare");
  groupingSel = gWrap.querySelector("select");
  bar.append(gWrap);
  const options = el("details", { class: "wx-chart-options" });
  if (showCI || scheme !== DEFAULT_SCHEME) options.open = true;
  options.append(el("summary", {}, "Chart options"));
  options.append(el("div", { class: "wx-chart-options-body" },
    schemeSelect(scheme, (sc) => {
      scheme = sc;
      setParams({ scheme: sc === DEFAULT_SCHEME ? null : sc });
      draw();
    }),
    el("label", { class: "wx-ci-label", for: "ci-toggle" },
      ciBox, " Show 95% confidence intervals")));
  bar.append(options);
  // The caption below the chart is the document's notes: how many answered,
  // that the percentages are weighted, which waves, the smallest group, and
  // the provenance with the variable code. A chart without them cannot be
  // handed to anyone.
  // Both downloads in one group. .wx-pdf-btn carries margin-left:auto, so two
  // of them loose in the toolbar each push themselves to the right edge and
  // end up at opposite ends of the row; the group takes the auto margin once
  // and the buttons sit together.
  // At the foot of the chart, under the caption that says who answered and
  // where the data come from: the R code is part of that account, and both
  // downloads are things to take away rather than ways to change the view.
  const actions = el("div", { class: "wx-toolbar-actions wx-result-downloads" });
  chartCard.append(actions);
  actions.append(pdfButton("Download chart (PNG)",
    () => saveFigure(chartImage(), exportName("png"), "png")));
  // The same picture as the PNG, on a page cut to its shape: 11 inches wide
  // and as tall as the picture needs, so nothing is letterboxed or cropped.
  actions.append(pdfButton("Download chart (PDF)",
    () => saveFigure(chartImage(), exportName("pdf"), "pdf")));
  // Beside the chart download, and a download rather than a viewer: someone
  // who wants the script wants it in their editor, not in a scrolling box.
  rcodeBtn = pdfButton("Download R code", async () => {
    if (!lastCodeArgs) return;
    const [id, g, armKey] = lastCodeArgs;
    try {
      const text = await rcodeFor(id, g, armKey);
      if (text) downloadRCode(text, id, g, armKey);
    } catch { /* a missing file leaves the chart alone rather than erroring */ }
  });
  // Hidden until draw() has a question in hand: it downloads that question's
  // script, so it has nothing to offer before one is chosen.
  rcodeBtn.style.display = "none";
  actions.append(rcodeBtn);
  // Beside the downloads: saving is another way of taking the question away.
  // Explained on hover and on keyboard focus, and read out as the button's
  // description, so it needs no second control.
  saveBtn.setAttribute("aria-describedby", "wx-save-tip");
  actions.append(el("span", { class: "wx-save-wrap" }, saveBtn,
    el("span", { class: "wx-hover-tip", id: "wx-save-tip", role: "tooltip" },
      "Save questions you want to revisit. You can reopen them or download " +
      "your saved list as a CSV at the bottom of this page. Saved questions " +
      "are stored only in this browser and may be removed if you clear your " +
      "browsing data.")));
  container.append(el("div", { class: "page wx-explore-page" },
    el("div", { class: "content" }, intro, search, savedJump,
       resultSection,
       tableCard,
       savedPanel,
       ...(flagPanel ? [flagPanel] : []))));
  resultSection.append(resultHead, bar, chartCard);
  renderFlagPanel();
  renderSaved();
  pageRestyle = () => draw();
  await draw();
};

/* The question browser under the explore page's results: three menus
 * (survey, topic, question type), a search within whatever they leave, a
 * count, and the questions as rows rather than spreadsheet cells. The item
 * leads each row and the stem it shares with its battery sits quietly above
 * it; the survey and topic are small labels over both. Rows are whole-row
 * links. Pagination stays, at a fixed ten, because there are over 900.
 *
 * Topics come from the question data and nothing else: `topic` is the one a
 * row is labelled with, and `topics` lists every topic the question was given
 * ("A | B"), which the menu matches against. Until the data carries them the
 * menu says so and stays disabled rather than guessing from the wording. */
function questionBrowser(rows, { onPick, flagCell = null, pageSize = 10 }) {
  const surveyName = (h) => String(h || "").replace(/\s*\([A-Z]+\)$/, "");
  const distinct = (key) => [...new Set(rows.map(r => r[key]).filter(Boolean))];
  const surveys = distinct("hazard");
  const topicsOf = (r) => String(r.topics || r.topic || "").split(" | ")
    .filter(Boolean);
  const topics = [...new Set(rows.flatMap(topicsOf))]
    .sort((a, b) => a.localeCompare(b));
  const kinds = distinct("kind");
  const norm = (t) => String(t || "").toLowerCase();
  const haystack = new Map(rows.map(r => [r, norm([r.question, r.variable,
    r.response_scale, r.topics || r.topic, r.kind].filter(Boolean).join(" "))]));

  let fSurvey = "", fTopic = "", fKind = "", q = "", page = 0, selected = null;
  let filtered = rows.slice();

  const root = el("div", { class: "wx-browse-body" });
  const menu = (label, allText, values, show, onChange) => {
    const sel = el("select", { class: "grouping", "aria-label": label,
                               onchange: () => onChange(sel.value) });
    sel.append(el("option", { value: "" }, allText));
    for (const v of values) sel.append(el("option", { value: v }, show(v)));
    return sel;
  };
  const surveySel = menu("Survey", "All surveys", surveys, surveyName,
    v => { fSurvey = v; apply(); });
  const topicSel = menu("Topic", "All topics", topics, v => v,
    v => { fTopic = v; apply(); });
  if (!topics.length) {
    topicSel.disabled = true;
    topicSel.title = "Topics are not in the question data yet.";
  }
  const kindSel = menu("Question type", "All question types", kinds, v => v,
    v => { fKind = v; apply(); });
  const find = el("input", { type: "search", class: "wx-browse-search",
    placeholder: "Search within results...", "aria-label": "Search within results",
    oninput: () => { q = find.value; apply(); } });
  const count = el("span", { class: "wx-browse-count", "aria-live": "polite" });
  root.append(el("div", { class: "wx-browse-filters" }, surveySel, topicSel, kindSel),
              el("div", { class: "wx-browse-searchrow" }, find, count));

  const list = el("ol", { class: "wx-browse-list" });
  const prev = el("button", { class: "wx-browse-page", type: "button",
    onclick: () => { page--; render(); } }, "‹ Previous");
  const next = el("button", { class: "wx-browse-page", type: "button",
    onclick: () => { page++; render(); } }, "Next ›");
  const where = el("span", { class: "wx-browse-where" });
  root.append(list, el("nav", { class: "wx-browse-pager", "aria-label": "Pages" },
                        prev, where, next));

  function apply() {
    const words = norm(q).split(/\s+/).filter(Boolean);
    filtered = rows.filter(r =>
      (!fSurvey || r.hazard === fSurvey) &&
      (!fTopic || topicsOf(r).includes(fTopic)) &&
      (!fKind || r.kind === fKind) &&
      words.every(w => haystack.get(r).includes(w)));
    page = 0;
    render();
  }

  function render() {
    const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
    page = Math.min(Math.max(0, page), pages - 1);
    const n = filtered.length;
    count.textContent = `${n.toLocaleString()} question${n === 1 ? "" : "s"}`;
    list.textContent = "";
    if (!n) list.append(el("li", { class: "wx-browse-none" },
      "No questions match. Try another filter or fewer words."));
    for (const r of filtered.slice(page * pageSize, (page + 1) * pageSize)) {
      // The list item stays a list item; the control inside it is the
      // button, so the list reads as a list to a screen reader.
      const li = el("li", { class: "wx-browse-row" + (r === selected ? " selected" : "") });
      const hit = el("div", { class: "wx-browse-hit", tabindex: "0", role: "button",
        "aria-current": r === selected ? "true" : "false",
        onclick: () => pick(r),
        onkeydown: (e) => {
          if (e.key === "Enter" || e.key === " ") { e.preventDefault(); pick(r); }
        } });
      const meta = el("div", { class: "wx-browse-meta" },
        el("span", { class: "wx-browse-survey" }, surveyName(r.hazard)));
      if (r.topic) meta.append(el("span", { class: "wx-browse-topic" }, r.topic));
      const body = el("div", { class: "wx-browse-q" });
      if (r.question_intro)
        body.append(el("p", { class: "wx-browse-stem" },
          readableWording(r.question_intro, r.id).text));
      const itemRow = el("div", { class: "wx-browse-itemrow" },
        el("p", { class: "wx-browse-item" },
          readableWording(r.question_text || r.question, r.id).text));
      // Neither the variable name nor the question type is shown on the row;
      // both are found by typing them in the search, and the type has a menu.
      if (flagCell) itemRow.append(flagCell(r));
      body.append(itemRow);
      hit.append(meta, body);
      li.append(hit);
      list.append(li);
    }
    where.textContent = `Page ${page + 1} of ${pages}`;
    prev.disabled = page === 0;
    next.disabled = page >= pages - 1;
  }

  function pick(r) { selected = r; render(); onPick && onPick(r); }

  // Select and page to the first row matching pred, for deep links and for
  // the search above; a question the filters hide is still selected, and the
  // list stays where it is.
  root.selectRow = (pred) => {
    const r = rows.find(pred);
    if (!r) return;
    selected = r;
    const i = filtered.indexOf(r);
    if (i >= 0) page = Math.floor(i / pageSize);
    render();
  };
  root.selectFirst = () => root.selectRow(() => true);
  root.rerender = render;
  render();
  return root;
}

/* The explore page's search: one large field over the full wording of every
 * question, stem and item together, with matches listed as the reader types.
 * Every word typed has to appear, in any order, so "tornado siren" finds
 * questions using both words. Matches whose item itself contains the words
 * come first, because the stem is shared by a whole battery and would
 * otherwise bury the one item the reader meant. Each suggestion shows the
 * item, the stem quietly above it where there is one, and the survey. */
function questionSearch(questions, onPick) {
  const LIMIT = 8;
  const norm = (t) => String(t || "").toLowerCase();
  const index = questions.map(r => ({
    row: r, all: norm(r.question), item: norm(r.question_text || r.question)
  }));

  const wrap = el("section", { class: "wx-qsearch" });
  const label = el("label", { class: "wx-qsearch-label", for: "wx-qsearch-input" },
    "What do you want to know?");
  const input = el("input", {
    id: "wx-qsearch-input", class: "wx-qsearch-input", type: "search",
    placeholder: "Search survey questions...", autocomplete: "off",
    "aria-describedby": "wx-qsearch-hint",
    role: "combobox", "aria-expanded": "false",
    "aria-controls": "wx-qsearch-list", "aria-autocomplete": "list"
  });
  const list = el("ul", { id: "wx-qsearch-list", class: "wx-qsearch-list",
                          role: "listbox", hidden: "" });
  const field = el("div", { class: "wx-qsearch-field" }, input, list);
  // Stays visible while typing, unlike a placeholder, and is not cut off on
  // a narrow screen.
  const hint = el("p", { id: "wx-qsearch-hint", class: "wx-qsearch-hint" },
    "Search question text for words or phrases, e.g., risk, flood warning, " +
    "social media");
  wrap.append(label, field, hint);

  let matches = [], active = -1;
  const close = () => {
    list.hidden = true; input.setAttribute("aria-expanded", "false");
    input.removeAttribute("aria-activedescendant"); active = -1;
  };
  const setActive = (i) => {
    active = i;
    [...list.querySelectorAll(".wx-qsearch-opt")].forEach((li, j) => {
      li.classList.toggle("active", j === i);
      li.setAttribute("aria-selected", j === i ? "true" : "false");
      if (j === i) {
        input.setAttribute("aria-activedescendant", li.id);
        li.scrollIntoView({ block: "nearest" });
      }
    });
  };
  const pick = (r) => { input.value = ""; close(); input.blur(); onPick(r); };

  const render = () => {
    const words = norm(input.value).split(/\s+/).filter(Boolean);
    list.textContent = "";
    if (!words.length) { close(); return; }
    const hits = index.filter(x => words.every(w => x.all.includes(w)));
    hits.sort((a, b) =>
      (words.every(w => b.item.includes(w)) - words.every(w => a.item.includes(w))));
    matches = hits.slice(0, LIMIT).map(x => x.row);
    if (!matches.length) {
      list.append(el("li", { class: "wx-qsearch-none" },
        "No questions use those words. Try fewer or different ones."));
    }
    matches.forEach((r, i) => {
      const li = el("li", { class: "wx-qsearch-opt", role: "option",
                            id: `wx-qsearch-opt-${i}`, "aria-selected": "false" });
      if (r.question_intro)
        li.append(el("span", { class: "wx-qsearch-stem" },
          readableWording(r.question_intro, r.id).text));
      li.append(el("span", { class: "wx-qsearch-item" },
          readableWording(r.question_text || r.question, r.id).text),
                el("span", { class: "wx-qsearch-survey" }, r.hazard));
      // mousedown rather than click, so the pick lands before the input's
      // blur closes the list underneath it.
      li.addEventListener("mousedown", (e) => { e.preventDefault(); pick(r); });
      li.addEventListener("mousemove", () => { if (active !== i) setActive(i); });
      list.append(li);
    });
    if (hits.length > LIMIT)
      list.append(el("li", { class: "wx-qsearch-more" },
        `Showing ${LIMIT} of ${hits.length.toLocaleString()} matches. Add a word to narrow them.`));
    list.hidden = false; input.setAttribute("aria-expanded", "true");
    active = -1;
  };

  input.addEventListener("input", render);
  input.addEventListener("focus", () => { if (input.value.trim()) render(); });
  input.addEventListener("blur", close);
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown" && matches.length) {
      e.preventDefault(); if (list.hidden) render();
      setActive(Math.min(active + 1, matches.length - 1));
    } else if (e.key === "ArrowUp" && matches.length) {
      e.preventDefault(); setActive(Math.max(active - 1, 0));
    } else if (e.key === "Enter" && !list.hidden && matches.length) {
      e.preventDefault(); pick(matches[Math.max(active, 0)]);
    } else if (e.key === "Escape") {
      close();
    }
  });
  return wrap;
}

/* ----------------------------------------------- WxDash components ------ */
/* Components for the WxDash bundle (09_build_dashboard.R). They render only
 * precomputed values: ranks, percentiles, medians, srvyr distributions and
 * CIs all come from the bundle, and the engine never computes statistics. */

// Measure catalog helpers (config.catalog rows from the builder).
const catalogByCode = () => new Map(CONFIG.catalog.map(c => [c.code, c]));

/* ---- methodology affordances --------------------------------------------
 * "What does this number mean?" popovers rather than walls of sidebar prose.
 * All text is authored by the builder in config.explainers (templated with
 * {tokens}), so the engine stays generic. Panels open BELOW their trigger. */

// The page's twin of the builder's counted_as(): a count from one survey
// year is adults, a count across several is responses.
function countedAs(years) {
  return /[-,\u2013]/.test(String(years || "")) ? "responses" : "U.S. adults";
}

function fillTpl(s, vals) {
  return String(s || "").replace(/\{(\w+)\}/g, (_, k) => (vals && vals[k] != null) ? vals[k] : "");
}
function explain(key, vals) {
  const t = CONFIG.explainers && CONFIG.explainers[key];
  return t ? fillTpl(t, vals) : null;
}

let openTipClose = null;
document.addEventListener("click", (e) => {
  if (openTipClose && !e.target.closest(".tip-wrap")) openTipClose();
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && openTipClose) openTipClose();
});

function infoTip(html, opts = {}) {
  const wrap = el("span", { class: "tip-wrap" });
  const btn = el("button", {
    class: "tip-btn" + (opts.text ? " text" : ""), type: "button",
    "aria-label": opts.label || opts.text || "What does this mean?",
    "aria-expanded": "false",
    onclick: (e) => { e.stopPropagation(); toggle(); }
  }, opts.text || "?");
  const panel = el("div", { class: "tip-panel", role: "note", html });
  function close() {
    wrap.classList.remove("open");
    btn.setAttribute("aria-expanded", "false");
    if (openTipClose === close) openTipClose = null;
  }
  function toggle() {
    if (wrap.classList.contains("open")) return close();
    if (openTipClose) openTipClose();
    wrap.classList.add("open");
    btn.setAttribute("aria-expanded", "true");
    // keep the panel on-screen: right-align when the trigger sits right of center
    panel.classList.toggle("align-right", btn.getBoundingClientRect().left > window.innerWidth * 0.55);
    openTipClose = close;
  }
  wrap.append(btn, panel);
  // ?tips=open auto-opens a tip — headless-screenshot aid. Opens the first
  // tip created on the page, or the Nth with &tipn=N.
  if (getParam("tips") === "open") {
    infoTip._count = (infoTip._count || 0) + 1;
    if (infoTip._count === (parseInt(getParam("tipn"), 10) || 1)) setTimeout(toggle, 60);
  }
  return wrap;
}

function gradientLegend(title, domain, stops, fmt = (v) => String(Math.round(v))) {
  const wrap = el("div", { class: "wx-legend" });
  wrap.append(el("div", { class: "wx-legend-title", html: title }));
  const bar = el("div", { class: "wx-legend-bar" });
  const colors = [];
  for (let i = 0; i <= 10; i++) colors.push(rampColor(stops, i / 10));
  bar.style.background = `linear-gradient(to right, ${colors.join(",")})`;
  wrap.append(bar);
  wrap.append(el("div", { class: "wx-legend-labels" },
    el("span", {}, fmt(domain[0])),
    el("span", {}, fmt((domain[0] + domain[1]) / 2)),
    el("span", {}, fmt(domain[1]))));
  return wrap;
}

// Tile-free basemap: neutral canvas + state outlines (self-contained bundle,
// no third-party requests).
async function baseMap(mapEl, opts = {}) {
  const map = L.map(mapEl, {
    renderer: L.canvas(),                       // one canvas, not an SVG node per polygon
    attributionControl: false,
    ...opts
  });
  // Fit CONUS rather than a fixed zoom: picks z4 on desktop containers and
  // z3 on phone widths, so the country is never cropped.
  map.fitBounds([[24.5, -125], [49.5, -66.9]]);
  // The state outlines ship with the site source (assets/), not the built
  // data — they are geometry only and never change with a data refresh.
  const states = await fetchJSON("assets/geo/states.geojson");
  const lineColor = getComputedStyle(document.documentElement)
    .getPropertyValue("--map-line").trim() || "#b8b8c0";
  L.geoJSON(states, { style: { color: lineColor, weight: 1, fill: false } }).addTo(map);
  return map;
}

// A theme token, read at build time. Safe to cache per call: switching themes
// re-renders the page, so nothing drawn from these outlives its theme.
function cssVar(name, fallback) {
  const v = getComputedStyle(document.documentElement).getPropertyValue(name);
  return (v && v.trim()) || fallback;
}

// Ink that reads on a given fill (sRGB luma). A constant outline color cannot
// serve both ends of a ramp: grey disappears into the dark end of the greys,
// which is exactly where a comparison map draws the eye.
function inkOn(fill) {
  const t = String(fill);
  let rgb;
  if (t.startsWith("#")) {
    const h = t.length === 4
      ? t.slice(1).split("").map(c => c + c).join("") : t.slice(1);
    rgb = [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16));
  } else {
    const n = t.match(/\d+(\.\d+)?/g);
    if (!n || n.length < 3) return "#111827";
    rgb = n.slice(0, 3).map(Number);
  }
  return (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) > 150
    ? "#111827" : "#ffffff";
}

// One choropleth layer with popups + click selection.
function choroLayer(geo, { idProp, valueOf, color, popupHTML, onSelect, onHover,
                           tooltipHTML }) {
  let selected = null;
  const outline = (id) => ({ weight: 4, color: inkOn(color(valueOf(id))) });
  // A neutral hairline rather than white: white borders vanish at the pale
  // end of a ramp because the map has no background of its own, taking the
  // shape of the lightest areas with them.
  const hairline = cssVar("--map-hairline", "rgba(35, 33, 48, 0.28)");
  const layer = L.geoJSON(geo, {
    style: (f) => ({
      fillColor: color(valueOf(f.properties[idProp])),
      fillOpacity: 0.9, color: hairline, weight: idProp === "FIPS" ? 0.5 : 1,
      opacity: 1
    }),
    onEachFeature: (f, lyr) => {
      const id = f.properties[idProp];
      lyr.bindPopup(() => popupHTML(id, f.properties));
      // Hover-to-read: sticky tooltip with the value.
      if (tooltipHTML) lyr.bindTooltip(() => tooltipHTML(id, f.properties),
        { sticky: true, direction: "top", opacity: 0.96 });
      lyr.on("mouseover", () => {
        lyr.setStyle(outline(id));
        lyr.bringToFront();
        onHover && onHover(id, true);
      });
      lyr.on("mouseout", () => {
        if (selected !== lyr) layer.resetStyle(lyr);
        onHover && onHover(id, false);
      });
      lyr.on("click", () => {
        if (selected) layer.resetStyle(selected);
        selected = lyr;
        onSelect && onSelect(id, f.properties, lyr);
      });
    }
  });
  // fit=false: highlight + popup without moving the view (static maps).
  layer.selectById = (id, map, fit = true, popup = true) => {
    layer.eachLayer(lyr => {
      if (String(lyr.feature.properties[idProp]) === String(id)) {
        if (selected) layer.resetStyle(selected);
        selected = lyr;
        lyr.setStyle(outline(id));
        lyr.bringToFront();
        if (map && fit) map.fitBounds(lyr.getBounds().pad(1.2));
        if (map && popup) lyr.openPopup();
        onSelect && onSelect(id, lyr.feature.properties, lyr);
      }
    });
  };
  // Drops the outline without touching the data: the scan panel's Clear has
  // to leave the map looking like nothing was ever picked.
  layer.clearSelection = () => {
    if (selected) { layer.resetStyle(selected); selected = null; }
  };
  // Outline an area without selecting it. Side-by-side comparison uses this
  // to make the twin map follow the area under the cursor on this one — the
  // two pictures are of the same 116 places, and the eye cannot find the
  // matching polygon on its own.
  layer.peekById = (id, on) => {
    layer.eachLayer(lyr => {
      if (String(lyr.feature.properties[idProp]) !== String(id)) return;
      if (on) { lyr.setStyle(outline(id)); lyr.bringToFront(); }
      else if (selected !== lyr) layer.resetStyle(lyr);
    });
  };
  return layer;
}

/* ---- map-story helpers ------------------------------------------------- */

function ordinal(n) {
  const mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return n + "th";
  if (n % 10 === 1) return n + "st";
  if (n % 10 === 2) return n + "nd";
  if (n % 10 === 3) return n + "rd";
  return n + "th";
}

// What a code measures, read off its shape (TO_RECEP → RECEP, ALERT_TORN →
// ALERT…). Drives the popup's "{quantity}" phrase from config.map.quantities.
function constructOf(code) {
  if (code.startsWith("ALERT_")) return "ALERT";
  if (code.startsWith("RISK_")) return "RISK";
  if (code.endsWith("_SUBJ_COMP")) return "SUBJ_COMP";
  if (code.endsWith("_RECEP")) return "RECEP";
  return "RESP";
}

function hazardOfLabel(label) {
  return String(label)
    .replace(/ warning (reception|comprehension|response)$/, "")
    .replace(/ risk perceptions$/, "")
    .replace(/ alert days per year$/, "")
    .toLowerCase();
}

// All areas on one axis with this one marked — the popup's context in one
// glance. Colors ride the theme's CSS variables so dark themes stay legible.
function stripPlotSVG(values, here, median, fmt) {
  const width = 280, pad = 10;
  const lo = Math.min(...values), hi = Math.max(...values);
  const at = (v) => hi === lo ? width / 2
    : +(pad + (v - lo) / (hi - lo) * (width - 2 * pad)).toFixed(1);
  const ticks = values.map(v => `M${at(v)} 12v14`).join("");
  const mid = at(median);
  return `<svg width="${width}" height="52" class="wx-strip" ` +
    `style="display:block;margin:8px 0 2px">` +
    `<path d="${ticks}" stroke="var(--map-line, #b8bec5)" stroke-width="1"/>` +
    `<path d="M${mid - 4} 34L${mid} 28L${mid + 4} 34Z" fill="var(--text-muted, #6e737a)"/>` +
    `<text x="${mid}" y="44" font-size="9" fill="var(--text-muted, #6e737a)" ` +
    `text-anchor="middle">median</text>` +
    `<circle cx="${at(here)}" cy="19" r="4.5" fill="var(--text, #111827)"/>` +
    `<text x="${pad}" y="9" font-size="10" fill="var(--text-muted, #6e737a)">${fmt(lo)}</text>` +
    `<text x="${width - pad}" y="9" font-size="10" fill="var(--text-muted, #6e737a)" ` +
    `text-anchor="end">${fmt(hi)}</text></svg>`;
}

// One row of the scan sheet — the popup strip at a size that repeats down a
// page: every area a tick, the median a triangle, this area a filled dot. The
// range ends print in their own columns rather than inside the SVG, so they
// line up down the sheet instead of drifting with each measure's width.
function scanStripSVG(values, here, median, lo, hi, W = 210) {
  const H = 16, pad = 6;
  const at = (v) => hi === lo ? W / 2
    : +(pad + (v - lo) / (hi - lo) * (W - 2 * pad)).toFixed(1);
  const ticks = values.map(v => `M${at(v)} 4v8`).join("");
  const mid = at(median);
  return `<svg class="wx-scan-strip" width="${W}" height="${H}" ` +
    `viewBox="0 0 ${W} ${H}" aria-hidden="true">` +
    `<path d="${ticks}" stroke="var(--map-line, #b8bec5)" stroke-width="1"/>` +
    `<path d="M${mid - 3.5} 15.5L${mid} 11L${mid + 3.5} 15.5Z" ` +
    `fill="var(--text-muted, #6e737a)"/>` +
    `<circle cx="${at(here)}" cy="8" r="4" fill="var(--accent, #443a83)" ` +
    `stroke="var(--panel, #ffffff)" stroke-width="1.2"/></svg>`;
}

// Config prose arrives as HTML; the PDF takes text. Going through a detached
// element decodes the entities too, so "measure&rsquo;s" does not reach the
// sheet as markup.
function plainText(html) {
  const d = document.createElement("div");
  // Block ends become spaces first: textContent runs two paragraphs together
  // into one word where the markup was the only thing separating them.
  d.innerHTML = String(html || "").replace(/<\/(p|div|li|h[1-6])>/gi, " ");
  return (d.textContent || "").replace(/\s+/g, " ").trim();
}

/* Map Explorer: estimates and alert layers. Controls across the top, a
 * fixed-frame full-width CWA map, hover tooltips, a click popup with the
 * full place story (value, rank, percentile, median, strip plot), and
 * per-measure notes below. Comparison is ONE thing, the NWS alert-day
 * history the measure's model is fitted on, drawn as a second map beside the
 * first so both pictures are on screen at once. */
components.wx_map_explorer = async function (page, container) {
  const cats = CONFIG.catalog;
  const byCode = catalogByCode();
  let measure = getParam("measure") || page.default_measure || cats[0].code;
  if (!byCode.get(measure)) measure = cats[0].code;
  let scheme = urlScheme();   // shared ?scheme= with the survey explorer

  const cwaValues = await fetchJSON("data/map/cwa_values.json");
  const geo = await fetchJSON("data/geo/cwa.geojson");
  const N = cwaValues.areas;
  const M = (code) => cwaValues.measures[code];
  const isAlert = (code) => byCode.get(code).kind === "alert";
  // Estimates print as "3.42 out of 5"; alert days per year to one decimal,
  // "4.2", with none of the false precision of the two the file carries.
  const fmtVal = (code) => (v) => isAlert(code)
    ? Number(v).toFixed(1) : Number(v).toFixed(2);
  const fmtRange = (code) => (v) => Number(v).toFixed(1);

  // Comparison state: one alert layer, drawn as a second map beside the
  // first, so the reader compares two pictures rather than holding one in
  // memory. ?compare= deep-links it.
  const alertCats = cats.filter(c => c.kind === "alert");
  let compare = alertCats.some(c => c.code === getParam("compare"))
    ? getParam("compare") : "";
  setParams({ mix: null });   // drops ?mix=, which nothing reads, from shared links

  // --- top control bar (controls across the top, full-width map below)
  const lead = pageHead(page);
  // What is on the map, named above the controls the way the survey page
  // names its question: a small label, then the measure. The same label and
  // title the map's download carries.
  const mapHead = el("div", { class: "wx-result-head" });
  const mapKind = el("p", { class: "wx-result-survey" });
  const mapTitle = el("h2", { class: "wx-question-head wx-result-item" });
  mapHead.append(mapKind, mapTitle);

  // The controls sit on the page, not in a card, as they do above the survey
  // chart; the map is the one card.
  const bar = el("div", { class: "wx-result-controls wx-map-toolbar" });
  const measureSel = el("select", { class: "grouping", id: "measure-sel", onchange: () => {
    measure = measureSel.value; setParams({ measure }, true);
    // A live comparison follows the measure to ITS paired alert history
    // (the exposure its model is fitted on) — or turns off when there is
    // none (drought, hail, lightning have no NWS alert product).
    if (compare) {
      compare = byCode.get(measure).compare_default || "";
      syncCompare();
    }
    redraw();
  } });
  const groupsSeen = [...new Set(cats.map(c => c.group))];
  for (const g of groupsSeen) {
    const og = el("optgroup", { label: g });
    for (const c of cats.filter(x => x.group === g))
      og.append(el("option", { value: c.code }, c.label));
    measureSel.append(og);
  }
  measureSel.value = measure;
  const measureWrap = el("div");
  measureWrap.append(el("label", { class: "field-label", for: "measure-sel" },
    "What do you want to explore?"), measureSel);

  const compareWrap = el("div");
  const compareSel = el("select", { class: "grouping", id: "compare-sel", onchange: async () => {
    compare = compareSel.value;
    setParams({ compare: compare || null }, true);
    await redraw();
  } });
  compareWrap.append(el("label", { class: "field-label", for: "compare-sel" },
    "Compare with alert history"), compareSel,
    el("p", { class: "wx-field-hint" },
      "Optional: compare community estimates with local alert history"));
  // Rebuilt per measure: the paired alert layer is marked, and measures
  // without one (NRI-modeled: drought, hail, lightning) say so.
  function syncCompare() {
    const def = byCode.get(measure).compare_default;
    compareSel.textContent = "";
    compareSel.append(el("option", { value: "" }, "None"));
    for (const c of alertCats) {
      compareSel.append(el("option", { value: c.code },
        c.label + (c.code === def ? " — matches this measure" : "")));
    }
    if (compare && !alertCats.some(c => c.code === compare)) compare = "";
    compareSel.value = compare;
    compareWrap.title = def ? "" :
      "This measure has no matching NWS alert product; its model uses FEMA National Risk Index frequencies instead.";
  }
  syncCompare();

  // A forecast office can be chosen from a list as well as from the map,
  // so everything the map does is reachable from the keyboard. It follows
  // the map: a click there shows here, and Clear empties it.
  const placeWrap = el("div");
  const placeSel = el("select", { class: "grouping", id: "place-sel", onchange: () => {
    if (!placeSel.value) { clearPlace(); return; }
    if (activeLayer) activeLayer.selectById(placeSel.value, map, false, true);
  } });
  placeSel.append(el("option", { value: "" }, "None selected"),
    ...Object.entries(cwaValues.places)
      .sort((a, b) => a[1].label.localeCompare(b[1].label))
      .map(([code, p]) => el("option", { value: code }, p.label)));
  placeWrap.append(el("label", { class: "field-label", for: "place-sel" },
    "Forecast office"), placeSel);

  bar.append(measureWrap, compareWrap, placeWrap);
  // Color is a setting, not a question, so it folds away as it does under
  // the survey chart: open from the start only when a link has set it.
  const colors = el("details", { class: "wx-chart-options wx-map-options" });
  if (scheme !== DEFAULT_SCHEME) colors.open = true;
  colors.append(el("summary", {}, "Map options"),
    el("div", { class: "wx-chart-options-body" },
      schemeSelect(scheme, async (sc) => {
        scheme = sc;
        setParams({ scheme: sc === DEFAULT_SCHEME ? null : sc });
        await redraw();
      })));
  bar.append(el("div", { class: "wx-map-options-wrap" }, colors));
  // On the map, where the area was picked, not among the settings; shown
  // only while an area is selected. Placed on the map card below.
  const clearBtn = el("button", { class: "wx-clear-btn wx-map-clear",
    type: "button", onclick: () => clearPlace() }, "Clear selection");
  clearBtn.style.display = "none";

  // --- full-width map card + per-measure notes card below
  // One pane normally; two side by side while comparing. Each pane carries
  // its own heading and legend, so neither map has to borrow the other's.
  const card = el("div", { class: "card wx-map-card wx-map-fullwidth" });
  const pane = (cls) => {
    const title = el("p", { class: "wx-map-pane-title" });
    const mapEl = el("div", { class: "wx-map" });
    const legend = el("div", { class: "wx-legend-row" });
    return { el: el("div", { class: "wx-map-pane " + cls }, title, mapEl, legend),
             title, mapEl, legend };
  };
  const paneA = pane("wx-pane-a"), paneB = pane("wx-pane-b");
  const mapEl = paneA.mapEl, mapElB = paneB.mapEl;
  const legendHolder = paneA.legend, legendHolderB = paneB.legend;
  const pairEl = el("div", { class: "wx-map-pair" }, paneA.el, paneB.el);
  const mapAlt = el("div", { class: "wx-sr-only" });
  card.append(clearBtn, pairEl,
    el("p", { class: "wx-field-hint wx-map-hint" },
      "Hover an area to see its value; click it to see every measure for " +
      "that community."));

  /* The map as a figure (figureImage), the same picture and resolution as a
   * chart on Explore Survey Questions: the one or two maps redrawn as
   * vectors, each with its legend, over the note's opening sentence and the
   * sources. Taken from the maps as they stand, so it shows whatever frame,
   * colors and selection are on screen. */
  function mapImage() {
    const bg = getComputedStyle(document.body).getPropertyValue("--panel").trim() || "#ffffff";
    const cat = byCode.get(measure), cmp = compare ? byCode.get(compare) : null;
    const inner = FIGURE.W - FIGURE.pad * 2, gap = 28;
    const views = [{ lmap: map, title: cat.label, legend: lastLegend }];
    if (cmp && mapB) views.push({ lmap: mapB, title: cmp.label, legend: lastLegendB });
    const colW = (inner - gap * (views.length - 1)) / views.length;
    for (const v of views) {
      v.img = vectorMap(v.lmap, FIGURE.S, bg);
      v.h = colW * v.img.height / v.img.width;
    }
    const titleH = views.length > 1 ? 26 : 0, legendH = 56;
    const mapH = Math.max(...views.map(v => v.h));
    const drawLegend = (ctx, leg, x, y, w, t) => {
      if (!leg) return;
      ctx.font = `600 12px ${t.family}`; ctx.fillStyle = t.muted;
      ctx.fillText(leg.title.replace(" \u2014 ", " \u00b7 "), x, y + 12);
      const grad = ctx.createLinearGradient(x, 0, x + w, 0);
      for (let i = 0; i <= 10; i++) grad.addColorStop(i / 10, rampColor(leg.stops, i / 10));
      ctx.fillStyle = grad; ctx.fillRect(x, y + 20, w, 10);
      ctx.font = `400 12px ${t.family}`; ctx.fillStyle = t.muted;
      const [lo, hi] = leg.domain, f = leg.fmt || ((v) => String(v));
      ctx.textAlign = "left"; ctx.fillText(f(lo), x, y + 46);
      ctx.textAlign = "center"; ctx.fillText(f((lo + hi) / 2), x + w / 2, y + 46);
      ctx.textAlign = "right"; ctx.fillText(f(hi), x + w, y + 46);
      ctx.textAlign = "left";
    };
    const alerts = isAlert(measure) || !!cmp;
    // The question respondents were asked, from the measure's own notes, in
    // the slot the chart gives its stem. Alert histories were not asked.
    let asked = "";
    const mine = notesCard.querySelector(".wx-note-half") || notesCard;
    for (const p of mine.querySelectorAll("p")) {
      const t = p.textContent;
      if (/^Respondents were asked:/.test(t)) {
        asked = t.replace(/^Respondents were asked:\s*/, "").replace(/^[\u201c"]|[\u201d"]$/g, "");
        break;
      }
    }
    return figureImage({
      label: isAlert(measure) ? "Alert history" : "Community estimates",
      stem: asked,
      title: cat.label + (cmp ? " and " + cmp.label.charAt(0).toLowerCase() +
                                cmp.label.slice(1) : ""),
      body: {
        height: titleH + mapH + 14 + legendH,
        draw: (ctx, x, y, w, t) => views.forEach((v, i) => {
          const vx = x + i * (colW + gap);
          if (titleH) {
            ctx.font = `600 12px ${t.mono}`; ctx.fillStyle = t.ink;
            ctx.fillText(v.title.toUpperCase(), vx, y + 14);
          }
          ctx.drawImage(v.img, vx, y + titleH + (mapH - v.h) / 2, colW, v.h);
          drawLegend(ctx, v.legend, vx, y + titleH + mapH + 14, Math.min(360, colW), t);
        })
      },
      // A facts line of the chart's form - the count first, then the scope -
      // over a sentence saying what the colors show, as the chart's second
      // line says what the bars are. Built from the phrases the popups use,
      // so the picture and the page describe a measure in the same words.
      lines: [{ text: `${N} National Weather Service forecast office areas \u00b7 ` +
                      "contiguous United States", strong: true },
              ...[measure, compare].filter(Boolean).map(code => {
                const quantity = fillTpl(CONFIG.map.quantities[constructOf(code)],
                  { hazard: hazardOfLabel(byCode.get(code).label) });
                const says = isAlert(code)
                  ? `colors show the average number of days a year with ${quantity} in each area` +
                    (M(code).span ? ` between ${M(code).span}` : "") + "."
                  : `colors show each area's estimate of ${quantity}, on a 1 to 5 scale.`;
                return { text: cmp ? `${byCode.get(code).label}: ${says}`
                                   : says.charAt(0).toUpperCase() + says.slice(1) };
              })],
      // An alert history alone owes nothing to the survey, so it names only
      // its own source.
      source: isAlert(measure) && !cmp
        ? "Source: National Weather Service alert records from the Iowa " +
          "Environmental Mesonet."
        : FIGURE_SOURCE + " Community estimates combine the survey with US " +
          "Census population data." +
          (alerts ? " Alert days are National Weather Service records from " +
                    "the Iowa Environmental Mesonet." : "")
    });
  }
  const mapName = (ext) =>
    `wxdash-map-${measure}${compare ? "-vs-" + compare : ""}.${ext}`;
  // At the foot of the map, as under a chart on Explore Survey Questions.
  card.append(el("div", { class: "wx-toolbar-actions wx-result-downloads" },
    pdfButton("Download map (PNG)", () => saveFigure(mapImage(), mapName("png"), "png")),
    pdfButton("Download map (PDF)", () => saveFigure(mapImage(), mapName("pdf"), "pdf"))));
  const notesCard = el("div", { class: "card wx-map-notes" });
  const scanCard = el("div", { class: "card wx-scan-card" });
  // Notes first, then the scan sheet: what the map is showing has to be read
  // before one area's standing on it means anything.
  container.append(el("div", { class: "page wx-explore-page wx-map-page" },
    el("div", { class: "content" }, lead,
       el("section", { class: "wx-result" }, mapHead, bar, card),
       notesCard, scanCard)));

  // Fixed-frame map: the page scrolls normally over it, with no
  // scroll-wheel zoom trap, no drag, no zoom buttons. CONUS fills the frame.
  const CONUS = [[24.5, -125], [49.5, -66.9]];
  const FIXED_FRAME = {
    zoomControl: false, dragging: false, scrollWheelZoom: false,
    doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false,
    // Fractional zoom so fitBounds can truly fill the frame at any width —
    // integer snapping leaves the CONUS floating small between zoom levels.
    // Safe here: the map is static, nobody zooms by hand.
    zoomSnap: 0.1
  };
  const refit = (m) => { if (m) { m.invalidateSize(); m.fitBounds(CONUS); } };
  const map = await baseMap(mapEl, FIXED_FRAME);

  // The second map is built the first time a comparison is asked for, and
  // kept afterwards. Built only while its pane is visible: Leaflet reads the
  // container size at construction, and a hidden container gives it the
  // 400x300 fallback that renders nothing.
  let mapB = null;
  async function ensureMapB() {
    if (!mapB) mapB = await baseMap(mapElB, FIXED_FRAME);
    return mapB;
  }

  // The frames are fluid (full-bleed page, and each halves when the second
  // map appears): re-render and re-frame CONUS whenever a container changes
  // size, so the maps scale with the window instead of cropping.
  let refitTimer = null;
  new ResizeObserver(() => {
    clearTimeout(refitTimer);
    refitTimer = setTimeout(() => { refit(map); refit(mapB); }, 120);
  }).observe(pairEl);

  let activeLayer = null;
  let compareLayer = null;
  let lastLegend = null;    // domain/stops/title of each view, for the PDF
  let lastLegendB = null;

  // --- scan sheet: every measure for one area, under the map. It computes
  // nothing: values, medians and
  // percentiles are the ones cwa_values.json already carries, so a row and
  // the popup above it cannot disagree.
  const scanCfg = (CONFIG.map && CONFIG.map.scan) || {};
  let place = (getParam("place") || "").toUpperCase();
  if (place && !cwaValues.places[place]) place = "";

  function clearPlace() {
    place = "";
    placeSel.value = "";
    setParams({ place: null }, true);
    if (activeLayer) activeLayer.clearSelection();
    if (compareLayer) compareLayer.clearSelection();
    map.closePopup();
    if (mapB) mapB.closePopup();
    // A popup auto-pans to stay in view, which shifts a frame that is
    // otherwise fixed. Clearing puts CONUS back where it started.
    refit(map);
    refit(mapB);
    renderScan();
  }

  function scanRow(cat) {
    const m = M(cat.code);
    return {
      cat,
      values: Object.values(m.values).filter(v => v != null).map(Number),
      here: Number(m.values[place]),
      median: Number(m.median),
      lo: Number(m.domain[0]), hi: Number(m.domain[1]),
      pct: m.pct[place]
    };
  }

  // The sheet in the order the measure menu lists it, so the row someone is
  // hunting for sits where the dropdown taught them to look.
  function scanSections() {
    return groupsSeen.map(g => {
      const rows = cats.filter(c => c.group === g);
      return {
        group: g,
        // A whole group of alert layers is days a year rather than a 1-5
        // estimate, and the Estimate column heading would otherwise read as
        // a claim about the counts.
        unit: rows.every(c => c.kind === "alert") ? "days per year" : "",
        rows
      };
    });
  }

  /* The overview sheet as a figure (figureImage), the same picture and
   * resolution as the chart and map downloads: the key, the column heads and
   * every row redrawn at the figure's density with the marks the page uses,
   * under the area's name and over the sheet's own lede and note. */
  function scanImage() {
    const label = (cwaValues.places[place] || {}).label || place;
    const sections = scanSections();
    const rowH = 26, groupH = 30, keyH = 30, headH = 22;
    const nRows = sections.reduce((t, s) => t + s.rows.length, 0);
    const css = getComputedStyle(document.body);
    const tickColor = css.getPropertyValue("--map-line").trim() || "#b8bec5";
    const bg = css.getPropertyValue("--panel").trim() || "#ffffff";
    const draw = (ctx, x, y, w, t) => {
      const SW = 420;
      const X = { label: x, lo: x + 380, strip: x + 392, hi: x + 392 + SW + 12,
                  value: x + w - 130, pct: x + w };
      const text = (str, px, py, font, color, align = "left") => {
        ctx.font = font; ctx.fillStyle = color; ctx.textAlign = align;
        ctx.fillText(str, px, py); ctx.textAlign = "left";
      };
      const tick = (px, cy, h) => {
        ctx.strokeStyle = tickColor; ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(px, cy - h); ctx.lineTo(px, cy + h); ctx.stroke();
      };
      const tri = (px, top) => {
        ctx.fillStyle = t.muted; ctx.beginPath();
        ctx.moveTo(px - 4, top + 6); ctx.lineTo(px + 4, top + 6); ctx.lineTo(px, top);
        ctx.closePath(); ctx.fill();
      };
      const dot = (px, cy) => {
        ctx.fillStyle = t.accent; ctx.strokeStyle = bg; ctx.lineWidth = 1.4;
        ctx.beginPath(); ctx.arc(px, cy, 5, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      };
      // The key, drawn rather than spelled out.
      let kx = x; const ky = y + 14;
      const keyItem = (mark, words) => {
        mark(kx + 5); text(words, kx + 16, ky + 4, `400 13px ${t.family}`, t.muted);
        ctx.font = `400 13px ${t.family}`; kx += 16 + ctx.measureText(words).width + 26;
      };
      keyItem(px => tick(px, ky, 6), `each of the ${N} areas`);
      keyItem(px => tri(px, ky - 3), "median");
      keyItem(px => dot(px, ky), "this area");
      let cy = y + keyH;
      const head = `600 11px ${t.mono}`;
      text("LOWEST AREA TO HIGHEST AREA", X.strip + SW / 2, cy + 12, head, t.muted, "center");
      text("ESTIMATE", X.value, cy + 12, head, t.muted, "right");
      text("PERCENTILE", X.pct, cy + 12, head, t.muted, "right");
      cy += headH;
      for (const sec of sections) {
        ctx.fillStyle = t.ink; ctx.fillRect(x, cy, w, groupH - 6);
        text(String(sec.group).toUpperCase(), x + 10, cy + 16, `700 12px ${t.family}`, bg);
        if (sec.unit) text(String(sec.unit).toUpperCase(), x + w - 10, cy + 16,
                           `700 12px ${t.family}`, bg, "right");
        cy += groupH;
        sec.rows.forEach((cat, i) => {
          const r = scanRow(cat), mid = cy + rowH / 2;
          if (i % 2) {
            ctx.globalAlpha = 0.05; ctx.fillStyle = t.ink; ctx.fillRect(x, cy, w, rowH);
            ctx.globalAlpha = 1;
          }
          text(cat.label, X.label + 6, mid + 5, `400 14px ${t.family}`, t.ink);
          text(fmtRange(cat.code)(r.lo), X.lo, mid + 4, `400 12px ${t.family}`, t.muted, "right");
          text(fmtRange(cat.code)(r.hi), X.hi, mid + 4, `400 12px ${t.family}`, t.muted);
          const span = r.hi - r.lo;
          const at = (v) => span === 0 ? X.strip + SW / 2
            : X.strip + 6 + (v - r.lo) / span * (SW - 12);
          for (const v of r.values) tick(at(v), mid, 6);
          tri(at(r.median), mid + 4);
          dot(at(r.here), mid);
          text(fmtVal(cat.code)(r.here), X.value, mid + 5, `700 14px ${t.family}`, t.ink, "right");
          text(ordinal(r.pct), X.pct, mid + 5, `400 13px ${t.family}`, t.muted, "right");
          cy += rowH;
        });
      }
    };
    return figureImage({
      label: "Community overview",
      stem: `County Warning Area ${place} · ${cats.length} measures`,
      title: label,
      body: { height: keyH + headH + sections.length * groupH + nRows * rowH, draw },
      lines: [{ text: `${N} National Weather Service forecast office areas · ` +
                      "contiguous United States", strong: true },
              ...[scanCfg.lede, scanCfg.note].filter(Boolean)
                .map(h => ({ text: plainText(h) }))],
      source: FIGURE_SOURCE + " Community estimates combine the survey with US " +
              "Census population data. Alert days are National Weather Service " +
              "records from the Iowa Environmental Mesonet."
    });
  }
  const scanName = (ext) => `wxdash-overview-${place.toLowerCase()}.${ext}`;

  const KEY_MARKS = [
    ['<svg width="9" height="12"><path d="M4.5 1v10" stroke="var(--map-line,#b8bec5)"/></svg>',
     `each of the ${N} areas`],
    ['<svg width="9" height="12"><path d="M1 9L4.5 4L8 9Z" fill="var(--text-muted,#6e737a)"/></svg>',
     "median"],
    ['<svg width="9" height="12"><circle cx="4.5" cy="6" r="4" fill="var(--accent,#443a83)"/></svg>',
     "this area"]
  ];

  function renderScan() {
    scanCard.textContent = "";
    clearBtn.style.display = place ? "" : "none";
    if (!place) { scanCard.style.display = "none"; return; }
    scanCard.style.display = "";
    const label = (cwaValues.places[place] || {}).label || place;

    scanCard.append(el("div", { class: "wx-scan-head" },
      el("h3", { class: "wx-scan-sub wx-scan-heading" },
        `Community overview \u00b7 ${label} \u00b7 ${cats.length} measures`),
      el("div", { class: "wx-scan-actions" },
        el("button", { class: "wx-clear-btn", type: "button",
          onclick: () => clearPlace() }, "Clear"))));

    if (scanCfg.lede) scanCard.append(el("div", { class: "wx-scan-lede", html: scanCfg.lede }));
    scanCard.append(el("p", { class: "wx-scan-key", html: KEY_MARKS
      .map(([mark, text]) => `<span>${mark} ${esc(text)}</span>`).join("") +
      `<span class="wx-scan-hint">Select a row to map it.</span>` }));

    const table = el("div", { class: "wx-scan-table" });
    table.append(el("div", { class: "wx-scan-cols" },
      el("span", {}), el("span", {}),
      el("span", { class: "wx-scan-colhead wx-scan-center" },
        "Lowest area to highest area"),
      el("span", {}),
      el("span", { class: "wx-scan-colhead wx-scan-right" }, "Estimate"),
      el("span", { class: "wx-scan-colhead wx-scan-right" }, "Percentile")));

    for (const s of scanSections()) {
      table.append(el("div", { class: "wx-scan-group" },
        el("span", {}, s.group),
        s.unit ? el("span", { class: "wx-scan-unit" }, s.unit) : null));
      s.rows.forEach((cat, i) => {
        const r = scanRow(cat);
        // The whole row is the control: a reader scanning 33 measures for the
        // one worth a map should not have to find a separate link for it.
        table.append(el("button", {
          type: "button",
          class: "wx-scan-row" + (i % 2 ? " is-band" : "") +
            (cat.code === measure ? " is-current" : ""),
          title: `Map ${cat.label}`,
          onclick: () => {
            measure = cat.code;
            measureSel.value = cat.code;
            setParams({ measure }, true);
            if (compare) {
              compare = byCode.get(measure).compare_default || "";
              syncCompare();
            }
            redraw();
          }
        },
          el("span", { class: "wx-scan-label" }, cat.label),
          el("span", { class: "wx-scan-lo" }, fmtRange(cat.code)(r.lo)),
          el("span", { class: "wx-scan-plot",
            html: scanStripSVG(r.values, r.here, r.median, r.lo, r.hi, stripWidth) }),
          el("span", { class: "wx-scan-hi" }, fmtRange(cat.code)(r.hi)),
          el("span", { class: "wx-scan-value" }, fmtVal(cat.code)(r.here)),
          el("span", { class: "wx-scan-pct" }, ordinal(r.pct))));
      });
    }
    scanCard.append(table);
    if (scanCfg.note) scanCard.append(el("div", { class: "wx-scan-note", html: scanCfg.note }));
    // At the foot of the sheet, as under the chart and the map.
    scanCard.append(el("div", { class: "wx-toolbar-actions wx-result-downloads" },
      pdfButton("Download overview (PNG)", () => saveFigure(scanImage(), scanName("png"), "png")),
      pdfButton("Download overview (PDF)", () => saveFigure(scanImage(), scanName("pdf"), "pdf"))));
    fitStrips();
  }

  // The strip column is elastic — the sheet runs the width of the page — so
  // the marks are drawn at the width the column actually got rather than a
  // fixed 210px, which would leave them bunched at one end of a wide cell.
  // Measured after layout, because a grid track has no width until then.
  let stripWidth = 210;
  function fitStrips() {
    const cells = scanCard.querySelectorAll(".wx-scan-plot");
    if (!cells.length) return;
    const w = Math.round(cells[0].getBoundingClientRect().width);
    if (!w || Math.abs(w - stripWidth) < 2) return;
    stripWidth = w;
    let i = 0;
    for (const s of scanSections()) {
      for (const cat of s.rows) {
        const r = scanRow(cat);
        cells[i++].innerHTML =
          scanStripSVG(r.values, r.here, r.median, r.lo, r.hi, stripWidth);
      }
    }
  }
  let stripTimer = null;
  new ResizeObserver(() => {
    clearTimeout(stripTimer);
    stripTimer = setTimeout(fitStrips, 120);
  }).observe(scanCard);

  // The popup's link into the sheet. Delegated on the container because
  // Leaflet rebuilds the popup element on every open.
  container.addEventListener("click", (e) => {
    const link = e.target.closest(".wx-scan-link");
    if (!link) return;
    e.preventDefault();
    place = String(link.dataset.place || "").toUpperCase();
    setParams({ place }, true);
    // Through the layers rather than straight to renderScan, so the area is
    // outlined on the maps as well as filled in below them.
    selectPlace(place);
    scanCard.scrollIntoView({ behavior: "smooth", block: "start" });
  });

  // The popup's one-paragraph place story (templates from config.map.popup).
  // rank/pct/median are precomputed by the builder; the engine only assembles
  // the sentence.
  function popupStory(id, code) {
    const cat = byCode.get(code);
    const m = M(code);
    const here = m.values[id];
    if (here == null) return "No data for this area.";
    const rank = m.rank[id], pct = m.pct[id];
    const alert = isAlert(code);
    const noun = alert ? "count" : "estimate";
    const quantity = fillTpl(CONFIG.map.quantities[constructOf(code)],
      { hazard: hazardOfLabel(cat.label) });
    // Naming the quantity lets the sentence work at any rank — a comparative
    // would be false in the middle of the distribution.
    let standing;
    if (rank === 1) standing = `has the highest ${noun} of the ${N}`;
    else if (rank === N) standing = `has the lowest ${noun} of the ${N}`;
    else if (rank <= N / 2) standing = `ranks ${ordinal(rank)} highest of the ${N}`;
    else standing = `ranks ${ordinal(rank)} of the ${N}`;
    return fillTpl(alert ? CONFIG.map.popup.alert : CONFIG.map.popup.estimate, {
      value: fmtVal(code)(here), quantity, n: N,
      median: fmtVal(code)(m.median), standing,
      percentile: ordinal(pct), span: m.span || ""
    });
  }

  // One picked area, both maps. selectById calls back into here, so the
  // guard is what stops the two layers handing the selection to each other.
  let syncing = false;
  function selectPlace(id) {
    place = String(id);
    placeSel.value = place;
    setParams({ place }, true);
    renderScan();
    if (syncing) return;
    syncing = true;
    if (activeLayer) activeLayer.selectById(place, null, false, false);
    if (compareLayer) compareLayer.selectById(place, null, false, false);
    syncing = false;
  }

  // One choropleth, built the same way for either pane. Colors stretch over
  // the measure's own observed range: on a shared 1-5
  // scale the warning measures would all come out one flat mid tone.
  function buildChoro(code, targetMap, stops, twin) {
    const cat = byCode.get(code);
    const m = M(code);
    const d = m.domain;
    const color = (v) => v == null ? "#d0d0d0"
      : rampColor(stops, (v - d[0]) / (d[1] - d[0]));
    const values = Object.values(m.values).filter(v => v != null).map(Number);
    return choroLayer(geo, {
      idProp: "CWA",
      valueOf: (id) => m.values[id],
      color,
      onSelect: (id) => selectPlace(id),
      onHover: (id, on) => { const t = twin(); if (t) t.peekById(id, on); },
      // Both numbers ride in either map's tooltip while comparing: the point
      // of the pairing is the two read together, and moving the cursor to
      // the other map to get the second one loses the first.
      tooltipHTML: (id, props) => {
        const other = compare ? (code === measure ? compare : measure) : null;
        const line = (c) => {
          const v = M(c).values[id];
          return `<span class="wx-tt-val">${esc(byCode.get(c).label)} ` +
            `${v == null ? "no data" : fmtVal(c)(v)}</span>`;
        };
        return `<strong>${esc(props.CWA_DISPLAY || id)}</strong><br>` + line(code) +
          (other ? "<br>" + line(other) : "") +
          `<br><span class="wx-tip-hint">Click for the full story</span>`;
      },
      popupHTML: (id, props) =>
        `<strong>${esc(props.CWA_DISPLAY || id)} (${esc(String(id))})</strong>` +
        `<br><br>` + esc(popupStory(id, code)) +
        stripPlotSVG(values, Number(m.values[id]), Number(m.median),
                     fmtRange(code)) +
        `<a class="wx-scan-link" href="#" data-place="${esc(String(id))}">` +
        `See every measure for this area &darr;</a>`
    }).addTo(targetMap);
  }

  // Paired, the pane heading already names the measure, so the legend says
  // only what the numbers are; alone, it has to carry the label itself.
  function drawLegend(holder, code, stops, withLabel) {
    holder.textContent = "";
    const m = M(code);
    // The counting period beside the alert colors, and the modeled nature of
    // an estimate beside its colors, so neither is read without it.
    const kind = isAlert(code)
      ? "Alert days per year" + (m.span ? ", " + String(m.span).replace(" and ", "\u2013") : "")
      : "Modeled estimate (1\u20135 scale; colors span the observed range)";
    // An alert legend already says "alert days per year", so its label adds
    // only the hazard rather than repeating the phrase.
    const named = isAlert(code)
      ? (h => h.charAt(0).toUpperCase() + h.slice(1))(hazardOfLabel(byCode.get(code).label))
      : byCode.get(code).label;
    holder.append(gradientLegend(
      withLabel ? kind + " \u2014 " + esc(named) : kind,
      m.domain, stops, fmtRange(code)));
    return { title: kind + " \u2014 " + named,
             domain: m.domain, stops, fmt: fmtRange(code) };
  }

  async function redraw() {
    const cat = byCode.get(measure);
    const compareCat = compare ? byCode.get(compare) : null;
    const stops = dataStops(schemeStops(scheme));
    // Contrasting ramp so the two maps stay tellable apart at a glance:
    // grey normally, blue when the main scheme is already grey.
    const compareStops = dataStops(scheme === "grey" ? BLUES_STOPS : GREYS_STOPS);

    // The pane has to be laid out before Leaflet measures it, and both
    // frames change width the moment the second one appears.
    pairEl.classList.toggle("is-paired", !!compare);
    paneB.el.style.display = compare ? "" : "none";
    if (compare) await ensureMapB();
    refit(map);
    refit(mapB);

    paneA.title.textContent = cat.label;
    mapKind.textContent = isAlert(measure) ? "Alert history" : "Community estimates";
    mapTitle.textContent = cat.label + (compareCat
      ? " and " + compareCat.label.charAt(0).toLowerCase() + compareCat.label.slice(1)
      : "");
    paneB.title.textContent = compareCat ? compareCat.label : "";

    if (activeLayer) map.removeLayer(activeLayer);
    activeLayer = buildChoro(measure, map, stops, () => compareLayer);

    if (compareLayer) { mapB.removeLayer(compareLayer); compareLayer = null; }
    if (compare) compareLayer = buildChoro(compare, mapB, compareStops,
                                           () => activeLayer);

    // The map's text alternative: a spoken label, and every office's value
    // in a table hidden on screen, rebuilt with each measure.
    pairEl.setAttribute("role", "region");
    pairEl.setAttribute("aria-label", mapTitle.textContent +
      ": map of National Weather Service forecast offices. The values are " +
      "in the table that follows.");
    const codes = [measure].concat(compare ? [compare] : []);
    mapAlt.textContent = "";
    mapAlt.append(el("table", {},
      el("caption", {}, mapTitle.textContent),
      el("thead", {}, el("tr", {}, el("th", { scope: "col" }, "Forecast office"),
        ...codes.map(c => el("th", { scope: "col" }, byCode.get(c).label)))),
      el("tbody", {}, ...Object.entries(cwaValues.places)
        .sort((a, b) => a[1].label.localeCompare(b[1].label))
        .map(([id, p]) => el("tr", {}, el("th", { scope: "row" }, p.label),
          ...codes.map(c => {
            const v = M(c).values[id];
            return el("td", {}, v == null ? "no data" : fmtVal(c)(v));
          }))))));
    if (!mapAlt.isConnected) pairEl.after(mapAlt);

    lastLegend = drawLegend(legendHolder, measure, stops, !compare);
    lastLegendB = compare
      ? drawLegend(legendHolderB, compare, compareStops, false) : null;
    if (!compare) legendHolderB.textContent = "";

    // Both explanations live here, in two columns under the two maps they
    // describe. An alert history picked for comparison is a second quantity
    // on the page, and the reader has the same questions about it as about
    // the measure: what it counts, where it came from, how it was used.
    const notes = CONFIG.map.notes || {};
    const mine = notes[measure] || "";
    const theirs = compare ? (notes[compare] || "") : "";
    notesCard.innerHTML = theirs
      ? `<div class="wx-notes-pair"><div class="wx-note-half">${mine}</div>` +
        `<div class="wx-note-half">${theirs}</div></div>`
      : mine;
    notesCard.style.display = notesCard.innerHTML ? "" : "none";

    // ?place=OUN deep-links an area, and a click keeps it selected across
    // measure changes: highlight without moving the fixed frame. The popup
    // opens on the first draw only — reopening it on every measure change
    // would fight the reader who just closed it.
    if (place) {
      activeLayer.selectById(place, map, false, firstDraw);
      firstDraw = false;
    } else {
      renderScan();
    }
  }
  let firstDraw = true;
  pageRestyle = () => redraw();
  await redraw();
};

/* Landing page — the program before its results, in seven steps down the
 * page: identity and title, a one-sentence introduction, the data gap as the
 * loudest thing on it, what the project is, its scale, why it matters, and
 * the three ways into the data. No chart: a teaser plot invites a reader to
 * judge the whole project on whichever question happens to be on it.
 * Hierarchy comes from type, whitespace, rules and one tinted band rather
 * than from boxes; the explore cards are the only cards, because they are
 * the only things on the page to click. Every word is authored in the
 * builder. */
components.wx_landing = async function (page, container) {
  const h = page.hero || {};

  const hero = el("section", { class: "wx-landing-hero" });
  if (h.eyebrow) hero.append(el("p", { class: "wx-eyebrow" }, h.eyebrow));
  // A headline given as lines keeps those breaks; each line still wraps on
  // its own when the screen is narrower than it.
  const title = el("h1", { class: "wx-landing-title" });
  for (const line of [].concat(h.headline || CONFIG.project.title))
    title.append(el("span", { class: "wx-title-line" }, line));
  hero.append(title);

  // Below the title: the words on the left and the dot field on the right,
  // so the picture of people gathered year on year sits beside the sentence
  // saying how little data there is about them.
  const top = el("div", { class: "wx-landing-top" });
  const words = el("div", { class: "wx-landing-words" });
  if (h.intro) words.append(el("p", { class: "wx-landing-intro" }, h.intro));
  // The data gap, set as a statement in the page's display type between two
  // rules - large enough to be read in a five-second scan, and deliberately
  // not boxed, so it cannot be mistaken for something to click.
  if (h.statement) {
    const stmt = el("p", { class: "wx-landing-statement" });
    [].concat(h.statement).forEach(line =>
      stmt.append(el("span", { class: "wx-statement-line" }, line)));
    words.append(stmt);
  }
  if (h.description)
    words.append(el("p", { class: "wx-landing-desc" }, h.description,
      ...(h.description_close ? [" ", el("strong", {}, h.description_close)] : [])));
  top.append(words);
  if (page.growth) top.append(dotField(page.growth));
  hero.append(top);

  // One band, not four cards: hairlines between the figures and a tint
  // behind them, so the scale reads as one fact about the program.
  let stats = null;
  if ((page.stats || []).length) {
    stats = el("section", { class: "wx-stats", "aria-label": "Project at a glance" });
    for (const st of page.stats) {
      const cell = el("div", { class: "wx-stat" });
      cell.append(el("p", { class: "wx-stat-value" }, st.value),
                  el("p", { class: "wx-stat-label" }, st.label));
      stats.append(cell);
    }
  }

  // A pair rather than stacked: two halves of one argument.
  const sections = (page.sections || []).map(sec => {
    const wrap = el("section", { class: "wx-sec" });
    const cols = el("div", { class: "wx-sec-cols" });
    for (const col of (sec.columns || [sec])) {
      const half = el("div", { class: "wx-sec-col" });
      if (col.lead) half.append(el("h2", { class: "wx-sec-lead" }, col.lead));
      const box = el("div", { class: "wx-sec-prose" });
      for (const para of [].concat(col.body || [])) box.append(el("p", {}, para));
      half.append(box);
      cols.append(half);
    }
    if (!sec.columns) cols.classList.add("wx-sec-wide");
    wrap.append(cols);
    return wrap;
  });

  let explore = null;
  const ex = page.explore;
  if (ex) {
    explore = el("section", { class: "wx-explore" });
    if (ex.heading) explore.append(el("h2", { class: "wx-explore-heading" }, ex.heading));
    if (ex.intro) explore.append(el("p", { class: "wx-explore-lede" }, ex.intro));
    const grid = el("nav", { class: "wx-explore-cards", "aria-label": ex.heading || "Explore" });
    for (const c of (ex.cards || [])) {
      const target = CONFIG.pages.find(p => p.id === c.page);
      if (!target) continue;
      const a = el("a", { class: "wx-explore-card", href: "#" + target.id });
      a.append(el("h3", {}, c.label || target.label),
               el("p", {}, c.body || target.blurb || ""));
      if (c.cta) a.append(el("span", { class: "wx-explore-cta" }, c.cta));
      grid.append(a);
    }
    explore.append(grid);
  }

  container.append(el("div", { class: "page wx-landing-page" },
    el("div", { class: "content" },
      ...[hero, stats, ...sections, explore].filter(Boolean))));
};

/* The landing page's dot field: the program as people accumulated over time.
 * One column per year, each holding every respondent surveyed up to that
 * year at one dot per `per_dot`, so the columns climb as the evidence base
 * grows. Each column stacks year on year, oldest at the bottom, and within a
 * year each survey's dots take its hazard's color - so the early layers are
 * all severe weather and the other hazards appear higher up as they join the
 * program. The year a column stands for is drawn full strength on top, the
 * years beneath it faded. Visual identity rather than an analytical figure -
 * no axes, only the first and last year - but every dot is counted from the
 * data. Drawn as SVG with a viewBox, so it scales with its column. */
function dotField(growth) {
  const NS = "http://www.w3.org/2000/svg";
  const years = growth.years || [];
  const surveys = growth.surveys || [];
  const perDot = growth.per_dot || 50;
  const wide = 10, pitch = 6, r = 1.9, gapCols = 12;

  // Dots per survey, rounded on the running total so a column's height is
  // its cumulative count rounded once rather than every survey's rounding
  // added up.
  let running = 0, prevDots = 0;
  const layers = surveys.map(sv => {
    running += sv.n;
    const dots = Math.round(running / perDot);
    const layer = { year: sv.year, hazard: sv.hazard, dots: dots - prevDots };
    prevDots = dots;
    return layer;
  });
  const cols = years.map(y => layers.filter(l => l.year <= y));
  const heightOf = c => c.reduce((t, l) => t + l.dots, 0);
  const tallest = Math.ceil(Math.max(1, ...cols.map(heightOf)) / wide);
  const colW = wide * pitch, W = cols.length * colW + (cols.length - 1) * gapCols;
  const H = tallest * pitch, labelH = 30;

  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", `0 0 ${W} ${H + labelH}`);
  svg.setAttribute("class", "wx-dotfield-svg");
  svg.setAttribute("role", "img");
  svg.setAttribute("aria-label",
    [growth.title, growth.caption].filter(Boolean).join(". "));
  cols.forEach((col, ci) => {
    const g = document.createElementNS(NS, "g");
    g.setAttribute("class", "wx-dot-col");
    g.style.setProperty("--i", ci);
    const x0 = ci * (colW + gapCols);
    let k = 0;
    for (const layer of col) {
      const cls = `wx-dot wx-haz-${layer.hazard}` +
        (layer.year === years[ci] ? "" : " wx-dot-old");
      for (let d = 0; d < layer.dots; d++, k++) {
        const dot = document.createElementNS(NS, "circle");
        dot.setAttribute("cx", x0 + (k % wide) * pitch + pitch / 2);
        dot.setAttribute("cy", H - Math.floor(k / wide) * pitch - pitch / 2);
        dot.setAttribute("r", r);
        dot.setAttribute("class", cls);
        g.append(dot);
      }
    }
    svg.append(g);
    if (ci === 0 || ci === cols.length - 1) {
      const t = document.createElementNS(NS, "text");
      t.setAttribute("x", x0 + colW / 2);
      t.setAttribute("y", H + labelH - 4);
      t.setAttribute("text-anchor", "middle");
      t.setAttribute("class", "wx-dot-year");
      t.textContent = years[ci];
      svg.append(t);
    }
  });

  const fig = el("figure", { class: "wx-dotfield" });
  if (growth.title) fig.append(el("p", { class: "wx-dotfield-title" }, growth.title));
  fig.append(svg);
  const cap = el("figcaption", { class: "wx-dotfield-caption" });
  if (growth.caption) cap.append(el("span", {}, growth.caption));
  // The key, in the order the hazards joined, which is also the order they
  // first appear going up the field.
  const key = el("span", { class: "wx-dot-key" });
  (growth.hazards || []).forEach((name, i) => key.append(
    el("span", { class: "wx-dot-key-item" },
      el("span", { class: `wx-dot-swatch wx-haz-${i + 1}`, "aria-hidden": "true" }),
      name)));
  if (key.children.length) cap.append(key);
  fig.append(cap);
  return fig;
}

/* Test Your Knowledge: each question asks for a national result, usually
 * followed by a subgroup, and answering reveals the REAL distribution as a
 * chart drawn from the same data/q/ file the explorer uses (part 1 =
 * national, follow-up = the builder's subgroup split). Prompts and answer
 * keys are authored by the builder (config.pages[quiz].questions) and derived
 * from bundle data. A segmented progress bar tracks ✓/✗, and every reveal and
 * the finale recap deep-link into the survey explorer, so a reader can leave
 * the quiz at any point to follow whatever caught their interest. */
components.wx_quiz = async function (page, container) {
  const quiz = page.questions || [];
  // Questions are numbered, prompts are not: a follow-up is depth on the
  // question it follows, so it carries that question's number, and a
  // question may have a follow-up or not without moving the count.
  // A question has one part or more: part1, an optional part2, and any
  // further parts in `more` (a series asked region by region, say).
  const partsOf = (q) => [q.part1, q.part2, ...(q.more || [])].filter(Boolean);
  // A part may accept several options (`accept`) where the data cannot
  // separate them; otherwise only `answer` is right.
  const isRight = (pp, i) => pp.accept ? pp.accept.includes(i) : i === pp.answer;
  const totalPrompts = quiz.reduce((t, q) => t + partsOf(q).length, 0);
  // Where the reader is, and each prompt's chosen option. Going back
  // revisits a prompt as it was answered rather than asking it again, so
  // the score counts first answers only.
  let idx = 0, part = 0;
  const choices = quiz.map(() => []);
  // Kept for the browser session, so a reader who follows a link into the
  // explorer and comes back resumes where they were, with their answers.
  // sessionStorage rather than localStorage: a new visit starts a new quiz.
  // Keyed to the quiz's own questions and parts, so a deploy that changes
  // the quiz starts it afresh rather than resuming into the wrong place.
  const QUIZ_KEY = "wxdash-quiz";
  const quizSig = quiz.map(q => (q.id || (q.explore && q.explore.params &&
    q.explore.params.q) || "") + ":" + partsOf(q).length).join("|");
  const saveQuiz = () => {
    try {
      sessionStorage.setItem(QUIZ_KEY,
        JSON.stringify({ sig: quizSig, idx, part, choices }));
    } catch { /* no storage: the quiz still works, it just does not resume */ }
  };
  try {
    const saved = JSON.parse(sessionStorage.getItem(QUIZ_KEY) || "null");
    if (saved && saved.sig === quizSig && Array.isArray(saved.choices)) {
      saved.choices.forEach((c, i) => {
        if (Array.isArray(c) && choices[i]) c.forEach((v, j) => {
          if (v !== null && v !== undefined) choices[i][j] = v;
        });
      });
      idx = Math.min(Math.max(0, saved.idx | 0), quiz.length);
      part = idx < quiz.length
        ? Math.min(Math.max(0, saved.part | 0), partsOf(quiz[idx]).length - 1)
        : 0;
    }
  } catch { /* unreadable: start from the beginning */ }
  // A community part stores its own verdict with the guess, since what is
  // right depends on the office picked.
  const results = () => quiz.map((q, i) => partsOf(q)
    .map((pp, j) => choices[i][j] === undefined ? undefined
      : pp.kind === "community" ? choices[i][j].right
      : isRight(pp, choices[i][j]))
    .filter(r => r !== undefined));
  const tally = () => {
    const flat = results().flat();
    return { answered: flat.length, score: flat.filter(Boolean).length };
  };
  // The same skeleton as the explore pages: title and introduction, then
  // each question as a small label over a large heading, its answers on the
  // page, and the chart that answers it as the one card.
  const card = el("section", { class: "wx-result wx-quiz" });
  container.append(el("div", { class: "page wx-explore-page wx-quiz-page" },
    el("div", { class: "content" }, pageHead(page), card)));

  // One group per question, one segment in it per prompt, so a follow-up
  // reads as part of its question. ✓/✗ glyphs carry the state (greyscale
  // theme, never color alone); the outlined segment is where you are.
  const progress = el("div", { class: "wx-quiz-progress" });
  // Back to the first question with every answer cleared, and the saved
  // session with it. From the score page directly; mid-quiz behind a
  // confirmation, since one stray click would otherwise lose every answer.
  function startOver() {
    idx = 0;
    choices.forEach(c => { c.length = 0; });
    renderQ(0);
    card.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  const resetBtn = el("button", { class: "wx-quiz-reset", type: "button",
    onclick: () => {
      if (window.confirm("Start the quiz over? Your answers will be cleared.")) startOver();
    } }, "\u21ba Start over");

  function drawProgress() {
    saveQuiz();
    progress.textContent = "";
    const t = tally();
    // Offered once there is something to clear, and not on the score page,
    // which has its own.
    resetBtn.style.display = t.answered > 0 && idx < quiz.length ? "" : "none";
    progress.setAttribute("aria-label",
      `${t.answered} of ${totalPrompts} answered, ${t.score} right`);
    // One row per section, read top to bottom: the section's name, then a
    // segment for every prompt in it, grouped by question. A segment opens
    // its question or part, answered or not; a section name opens the
    // section's first question.
    const go = (i, j) => {
      idx = i; renderQ(j);
      card.scrollIntoView({ behavior: "smooth", block: "start" });
    };
    let row = null;
    quiz.forEach((q, i) => {
      if (!row || quiz[i - 1].theme !== q.theme) {
        row = el("div", { class: "wx-quiz-theme-row" });
        // The section being answered is named in the accent, since the
        // rows are what say where the reader is.
        const here = quiz[idx] && quiz[idx].theme === q.theme;
        progress.append(
          el("button", { class: "wx-quiz-theme-label" + (here ? " current" : ""),
            type: "button", onclick: () => go(i, 0) }, q.theme || ""),
          row);
      }
      const group = el("span", { class: "wx-quiz-seg-group" });
      partsOf(q).forEach((pp, j) => {
        const what = j ? (pp.tag ? ` \u00b7 ${pp.tag}` : " \u00b7 follow-up") : "";
        const seg = el("button", { class: "wx-quiz-seg", type: "button",
          title: `Question ${i + 1}${what}`,
          "aria-label": `Go to question ${i + 1}${what.replace(" \u00b7", ",")}`,
          onclick: () => go(i, j) });
        const c = choices[i][j];
        if (c !== undefined) {
          const r = pp.kind === "community" ? c.right : isRight(pp, c);
          seg.classList.add(r ? "correct" : "wrong");
          seg.textContent = r ? "\u2713" : "\u2717";
        }
        if (i === idx && j === part) seg.classList.add("current");
        group.append(seg);
      });
      row.append(group);
    });
  }

  // The verdict names the result outright on a miss, so the reader learns
  // the answer before reading why; `result` comes from the builder, computed
  // from the same numbers as the answer key.
  // A part may word its own miss ("65+ has the highest reported
  // understanding"); otherwise the result is named plainly.
  const verdict = (right, pp) => right ? "You got it."
    : pp.miss || `The survey result is ${pp.result || pp.options[pp.answer]}`;

  // Explorer deep link. grouping=null keeps the builder's split (the
  // follow-up's subject); part 1 passes "All" for the national view.
  function exploreLink(q, grouping, label) {
    if (!q.explore) return null;
    const params = Object.assign({}, q.explore.params,
      grouping ? { grouping } : null);
    if (params.grouping === "All") delete params.grouping;
    return pageLink(q.explore.href, params, { class: "wx-quiz-explore" },
      label || q.explore.label || "See the data");
  }

  // One step back through the prompts: a follow-up goes to its question,
  // a question to the last prompt of the one before, the score page to the
  // last prompt of all.
  const hasPrevious = () => idx > 0 || part > 0;
  function goPrevious() {
    if (part > 0) part--;
    else { idx--; part = partsOf(quiz[idx]).length - 1; }
    renderQ(part);
    card.scrollIntoView({ behavior: "smooth", block: "start" });
  }
  const previousButton = () => el("button", { class: "wx-quiz-again",
    onclick: goPrevious }, "\u2190 Previous Question");

  function renderQ(startPart = 0) {
    card.textContent = "";
    part = startPart;
    card.append(progress, resetBtn);
    drawProgress();
    if (idx >= quiz.length) {
      const t = tally();
      card.append(el("div", { class: "wx-result-head" },
        el("p", { class: "wx-result-survey" }, "Your score"),
        el("h2", { class: "wx-question-head wx-result-item" },
          `You got ${t.score} of ${t.answered} right.`)));
      card.append(el("p", { class: "wx-quiz-lede" },
        "Every answer lives in the dashboard, and the interesting part is " +
        "why. Keep exploring."));
      // Recap: one row per question, marks + topic + its explorer deep link.
      const topicOf = (q) => {
        const s = q.part1.prompt;
        return s.length > 76 ? s.slice(0, 76).replace(/\s+\S*$/, "") + "…" : s;
      };
      // Grouped under each theme with its own count, so the recap shows
      // which part of the warning chain the reader's instincts missed.
      const r = results();
      const recap = el("div", { class: "card wx-result-chart wx-quiz-recap" });
      quiz.forEach((q, i) => {
        if (q.theme && (i === 0 || quiz[i - 1].theme !== q.theme)) {
          const mine = quiz.map((x, j) => x.theme === q.theme ? r[j] : [])
            .flat();
          recap.append(el("p", { class: "wx-quiz-recap-theme" },
            `${q.theme} \u00b7 ${mine.filter(Boolean).length} of ` +
            `${mine.length} right`));
        }
        // Each mark names its part, so a follow-up's result is not read as
        // the question's: "✓ Question ✗ Follow-up", or a series' own tags.
        const ps = partsOf(q);
        recap.append(el("div", { class: "wx-quiz-recap-row" },
          el("span", { class: "wx-quiz-recap-marks" },
            ...r[i].map((ok, j) => el("span", { class: "wx-quiz-recap-mark" +
              (ok ? " is-right" : " is-wrong") },
              (ok ? "\u2713 " : "\u2717 ") +
              (j === 0 ? (ps[0].tag || "Question") : (ps[j].tag || "Follow-up"))))),
          el("span", { class: "wx-quiz-recap-topic" }, topicOf(q)),
          exploreLink(q, null, "explore ↗")));
      });
      card.append(recap);
      card.append(el("div", { class: "wx-quiz-nav" },
        previousButton(),
        el("a", { class: "wx-cta-button", href: "#survey" }, "Explore the survey questions"),
        el("button", { class: "wx-quiz-again", onclick: startOver }, "Start over")));
      return;
    }
    const q = quiz[idx];
    // Prefetch the question's data file so the reveal chart is instant;
    // null (missing id or fetch failure) just means no chart renders.
    const dataPromise = (q.explore && q.explore.params && q.explore.params.q)
      ? fetchQuestion(q.explore.params.q).catch(() => null)
      : Promise.resolve(null);
    const parts = partsOf(q);
    const zone = el("div");
    card.append(zone);

    // The real data behind the prompt just answered: national split for
    // part 1, the builder's subgroup split for the follow-up: the same
    // rows/orientation the explorer will show when they click through.
    // Exception: a part carrying builder-emitted `chart` rows (a prompt
    // that compares several survey variables, so no single data/q file
    // matches) charts those rows instead.
    // The survey page's colors: its default scheme, or whichever one a
    // reader has picked there (?scheme= is shared across the site).
    const quizColors = (rows) => schemeSeriesColors(urlScheme(),
      new Set(rows.map(r => naLabel(r.group))).size);
    function revealChart(pp) {
      // A part that names its own survey item charts that item's file, at
      // the split its own link names.
      const own = pp.explore && pp.explore.params;
      const grouping = own ? (own.grouping || "All")
        : part === 0 ? "All"
        : ((q.explore && q.explore.params && q.explore.params.grouping) || "All");
      const itemData = own && own.q
        ? fetchQuestion(own.q).catch(() => null)
        : dataPromise;
      const grouped = !pp.chart && grouping !== "All";
      // The answer as the page's one card, like the explore pages' figures:
      // the chart, a line saying what it shows, and the way into the
      // explorer at its foot where they put their downloads.
      const panel = el("div", { class: "card wx-result-chart wx-quiz-chart" });
      const wrap = el("div", {
        class: "wx-quiz-chartwrap" + (grouped ? " grouped" : "") });
      const canvas = el("canvas");
      wrap.append(canvas);
      // The same note the survey page puts under its chart: a line of facts,
      // then what the bars are, from the same templates and question file.
      const cap = el("div", { class: "wx-caption wx-explore-caption wx-quiz-cap" });
      const foot = el("div", { class: "wx-toolbar-actions wx-result-downloads" });
      // The survey question as respondents read it, above the chart: the
      // quiz prompt paraphrases, and the chart answers the question itself.
      const asked = el("div", { class: "wx-quiz-asked" });
      const setAsked = (stem, items) => {
        asked.append(el("p", { class: "wx-quiz-asked-label" }, "Survey question"));
        if (stem) asked.append(el("p", { class: "wx-quiz-asked-stem" }, stem));
        if (items.length === 1)
          asked.append(el("p", { class: "wx-quiz-asked-item" }, items[0]));
        else if (items.length)
          asked.append(el("ul", { class: "wx-quiz-asked-items" },
            ...items.map(t => el("li", {}, t))));
      };
      panel.append(asked, wrap, cap, foot);
      // A part may chart a different survey item from its question (a
      // follow-up asked of another hazard); its link then goes there.
      const toExplorer = (g) => {
        const a = exploreLink(pp.explore ? { explore: pp.explore } : q, g,
          "Open in the survey explorer \u2192");
        if (a) { a.classList.add("wx-foot-link"); foot.append(a); }
        else foot.remove();
      };
      if (pp.chart) {
        // Where the options are what respondents compared, the builder sends
        // them as a table, which replaces the list of question stems.
        if (pp.asked && pp.asked.table) {
          const t = pp.asked.table;
          asked.append(el("p", { class: "wx-quiz-asked-label" }, "Survey question"));
          if (pp.asked.stem) asked.append(el("p", { class: "wx-quiz-asked-stem" }, pp.asked.stem));
          if (t.lead) asked.append(el("p", { class: "wx-quiz-asked-stem" }, t.lead));
          asked.append(el("table", { class: "wx-quiz-asked-table" },
            el("thead", {}, el("tr", {}, ...t.head.map(h => el("th", {}, h)))),
            el("tbody", {}, ...t.rows.map(r => el("tr", {},
              ...r.map((c, k) => el(k ? "td" : "th", {}, c)))))));
        } else if (pp.asked) setAsked(pp.asked.stem, [].concat(pp.asked.items || []));
        // A follow-up's chart is its group values, with the survey page's
        // note written by the builder; a comparison across questions has
        // no one sample to describe.
        if (pp.caption) {
          cap.append(el("p", { class: "wx-caption-meta" }, pp.caption.meta),
            el("p", { class: "wx-caption-bars" }, pp.caption.bars));
        } else cap.append(el("p", { class: "wx-caption-bars" },
          "Bars show weighted survey estimates."));
        toExplorer(pp.grouping || (part === 0 ? "All" : null));
        const hl = pp.highlight || {};
        // Rows in more than one group (two scenarios side by side) get a
        // legend to say which is which.
        const nGroups = new Set(pp.chart.rows.map(r => naLabel(r.group))).size;
        const nCats = new Set(pp.chart.rows.map(r => naLabel(r.category))).size;
        wrap.style.height = Math.max(250, 60 + nCats * (nGroups * 20 + 14) +
          (nGroups > 1 ? 50 : 0)) + "px";
        groupedBarChart(canvas, pp.chart.rows,
          { yLabel: pp.chart.y_label, altTitle: pp.prompt, horizontal: true, legend: nGroups > 1,
            legendTitle: pp.chart.legend_title || "",
            colors: quizColors(pp.chart.rows),
            highlight: hl.category ? { categories: new Set([].concat(hl.category)) } : null });
        if (hl.category && !pp.caption) cap.append(el("p", { class: "wx-caption-hl" },
          `The highlighted bar is the answer: ${hl.category}.`));
        return panel;
      }
      itemData.then(v => {
        if (!v || !v.splits) { panel.remove(); return; }
        const { splits: pSplits, summaries } = questionSlice(v);
        setAsked(v.question_intro || "", [v.question_text || v.question || ""]);
        const g = (pSplits[grouping] && pSplits[grouping].length) ? grouping : "All";
        const tick = tickLabeller((v.options || []).map(o => o.label));
        const labelFor = (resp) => {
          const hit = (v.options || []).find(o => String(o.value) === String(resp));
          return hit ? tick(hit.label) : String(resp);
        };
        const rows = (pSplits[g] || []).map(r => ({
          group: r.group, category: labelFor(r.resp), value: r.p,
          label: Math.round(r.p) + "%"
        }));
        if (!rows.length) { panel.remove(); return; }
        // Room for the labels: long options wrap to several lines, and a
        // fixed height would squeeze their bars thin.
        if (g === "All") {
          const lines = Math.max(...rows.map(r => String(r.category).split("\n").length));
          const nCats = new Set(rows.map(r => r.category)).size;
          wrap.style.height = Math.max(250, 70 + nCats * Math.max(34, lines * 18)) + "px";
        }
        const gLabel = (CONFIG.groupings.find(x => x.id === g) || {}).label;
        // The bars the answer is made of: the response codes it adds up, for
        // the group it names. A group the fallback split does not carry is
        // dropped rather than fading every bar.
        const hl = pp.highlight || {};
        const hlCats = hl.resp ? new Set(hl.resp.map(c => labelFor(c))) : null;
        const hlGroup = hl.group && rows.some(r => r.group === hl.group) ? hl.group : null;
        const highlight = (hlCats || hlGroup) ? { categories: hlCats, group: hlGroup } : null;
        const tpl = CONFIG.explore_caption, sm = summaries && summaries[g];
        if (tpl && sm) {
          const survey = String(v.hazard || "").replace(/\s*\([A-Z]+\)$/, "");
          cap.append(el("p", { class: "wx-caption-meta" }, fillTpl(tpl.meta, { who: countedAs(sm.years),
            n: Number(sm.n).toLocaleString(), survey,
            years: String(sm.years || "").replace(/-/g, "\u2013") })));
          const gcfg = CONFIG.groupings.find(x => x.id === g);
          let bars = g === "All" ? tpl.bars : fillTpl(tpl.bars_split,
            { group_phrase: (gcfg && gcfg.phrase) || "group" });
          if (g !== "All") bars += fillTpl(tpl.smallest, { smallest: sm.smallest,
            smallest_n: Number(sm.smallest_n).toLocaleString() });
          // A part may say in its own words what the highlight marks; it
          // then replaces the generated "Highlighted:" line.
          if (pp.chart_note) bars += " " + pp.chart_note;
          cap.append(el("p", { class: "wx-caption-bars" }, bars));
        }
        toExplorer(g === "All" ? "All" : null);
        groupedBarChart(canvas, rows, { yLabel: "Respondents (%)", altTitle: pp.prompt,
          horizontal: true, legend: g !== "All", legendTitle: gLabel || "Group",
          colors: quizColors(rows), highlight });
        if (highlight && !pp.chart_note) {
          const names = hl.resp ? hl.resp.map(c => {
            const o = (v.options || []).find(x => String(x.value) === String(c));
            return o ? `\u201c${o.label}\u201d` : String(c);
          }) : [];
          const list = names.length > 1
            ? names.slice(0, -1).join(", ") + " and " + names[names.length - 1]
            : names[0];
          const text = !names.length
            ? `Highlighted: the ${hlGroup} bars, the group the answer names.`
            : `Highlighted: ${list}${hlGroup ? " for " + hlGroup : ""}, the ` +
              `${names.length > 1 ? "responses" : "response"} the answer is based on.`;
          cap.append(el("p", { class: "wx-caption-hl" }, text));
        }
      });
      return panel;
    }

    // The community question: pick a forecast office, then guess its
    // top-rated hazard. The estimates come from the Communities page's own
    // file and are only put in order here; hazards within `tie` of the top
    // all count as right. The guess is locked once made, like any answer.
    function renderCommunity(pp, step) {
      const nav = el("div", { class: "wx-quiz-nav" });
      if (hasPrevious()) nav.append(previousButton());
      const pick = el("select", { class: "wx-quiz-place",
        "aria-label": "Your forecast office" });
      const guessZone = el("div");
      const out = el("div");
      step.append(pick, guessZone, out, nav);
      fetchJSON("data/map/cwa_values.json").then(cv => {
        const places = Object.entries(cv.places || {})
          .sort((a, b) => a[1].label.localeCompare(b[1].label));
        pick.append(el("option", { value: "" }, pp.choose || "Choose"),
          ...places.map(([code, p]) => el("option", { value: code }, p.label)));
        const lc = (m) => m.label.toLowerCase();
        const cap1 = (t) => t.charAt(0).toUpperCase() + t.slice(1);
        const fmt = (x) => x.toFixed(2);
        const rank = (code) => pp.measures
          .map(m => ({ ...m, v: ((cv.measures[m.code] || {}).values || {})[code] }))
          .filter(m => typeof m.v === "number")
          .sort((a, b) => b.v - a.v);
        const nextButton = () => el("button", { class: "wx-cta-button", onclick: () => {
          idx++; renderQ();
          card.scrollIntoView({ behavior: "smooth", block: "start" });
        } }, idx + 1 < quiz.length ? "Next Question \u2192" : "See Your Score \u2192");
        // One office's hazards ranked, as the reveal chart, with its way into
        // the map at its foot.
        const officeChart = (code, alongside = false) => {
          const vals = rank(code);
          const tied = vals.filter(m => vals[0].v - m.v < pp.tie);
          const place = cv.places[code].label;
          const panel = el("div", { class: "card wx-result-chart wx-quiz-chart" });
          const wrap = el("div", { class: "wx-quiz-chartwrap" });
          const canvas = el("canvas");
          wrap.append(canvas);
          wrap.style.height = Math.max(250, 60 + vals.length * 34) + "px";
          const rows = vals.map(m => ({ group: "All", category: m.label,
            value: m.v, label: fmt(m.v) }));
          // The question behind the estimates, as every reveal shows it.
          const asked = el("div", { class: "wx-quiz-asked" });
          if (pp.asked) {
            asked.append(el("p", { class: "wx-quiz-asked-label" }, "Survey question"));
            if (pp.asked.stem) asked.append(el("p", { class: "wx-quiz-asked-stem" }, pp.asked.stem));
            if (pp.asked.items) asked.append(el("ul", { class: "wx-quiz-asked-items" },
              ...[].concat(pp.asked.items).map(t => el("li", {}, t))));
          }
          panel.append(asked, wrap,
            el("div", { class: "wx-caption wx-explore-caption wx-quiz-cap" },
              el("p", { class: "wx-caption-meta" }, fillTpl(pp.meta, { place })),
              el("p", { class: "wx-caption-bars" }, pp.bars)),
            el("div", { class: "wx-toolbar-actions wx-result-downloads" },
              pageLink("#map", { place: code, measure: vals[0].code },
                { class: "wx-quiz-explore wx-foot-link" },
                fillTpl(pp.map_link, { place }))));
          // Drawn once the panel is on the page, which Chart.js needs to size.
          setTimeout(() => groupedBarChart(canvas, rows, {
            yLabel: "Perceived risk (1\u20135)",
            altTitle: fillTpl(pp.meta, { place }),
            horizontal: true, legend: false, colors: quizColors(rows),
            highlight: { categories: new Set(tied.map(m => m.label)) },
            alongside }), 0);
          return panel;
        };
        // The options for an office, then, once guessed, the verdict, the
        // reveal and the chart.
        const showGuess = (code) => {
          guessZone.textContent = ""; out.textContent = "";
          if (!code) return;
          const vals = rank(code);
          if (!vals.length) return;
          const tied = vals.filter(m => vals[0].v - m.v < pp.tie);
          const opts = el("div", { class: "wx-quiz-opts wx-quiz-opts-grid" });
          guessZone.append(opts);
          const settle = (g) => {
            const right = tied.some(m => m.code === g);
            choices[idx][part] = { code, guess: g, right };
            pick.disabled = true;
            drawProgress();
            opts.querySelectorAll("button").forEach(bb => {
              bb.disabled = true;
              if (tied.some(m => m.code === bb.dataset.code)) {
                bb.classList.add("correct"); bb.prepend("\u2713 ");
              } else if (bb.dataset.code === g) {
                bb.classList.add("wrong"); bb.prepend("\u2717 ");
              }
            });
            const place = cv.places[code].label;
            const list = tied.map(m => `${lc(m)} (${fmt(m.v)})`);
            const joined = list.length > 2
              ? list.slice(0, -1).join(", ") + ", and " + list[list.length - 1]
              : list.join(" and ");
            const names = tied.map(lc);
            const namesJoined = names.length > 2
              ? names.slice(0, -1).join(", ") + ", and " + names[names.length - 1]
              : names.join(" and ");
            const text = tied.length > 1
              ? fillTpl(pp.reveal_tied, { place, tied: joined,
                  either: tied.length === 2 ? "either" : "any of them" })
              : fillTpl(pp.reveal_one, { place, top: lc(vals[0]), value: fmt(vals[0].v),
                  second: lc(vals[1]), second_value: fmt(vals[1].v) });
            const miss = tied.length > 1
              ? fillTpl(pp.miss_tied, { place, Tied: cap1(namesJoined) })
              : fillTpl(pp.miss_one, { place, Top: cap1(lc(vals[0])) });
            out.append(el("div", { class: "wx-quiz-reveal" + (right ? " is-right" : ""),
              role: "status" },
              el("p", { class: "wx-quiz-verdict" }, right ? "You got it." : miss),
              el("p", { class: "wx-quiz-answer" }, text)));
            out.append(officeChart(code));
            // Other offices can be looked up once this one is answered; the
            // look-up redraws the chart below it and leaves the score alone.
            const other = el("select", { class: "wx-quiz-place" },
              el("option", { value: "" }, "Choose another office"),
              ...places.filter(([c]) => c !== code)
                .map(([c, p]) => el("option", { value: c }, p.label)));
            const otherOut = el("div");
            other.addEventListener("change", () => {
              otherOut.textContent = "";
              if (other.value) otherOut.append(officeChart(other.value, true));
            });
            out.append(el("div", { class: "wx-quiz-other" },
              el("label", { class: "wx-quiz-other-label" },
                "See another office (not scored): ", other), otherOut));
            if (!nav.querySelector(".wx-cta-button")) nav.append(nextButton());
          };
          pp.measures.forEach(m => opts.append(el("button", { class: "wx-quiz-opt",
            "data-code": m.code, onclick: () => settle(m.code) }, m.label)));
          const had = choices[idx][part];
          if (had && had.code === code) settle(had.guess);
        };
        pick.addEventListener("change", () => showGuess(pick.value));
        const had = choices[idx][part];
        if (had) { pick.value = had.code; showGuess(had.code); }
      });
    }

    function renderPart() {
      drawProgress();
      zone.textContent = "";
      const pp = parts[part];
      const step = el("div", { class: "wx-quiz-step" });
      zone.append(step);
      // A long prompt comes in layers: a quiet setup, the text respondents
      // read as a quotation, then the question itself as the heading.
      if (pp.setup) step.append(el("p", { class: "wx-quiz-setup" }, pp.setup));
      if (pp.quote) step.append(el("blockquote", { class: "wx-quiz-quote" }, pp.quote));
      (pp.quotes || []).forEach(qt => step.append(el("blockquote",
        { class: "wx-quiz-quote" }, el("strong", {}, qt.label + ": "), qt.text)));
      step.append(el("h2", { class: "wx-question-head wx-result-item wx-quiz-q" },
        pp.prompt));
      if (pp.kind === "community") { renderCommunity(pp, step); return; }
      const opts = el("div", { class: "wx-quiz-opts" });
      // Until the prompt is answered the only way on is back.
      const nav = el("div", { class: "wx-quiz-nav" });
      if (hasPrevious()) nav.append(previousButton());
      const show = (i) => {
        const right = isRight(pp, i);
        drawProgress();
        opts.querySelectorAll("button").forEach((bb, j) => {
          bb.disabled = true;
          if (isRight(pp, j)) { bb.classList.add("correct"); bb.prepend("✓ "); }
          else if (j === i) { bb.classList.add("wrong"); bb.prepend("✗ "); }
        });
        // The answer as a callout: the verdict on its own line, then what
        // the survey says, set larger than anything around it but the
        // question.
        const fb = el("div", { class: "wx-quiz-reveal" + (right ? " is-right" : ""),
                               role: "status" },
          el("p", { class: "wx-quiz-verdict" }, verdict(right, pp)),
          el("p", { class: "wx-quiz-answer" }, pp.reveal));
        if (part + 1 < parts.length) {
          nav.append(el("button", { class: "wx-cta-button", onclick: () => {
            part++; renderPart();
          } }, parts[part + 1].lead || "Try a Follow-Up \u2192"));
        } else {
          nav.append(el("button", { class: "wx-cta-button", onclick: () => {
            idx++; renderQ();
            card.scrollIntoView({ behavior: "smooth", block: "start" });
          } }, idx + 1 < quiz.length ? "Next Question \u2192" : "See Your Score \u2192"));
        }
        nav.before(fb, revealChart(pp));
      };
      pp.options.forEach((o, i) => {
        opts.append(el("button", { class: "wx-quiz-opt", onclick: () => {
          choices[idx][part] = i;
          saveQuiz();
          show(i);
        } }, o));
      });
      step.append(opts, nav);
      if (choices[idx][part] !== undefined) show(choices[idx][part]);
    }
    renderPart();
  }
  pageRestyle = () => renderQ(part);
  renderQ(part);
};

/* Static page (About): builder-authored HTML from config, under the same
 * head every other page carries, so it opens with its title rather than with
 * a heading buried in the card. */
components.static_page = async function (page, container) {
  container.append(el("div", { class: "page" },
    el("div", { class: "content" }, pageHead(page),
      el("div", { class: "card wx-static", html: page.html || "" }))));
};

/* A page opens with what it is, then how to use it: a title that is a phrase
 * rather than an instruction, and the paragraph under it that instructs. Both
 * are authored in the builder like every other sentence on the site; a page
 * without a title renders the paragraph alone, and a page with neither
 * renders an empty head that takes no space. */
function pageHead(page, fallback) {
  const wrap = el("div", { class: "wx-page-head" });
  if (page.title) wrap.append(el("h1", { class: "wx-page-title" }, page.title));
  // An intro given as a list is set as that many paragraphs.
  for (const text of [].concat(page.intro || fallback || []))
    wrap.append(el("p", { class: "wx-explore-intro" }, text));
  return wrap;
}

/* ------------------------------------------------------------- routing -- */

function currentPageId() {
  return location.hash.replace(/^#/, "") || CONFIG.pages[0].id;
}

// Set by a page that can repaint itself in a new theme without being rebuilt,
// so changing colors keeps what the reader has done there (filters, search,
// a quiz in progress, a chosen area). Cleared on every page change.
let pageRestyle = null;

// The hash the page on screen was drawn for.
let shownHash = location.hash;

async function renderPage() {
  pageRestyle = null;
  shownHash = location.hash;
  const app = document.getElementById("app");
  const id = currentPageId();
  const page = CONFIG.pages.find(p => p.id === id) || CONFIG.pages[0];

  document.querySelectorAll("#nav-pages a").forEach(a =>
    a.classList.toggle("active", a.getAttribute("href") === "#" + page.id));
  document.querySelectorAll("#nav-pages .nav-group").forEach(g => {
    g.classList.remove("open");
    g.querySelector(".nav-group-btn").classList.toggle("active",
      !!g.querySelector(`a[href="#${page.id}"]`));
  });

  if (activeChart) { activeChart.destroy(); activeChart = null; }
  pageCharts.forEach(c => c.destroy());
  pageCharts = [];
  app.textContent = "";
  const renderer = components[page.component];
  if (!renderer) {
    app.append(el("div", { class: "error" }, `Unknown component: ${page.component}`));
    return;
  }
  try {
    await renderer(page, app);
  } catch (err) {
    console.error(err);
    app.append(el("div", { class: "error" }, `Failed to render "${page.label}": ${err.message}`));
  }
}

/* ---- viewer theme switcher ---------------------------------------------- */
// Themes restyle chrome; data colors come from the color scheme, except that
// the greyscale theme repaints map ramps in greys (dataStops).
const THEMES = [
  { id: "wxdash", label: "WxDash", swatch: "#443A83" },
  { id: "wxops", label: "Ops (dark)", swatch: "#0f172a" },
  { id: "greyscale", label: "Greyscale (high contrast)", swatch: "#000000" }
];

function applyTheme(id, { rerender = false } = {}) {
  document.documentElement.dataset.theme = id;
  // Chart text (titles, ticks, legends) follows the theme's ink so dark
  // themes don't render Chart.js's default grey-on-dark.
  if (window.Chart)
    Chart.defaults.color = getComputedStyle(document.body).getPropertyValue("--text").trim() || "#666";
  try { sessionStorage.setItem("engine-theme", id); } catch { /* private mode */ }
  document.querySelectorAll("#theme-menu button").forEach(b =>
    b.classList.toggle("active", b.dataset.theme === id));
  // Charts capture label colors at creation — redraw the page so they follow.
  if (rerender) { if (pageRestyle) pageRestyle(); else renderPage(); }
}

function themeSwitcher() {
  const wrap = el("div", { id: "theme-switch" });
  const btn = el("button", { id: "theme-btn", title: "Adjust colors",
    onclick: () => menu.classList.toggle("open") }, "◐ Adjust colors");
  const menu = el("div", { id: "theme-menu" });
  for (const t of THEMES) {
    menu.append(el("button", { "data-theme": t.id, onclick: () => {
      applyTheme(t.id, { rerender: true });
      menu.classList.remove("open");
    } }, el("span", { class: "swatch", style: `background:${t.swatch}` }), t.label));
  }
  document.addEventListener("click", (e) => {
    if (!wrap.contains(e.target)) menu.classList.remove("open");
  });
  wrap.append(btn, menu);
  return wrap;
}

async function boot() {
  try {
    CONFIG = await fetchJSON("config.json");
  } catch (err) {
    document.getElementById("app").innerHTML =
      `<div class="error">Could not load bundle config from <code>${esc(BUNDLE)}config.json</code>. ` +
      `Serve the repo root and pass ?bundle=/DASHBOARDS/&lt;slug&gt;/ or copy the engine into the bundle.</div>`;
    return;
  }
  document.title = CONFIG.project.title;
  // Brand lockup: wordmark + optional small institutional subtitle line.
  const navTitle = document.getElementById("nav-title");
  navTitle.textContent = "";
  const brandName = el("span", { class: "brand-name" }, CONFIG.project.nav_title || CONFIG.project.title);
  // The GitHub Pages build says so, so a link to it is not taken for the
  // production site.
  if (CONFIG.project.beta) brandName.append(el("span", { class: "brand-beta" }, "Beta"));
  navTitle.append(brandName);
  if (CONFIG.project.nav_subtitle)
    navTitle.append(el("span", { class: "brand-sub" }, CONFIG.project.nav_subtitle));
  const nav = document.getElementById("nav-pages");
  // Featured pages render as links; pages carrying nav_group fold into a
  // labeled dropdown at the position of the group's first member.
  const navGroups = new Map();
  const closeMenus = () => nav.querySelectorAll(".nav-group.open")
    .forEach(g => { g.classList.remove("open");
      g.querySelector(".nav-group-btn").setAttribute("aria-expanded", "false"); });
  for (const p of CONFIG.pages) {
    if (p.hidden) continue; // a page reached by link rather than from the menu
    if (!p.nav_group) { nav.append(el("a", { href: "#" + p.id }, p.label)); continue; }
    if (!navGroups.has(p.nav_group)) {
      const wrap = el("div", { class: "nav-group" });
      const btn = el("button", { class: "nav-group-btn", type: "button",
        "aria-expanded": "false", "aria-haspopup": "true",
        onclick: (e) => {
          e.stopPropagation();
          const open = wrap.classList.contains("open");
          closeMenus();
          if (!open) {
            // Fixed positioning from the button's viewport rect: the wxdash
            // navbar scrolls horizontally (overflow-x), which clips
            // absolutely-positioned children — fixed escapes any ancestor
            // overflow in every theme.
            const r = btn.getBoundingClientRect();
            menu.style.left = Math.round(r.left) + "px";
            menu.style.top = Math.round(r.bottom) + "px";
            wrap.classList.add("open");
            btn.setAttribute("aria-expanded", "true");
          }
        } }, p.nav_group, el("span", { class: "nav-caret" }, " ▾"));
      const menu = el("div", { class: "nav-menu", role: "menu" });
      wrap.append(btn, menu);
      nav.append(wrap);
      navGroups.set(p.nav_group, menu);
    }
    navGroups.get(p.nav_group).append(el("a", { href: "#" + p.id, onclick: closeMenus }, p.label));
  }
  document.addEventListener("click", closeMenus);
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") closeMenus(); });
  // Theme precedence: ?theme= deep link > viewer's per-tab pick > bundle default.
  let saved = null;
  try { saved = sessionStorage.getItem("engine-theme"); } catch { /* private mode */ }
  const themeParam = new URLSearchParams(location.search).get("theme");
  const initialTheme = [themeParam, saved, CONFIG.theme && CONFIG.theme.default, "wxdash"]
    .find(t => t && THEMES.some(x => x.id === t));
  if (CONFIG.theme && CONFIG.theme.allow_viewer_switch !== false) {
    document.getElementById("navbar").append(themeSwitcher());
  }
  applyTheme(initialTheme);
  // Guarded: a blocked/failed vendor script must not freeze boot on the
  // loading screen — chartless pages still render, chart pages fail visibly
  // through renderPage's per-component catch.
  if (window.Chart) Chart.defaults.font.family = getComputedStyle(document.body).fontFamily;
  // Config-driven footer: a clear end-of-page bookend (navbar colors).
  if (CONFIG.footer && !document.getElementById("site-footer")) {
    const f = CONFIG.footer;
    const brand = el("div", { class: "foot-brand" },
      el("span", { class: "brand-name" },
         f.name || CONFIG.project.nav_title || CONFIG.project.title));
    if (f.tagline) brand.append(el("p", { class: "foot-tag" }, f.tagline));
    const cols = el("div", { class: "foot-inner" }, brand);
    if (f.links_html) cols.append(el("nav", { class: "foot-links", html: f.links_html }));
    const meta = el("div", { class: "foot-meta" });
    if (f.funding) meta.append(el("p", {}, f.funding));
    meta.append(el("p", { class: "foot-build" }, "BUILD " + (window.WX_BUILD || "dev")));
    cols.append(meta);
    document.body.append(el("footer", { id: "site-footer" }, cols));
  }
  window.addEventListener("hashchange", renderPage);
  // Back and Forward within a page change only the query, which fires no
  // hashchange; the page is drawn again from the address it now shows, so
  // the selection, the chart and the URL agree. A step across pages changes
  // the hash, and hashchange draws that.
  window.addEventListener("popstate", () => {
    if (location.hash === shownHash) renderPage();
  });
  await renderPage();
}

boot();
