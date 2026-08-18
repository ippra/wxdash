/* engine.js — the WxDash dashboard, client side.
 *
 * Renders the site 11_build_dashboard.R assembles: 10_build_static_site.R's
 * question and map data plus a config.json of presentation content. Nothing
 * here computes a statistic — every percentage, CI, rank, percentile and
 * median was precomputed upstream, so this file only ever picks a slice and
 * draws it. That is what lets the site run with no server.
 *
 * Components (registered on the `components` object): explore (the survey
 * question explorer), wx_map_explorer, wx_landing, wx_quiz, static_page.
 * Each receives (pageConfig, container) and renders itself from the files it
 * references.
 *
 * Forked 2026-08-14 from the ShinyRails shared engine (which continues to
 * serve S3OK); this copy serves WxDash alone and is maintained here.
 */

"use strict";

window.WX_ENGINE_LOADED = true; // watchdog diagnostics: proves this file executed

const BUNDLE = (() => {
  // Pre-rendered place-profile stubs live at <bundle>/cwa/XXX/ and set
  // window.WX_BUNDLE = "../../" so fetches resolve to the bundle root.
  const p = window.WX_BUNDLE ||
    new URLSearchParams(location.search).get("bundle") || "./";
  return p.endsWith("/") ? p : p + "/";
})();

let CONFIG = null;
const jsonCache = new Map();

