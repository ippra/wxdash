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
 * Viridis stays the default everywhere; "Blue (one hue)" and "Grey (print
 * safe)" are viewer choices offered on the survey explorer and map explorer
 * only — every other surface keeps the approved viridis look. The greyscale
 * accessibility theme still overrides ramps via dataStops(). */
const BLUES_STOPS = [
  [239,243,255],[198,219,239],[158,202,225],[107,174,214],
  [66,146,198],[33,113,181],[8,69,148]
];
const COLOR_SCHEMES = [
  { id: "viridis", label: "Viridis", stops: VIRIDIS_STOPS },
  { id: "blue", label: "Blue (one hue)", stops: BLUES_STOPS },
  { id: "grey", label: "Grey (print safe)", stops: GREYS_STOPS }
];
const urlScheme = () => {
  const s = getParam("scheme");
  return COLOR_SCHEMES.some(x => x.id === s) ? s : "viridis";
};
const schemeStops = (id) => (COLOR_SCHEMES.find(x => x.id === id) || COLOR_SCHEMES[0]).stops;
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
// Composite every Leaflet canvas in the map element (basemap + choropleth
// share the map-level canvas renderer; getBoundingClientRect resolves the
// pane transforms). No tiles, no external images — canvas stays untainted.
function mapSnapshot(mapEl) {
  const r = mapEl.getBoundingClientRect();
  const out = document.createElement("canvas");
  out.width = Math.round(r.width * 2); out.height = Math.round(r.height * 2);
  const ctx = out.getContext("2d");
  ctx.fillStyle = getComputedStyle(mapEl).backgroundColor || "#eef1f4";
  ctx.fillRect(0, 0, out.width, out.height);
  mapEl.querySelectorAll("canvas").forEach(cv => {
    const cr = cv.getBoundingClientRect();
    // The comparison crossfade is CSS opacity on a pane — drawImage ignores
    // CSS, so carry the effective opacity into the composite.
    let alpha = 1, node = cv;
    while (node && node !== mapEl) {
      alpha *= parseFloat(getComputedStyle(node).opacity) || 1;
      node = node.parentElement;
    }
    ctx.globalAlpha = alpha;
    ctx.drawImage(cv, (cr.left - r.left) * 2, (cr.top - r.top) * 2, cr.width * 2, cr.height * 2);
    ctx.globalAlpha = 1;
  });
  return out;
}
// One-page PDF: title, the snapshot, optional gradient legend underneath.
function pdfDownload({ title, canvas, filename, legend }) {
  if (!window.jspdf) { alert("The PDF library did not load — try reloading the page."); return; }
  const doc = new window.jspdf.jsPDF({
    orientation: canvas.width >= canvas.height ? "l" : "p", unit: "pt", format: "letter" });
  const pw = doc.internal.pageSize.getWidth(), ph = doc.internal.pageSize.getHeight();
  const margin = 40;
  doc.setFontSize(13);
  const titleLines = doc.splitTextToSize(String(title || ""), pw - 2 * margin);
  doc.text(titleLines, margin, margin);
  const imgY = margin + 14 * titleLines.length + 10;
  const maxW = pw - 2 * margin, maxH = ph - imgY - margin - (legend ? 46 : 0);
  const scale = Math.min(maxW / canvas.width, maxH / canvas.height);
  const w = canvas.width * scale, h = canvas.height * scale;
  doc.addImage(canvas.toDataURL("image/png"), "PNG", margin, imgY, w, h);
  if (legend) {
    const ly = imgY + h + 18, lw = 220, steps = 55;
    doc.setFontSize(9);
    doc.text(String(legend.title || ""), margin, ly - 4);
    for (let i = 0; i < steps; i++) {
      const c = rampColor(legend.stops, i / (steps - 1)).match(/\d+/g).map(Number);
      doc.setFillColor(c[0], c[1], c[2]);
      doc.rect(margin + (lw / steps) * i, ly, lw / steps + 0.5, 10, "F");
    }
    // legend.fmt keeps 1-5 estimate ends readable ("1.5", not "2") while
    // alert-day counts stay whole numbers.
    const lf = legend.fmt || ((v) => String(Math.round(v)));
    doc.setTextColor(60);
    doc.text(lf(legend.domain[0]), margin, ly + 20);
    doc.text(lf((legend.domain[0] + legend.domain[1]) / 2), margin + lw / 2, ly + 20, { align: "center" });
    doc.text(lf(legend.domain[1]), margin + lw, ly + 20, { align: "right" });
  }
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
// arrays parallel to data. Draws along the value axis: vertical normally,
// horizontal when the chart uses indexAxis "y" (flipped bars).
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
        ctx.beginPath();
        if (flipped) { ctx.moveTo(p1, pt.y); ctx.lineTo(p2, pt.y); }
        else { ctx.moveTo(pt.x, p1); ctx.lineTo(pt.x, p2); }
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
function groupedBarChart(canvas, rows, { title = "", xLabel = "", yLabel = "", categoryOrder = null, showCI = false, horizontal = false, colors = null }) {
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
        legend: { position: "bottom", title: { display: true, text: "Group" } },
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
    scheme = sc; setParams({ scheme: sc === "viridis" ? null : sc }); draw();
  }));
  bar.append(el("label", { class: "wx-ci-label", for: "ci-toggle" },
    ciBox, " Show 95% confidence intervals"));
  bar.append(pdfButton("Download chart (PDF)", () => pdfDownload({
    title: currentQuestionText, canvas: chartSnapshot(canvas),
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

// One choropleth layer with popups + click selection.
function choroLayer(geo, { idProp, valueOf, color, popupHTML, onSelect, tooltipHTML }) {
  let selected = null;
  const layer = L.geoJSON(geo, {
    style: (f) => ({
      fillColor: color(valueOf(f.properties[idProp])),
      fillOpacity: 0.9, color: "white", weight: idProp === "FIPS" ? 0.5 : 1.5,
      opacity: 1
    }),
    onEachFeature: (f, lyr) => {
      const id = f.properties[idProp];
      lyr.bindPopup(() => popupHTML(id, f.properties));
      // Hover-to-read (Joe's map page): sticky tooltip with the value.
      if (tooltipHTML) lyr.bindTooltip(() => tooltipHTML(id, f.properties),
        { sticky: true, direction: "top", opacity: 0.96 });
      lyr.on("mouseover", () => lyr.setStyle({ weight: 4, color: "grey" }));
      lyr.on("mouseout", () => { if (selected !== lyr) layer.resetStyle(lyr); });
      lyr.on("click", () => {
        if (selected) layer.resetStyle(selected);
        selected = lyr;
        onSelect && onSelect(id, f.properties, lyr);
      });
    }
  });
  // fit=false: highlight + popup without moving the view (static maps).
  layer.selectById = (id, map, fit = true) => {
    layer.eachLayer(lyr => {
      if (String(lyr.feature.properties[idProp]) === String(id)) {
        if (selected) layer.resetStyle(selected);
        selected = lyr;
        lyr.setStyle({ weight: 4, color: "grey" });
        if (map && fit) map.fitBounds(lyr.getBounds().pad(1.2));
        if (map) lyr.openPopup();
        onSelect && onSelect(id, lyr.feature.properties, lyr);
      }
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

/* Map Explorer — 2.0 (Joe's estimates + alert layers, our layout): top
 * toolbar, fixed-frame full-width CWA map, hover tooltips, click popup with
 * the full place story (value, rank, percentile, median, strip plot — Joe's
 * popup-only pattern, user ruling 2026-08-13), per-measure notes below.
 * Comparison = ONE thing, the NWS alert-day history, crossfaded over the
 * estimate (replaces the 1.0 SVI comparison, user ruling 2026-08-13). */
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

  // Comparison state: one alert layer, crossfaded. ?compare=&mix= deep-link.
  const alertCats = cats.filter(c => c.kind === "alert");
  let compare = alertCats.some(c => c.code === getParam("compare"))
    ? getParam("compare") : "";
  let mix = Math.max(0, Math.min(100, parseInt(getParam("mix"), 10) || 50));

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
    setParams({ compare: compare || null, mix: compare ? String(mix) : null });
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
    scheme = sc; setParams({ scheme: sc === "viridis" ? null : sc }); await redraw();
  }));
  bar.append(pdfButton("Download map (PDF)", () => {
    const cat = byCode.get(measure);
    pdfDownload({
      title: (cat ? cat.label : measure) + " — NWS County Warning Area " +
        (isAlert(measure) ? "alert days" : "estimates"),
      canvas: mapSnapshot(mapEl),
      filename: `wxdash-map-${measure}.pdf`,
      legend: lastLegend
    });
  }));

  // --- full-width map card + per-measure notes card below
  const card = el("div", { class: "card wx-map-card wx-map-fullwidth" });
  const legendHolder = el("div", { class: "wx-legend-row" });
  const mapEl = el("div", { class: "wx-map" });
  // Crossfade control: measure label — slider — alert label. Lives on the
  // map card so the mix and the map read as one instrument.
  const fadeLeft = el("span", { class: "wx-fade-label" });
  const fadeRight = el("span", { class: "wx-fade-label" });
  const fadeInput = el("input", { class: "wx-fade-input", type: "range",
    min: "0", max: "100", step: "1", "aria-label": "Blend between the two maps" });
  const fadeBar = el("div", { class: "wx-fade-bar" }, fadeLeft, fadeInput, fadeRight);
  card.append(fadeBar, mapEl, legendHolder);
  const notesCard = el("div", { class: "card wx-map-notes" });
  container.append(el("div", { class: "page wx-explore-page wx-map-page" },
    el("div", { class: "content" }, lead, bar, card, notesCard)));

  // Fixed-frame map (Joe's design): the page scrolls normally over it — no
  // scroll-wheel zoom trap, no drag, no zoom buttons. CONUS fills the frame.
  const map = await baseMap(mapEl, {
    zoomControl: false, dragging: false, scrollWheelZoom: false,
    doubleClickZoom: false, boxZoom: false, keyboard: false, touchZoom: false,
    // Fractional zoom so fitBounds can truly fill the frame at any width —
    // integer snapping leaves the CONUS floating small between zoom levels.
    // Safe here: the map is static, nobody zooms by hand.
    zoomSnap: 0.1
  });
  // The frame is fluid (full-bleed page, vh-based height): re-render and
  // re-frame CONUS whenever the container changes size, so the map scales
  // with the window instead of cropping.
  let refitTimer = null;
  new ResizeObserver(() => {
    clearTimeout(refitTimer);
    refitTimer = setTimeout(() => {
      map.invalidateSize();
      map.fitBounds([[24.5, -125], [49.5, -66.9]]);
    }, 120);
  }).observe(mapEl);

  // Overlay pane for the comparison layer: above the base choropleth, mouse-
  // transparent (hover/click always reach the base layer), and crossfaded by
  // a single CSS opacity on the pane.
  const comparePane = map.createPane("wx-compare");
  comparePane.style.zIndex = 450;
  comparePane.style.pointerEvents = "none";
  const applyMix = () => { comparePane.style.opacity = compare ? String(mix / 100) : "0"; };
  fadeInput.value = String(mix);
  fadeInput.addEventListener("input", () => { mix = Number(fadeInput.value); applyMix(); });
  fadeInput.addEventListener("change", () => setParams({ mix: compare ? String(mix) : null }));

  let activeLayer = null;
  let lastLegend = null;   // domain/stops/title of the current view, for the PDF
  let compareLayer = null;

  // The popup's one-paragraph place story (Joe's narrative(), templates from
  // config.map.popup). rank/pct/median are compiler-precomputed — the engine
  // only assembles the sentence.
  function popupStory(id) {
    const cat = byCode.get(measure);
    const m = M(measure);
    const here = m.values[id];
    if (here == null) return "No data for this area.";
    const rank = m.rank[id], pct = m.pct[id];
    const alert = isAlert(measure);
    const noun = alert ? "count" : "estimate";
    const quantity = fillTpl(CONFIG.map.quantities[constructOf(measure)],
      { hazard: hazardOfLabel(cat.label) });
    // Naming the quantity lets the sentence work at any rank — a comparative
    // would be false in the middle of the distribution (Joe's design note).
    let standing;
    if (rank === 1) standing = `has the highest ${noun} of the ${N}`;
    else if (rank === N) standing = `has the lowest ${noun} of the ${N}`;
    else if (rank <= N / 2) standing = `ranks ${ordinal(rank)} highest of the ${N}`;
    else standing = `ranks ${ordinal(rank)} of the ${N}`;
    return fillTpl(alert ? CONFIG.map.popup.alert : CONFIG.map.popup.estimate, {
      value: fmtVal(measure)(here), quantity, n: N,
      median: fmtVal(measure)(m.median), standing,
      percentile: ordinal(pct), span: m.span || ""
    });
  }

  async function redraw() {
    const cat = byCode.get(measure);
    const m = M(measure);
    // Colors stretch over the measure's own observed range (Joe's 2.0
    // design): on a shared 1-5 scale the warning measures would all come out
    // one flat mid tone.
    const domain = m.domain;
    const stops = dataStops(schemeStops(scheme));
    const color = (v) => v == null ? "#d0d0d0"
      : rampColor(stops, (v - domain[0]) / (domain[1] - domain[0]));

    const compareCat = compare ? byCode.get(compare) : null;
    const compareM = compare ? M(compare) : null;
    // Contrasting ramp so the two signals stay tellable apart mid-fade:
    // grey normally, blue when the main scheme is already grey.
    const compareStops = dataStops(scheme === "grey" ? BLUES_STOPS : GREYS_STOPS);

    if (activeLayer) map.removeLayer(activeLayer);
    activeLayer = choroLayer(geo, {
      idProp: "CWA",
      valueOf: (id) => m.values[id],
      color,
      tooltipHTML: (id, props) => {
        const v = m.values[id];
        let core = `<span class="wx-tt-val">${isAlert(measure) ? "Alert days" : "Estimate"} ` +
          `${v == null ? "no data" : fmtVal(measure)(v)}</span>`;
        if (compareM) {
          const cv = compareM.values[id];
          core += `<br><span class="wx-tt-val">${esc(compareCat.label)} ` +
            `${cv == null ? "no data" : fmtVal(compare)(cv)}</span>`;
        }
        return `<strong>${esc(props.CWA_DISPLAY || id)}</strong><br>` + core +
          `<br><span class="wx-tip-hint">Click for the full story</span>`;
      },
      popupHTML: (id, props) => {
        const values = Object.values(m.values).filter(v => v != null).map(Number);
        return `<strong>${esc(props.CWA_DISPLAY || id)} (${esc(String(id))})</strong>` +
          `<br><br>` + esc(popupStory(id)) +
          stripPlotSVG(values, Number(m.values[id]), Number(m.median),
                       fmtRange(measure));
      },
    }).addTo(map);

    // Rebuild the comparison overlay (mouse-transparent, own pane).
    if (compareLayer) { map.removeLayer(compareLayer); compareLayer = null; }
    if (compare) {
      const cd = compareM.domain;
      const cColor = (v) => v == null ? "#d0d0d0"
        : rampColor(compareStops, (v - cd[0]) / (cd[1] - cd[0]));
      compareLayer = L.geoJSON(geo, {
        // Own renderer in the compare pane — the map-level canvas renderer
        // would otherwise paint this into the SAME canvas as the base layer,
        // and the pane's crossfade opacity would take both maps with it.
        renderer: L.canvas({ pane: "wx-compare" }),
        pane: "wx-compare", interactive: false,
        style: (f) => ({
          fillColor: cColor(compareM.values[f.properties.CWA]),
          fillOpacity: 0.95, color: "rgba(255,255,255,0.6)", weight: 1
        })
      }).addTo(map);
    }
    fadeBar.style.display = compare ? "" : "none";
    fadeLeft.textContent = cat.label;
    fadeRight.textContent = compareCat ? compareCat.label : "";
    applyMix();

    legendHolder.textContent = "";
    const legendTitle = (isAlert(measure) ? "Alert days — " : "Estimate (1–5 scale) — ") + esc(cat.label);
    legendHolder.append(gradientLegend(legendTitle, domain, stops, fmtRange(measure)));
    lastLegend = { title: isAlert(measure) ? "Alert days" : "Estimate (1–5 scale)",
                   domain, stops, fmt: fmtRange(measure) };
    if (compare) legendHolder.append(
      gradientLegend("Alert days — " + esc(compareCat.label), compareM.domain,
                     compareStops, fmtRange(compare)));

    notesCard.innerHTML = (CONFIG.map.notes || {})[measure] || "";
    notesCard.style.display = notesCard.innerHTML ? "" : "none";

    // ?place=OUN deep-links an area: highlight + popup without moving the
    // fixed frame.
    const preselect = getParam("place");
    if (preselect) activeLayer.selectById(preselect, map, false);
  }
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
 * (config.pages[quiz].questions) and derived from bundle data. */
components.wx_quiz = async function (page, container) {
  const quiz = page.questions || [];
  // Prompts number straight through 1..N (Matthew: "1 of 5" was confusing
  // when ten prompts get asked); follow-ups keep their label.
  const partsOf = (q) => [q.part1, q.part2].filter(Boolean);
  const totalPrompts = quiz.reduce((t, q) => t + partsOf(q).length, 0);
  const promptsBefore = quiz.map((_, i) =>
    quiz.slice(0, i).reduce((t, q) => t + partsOf(q).length, 0));
  let idx = 0, score = 0, answered = 0;
  const card = el("div", { class: "card wx-quiz-card" });
  container.append(el("div", { class: "page wx-quiz-page" },
    el("div", { class: "content" }, card)));

  function renderQ() {
    card.textContent = "";
    if (idx >= quiz.length) {
      card.append(el("p", { class: "wx-eyebrow" }, "Done"));
      card.append(el("h2", { class: "wx-quiz-q" }, `You got ${score} of ${answered} right.`));
      card.append(el("p", { class: "wx-note" },
        "Every answer lives in the dashboard — the interesting part is why. Keep exploring."));
      card.append(el("div", { class: "wx-quiz-nav" },
        el("a", { class: "wx-cta-button", href: "#survey" }, "Explore the survey questions"),
        el("button", { class: "wx-quiz-again", onclick: () => {
          idx = 0; score = 0; answered = 0; renderQ();
        } }, "Start over")));
      return;
    }
    const q = quiz[idx];
    if (idx === 0 && answered === 0 && page.intro)
      card.append(el("p", { class: "wx-note wx-quiz-intro" }, page.intro));
    const eyebrow = el("p", { class: "wx-eyebrow" });
    card.append(eyebrow);
    const parts = partsOf(q);
    let part = 0;
    const zone = el("div");
    card.append(zone);
    function renderPart() {
      eyebrow.textContent =
        `Question ${promptsBefore[idx] + part + 1} of ${totalPrompts}` +
        (part > 0 ? " — follow-up" : "");
      zone.textContent = "";
      const pp = parts[part];
      zone.append(el("h3", { class: "wx-quiz-q" }, pp.prompt));
      const opts = el("div", { class: "wx-quiz-opts" });
      pp.options.forEach((o, i) => {
        opts.append(el("button", { class: "wx-quiz-opt", onclick: () => {
          answered++;
          if (i === pp.answer) score++;
          opts.querySelectorAll("button").forEach((bb, j) => {
            bb.disabled = true;
            if (j === pp.answer) { bb.classList.add("correct"); bb.prepend("✓ "); }
            else if (j === i) { bb.classList.add("wrong"); bb.prepend("✗ "); }
          });
          const fb = el("div", { class: "wx-quiz-reveal" },
            el("p", {}, (i === pp.answer ? "Right. " : "Not quite — ") + pp.reveal));
          const nav = el("div", { class: "wx-quiz-nav" });
          if (part + 1 < parts.length) {
            nav.append(el("button", { class: "wx-cta-button", onclick: () => {
              part++; renderPart();
            } }, "Follow-up question"));
          } else {
            if (q.explore) nav.append(el("a", { class: "wx-quiz-explore",
              href: q.explore.href,
              onclick: () => q.explore.params && setParams(q.explore.params)
            }, q.explore.label || "See the data"));
            nav.append(el("button", { class: "wx-cta-button", onclick: () => {
              idx++; renderQ(); window.scrollTo({ top: 0, behavior: "smooth" });
            } }, idx + 1 < quiz.length ? "Next question" : "Finish"));
          }
          zone.append(fb, nav);
        } }, o));
      });
      zone.append(opts);
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