async function fetchJSON(rel) {
  if (jsonCache.has(rel)) return jsonCache.get(rel);
  // Build stamp (set by the bundle's index.html) busts long-lived caches —
  // the c.itation.net Rails static handler serves a 1-year max-age.
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

// cividis (viridisLite option "cividis") — WxDash difference maps/scatter.
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

// Drought-engine idea, scoped: in the greyscale accessibility theme the maps
// repaint in greys (one-motion theme switch); every other theme keeps the
// viridis/cividis data palettes (parity look + colorblind-safe). Charts are
// untouched — this applies to choropleths/scatter ramps only.
function dataStops(stops) {
  return document.documentElement.dataset.theme === "greyscale" ? GREYS_STOPS : stops;
}

// Continuous colour ramp over stop array; t clamped to [0,1]. Used by the
// choropleth components (clamping is a deliberate deviation from R
// colorNumeric, which paints out-of-domain values grey — see deviations).
function rampColor(stops, t) {
  t = Math.max(0, Math.min(1, t));
  const x = t * (stops.length - 1);
  const lo = Math.floor(x), hi = Math.min(lo + 1, stops.length - 1), f = x - lo;
  const c = [0, 1, 2].map(k => Math.round(stops[lo][k] * (1 - f) + stops[hi][k] * f));
  return `rgb(${c[0]},${c[1]},${c[2]})`;
}

/* ---- user-facing data-color schemes (Joe's demo, Aug 2026) --------------
 * The two explorer tabs open in blue and offer viridis and print-safe grey
 * as viewer choices; every other surface keeps the approved viridis look,
 * which is why the default lives here rather than in the scheme list order.
 * The greyscale accessibility theme still overrides ramps via dataStops(). */
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

/* ---- PDF export (Joe's demo affordance; jsPDF vendored per bundle) ------ */
// Composite the visible chart canvas onto the theme's panel background (the
// chart itself is transparent — dark themes would otherwise export
// light-on-white text).
function chartSnapshot(canvas) {
  const out = document.createElement("canvas");
  out.width = canvas.width; out.height = canvas.height;
  const ctx = out.getContext("2d");
  ctx.fillStyle = getComputedStyle(document.body).getPropertyValue("--panel").trim() || "#ffffff";
  ctx.fillRect(0, 0, out.width, out.height);
  ctx.drawImage(canvas, 0, 0);
  return out;
}
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

// Nearest ancestor with a background that actually paints, white if none does.
function opaqueBackdrop(node) {
  for (let n = node; n && n !== document.documentElement; n = n.parentElement) {
    const bg = getComputedStyle(n).backgroundColor;
    if (bg && bg !== "transparent" && !/rgba\(\s*0,\s*0,\s*0,\s*0\s*\)/.test(bg))
      return bg;
  }
  return "#ffffff";
}

// Composite every Leaflet canvas in the map element (basemap + choropleth
// share the map-level canvas renderer; getBoundingClientRect resolves the
// pane transforms). No tiles, no external images — canvas stays untainted.
function mapSnapshot(mapEl) {
  const r = mapEl.getBoundingClientRect();
  const out = document.createElement("canvas");
  out.width = Math.round(r.width * 2); out.height = Math.round(r.height * 2);
  const ctx = out.getContext("2d");
  // The map itself is transparent, so the paper color has to come from the
  // first ancestor that paints one — filling with rgba(0,0,0,0) would leave
  // the snapshot transparent and the PDF would render it black.
  ctx.fillStyle = opaqueBackdrop(mapEl);
  ctx.fillRect(0, 0, out.width, out.height);
  mapEl.querySelectorAll("canvas").forEach(cv => {
    const cr = cv.getBoundingClientRect();
    // drawImage ignores CSS, so any opacity a pane carries has to be walked
    // up and applied by hand or it is lost in the composite.
    let alpha = 1, node = cv;
    while (node && node !== mapEl) {
      alpha *= parseFloat(getComputedStyle(node).opacity) || 1;
      node = node.parentElement;
    }
    ctx.globalAlpha = alpha;
    ctx.drawImage(cv, (cr.left - r.left) * 2, (cr.top - r.top) * 2, cr.width * 2, cr.height * 2);
    ctx.globalAlpha = 1;
  });
  return trimCanvas(out, ctx.fillStyle);
}
// Two map snapshots on one canvas, in the order they sit on the page, so a
// side-by-side comparison prints as the comparison it is.
function mapPairSnapshot(elA, elB) {
  const a = mapSnapshot(elA), b = mapSnapshot(elB);
  const gap = 28;
  const out = document.createElement("canvas");
  out.width = a.width + gap + b.width;
  out.height = Math.max(a.height, b.height);
  const ctx = out.getContext("2d");
  ctx.fillStyle = opaqueBackdrop(elA);
  ctx.fillRect(0, 0, out.width, out.height);
  // Trimmed snapshots can differ by a pixel or two in height; centring keeps
  // the two coastlines on the same line.
  ctx.drawImage(a, 0, (out.height - a.height) / 2);
  ctx.drawImage(b, a.width + gap, (out.height - b.height) / 2);
  return out;
}

// Page prose as a flat block list the PDF flow can set: the lede becomes a
// heading, list items keep their bullet, everything else is a paragraph.
// Reading it off the rendered page rather than re-authoring it is what keeps
// a downloaded sheet saying the same thing as the screen it came from.
function htmlBlocks(html) {
  const root = document.createElement("div");
  root.innerHTML = String(html || "");
  const txt = (n) => (n.textContent || "").replace(/\s+/g, " ").trim();
  const out = [];
  (function walk(node) {
    for (const n of node.children) {
      const tag = n.tagName.toLowerCase();
      if (tag === "ul" || tag === "ol") {
        for (const li of n.children) { const t = txt(li); if (t) out.push({ type: "li", text: t }); }
      } else if (tag === "div" || tag === "section") {
        walk(n);
      } else if (tag === "hr") {
        continue;
      } else {
        const t = txt(n);
        if (!t) continue;
        const head = /^h[1-6]$/.test(tag) || n.classList.contains("wx-lede");
        out.push({ type: head ? "h" : "p", text: t });
      }
    }
  })(root);
  return out;
}

/* A standalone one-or-more page document: header, the plot, its legends, and
 * the page's own notes set in columns underneath, with a footer on every
 * page. The notes are the point — a map or a chart lifted out of the site
 * with no statement of what was asked, how it was scored or where it came
 * from is not something anyone can hand to a third party. */
function pdfDocument({ title, subtitle, canvas, legends, notesHTML, filename }) {
  if (!window.jspdf) { alert("The PDF library did not load — try reloading the page."); return; }
  const landscape = canvas.width >= canvas.height;
  const doc = new window.jspdf.jsPDF({
    orientation: landscape ? "l" : "p", unit: "pt", format: "letter" });
  const pw = doc.internal.pageSize.getWidth(), ph = doc.internal.pageSize.getHeight();
  const M = 44;
  const INK = [46, 42, 87], BODY = [35, 33, 48], GREY = [110, 115, 122],
        RULE = [214, 214, 224];
  const legendList = (legends == null ? [] : [].concat(legends)).filter(Boolean);
  const project = (CONFIG.project && CONFIG.project.nav_subtitle) || "WxDash";
  const stamp = new Date().toLocaleDateString(undefined,
    { year: "numeric", month: "long", day: "numeric" });

  const footer = () => {
    const y = ph - 26;
    doc.setDrawColor(...RULE); doc.setLineWidth(0.5);
    doc.line(M, y - 10, pw - M, y - 10);
    doc.setFont("helvetica", "normal"); doc.setFontSize(7.5); doc.setTextColor(...GREY);
    doc.text(project, M, y);
    doc.text(`Downloaded ${stamp}`, pw - M, y, { align: "right" });
  };

  // --- header
  doc.setFont("helvetica", "bold"); doc.setFontSize(14); doc.setTextColor(...INK);
  const titleLines = doc.splitTextToSize(String(title || ""), pw - 2 * M);
  doc.text(titleLines, M, M + 10);
  let y = M + 10 + titleLines.length * 17;
  if (subtitle) {
    doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(...GREY);
    const subLines = doc.splitTextToSize(String(subtitle), pw - 2 * M);
    doc.text(subLines, M, y);
    y += subLines.length * 11;
  }
  y += 6;
  doc.setDrawColor(...RULE); doc.setLineWidth(0.5);
  doc.line(M, y, pw - M, y);
  y += 16;

  // --- how much room the notes need, before the plot claims the page.
  // Measured with the same wrapping the flow will use, so the plot can be
  // sized to leave exactly enough and the document comes out one page.
  const blocks = htmlBlocks(notesHTML);
  const gap = 30;
  const contentW = pw - 2 * M;
  // Two columns only when there is enough prose to fill them — a short
  // caption set in two columns leaves one of them empty. A lone column runs
  // the full width of the page rather than a reading measure: the notes are
  // the foot of a one-page document, and a narrow block of text under a
  // full-width plot reads as an unfinished page.
  const long = blocks.reduce((n, b) => n + b.text.length, 0) > 700;
  const cols = long ? 2 : 1;
  const colW = long ? (contentW - gap) / 2 : contentW;
  const style = {
    h:  { size: 9.5, font: "bold",   color: INK,  before: 4, after: 4, lead: 12, indent: 0 },
    p:  { size: 8.5, font: "normal", color: BODY, before: 0, after: 7, lead: 11, indent: 0 },
    li: { size: 8.5, font: "normal", color: BODY, before: 0, after: 4, lead: 11, indent: 11 }
  };
  const measured = blocks.map(b => {
    const st = style[b.type];
    doc.setFont("helvetica", st.font); doc.setFontSize(st.size);
    const lines = doc.splitTextToSize(b.text, colW - st.indent);
    return { b, st, lines, height: st.before + lines.length * st.lead + st.after };
  });
  // Column breaks land on block boundaries, so the flow runs a little taller
  // than an even split of the total.
  const notesH = measured.length
    ? measured.reduce((n, m) => n + m.height, 0) / cols * 1.12 : 0;

  // --- plot, sized to what the page has left once the notes are allowed for
  const bottom = ph - 46;
  const maxW = contentW;
  const legendH = legendList.length ? 36 : 0;
  const room = bottom - y - legendH - notesH - 16;
  const maxH = Math.max(ph * 0.26, Math.min(ph * 0.52, room));
  const scale = Math.min(maxW / canvas.width, maxH / canvas.height);
  const w = canvas.width * scale, h = canvas.height * scale;
  const imgX = M + (maxW - w) / 2;
  doc.addImage(canvas.toDataURL("image/png"), "PNG", imgX, y, w, h);
  y += h + 16;

  // --- legends, each under the map it describes. Anchored to the image
  // rather than the page margin: the plot is centred and, when two maps are
  // composited, a second legend measured from the margin lands under the gap
  // between them instead of under its own map.
  legendList.forEach((lg, i) => {
    const slot = w / legendList.length;
    const lx = imgX + i * slot;
    const lw = Math.min(200, slot - 24), steps = 55;
    doc.setFont("helvetica", "normal"); doc.setFontSize(8); doc.setTextColor(...BODY);
    doc.text(String(lg.title || ""), lx, y);
    for (let k = 0; k < steps; k++) {
      const c = rampColor(lg.stops, k / (steps - 1)).match(/\d+/g).map(Number);
      doc.setFillColor(c[0], c[1], c[2]);
      doc.rect(lx + (lw / steps) * k, y + 4, lw / steps + 0.5, 9, "F");
    }
    // lg.fmt keeps 1-5 estimate ends readable ("1.5", not "2") while
    // alert-day counts stay whole numbers.
    const lf = lg.fmt || ((v) => String(Math.round(v)));
    doc.setFontSize(7.5); doc.setTextColor(...GREY);
    doc.text(lf(lg.domain[0]), lx, y + 22);
    doc.text(lf((lg.domain[0] + lg.domain[1]) / 2), lx + lw / 2, y + 22, { align: "center" });
    doc.text(lf(lg.domain[1]), lx + lw, y + 22, { align: "right" });
  });
  if (legendList.length) y += 36;

  // --- notes, flowed into the columns measured above
  if (measured.length) {
    let col = 0, top = y, cy = y;
    const colX = () => M + col * (colW + gap);
    const nextColumn = () => {
      if (col === 0 && cols === 2) { col = 1; cy = top; return; }
      footer(); doc.addPage(); col = 0; top = M; cy = M;
    };
    for (const { b, st, lines } of measured) {
      doc.setFont("helvetica", st.font); doc.setFontSize(st.size);
      // Never leave a heading stranded at the foot of a column.
      const need = st.before + lines.length * st.lead +
        (b.type === "h" ? style.p.lead : 0);
      if (cy + need > bottom && !(cy === top)) nextColumn();
      cy += st.before;
      doc.setTextColor(...st.color);
      for (const line of lines) {
        if (cy + st.lead > bottom) { nextColumn(); doc.setFont("helvetica", st.font); doc.setFontSize(st.size); doc.setTextColor(...st.color); }
        if (b.type === "li" && line === lines[0]) {
          doc.text("•", colX(), cy + st.lead - 3);
        }
        doc.text(line, colX() + st.indent, cy + st.lead - 3);
        cy += st.lead;
      }
      cy += st.after;
    }
  }
  footer();
  doc.save(filename || "wxdash.pdf");
}

function pdfButton(label, onClick) {
  return el("button", { class: "wx-pdf-btn", onclick: onClick }, label);
}

// Charts owned by the current page (WxDash pages can hold several); destroyed
// on navigation alongside the legacy single activeChart.
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
function setParams(obj) {
  const q = new URLSearchParams(location.search);
  for (const [k, v] of Object.entries(obj)) {
    if (v == null || v === "") q.delete(k); else q.set(k, v);
  }
  history.replaceState(null, "", location.pathname + "?" + q.toString() + location.hash);
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

/* Generic table: sort (click header), global search, optional per-column
   filters (Shiny DT filter="top" equivalent), pagination. rows = array of
   objects; columns = [{id, label, width?}]. */
function dataTable({ columns, rows, pageSize = 25, pageSizeOptions = null, columnFilters = true, clickable = false, onRowClick = null, searchFields = [] }) {
  let sortCol = null, sortDir = 1, page = 0, globalQ = "";
  const colQ = {};
  let filtered = rows.slice();
  let selectedRow = null;

  const root = el("div");
  const tools = el("div", { class: "table-tools" });
  const search = el("input", { type: "search", placeholder: "Search…",
    oninput: () => { globalQ = search.value.toLowerCase(); page = 0; refresh(); } });
  const count = el("span", { class: "count" });
  tools.append(search);
  if (pageSizeOptions) {   // viewer-adjustable page length (opt-in per table)
    const psSel = el("select", { onchange: () => {
      pageSize = Number(psSel.value); page = 0; refresh();
    } });
    for (const n of pageSizeOptions) psSel.append(el("option", { value: n }, String(n)));
    psSel.value = String(pageSize);
    tools.append(el("label", { class: "pagesize" }, "Show ", psSel, " rows"));
  }
  tools.append(count);

  const scroll = el("div", { class: "table-scroll" });
  const table = el("table", { class: "data" + (clickable ? " clickable" : "") });
  const thead = el("thead");
  const headRow = el("tr");
  for (const c of columns) {
    const th = el("th", c.width ? { style: `width:${c.width}` } : {});
    const name = el("span", { class: "col-name", onclick: () => {
      if (sortCol === c.id) sortDir = -sortDir; else { sortCol = c.id; sortDir = 1; }
      refresh();
    } }, c.label, " ", el("span", { class: "arrow" }, ""));
    th.append(name);
    if (columnFilters) {
      const inp = el("input", { type: "text", placeholder: "Filter…",
        oninput: () => { colQ[c.id] = inp.value.toLowerCase(); page = 0; refresh(); } });
      th.append(inp);
    }
    headRow.append(th);
  }
  thead.append(headRow);
  const tbody = el("tbody");
  table.append(thead, tbody);
  scroll.append(table);

  const pager = el("div", { class: "pager" });
  const prev = el("button", { onclick: () => { page--; refresh(); } }, "‹ Prev");
  const info = el("span");
  const next = el("button", { onclick: () => { page++; refresh(); } }, "Next ›");
  pager.append(prev, info, next);

  function refresh() {
    filtered = rows.filter(r => {
      // Global search covers the visible columns plus any hidden searchFields
      // (e.g. Joe's content keywords, so "reception" finds questions whose
      // wording never uses the word).
      if (globalQ && !columns.some(c => String(r[c.id] ?? "").toLowerCase().includes(globalQ)) &&
          !searchFields.some(f => String(r[f] ?? "").toLowerCase().includes(globalQ))) return false;
      for (const c of columns) {
        const q = colQ[c.id];
        if (q && !String(r[c.id] ?? "").toLowerCase().includes(q)) return false;
      }
      return true;
    });
    if (sortCol) {
      filtered.sort((a, b) => {
        const av = a[sortCol] ?? "", bv = b[sortCol] ?? "";
        const an = parseFloat(av), bn = parseFloat(bv);
        const cmp = (!isNaN(an) && !isNaN(bn)) ? an - bn : String(av).localeCompare(String(bv));
        return cmp * sortDir;
      });
    }
    const pages = Math.max(1, Math.ceil(filtered.length / pageSize));
    page = Math.min(Math.max(0, page), pages - 1);
    const slice = filtered.slice(page * pageSize, (page + 1) * pageSize);

    tbody.textContent = "";
    for (const r of slice) {
      const tr = el("tr");
      if (r === selectedRow) tr.classList.add("selected");
      for (const c of columns) tr.append(el("td", {}, String(r[c.id] ?? "")));
      if (clickable) tr.addEventListener("click", () => {
        selectedRow = r;
        refresh();
        onRowClick && onRowClick(r);
      });
      tbody.append(tr);
    }
    count.textContent = `${filtered.length} of ${rows.length} rows`;
    info.textContent = `Page ${page + 1} of ${pages}`;
    prev.disabled = page === 0;
    next.disabled = page >= pages - 1;
    headRow.querySelectorAll(".arrow").forEach((a, i) =>
      a.textContent = columns[i].id === sortCol ? (sortDir === 1 ? "▲" : "▼") : "");
  }

  refresh();
  root.append(tools, scroll, pager);
  // Select (and page to) the first row matching pred — for deep-linked rows.
  root.selectRow = (pred) => {
    const i = rows.findIndex(pred);
    if (i >= 0) { selectedRow = rows[i]; page = Math.floor(i / pageSize); refresh(); }
  };
  root.selectFirst = () => root.selectRow(() => true);
  return root;
}

/* Grouped bar chart from long rows [{group, category, value, label}].
   Category axis order + series (group) order = first-appearance order in the
   data (which preserves R's factor-level ordering from the compiler), unless
   an explicit categoryOrder is supplied by config. */
let activeChart = null;
function groupedBarChart(canvas, rows, { title = "", xLabel = "", yLabel = "", categoryOrder = null, showCI = false, horizontal = false, colors = null, legend = true }) {
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
  const datasets = groupsSeen.map((g, i) => ({
    label: g,
    backgroundColor: colors[i],
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

  if (activeChart) { activeChart.destroy(); activeChart = null; }
  activeChart = new Chart(canvas, {
    type: "bar",
    data: { labels: cats.map(tickLines), datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      // horizontal (Joe's Aug-2026 explorer): categories run down the y-axis
      indexAxis: horizontal ? "y" : "x",
      interaction: { mode: "nearest", intersect: false, axis: horizontal ? "y" : "x" },
      layout: { padding: horizontal ? { right: 48 } : { top: 24 } },
      plugins: {
        title: title ? { display: true, text: title, align: "start",
          font: { size: 15, weight: "600" }, padding: { bottom: 16 } } : { display: false },
        // legend:false for single-group charts (quiz reveal) — a one-entry
        // "Group: All" legend is noise.
        legend: legend ? { position: "bottom", title: { display: true, text: "Group" } }
          : { display: false },
        datalabels: showCI ? { display: false } : {
          anchor: "end", align: "end", offset: 0, clip: false,
          color: getComputedStyle(document.body).getPropertyValue("--text").trim() || "#000",
          font: { size: groupsSeen.length > 8 ? 9 : 11 },
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
        y: { title: { display: !!xLabel, text: xLabel }, grid: { display: false } },
        x: { title: { display: !!yLabel, text: yLabel }, beginAtZero: true, grace: "15%" }
      } : {
        x: { title: { display: !!xLabel, text: xLabel }, grid: { display: false } },
        y: { title: { display: !!yLabel, text: yLabel }, beginAtZero: true, grace: "15%" }
      }
    },
    plugins: [ChartDataLabels, ErrorBarsPlugin]   // ErrorBarsPlugin no-ops without errorLow
  });
  return activeChart;
}

/* ------------------------------------------------------------ components -- */

const components = {};

/* Explore: question table + grouping dropdown + distribution chart.
 * Two layouts:
 *  - default: the S3OK/Shiny welcome-sidebar layout (approved, deployed).
 *  - page.layout === "toolbar": Joe's Aug-2026 explorer redesign (WxDash) —
 *    no sidebar; intro line → control bar (Split by + CI toggle) → the
 *    selected question as a heading → full-width chart → caption → table.
 *
 * 2.0 content mode (WxDash, Aug 2026 — Joe's static-site behavior in our
 * formatting) is DATA-driven, not config-driven: when a question file carries
 * `options` (instrument value labels) and `summaries` (per-split respondent
 * counts) and the bundle config carries `explore_caption` templates, bars are
 * labeled with the instrument's own response labels and the caption rewrites
 * itself for the selected split ("… the weighted percentage of each age group
 * giving each answer. The smallest group, X, has N respondents."). S3OK's
 * bundle has none of those fields, so it renders exactly as before. */

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

components.explore = async function (page, container) {
  const questions = await fetchJSON(page.questions.replace(/^data\//, "data/"));
  let grouping = urlGrouping() || page.default_grouping || "All";
  let showCI = getParam("ci") === "1";   // ?ci=1 deep-links the CI view
  let scheme = urlScheme();              // ?scheme= deep-links a color scheme
  let currentQuestionText = "";          // for the PDF title
  let currentSurveyLabel = "";           // and its subtitle line
  // Question files are keyed by `id` — hazard code + variable, because two
  // surveys can share a variable name (alert_und is asked in all four).
  const keyOf = (r) => r.id;
  // ?q=<id> deep-links a question; else row 1.
  const urlQ = getParam("q");
  let currentKey = (urlQ && questions.some(x => keyOf(x) === urlQ))
    ? urlQ : (questions[0] && keyOf(questions[0]));

  const chartCard = el("div", { class: "card" });
  const weightedTip = explain("weighted_pct");
  const wrap = el("div", { class: "chart-wrap" });
  const canvas = el("canvas");
  wrap.append(canvas);

  // Chrome created up front so draw() can update it.
  const qHead = el("h3", { class: "wx-question-head" }, "");
  const caption = el("div", { class: "wx-caption wx-explore-caption" });
  const ciBox = el("input", { type: "checkbox", id: "ci-toggle" });
  ciBox.checked = showCI;
  ciBox.onchange = () => { showCI = ciBox.checked; setParams({ ci: showCI ? "1" : null }); draw(); };
  chartCard.append(qHead, wrap, caption);

  let groupingSel = null;   // set below; draw() updates it on split fallback

  // The split-aware caption (Joe's 2.0 wording, compiler-authored templates
  // in config.explore_caption; provenance carries links + the variable code).
  function renderCaption2(v, g) {
    const tpl = CONFIG.explore_caption;
    const s = v.summaries && v.summaries[g];
    caption.textContent = "";
    if (!s) return;
    const waves = /[-,]/.test(s.years)
      ? fillTpl(tpl.waves_many, { years: s.years })
      : fillTpl(tpl.waves_one, { years: s.years });
    const gcfg = CONFIG.groupings.find(x => x.id === g);
    const splitClause = g === "All" ? ""
      : fillTpl(tpl.split_clause, { group_phrase: (gcfg && gcfg.phrase) || "group" });
    let text = fillTpl(tpl.answered, {
      n: Number(s.n).toLocaleString(), hazard_phrase: v.hazard_phrase,
      waves, split_clause: splitClause });
    if (g !== "All") text += fillTpl(tpl.smallest, {
      smallest: s.smallest, smallest_n: Number(s.smallest_n).toLocaleString() });
    caption.append(el("p", {}, text));
    caption.append(el("p", { class: "wx-caption-provenance",
      html: fillTpl(tpl.provenance, { variable: esc(v.variable) }) }));
  }

  async function draw() {
    if (!currentKey) return;
    const v = await fetchJSON(`data/q/${currentKey}.json`);
    // A question is not asked under every split — fall back to Everyone
    // rather than drawing an empty panel, and show the select doing it.
    let g = grouping;
    if (!(v.splits[g] && v.splits[g].length)) g = "All";
    if (groupingSel) groupingSel.value = g;
    const labelFor = (resp) => {
      const hit = (v.options || []).find(o => String(o.value) === String(resp));
      // An unlabelled value is shown as itself rather than dropped: it means
      // the data carries a code the instrument does not document.
      return hit ? hit.label : String(resp);
    };
    currentQuestionText = v.question || currentKey;
    currentSurveyLabel = [v.hazard, v.variable && `Variable ${v.variable}`]
      .filter(Boolean).join("  ·  ");
    qHead.textContent = v.question || currentKey;
    if (weightedTip) qHead.append(" ", infoTip(weightedTip));
    renderCaption2(v, g);
    const rows = (v.splits[g] || []).map(r => ({
      group: r.group, category: wrapTickLabel(labelFor(r.resp)),
      value: r.p, label: Math.round(r.p) + "%", low: r.p_low, upp: r.p_upp
    }));
    // Horizontal bars need vertical room proportional to bar count —
    // grow the canvas instead of cramming (long scales × many groups).
    const nCats = new Set(rows.map(r => naLabel(r.category))).size;
    const nGroups = new Set(rows.map(r => naLabel(r.group))).size;
    wrap.style.height =
      Math.max(340, Math.min(1000, 130 + nCats * Math.max(34, nGroups * 18))) + "px";
    groupedBarChart(canvas, rows, {
      title: "",
      xLabel: page.chart.x_label, yLabel: page.chart.y_label,
      showCI,
      horizontal: true,
      colors: schemeSeriesColors(scheme, new Set(rows.map(r => naLabel(r.group))).size)
    });
  }

  const tableCard = el("div", { class: "card" });
  tableCard.append(el("h3", {}, "Questions (click on a question)"));
  const qTable = dataTable({
    columns: [
      { id: "hazard", label: "Survey", width: "20%" },
      { id: "question", label: "Question Text", width: "62%" },
      { id: "kind", label: "Type" }
    ],
    rows: questions, pageSize: 10, clickable: true,
    // Search also matches the variable name, scale id and content keywords
    // ("reception" finds questions whose wording never uses the word).
    searchFields: ["variable", "response_scale", "keywords"],
    pageSizeOptions: [10, 25, 50, 100],
    onRowClick: (r) => {
      currentKey = keyOf(r);
      setParams({ q: currentKey });   // keep the URL shareable
      // The chart lives well above the table — scroll it into view so the
      // click visibly loads the new question.
      window.scrollTo({ top: 0, behavior: "smooth" });
      draw();
    }
  });
  if (currentKey === urlQ) qTable.selectRow(r => keyOf(r) === urlQ);
  else qTable.selectFirst();
  tableCard.append(qTable);

  const intro = el("p", { class: "wx-explore-intro" }, page.intro ||
    "Click a survey question in the table below to see the weighted distribution of responses, split by the group you choose.");
  const bar = el("div", { class: "card wx-toolbar" });
  const gWrap = groupingSelect(g => { grouping = g; draw(); }, grouping, "Split responses by");
  groupingSel = gWrap.querySelector("select");
  bar.append(gWrap);
  bar.append(schemeSelect(scheme, (sc) => {
    scheme = sc;
    setParams({ scheme: sc === DEFAULT_SCHEME ? null : sc });
    draw();
  }));
  bar.append(el("label", { class: "wx-ci-label", for: "ci-toggle" },
    ciBox, " Show 95% confidence intervals"));
  // The caption below the chart is the document's notes: how many answered,
  // that the percentages are weighted, which waves, the smallest group, and
  // the provenance with the variable code. A chart without them cannot be
  // handed to anyone.
  bar.append(pdfButton("Download chart (PDF)", () => pdfDocument({
    title: currentQuestionText,
    subtitle: [
      currentSurveyLabel,
      grouping === "All" ? "All respondents"
        : "Split by " + ((CONFIG.groupings.find(x => x.id === grouping) || {}).label || grouping),
      showCI ? "95% confidence intervals shown" : null
    ].filter(Boolean).join("  ·  "),
    canvas: chartSnapshot(canvas),
    notesHTML: caption.innerHTML,
    filename: `wxdash-${currentKey}.pdf`
  })));
  container.append(el("div", { class: "page wx-explore-page" },
    el("div", { class: "content" }, intro, bar, chartCard, tableCard)));
  await draw();
};

/* ----------------------------------------------- WxDash components ------ */
/* Components for the WxDash bundle (compile_wxdash.R). They render only
 * precomputed values: APP percentiles, place-vs-place percentiles, srvyr
 * distributions and CIs all come from the bundle — the engine never computes
 * statistics (platform parity guarantee). */

// Measure catalog helpers (config.catalog rows from the compiler).
const catalogByCode = () => new Map(CONFIG.catalog.map(c => [c.code, c]));

/* ---- methodology affordances --------------------------------------------
 * "What does this number mean?" popovers replace sidebar prose walls. All
 * text is compiler-authored in config.explainers (templated with {tokens}),
 * so the engine stays generic. Panels open BELOW their trigger. */

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
// no third-party requests — basemap choice is an open design decision).
async function baseMap(mapEl, opts = {}) {
  const map = L.map(mapEl, {
    renderer: L.canvas(),                       // ~3k county polygons: canvas, not SVG
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
  // end of a ramp now that the map has no background of its own, taking the
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
      // Hover-to-read (Joe's map page): sticky tooltip with the value.
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

/* ---- 2.0 map-story helpers (Joe's app.js narrative machinery, ported) ---- */

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
    .replace(/ alert days$/, "")
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

/* The scan sheet as a vector PDF (Joe's 09 overview sheet): rows drawn with
 * jsPDF primitives rather than snapshotted, so labels and numbers stay
 * selectable and the marks stay sharp at any zoom. Paginates on row count —
 * a longer catalog spills onto a second page rather than shrinking to fit,
 * which is what keeps the sheet the same size whichever area it is for. */
function scanPDF({ title, subtitle, sections, note, filename }) {
  if (!window.jspdf) { alert("The PDF library did not load — try reloading the page."); return; }
  const doc = new window.jspdf.jsPDF({ orientation: "p", unit: "pt", format: "letter" });
  const pw = doc.internal.pageSize.getWidth(), ph = doc.internal.pageSize.getHeight();
  const margin = 40;
  // Fixed inks rather than the theme's: a sheet is printed, and the dark
  // theme's paper colors would come out as ink on white.
  const INK = [46, 42, 87], BODY = [35, 33, 48], GREY = [110, 115, 122],
        TICK = [184, 190, 197], BAND = [244, 246, 248], DOT = [68, 58, 131];
  const SW = 200;                                    // strip width
  const X = { label: margin, lo: 200, strip: 205, hi: 412, value: 508, pct: pw - margin };
  // Sized so the whole catalog and its footnote land on one letter page —
  // a sheet that spills is a sheet nobody prints double-sided correctly.
  const rowH = 14, sectionH = 16;
  let y = margin;

  const columnHeads = () => {
    doc.setFont("helvetica", "bold"); doc.setFontSize(7.2); doc.setTextColor(...GREY);
    doc.text("LOWEST AREA TO HIGHEST AREA", X.strip + SW / 2, y, { align: "center" });
    doc.text("ESTIMATE", X.value, y, { align: "right" });
    doc.text("PERCENTILE", X.pct, y, { align: "right" });
    doc.setFont("helvetica", "normal");
    y += 9;
  };
  const room = (need) => {
    if (y + need <= ph - margin) return;
    doc.addPage(); y = margin; columnHeads();
  };

  doc.setFont("helvetica", "bold"); doc.setFontSize(16); doc.setTextColor(...INK);
  doc.text(String(title), margin, y + 6);
  y += 22;
  doc.setFont("helvetica", "normal"); doc.setFontSize(9); doc.setTextColor(...GREY);
  doc.text(String(subtitle), margin, y);
  y += 16;

  // The key is drawn rather than spelled out: the marks are the only thing
  // explaining what a row means, and a character key cannot show a triangle.
  doc.setFontSize(8);
  let kx = margin;
  const keyMark = (draw, label) => {
    draw(kx + 3);
    doc.setTextColor(...GREY);
    doc.text(label, kx + 10, y + 3);
    kx += 10 + doc.getTextWidth(label) + 18;
  };
  keyMark((x) => { doc.setDrawColor(...TICK); doc.setLineWidth(0.8);
                   doc.line(x, y - 3, x, y + 4); }, "each area");
  keyMark((x) => { doc.setFillColor(...GREY);
                   doc.triangle(x - 3, y + 4, x + 3, y + 4, x, y, "F"); }, "median");
  keyMark((x) => { doc.setFillColor(...DOT); doc.circle(x, y, 2.6, "F"); }, "this area");
  y += 14;
  columnHeads();

  for (const s of sections) {
    room(sectionH + rowH);
    doc.setFillColor(...INK);
    doc.rect(margin, y, pw - 2 * margin, sectionH - 3, "F");
    doc.setFont("helvetica", "bold"); doc.setFontSize(8);
    doc.setTextColor(255, 255, 255);
    doc.text(String(s.group).toUpperCase(), margin + 6, y + sectionH - 8);
    if (s.unit) doc.text(String(s.unit).toUpperCase(), pw - margin - 6,
                         y + sectionH - 8, { align: "right" });
    y += sectionH;

    s.rows.forEach((r, i) => {
      room(rowH);
      if (i % 2) { doc.setFillColor(...BAND); doc.rect(margin, y, pw - 2 * margin, rowH, "F"); }
      const midY = y + rowH / 2;
      doc.setFont("helvetica", "normal"); doc.setFontSize(8.4); doc.setTextColor(...BODY);
      doc.text(doc.splitTextToSize(r.label, X.lo - X.label - 10)[0], X.label, midY + 3);
      doc.setFontSize(7); doc.setTextColor(...GREY);
      doc.text(r.loText, X.lo, midY + 3, { align: "right" });
      doc.text(r.hiText, X.hi, midY + 3);

      const span = r.hi - r.lo;
      const at = (v) => span === 0 ? X.strip + SW / 2
        : X.strip + 4 + (v - r.lo) / span * (SW - 8);
      doc.setDrawColor(...TICK); doc.setLineWidth(0.5);
      for (const v of r.values) doc.line(at(v), midY - 4, at(v), midY + 4);
      const mid = at(r.median);
      doc.setFillColor(...GREY);
      doc.triangle(mid - 3, midY + 7, mid + 3, midY + 7, mid, midY + 3, "F");
      doc.setFillColor(...DOT);
      doc.circle(at(r.here), midY, 2.6, "F");

      doc.setFont("helvetica", "bold"); doc.setFontSize(8.8); doc.setTextColor(...INK);
      doc.text(r.valueText, X.value, midY + 3, { align: "right" });
      doc.setFont("helvetica", "normal"); doc.setFontSize(8); doc.setTextColor(...GREY);
      doc.text(r.pctText, X.pct, midY + 3, { align: "right" });
      y += rowH;
    });
  }

  if (note) {
    doc.setFont("helvetica", "normal"); doc.setFontSize(7); doc.setTextColor(...GREY);
    const lines = doc.splitTextToSize(String(note), pw - 2 * margin);
    room(lines.length * 9 + 12);
    y += 11;
    doc.text(lines, margin, y, { lineHeightFactor: 1.3 });
  }
  doc.save(filename || "wxdash-overview.pdf");
}

/* Map Explorer — 2.0 (Joe's estimates + alert layers, our layout): top
 * toolbar, fixed-frame full-width CWA map, hover tooltips, click popup with
 * the full place story (value, rank, percentile, median, strip plot — Joe's
 * popup-only pattern, user ruling 2026-08-13), per-measure notes below.
 * Comparison = ONE thing, the NWS alert-day history, drawn as a second map
 * beside the first (replaces the 1.0 SVI comparison, user ruling 2026-08-13;
 * side by side rather than crossfaded, user ruling 2026-08-18). */
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
  // Estimates print as "3.42 out of 5"; alert counts as whole days — never
  // "342.00 days" (Joe's formatValue/formatRange split).
  const fmtVal = (code) => (v) => isAlert(code)
    ? Math.round(v).toLocaleString() : Number(v).toFixed(2);
  const fmtRange = (code) => (v) => isAlert(code)
    ? Math.round(v).toLocaleString() : Number(v).toFixed(1);

  // Comparison state: one alert layer, drawn as a second map beside the
  // first (Joe's ruling, Aug 2026 — a crossfade shows one picture at a time
  // and asks the reader to hold the other in memory). ?compare= deep-links it.
  const alertCats = cats.filter(c => c.kind === "alert");
  let compare = alertCats.some(c => c.code === getParam("compare"))
    ? getParam("compare") : "";
  setParams({ mix: null });   // retires the crossfade's parameter on old links

  // --- top control bar (controls across the top, full-width map below)
  const lead = el("p", { class: "wx-explore-intro" }, page.sidebar_lead || "");
  const aboutHtml = explain("about_estimates");
  if (aboutHtml) lead.append(" ", infoTip(aboutHtml, { label: "About the estimates" }));

  const bar = el("div", { class: "card wx-toolbar wx-map-toolbar" });
  const measureSel = el("select", { class: "grouping", id: "measure-sel", onchange: () => {
    measure = measureSel.value; setParams({ measure });
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
    "Select a measure to explore"), measureSel);

  const compareWrap = el("div");
  const compareSel = el("select", { class: "grouping", id: "compare-sel", onchange: async () => {
    compare = compareSel.value;
    setParams({ compare: compare || null });
    await redraw();
  } });
  compareWrap.append(el("label", { class: "field-label", for: "compare-sel" },
    "Compare with alert history"), compareSel);
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

  bar.append(measureWrap, compareWrap);
  bar.append(schemeSelect(scheme, async (sc) => {
    scheme = sc;
    setParams({ scheme: sc === DEFAULT_SCHEME ? null : sc });
    await redraw();
  }));
  // The notes card below the maps is the document's notes: what was asked,
  // how it was scored, how the colors are stretched, where it came from —
  // and, while comparing, the same for the alert history beside it.
  bar.append(pdfButton("Download map (PDF)", () => {
    const cat = byCode.get(measure);
    const cmp = compare ? byCode.get(compare) : null;
    pdfDocument({
      title: (cat ? cat.label : measure) +
        (cmp ? " and " + cmp.label : ""),
      subtitle: `NWS County Warning Area ` +
        (isAlert(measure) ? "alert days" : "estimates") +
        `  ·  ${N} areas of the contiguous United States`,
      canvas: cmp ? mapPairSnapshot(mapEl, mapElB) : mapSnapshot(mapEl),
      notesHTML: notesCard.innerHTML,
      filename: `wxdash-map-${measure}${cmp ? "-vs-" + compare : ""}.pdf`,
      legends: cmp ? [lastLegend, lastLegendB] : lastLegend
    });
  }));
  const clearBtn = el("button", { class: "wx-clear-btn wx-toolbar-clear",
    type: "button", onclick: () => clearPlace() }, "Clear selection");
  clearBtn.style.display = "none";
  bar.append(clearBtn);

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
  card.append(pairEl);
  const notesCard = el("div", { class: "card wx-map-notes" });
  const scanCard = el("div", { class: "card wx-scan-card" });
  // Notes first, then the scan sheet: what the map is showing has to be read
  // before one area's standing on it means anything.
  container.append(el("div", { class: "page wx-explore-page wx-map-page" },
    el("div", { class: "content" }, lead, bar, card, notesCard, scanCard)));

  // Fixed-frame map (Joe's design): the page scrolls normally over it — no
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

  // --- scan sheet: every measure for one area, under the map (Joe's 09 CWA
  // overview sheet, on the page). It computes nothing — values, medians and
  // percentiles are the ones cwa_values.json already carries, so a row and
  // the popup above it cannot disagree.
  const scanCfg = (CONFIG.map && CONFIG.map.scan) || {};
  let place = (getParam("place") || "").toUpperCase();
  if (place && !cwaValues.places[place]) place = "";

  function clearPlace() {
    place = "";
    setParams({ place: null });
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
        // A whole group of alert layers is counted days rather than a 1-5
        // estimate, and the Estimate column heading would otherwise read as
        // a claim about the counts.
        unit: rows.every(c => c.kind === "alert") ? "days" : "",
        rows
      };
    });
  }

  function downloadScan() {
    const label = (cwaValues.places[place] || {}).label || place;
    scanPDF({
      title: label,
      subtitle: `County Warning Area overview · ${place} · ` +
        `${CONFIG.project.nav_subtitle || CONFIG.project.nav_title || ""}`,
      sections: scanSections().map(s => ({
        group: s.group, unit: s.unit,
        rows: s.rows.map(cat => {
          const r = scanRow(cat);
          return {
            label: cat.label, values: r.values, here: r.here,
            median: r.median, lo: r.lo, hi: r.hi,
            loText: fmtRange(cat.code)(r.lo), hiText: fmtRange(cat.code)(r.hi),
            valueText: fmtVal(cat.code)(r.here), pctText: ordinal(r.pct)
          };
        })
      })),
      note: [scanCfg.lede, scanCfg.note].filter(Boolean).map(plainText).join(" "),
      filename: `wxdash-overview-${place.toLowerCase()}.pdf`
    });
  }

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
      el("div", {},
        el("h3", { class: "wx-scan-title" }, label),
        el("p", { class: "wx-scan-sub" },
          `County Warning Area overview · ${place} · ${cats.length} measures`)),
      el("div", { class: "wx-scan-actions" },
        pdfButton("Download overview (PDF)", downloadScan),
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
            setParams({ measure });
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
    setParams({ place });
    // Through the layers rather than straight to renderScan, so the area is
    // outlined on the maps as well as filled in below them.
    selectPlace(place);
    scanCard.scrollIntoView({ behavior: "smooth", block: "start" });
  });

  // The popup's one-paragraph place story (Joe's narrative(), templates from
  // config.map.popup). rank/pct/median are compiler-precomputed — the engine
  // only assembles the sentence.
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
    // would be false in the middle of the distribution (Joe's design note).
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
    setParams({ place });
    renderScan();
    if (syncing) return;
    syncing = true;
    if (activeLayer) activeLayer.selectById(place, null, false, false);
    if (compareLayer) compareLayer.selectById(place, null, false, false);
    syncing = false;
  }

  // One choropleth, built the same way for either pane. Colors stretch over
  // the measure's own observed range (Joe's 2.0 design): on a shared 1-5
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
    const kind = isAlert(code) ? "Alert days" : "Estimate (1\u20135 scale)";
    const m = M(code);
    holder.append(gradientLegend(
      withLabel ? kind + " \u2014 " + esc(byCode.get(code).label) : kind,
      m.domain, stops, fmtRange(code)));
    return { title: kind + " \u2014 " + byCode.get(code).label,
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
    paneB.title.textContent = compareCat ? compareCat.label : "";

    if (activeLayer) map.removeLayer(activeLayer);
    activeLayer = buildChoro(measure, map, stops, () => compareLayer);

    if (compareLayer) { mapB.removeLayer(compareLayer); compareLayer = null; }
    if (compare) compareLayer = buildChoro(compare, mapB, compareStops,
                                           () => activeLayer);

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
  await redraw();
};

/* Landing page — survey-first (Joe's direction, Aug 2026): headline and CTA
 * into the survey explorer, beside a live flagship-question chart with the
 * explorer's own grouping split. The choropleth hero lives on Find Your
 * Place (wx_places) now. */
components.wx_landing = async function (page, container) {
  const h = page.hero || {};
  const surveyPage = CONFIG.pages.find(p => p.component === "explore");
  const mapPage = CONFIG.pages.find(p => p.component === "wx_map_explorer");

  const hero = el("section", { class: "wx-hero wx-hero-survey" });
  const content = el("div", { class: "wx-hero-content" });
  if (h.eyebrow) content.append(el("p", { class: "wx-eyebrow" }, h.eyebrow));
  content.append(el("h1", {}, h.headline || CONFIG.project.title));
  if (h.sub) content.append(el("p", { class: "wx-hero-sub" }, h.sub));
  // Entering the explorer lands on the example question shown here (with the
  // chosen split carried along), so people continue from what they saw.
  const flagship = h.question || "alert_und";
  const intoExplorer = () => setParams({
    q: flagship,
    grouping: sel.value !== "All" ? sel.value : null
  });
  if (surveyPage) content.append(el("p", { class: "wx-hero-cta" },
    el("a", { class: "wx-cta-button", href: "#" + surveyPage.id, onclick: intoExplorer },
      h.cta_label || "Explore the survey results")));
  if (mapPage) content.append(el("p", { class: "wx-hero-alt" },
    "Looking for one place? ",
    el("a", { href: "#" + mapPage.id }, "Explore your forecast office's community"),
    " on the map."));
  const metaLine = el("p", { class: "wx-meta-line" });
  content.append(metaLine);

  // Live flagship chart — real explorer data drawn by the explorer's own
  // chart code, with the grouping select as a working teaser of the split
  // feature. Everything routes into #survey.
  const chartCard = el("div", { class: "card wx-hero-chartcard" });
  const chartTitle = el("h3", {}, "");
  const wrap = el("div", { class: "chart-wrap wx-hero-chartwrap" });
  const canvas = el("canvas");
  wrap.append(canvas);
  const controls = el("div", { class: "wx-hero-chartbar" });
  const splitLabel = el("label", { class: "field-label", for: "hero-split" }, "Split by");
  const sel = el("select", { class: "grouping", id: "hero-split" });
  for (const g of CONFIG.groupings || [{ id: "All", label: "All" }])
    sel.append(el("option", { value: g.id }, g.label));
  sel.value = "All";
  const caption = el("p", { class: "wx-caption" });
  controls.append(splitLabel, sel);
  chartCard.append(chartTitle, controls, wrap, caption);
  hero.append(content, chartCard);

  const directory = el("div", { class: "card wx-directory-card" });
  const grid = el("div", { class: "wx-directory" });
  for (const p of CONFIG.pages.filter(p => p.blurb && !p.hidden)) {
    const a = el("a", { class: "wx-dir-row", href: "#" + p.id });
    a.append(el("h3", {}, p.label), el("p", {}, p.blurb));
    grid.append(a);
  }
  directory.append(grid);

  container.append(el("div", { class: "page wx-landing-page" },
    el("div", { class: "content" }, hero, directory)));

  // Meta line: real numbers from the bundle (2.0: CWA-only — no counties).
  try {
    const [meta, cwaValues] = await Promise.all([
      fetchJSON("data/meta.json"), fetchJSON("data/map/cwa_values.json")]);
    const years = meta.years || [];
    metaLine.innerHTML =
      `<b>${Number(meta.rows).toLocaleString()}</b> survey responses · ` +
      `<b>${years[0]}–${years[years.length - 1]}</b> · ` +
      `<b>${cwaValues.areas}</b> forecast offices`;
  } catch { metaLine.remove(); }

  // Flagship question: compiler-chosen (hero.question), explorer data.
  try {
    if (!surveyPage) { chartCard.remove(); return; }
    const [v, questions] = await Promise.all([
      fetchJSON(`data/q/${flagship}.json`),
      fetchJSON(surveyPage.questions)]);
    chartTitle.textContent = v.question || flagship;
    const labelFor = (resp) => {
      const hit = (v.options || []).find(o => String(o.value) === String(resp));
      return hit ? wrapTickLabel(hit.label) : String(resp);
    };
    const draw = () => {
      const g = (v.splits[sel.value] && v.splits[sel.value].length)
        ? sel.value : "All";   // same not-asked-under-this-split fallback as the explorer
      const rows = (v.splits[g] || []).map(r => ({
        group: r.group, category: labelFor(r.resp), value: r.p,
        label: Math.round(r.p) + "%"
      }));
      // Same orientation as the explorer it advertises.
      groupedBarChart(canvas, rows,
        { xLabel: "Response", yLabel: "Respondents (%)", horizontal: true });
    };
    sel.onchange = draw;
    caption.append(`One of ${questions.length} questions in the survey — `,
      el("a", { href: "#" + surveyPage.id, onclick: intoExplorer }, "explore them all"), ".");
    draw();
  } catch { chartCard.remove(); }
};

/* Test Your Knowledge — Joe's quiz (Aug 2026): each question is guess the
 * national result, then guess the subgroup, then a deep link into the
 * dashboard to see why. Content + answer keys are compiler-authored
 * (config.pages[quiz].questions) and derived from bundle data.
 *
 * Visual pass (Aug 2026): answering reveals the REAL distribution as a chart
 * drawn from the same data/q/ file the explorer uses (part 1 = national,
 * follow-up = the compiler's subgroup split), a segmented progress bar
 * tracks ✓/✗, and every reveal + the finale recap deep-link into the survey
 * explorer — Joe's ask: people should be able to exit the quiz at any point
 * to dive into whatever piqued their interest. */
components.wx_quiz = async function (page, container) {
  const quiz = page.questions || [];
  // Prompts number straight through 1..N (Matthew: "1 of 5" was confusing
  // when ten prompts get asked); follow-ups keep their label.
  const partsOf = (q) => [q.part1, q.part2].filter(Boolean);
  const totalPrompts = quiz.reduce((t, q) => t + partsOf(q).length, 0);
  const promptsBefore = quiz.map((_, i) =>
    quiz.slice(0, i).reduce((t, q) => t + partsOf(q).length, 0));
  let idx = 0, score = 0, answered = 0;
  const results = quiz.map(() => []);   // per-question ✓/✗, feeds progress + recap
  const card = el("div", { class: "card wx-quiz-card" });
  container.append(el("div", { class: "page wx-quiz-page" },
    el("div", { class: "content" }, card)));

  // One segment per prompt; ✓/✗ glyphs carry the state (greyscale theme —
  // never color alone), the outlined segment is where you are.
  const progress = el("div", { class: "wx-quiz-progress" });
  function drawProgress() {
    progress.textContent = "";
    progress.setAttribute("aria-label",
      `${answered} of ${totalPrompts} answered, ${score} right`);
    const flat = results.flat();
    for (let i = 0; i < totalPrompts; i++) {
      const seg = el("span", { class: "wx-quiz-seg" });
      if (i < flat.length) {
        seg.classList.add(flat[i] ? "correct" : "wrong");
        seg.textContent = flat[i] ? "✓" : "✗";
      } else if (i === flat.length) seg.classList.add("current");
      progress.append(seg);
    }
  }

  // Wrong-answer lead-ins rotate, never repeating back-to-back (Matthew: a
  // flat "Not quite" on every miss reads robotic). Keep them friendly, in
  // the "not quite" register — earlier blunter drafts read snarky — and
  // free of factual claims ("so close!" could be false); the reveal
  // sentence carries the data, these only soften the miss.
  const WRONG_LEADS = ["Not quite — ", "Good guess, but not quite — ",
    "Not exactly — ", "A tricky one — ", "This one surprises many people — "];
  let lastLead = -1;
  function wrongLead() {
    let i;
    do { i = Math.floor(Math.random() * WRONG_LEADS.length); }
    while (i === lastLead);
    lastLead = i;
    return WRONG_LEADS[i];
  }

  // Explorer deep link. grouping=null keeps the compiler's split (the
  // follow-up's subject); part 1 passes "All" for the national view.
  function exploreLink(q, grouping, label) {
    if (!q.explore) return null;
    const params = Object.assign({}, q.explore.params,
      grouping ? { grouping } : null);
    return el("a", { class: "wx-quiz-explore", href: q.explore.href,
      onclick: () => q.explore.params && setParams(params) },
      label || q.explore.label || "See the data");
  }

  function renderQ() {
    card.textContent = "";
    card.append(progress);
    drawProgress();
    if (idx >= quiz.length) {
      card.append(el("p", { class: "wx-eyebrow" }, "Done"));
      card.append(el("h2", { class: "wx-quiz-q wx-quiz-score" },
        `You got ${score} of ${answered} right.`));
      card.append(el("p", { class: "wx-note" },
        "Every answer lives in the dashboard — the interesting part is why. Keep exploring."));
      // Recap: one row per question, marks + topic + its explorer deep link.
      const topicOf = (q) => {
        const s = q.part1.prompt;
        return s.length > 76 ? s.slice(0, 76).replace(/\s+\S*$/, "") + "…" : s;
      };
      card.append(el("div", { class: "wx-quiz-recap" },
        ...quiz.map((q, i) => el("div", { class: "wx-quiz-recap-row" },
          el("span", { class: "wx-quiz-recap-marks" },
            results[i].map(ok => ok ? "✓" : "✗").join(" ")),
          el("span", { class: "wx-quiz-recap-topic" }, topicOf(q)),
          exploreLink(q, null, "explore ↗")))));
      card.append(el("div", { class: "wx-quiz-nav" },
        el("a", { class: "wx-cta-button", href: "#survey" }, "Explore the survey questions"),
        el("button", { class: "wx-quiz-again", onclick: () => {
          idx = 0; score = 0; answered = 0;
          results.forEach(r => { r.length = 0; });
          renderQ();
        } }, "Start over")));
      return;
    }
    const q = quiz[idx];
    // Prefetch the question's data file so the reveal chart is instant;
    // null (missing id or fetch failure) just means no chart renders.
    const dataPromise = (q.explore && q.explore.params && q.explore.params.q)
      ? fetchJSON(`data/q/${q.explore.params.q}.json`).catch(() => null)
      : Promise.resolve(null);
    if (idx === 0 && answered === 0 && page.intro)
      card.append(el("p", { class: "wx-note wx-quiz-intro" }, page.intro));
    const eyebrow = el("p", { class: "wx-eyebrow" });
    card.append(eyebrow);
    const parts = partsOf(q);
    let part = 0;
    const zone = el("div");
    card.append(zone);

    // The real data behind the prompt just answered: national split for
    // part 1, the compiler's subgroup split for the follow-up — the same
    // rows/orientation the explorer will show when they click through.
    // Exception: a part carrying compiler-emitted `chart` rows (a prompt
    // that compares several survey variables, so no single data/q file
    // matches) charts those rows instead.
    function revealChart(pp) {
      const grouping = part === 0 ? "All"
        : ((q.explore && q.explore.params && q.explore.params.grouping) || "All");
      const grouped = !pp.chart && grouping !== "All";
      const panel = el("div", { class: "wx-quiz-chart" });
      panel.append(el("p", { class: "wx-eyebrow" }, "What the survey says"));
      const wrap = el("div", {
        class: "wx-quiz-chartwrap" + (grouped ? " grouped" : "") });
      const canvas = el("canvas");
      wrap.append(canvas);
      const cap = el("p", { class: "wx-caption" });
      panel.append(wrap, cap);
      if (pp.chart) {
        cap.append("Weighted survey estimates — ",
          exploreLink(q, "All", "open in the survey explorer"), ".");
        groupedBarChart(canvas, pp.chart.rows,
          { yLabel: pp.chart.y_label, horizontal: true, legend: false });
        return panel;
      }
      dataPromise.then(v => {
        if (!v || !v.splits) { panel.remove(); return; }
        const g = (v.splits[grouping] && v.splits[grouping].length) ? grouping : "All";
        const labelFor = (resp) => {
          const hit = (v.options || []).find(o => String(o.value) === String(resp));
          return hit ? wrapTickLabel(hit.label) : String(resp);
        };
        const rows = (v.splits[g] || []).map(r => ({
          group: r.group, category: labelFor(r.resp), value: r.p,
          label: Math.round(r.p) + "%"
        }));
        if (!rows.length) { panel.remove(); return; }
        const gLabel = (CONFIG.groupings.find(x => x.id === g) || {}).label;
        cap.append(g === "All"
          ? "Weighted national distribution — " : `Split by ${gLabel} — `,
          exploreLink(q, g === "All" ? "All" : null, "open in the survey explorer"), ".");
        groupedBarChart(canvas, rows, { yLabel: "Respondents (%)",
          horizontal: true, legend: g !== "All" });
      });
      return panel;
    }

    function renderPart() {
      eyebrow.textContent =
        `Question ${promptsBefore[idx] + part + 1} of ${totalPrompts}` +
        (part > 0 ? " — follow-up" : "");
      zone.textContent = "";
      const pp = parts[part];
      const step = el("div", { class: "wx-quiz-step" });
      zone.append(step);
      step.append(el("h3", { class: "wx-quiz-q" }, pp.prompt));
      const opts = el("div", { class: "wx-quiz-opts" });
      pp.options.forEach((o, i) => {
        opts.append(el("button", { class: "wx-quiz-opt", onclick: () => {
          answered++;
          const right = i === pp.answer;
          if (right) score++;
          results[idx].push(right);
          drawProgress();
          opts.querySelectorAll("button").forEach((bb, j) => {
            bb.disabled = true;
            if (j === pp.answer) { bb.classList.add("correct"); bb.prepend("✓ "); }
            else if (j === i) { bb.classList.add("wrong"); bb.prepend("✗ "); }
          });
          const fb = el("div", { class: "wx-quiz-reveal", role: "status" },
            el("p", {}, (right ? "Right. " : wrongLead()) + pp.reveal));
          const nav = el("div", { class: "wx-quiz-nav" });
          if (part + 1 < parts.length) {
            nav.append(el("button", { class: "wx-cta-button", onclick: () => {
              part++; renderPart();
            } }, "Follow-up question"));
          } else {
            nav.append(el("button", { class: "wx-cta-button", onclick: () => {
              idx++; renderQ(); window.scrollTo({ top: 0, behavior: "smooth" });
            } }, idx + 1 < quiz.length ? "Next question" : "Finish"));
          }
          step.append(fb, revealChart(pp), nav);
        } }, o));
      });
      step.append(opts);
    }
    renderPart();
  }
  renderQ();
};

/* Static page (About) — compiler-authored HTML from config. */
components.static_page = async function (page, container) {
  container.append(el("div", { class: "page" },
    el("div", { class: "content" },
      el("div", { class: "card wx-static", html: page.html || "" }))));
};

/* ------------------------------------------------------------- routing -- */

function currentPageId() {
  return location.hash.replace(/^#/, "") || CONFIG.pages[0].id;
}

async function renderPage() {
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

/* ---- viewer theme switcher (user-approved roster, 2026-07-07) ----------- */
// Themes restyle chrome only; chart data colors stay viridis in all of them.
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
  if (rerender) renderPage();
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
  navTitle.append(el("span", { class: "brand-name" }, CONFIG.project.nav_title || CONFIG.project.title));
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
    if (p.hidden) continue; // e.g. the place-profile page (reached via stubs/search)
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
      el("span", { class: "brand-name" }, CONFIG.project.nav_title || CONFIG.project.title));
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
  await renderPage();
}

boot();
