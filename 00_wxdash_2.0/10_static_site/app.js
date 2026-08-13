/*
  The whole dashboard, client side. No framework: the state is a handful of
  variables and every control redraws what it affects.

  Nothing here computes an estimate. 10_build_static_site.R worked all of them
  out with srvyr and wrote them to data/, so this file only ever picks a slice
  and draws it - which is why the page needs no server.
*/
"use strict";

const INSTITUTE =
  "The University of Oklahoma's Institute for Public Policy Research and " +
  "Analysis";
const INSTITUTE_URL = "https://www.ou.edu/ippra";
const ARCHIVE = "dataverse.harvard.edu/dataverse/wxsurvey";
const ARCHIVE_URL = "https://dataverse.harvard.edu/dataverse/wxsurvey";

/*
  The ramps validated for the R charts, carried over unchanged. Blue and grey
  are stepped evenly in OKLCH so lightness alone carries the order; the
  distinct set is Okabe-Ito with yellow and black dropped.
*/
const RAMP_BLUE = ["#032A4C", "#043C69", "#054E88", "#1061A5",
                   "#2B76BB", "#428BD2", "#57A1E9", "#70B6FD"];
const RAMP_GREY = ["#25292F", "#363B40", "#474D53", "#5A6066",
                   "#6E737A", "#82888E", "#969CA3", "#ACB2B9"];
const HUES_DISTINCT = ["#009E73", "#0072B2", "#D55E00",
                       "#56B4E9", "#E69F00", "#CC79A7"];
const VIRIDIS = ["#440154", "#46327E", "#365C8D", "#277F8E",
                 "#1FA187", "#4AC16D", "#9FDA3A", "#BBDF27"];

const PALETTES = [
  ["Blue (one hue)", "blue"],
  ["Grey (print safe)", "grey"],
  ["Viridis", "viridis"],
  ["Distinct hues", "distinct"]
];

const SPLITS = [
  ["Everyone", "All"],
  ["Age", "AGE_GROUP"],
  ["Gender", "GENDER_GROUP"],
  ["Race and ethnicity", "RACE_GROUP"],
  ["Education", "EDUC_GROUP"],
  ["Income", "INCOME_GROUP"],
  ["Census region", "CENSUS_REGION"],
  ["Urban, suburban, rural", "RURAL_GROUP"],
  ["Housing tenure", "TENURE_GROUP"],
  ["Residence type", "HOME_GROUP"],
  ["Children in household", "CHILDREN_GROUP"],
  ["Weather salience", "SALIENCE_GROUP"],
  ["Survey year", "survey_year"]
];

const GROUP_PHRASES = {
  AGE_GROUP: "age group",
  GENDER_GROUP: "gender",
  RACE_GROUP: "race and ethnicity group",
  EDUC_GROUP: "education group",
  INCOME_GROUP: "income group",
  CENSUS_REGION: "census region",
  RURAL_GROUP: "community type",
  TENURE_GROUP: "housing tenure",
  HOME_GROUP: "residence type",
  CHILDREN_GROUP: "children-in-household group",
  SALIENCE_GROUP: "weather salience group",
  survey_year: "survey year's respondents"
};

const PAGE_SIZE = 10;

const state = {
  questions: [],
  filtered: [],
  page: 0,
  selectedId: null,
  question: null,
  split: "All",
  palette: "blue",
  ci: false,
  measures: null,
  measure: null,
  mapPalette: "blue",
  map: null,
  mapFitted: false,
  areas: 0
};

/* Eight steps is the ceiling for an ordered ramp on white; past that it falls
   back to viridis, which stays perceptually even where a hand-stepped ramp
   would not. */
function rampColours(ramp, n) {
  if (n > ramp.length) return evenly(VIRIDIS, n);
  return evenly(ramp, n);
}

function evenly(ramp, n) {
  if (n <= 1) return [ramp[0]];
  const out = [];
  for (let i = 0; i < n; i++) {
    const at = Math.round(i * (ramp.length - 1) / (n - 1));
    out.push(ramp[at]);
  }
  return out;
}

function seriesColours(palette, n) {
  if (palette === "blue") return rampColours(RAMP_BLUE, n);
  if (palette === "grey") return rampColours(RAMP_GREY, n);
  if (palette === "viridis") return evenly(VIRIDIS, n);
  /* Never invent a hue for an extra series - fall back to the ordered ramp. */
  if (n <= HUES_DISTINCT.length) return HUES_DISTINCT.slice(0, n);
  return evenly(VIRIDIS, n);
}

/* Reversed for blue and grey so the darkest step carries the highest value,
   which is the direction a choropleth is read in. Viridis keeps its own order:
   it already runs dark to bright. */
function mapColours(palette, n) {
  if (palette === "blue") return rampColours(RAMP_BLUE, n).slice().reverse();
  if (palette === "grey") return rampColours(RAMP_GREY, n).slice().reverse();
  return evenly(VIRIDIS, n);
}

function escapeHtml(s) {
  return String(s ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function ordinal(n) {
  const mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return n + "th";
  if (n % 10 === 1) return n + "st";
  if (n % 10 === 2) return n + "nd";
  if (n % 10 === 3) return n + "rd";
  return n + "th";
}

function countWord(n) {
  const words = ["one", "two", "three", "four", "five", "six", "seven",
                 "eight", "nine"];
  return (n >= 1 && n <= words.length) ? words[n - 1] : String(n);
}

function linkify(text) {
  return escapeHtml(text)
    .replace(escapeHtml(INSTITUTE),
      `<a href="${INSTITUTE_URL}" target="_blank">${escapeHtml(INSTITUTE)}</a>`)
    .replace(ARCHIVE,
      `<a href="${ARCHIVE_URL}" target="_blank">${ARCHIVE}</a>`);
}

function el(id) { return document.getElementById(id); }

function fillSelect(node, pairs) {
  node.innerHTML = pairs
    .map(([label, value]) => `<option value="${escapeHtml(value)}">` +
                             `${escapeHtml(label)}</option>`)
    .join("");
}

/* Tabs ---------------------------------------------------------------------
   The map is only sized once its panel is visible: MapLibre measures its
   container on creation, and a container that is display:none measures zero,
   which leaves a blank square until something forces a resize. */
function showTab(name) {
  document.querySelectorAll(".tab").forEach(t =>
    t.classList.toggle("is-active", t.dataset.tab === name));
  el("panel-results").classList.toggle("is-hidden", name !== "results");
  el("panel-map").classList.toggle("is-hidden", name !== "map");
  /* The map is built while this panel is display:none, so its first fitBounds
     runs against a container of zero size and lands on a meaningless zoom.
     resize() alone does not re-fit - it keeps that zoom and just changes the
     viewport - so the bounds are applied again the first time the panel is
     really on screen. Only the first time, or switching tabs would throw away
     wherever the reader had panned to. */
  /* A chart drawn while this panel was hidden fell back to a fixed width,
     so it is redrawn once the real container width can be measured. */
  if (name === "results" && state.question) renderChart();
  if (name === "map" && state.map) {
    state.map.resize();
    if (!state.mapFitted) {
      state.map.fitBounds(state.bounds, { padding: 20, animate: false });
      state.mapFitted = true;
    }
  }
}

/* Question table ------------------------------------------------------------
   Searched over the wording, the variable name, the scale and the content
   keywords together, so "reception" finds questions whose text never uses the
   word. The keywords are what make that work. */
function applyFilters() {
  const term = el("question-search").value.trim().toLowerCase();
  const hazard = el("hazard-filter").value;
  const kind = el("kind-filter").value;

  state.filtered = state.questions.filter(q => {
    if (hazard && q.hazard !== hazard) return false;
    if (kind && q.kind !== kind) return false;
    if (!term) return true;
    const hay = [q.question, q.variable, q.response_scale, q.keywords]
      .join(" ").toLowerCase();
    return hay.includes(term);
  });

  state.page = 0;
  renderTable();
}

function renderTable() {
  const total = state.filtered.length;
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  state.page = Math.min(state.page, pages - 1);
  const start = state.page * PAGE_SIZE;
  const rows = state.filtered.slice(start, start + PAGE_SIZE);

  el("question-count").textContent =
    `${total.toLocaleString()} question${total === 1 ? "" : "s"}`;
  el("page-label").textContent = `Page ${state.page + 1} of ${pages}`;
  el("prev-page").disabled = state.page === 0;
  el("next-page").disabled = state.page >= pages - 1;

  el("question-table").innerHTML =
    "<table><thead><tr><th>Survey</th><th>Question Text</th>" +
    "<th>Type</th></tr></thead><tbody>" +
    rows.map(q =>
      `<tr data-id="${escapeHtml(q.id)}"` +
      `${q.id === state.selectedId ? ' class="is-selected"' : ""}>` +
      `<td>${escapeHtml(q.hazard)}</td>` +
      `<td>${escapeHtml(q.question)}</td>` +
      `<td>${escapeHtml(q.kind)}</td></tr>`).join("") +
    "</tbody></table>";

  el("question-table").querySelectorAll("tr[data-id]").forEach(tr => {
    tr.addEventListener("click", () => selectQuestion(tr.dataset.id));
  });
}

async function selectQuestion(id) {
  state.selectedId = id;
  renderTable();
  const res = await fetch(`data/q/${encodeURIComponent(id)}.json`);
  if (!res.ok) {
    el("chart").innerHTML =
      '<p class="help">That question could not be loaded.</p>';
    return;
  }
  state.question = await res.json();
  /* A question is not asked under every split, so the chosen split falls back
     rather than drawing an empty panel. */
  if (!state.question.splits[state.split]) state.split = "All";
  el("split").value = state.split;
  renderChart();
}

/* Chart ---------------------------------------------------------------------
   Horizontal bars because response options are sentences as often as they are
   words - "I would trust forecasts generated by machine learning much less
   than forecasts generated by humans" does not fit under a tick. */
function renderChart() {
  const q = state.question;
  if (!q) return;

  const rows = q.splits[state.split] || [];
  const options = q.options || [];
  const labelFor = v => {
    const hit = options.find(o => String(o.value) === String(v));
    return hit ? hit.label : String(v);
  };

  /* Response order comes from the option codes, which sort the levels; an
     unlabelled value is shown as itself rather than dropped, because it means
     the data carries a code the instrument does not document. */
  const responses = [...new Set(rows.map(r => r.resp))]
    .sort((a, b) => (Number(a) - Number(b)) || String(a).localeCompare(b));
  const groups = [...new Set(rows.map(r => r.group))].sort();

  el("question-text").textContent = q.question;

  const colours = state.split === "All"
    ? [seriesColours(state.palette, 1)[0]]
    : seriesColours(state.palette, groups.length);

  const rowHeight = Math.max(22, 26 - groups.length);
  const groupHeight = groups.length * rowHeight + 16;
  const top = state.split === "All" ? 12 : 34;
  const left = 210;
  const right = 60;
  /* Drawn at the width of its container rather than a fixed 900, so the bars
     run the full width of the question above them. Measured rather than set to
     100% in CSS: scaling the SVG would enlarge the type with it, and the labels
     are already the size they should be. The fallback covers being drawn while
     the panel is hidden, where clientWidth is 0. */
  const width = Math.max(720, el("chart").clientWidth || 900);
  const height = top + responses.length * groupHeight + 34;
  const plotWidth = width - left - right;
  const maxP = Math.max(10, ...rows.map(r => state.ci ? r.p_upp : r.p));
  const x = p => left + (p / maxP) * plotWidth;

  const parts = [];
  parts.push(`<svg viewBox="0 0 ${width} ${height}" width="${width}" ` +
             `height="${height}" role="img">`);

  if (state.split !== "All") {
    let lx = left;
    groups.forEach((g, i) => {
      parts.push(`<rect x="${lx}" y="6" width="11" height="11" rx="2" ` +
                 `fill="${colours[i]}"/>`);
      parts.push(`<text class="legend-text" x="${lx + 16}" y="16">` +
                 `${escapeHtml(g)}</text>`);
      lx += 26 + String(g).length * 6.4;
    });
  }

  responses.forEach((resp, ri) => {
    const y0 = top + ri * groupHeight;
    parts.push(`<text class="bar-label" x="${left - 10}" ` +
               `y="${y0 + groupHeight / 2}" text-anchor="end">` +
               `${escapeHtml(wrapLabel(labelFor(resp)))}</text>`);

    groups.forEach((g, gi) => {
      const row = rows.find(r => r.resp === resp && r.group === g);
      if (!row) return;
      const y = y0 + gi * rowHeight;
      parts.push(`<rect x="${left}" y="${y}" ` +
                 `width="${Math.max(0, x(row.p) - left)}" ` +
                 `height="${rowHeight - 4}" fill="${colours[gi]}"/>`);
      if (state.ci) {
        const mid = y + (rowHeight - 4) / 2;
        parts.push(`<line class="axis-line" x1="${x(row.p_low)}" ` +
                   `x2="${x(row.p_upp)}" y1="${mid}" y2="${mid}" ` +
                   `stroke="#1F2933"/>`);
      }
      const at = state.ci ? row.p_upp : row.p;
      parts.push(`<text class="bar-value" x="${x(at) + 6}" ` +
                 `y="${y + rowHeight / 2}">${Math.round(row.p)}%</text>`);
    });
  });

  const axisY = height - 20;
  parts.push(`<line class="axis-line" x1="${left}" x2="${left + plotWidth}" ` +
             `y1="${axisY}" y2="${axisY}"/>`);
  [0, 0.25, 0.5, 0.75, 1].forEach(f => {
    const p = maxP * f;
    parts.push(`<text class="axis-text" x="${x(p)}" y="${axisY + 14}" ` +
               `text-anchor="middle">${Math.round(p)}%</text>`);
  });
  parts.push("</svg>");

  el("chart").innerHTML = parts.join("");
  renderChartCaption();
}

/* SVG has no text wrapping, so a long option label is trimmed rather than
   drawn over the bars. */
function wrapLabel(text) {
  return text.length > 34 ? text.slice(0, 33) + "…" : text;
}

function renderChartCaption() {
  const q = state.question;
  const s = q.summaries[state.split];
  if (!s) { el("chart-caption").innerHTML = ""; return; }

  const waves = /[-,]/.test(s.years)
    ? `across the ${s.years} waves` : `in the ${s.years} wave`;
  const splitText = state.split === "All"
    ? "" : ` of each ${GROUP_PHRASES[state.split]}`;
  const smallest = state.split === "All" ? "" :
    ` The smallest group, ${s.smallest}, has ` +
    `${s.smallest_n.toLocaleString()} respondents.`;

  const text =
    `${s.n.toLocaleString()} US adults answered this question about ` +
    `${q.hazard_phrase} ${waves}. Bars show the weighted percentage` +
    `${splitText} giving each answer.${smallest}\n\n` +
    `From the Extreme Weather and Society Survey, run by ${INSTITUTE}. ` +
    `Every wave is raked to American Community Survey benchmarks for age, ` +
    `gender, race, education, income and region, so the percentages describe ` +
    `US adults rather than only the people surveyed. This question is stored ` +
    `as ${q.variable}; the survey data is available at ${ARCHIVE}.`;

  el("chart-caption").innerHTML = linkify(text)
    .replace(/\n\n/g, "<br><br>")
    .replace(`stored as ${escapeHtml(q.variable)};`,
             `stored as <code>${escapeHtml(q.variable)}</code>;`);
}

/* Map -----------------------------------------------------------------------
   No basemap: the 116 areas already tile the country, so a style with no
   sources is enough and nothing is fetched for the background. */
const BLANK_STYLE = {
  version: 8,
  sources: {},
  layers: [{ id: "background", type: "background",
             paint: { "background-color": "#FFFFFF" } }]
};

function measureById(id) {
  for (const group of Object.values(state.measures.measures)) {
    for (const m of group) if (m.measure === id) return m;
  }
  return null;
}

function valuesFor(id) {
  return state.geo.features.map(f => f.properties[id]);
}

function buildMap() {
  state.map = new maplibregl.Map({
    container: "map",
    style: BLANK_STYLE,
    bounds: state.bounds,
    fitBoundsOptions: { padding: 20 },
    /* Without this the WebGL drawing buffer is free to be cleared once a frame
       has been shown, and anything that reads the canvas back - printing, a
       screenshot, save-as-image - can get a blank rectangle instead of the map.
       It costs a little memory and is the difference between the print button
       working and appearing to work. */
    preserveDrawingBuffer: true,
    /* All four ways to zoom, because any one left on is a way out of the
       fitted view. No navigation control is added, so there are no buttons. */
    scrollZoom: false,
    doubleClickZoom: false,
    touchZoomRotate: false,
    boxZoom: false
  });

  state.map.on("load", () => {
    state.map.addSource("cwa", { type: "geojson", data: state.geo });
    state.map.addLayer({
      id: "cwa",
      type: "fill",
      source: "cwa",
      paint: {
        "fill-color": fillExpression(),
        "fill-opacity": 1,
        "fill-outline-color": "#FFFFFF"
      }
    });
    attachMapInteraction();
    renderLegend();
  });
}

/* A MapLibre interpolate expression over the measure's own range, the same
   stretch the R map uses: on a shared 1-5 scale the warning measures would all
   come out one flat mid tone. */
function fillExpression() {
  const values = valuesFor(state.measure);
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const colours = mapColours(state.mapPalette, 7);
  const stops = [];
  colours.forEach((c, i) => {
    stops.push(lo + (hi - lo) * (i / (colours.length - 1)), c);
  });
  return ["interpolate", ["linear"], ["get", state.measure], ...stops];
}

function attachMapInteraction() {
  const tip = new maplibregl.Popup({
    closeButton: false, closeOnClick: false, className: "tip"
  });

  state.map.on("mousemove", "cwa", e => {
    state.map.getCanvas().style.cursor = "pointer";
    const f = e.features[0];
    const m = measureById(state.measure);
    tip.setLngLat(e.lngLat).setHTML(
      `<strong>${escapeHtml(f.properties.CWA_DISPLAY)} ` +
      `(${escapeHtml(f.properties.CWA)})</strong><br>` +
      `Estimate: ${Number(f.properties[state.measure]).toFixed(2)}` +
      `<br><span style="font-size:11px;color:#6E737A">` +
      `Click for more information</span>`
    ).addTo(state.map);
  });

  state.map.on("mouseleave", "cwa", () => {
    state.map.getCanvas().style.cursor = "";
    tip.remove();
  });

  state.map.on("click", "cwa", e => {
    const f = e.features[0];
    new maplibregl.Popup({ maxWidth: "320px" })
      .setLngLat(e.lngLat)
      .setHTML(areaPopup(f.properties))
      .addTo(state.map);
  });
}

function areaPopup(props) {
  const values = valuesFor(state.measure);
  const here = Number(props[state.measure]);
  const sorted = [...values].sort((a, b) => a - b);
  const n = values.length;
  const below = values.filter(v => v < here).length;
  const rank = values.filter(v => v > here).length + 1;
  const middle = median(sorted);
  const percentile = Math.round(100 * below / n);
  const m = measureById(state.measure);

  return `<strong>${escapeHtml(props.CWA_DISPLAY)} ` +
    `(${escapeHtml(props.CWA)})</strong><br><br>` +
    escapeHtml(narrative(m, here, rank, percentile, n, middle)) +
    stripPlot(values, here, middle);
}

function median(sorted) {
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid]
                           : (sorted[mid - 1] + sorted[mid]) / 2;
}

/* What the 1-5 scale is measuring, as a phrase that follows "out of 5 for".
   Naming the quantity is what lets the sentence work at any rank: a
   comparative would be false in the middle of the distribution. */
const CONSTRUCT_QUANTITY = {
  RECEP: "agreement that people receive the {hazard} warnings issued for " +
         "their area",
  RESP: "agreement that people take protective action when {hazard} " +
        "warnings are issued",
  SUBJ_COMP: "how well people say they understand {hazard} warnings",
  RISK: "how people rate their risk from {hazard}"
};

function constructOf(id) {
  if (id.startsWith("RISK_")) return "RISK";
  if (id.endsWith("_SUBJ_COMP")) return "SUBJ_COMP";
  if (id.endsWith("_RECEP")) return "RECEP";
  return "RESP";
}

function hazardOf(m) {
  return m.label
    .replace(/ warning (reception|comprehension|response)$/, "")
    .replace(/ risk perceptions$/, "")
    .toLowerCase();
}

function narrative(m, here, rank, percentile, n, middle) {
  const quantity = CONSTRUCT_QUANTITY[constructOf(m.measure)]
    .replace("{hazard}", hazardOf(m));

  let standing;
  if (rank === 1) standing = `has the highest estimate of the ${n}`;
  else if (rank === n) standing = `has the lowest estimate of the ${n}`;
  else if (rank <= n / 2)
    standing = `ranks ${ordinal(rank)} highest of the ${n}`;
  else standing = `ranks ${ordinal(rank)} of the ${n}`;

  return `The estimate for this area is ${here.toFixed(2)} out of 5 for ` +
    `${quantity}. The median estimate across the ${n} County Warning Areas ` +
    `is ${middle.toFixed(2)}. This area ${standing}, at the ` +
    `${ordinal(percentile)} percentile.`;
}

/* All 116 on one axis with this area marked. The other areas are one path
   rather than 116 lines, which keeps the popup markup small. */
function stripPlot(values, here, middle) {
  const width = 280;
  const pad = 10;
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const at = v => hi === lo ? width / 2
    : +(pad + (v - lo) / (hi - lo) * (width - 2 * pad)).toFixed(1);

  const ticks = values.map(v => `M${at(v)} 12v14`).join("");
  const mid = at(middle);

  return `<svg width="${width}" height="52" ` +
    `style="display:block;margin:8px 0 2px">` +
    `<path d="${ticks}" stroke="#B8BEC5" stroke-width="1"/>` +
    `<path d="M${mid - 4} 34L${mid} 28L${mid + 4} 34Z" fill="#6E737A"/>` +
    `<text x="${mid}" y="44" font-size="9" fill="#6E737A" ` +
    `text-anchor="middle">median</text>` +
    `<circle cx="${at(here)}" cy="19" r="4.5" fill="#111827"/>` +
    `<text x="${pad}" y="9" font-size="10" fill="#6E737A">` +
    `${lo.toFixed(1)}</text>` +
    `<text x="${width - pad}" y="9" font-size="10" fill="#6E737A" ` +
    `text-anchor="end">${hi.toFixed(1)}</text></svg>`;
}

function renderLegend() {
  const values = valuesFor(state.measure);
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const colours = mapColours(state.mapPalette, 7);
  const m = measureById(state.measure);

  let legend = document.querySelector("#map .legend");
  if (!legend) {
    legend = document.createElement("div");
    legend.className = "legend";
    legend.style.cssText =
      "position:absolute;bottom:12px;left:12px;z-index:2";
    el("map").appendChild(legend);
  }
  legend.innerHTML =
    `<div><strong>${escapeHtml(m.label)}</strong></div>` +
    `<div class="legend-bar" style="background:linear-gradient(to right,` +
    `${colours.join(",")})"></div>` +
    `<div class="legend-ends"><span>${lo.toFixed(1)}</span>` +
    `<span>${hi.toFixed(1)}</span></div>`;
}

/* The order below is the point: what the map is, then the questions behind it,
   then how to read the colors, then where it came from. */
function renderMapNotes() {
  const m = measureById(state.measure);
  const values = valuesFor(state.measure);
  const lo = Math.min(...values), hi = Math.max(...values);
  const n = state.areas;

  const anchors = scaleAnchors(m.response_options);
  const items = m.items;
  const scored = items.length > 1
    ? `The ${countWord(items.length)} answers, all from the ` +
      `${m.hazard.replace(/ \(..\)$/, "")} survey, are averaged into one ` +
      `score${anchors ? ` from ${anchors}` : ""}.`
    : `Answers run${anchors ? ` from ${anchors}` : ""}.`;

  const varies = m.n_intros > 1
    ? ` The introduction was worded ${countWord(m.n_intros)} slightly ` +
      `different ways across the surveys that asked it; the most widely ` +
      `used version is shown.` : "";

  const source =
    `From the Extreme Weather and Society Survey, run by ${INSTITUTE}. ` +
    `Estimates come from multilevel models fitted to survey responses and ` +
    `reweighted to the adult population of each county, then combined to the ` +
    `County Warning Area, so they describe US adults in each area rather ` +
    `than only the people surveyed. The survey data behind them is available ` +
    `at ${ARCHIVE}.`;

  const bullets = items.map(it =>
    "<li>" + escapeHtml(m.shared_intro ? it.question_text
      : `${it.question_intro ?? ""} ${it.question_text}`.trim()) +
    (it.reverse_coded ? " <em>(reverse coded)</em>" : "") + "</li>").join("");

  el("map-notes").innerHTML =
    `<p>${escapeHtml(m.label)} across the ${n} National Weather Service ` +
    `County Warning Areas of the contiguous United States.</p>` +
    `<p><strong>Respondents were asked:</strong>` +
    (m.shared_intro ? ` &ldquo;${escapeHtml(m.intro)}&rdquo;` : "") + `</p>` +
    `<ul>${bullets}</ul>` +
    `<p>${escapeHtml(scored + varies)} Colors are stretched over ` +
    `${lo.toFixed(1)} to ${hi.toFixed(1)} rather than the full 1 to 5, so ` +
    `areas are compared against each other rather than against the ends of ` +
    `the scale.</p><p>${linkify(source)}</p>`;
}

function scaleAnchors(options) {
  if (!options) return null;
  const parts = String(options).split(" | ")
    .map(p => p.match(/^\s*(.+?)\s*=\s*(.*)$/)).filter(Boolean);
  if (!parts.length) return null;
  const first = parts[0], last = parts[parts.length - 1];
  return `${first[1]} (${first[2].toLowerCase()}) to ` +
         `${last[1]} (${last[2].toLowerCase()})`;
}

function updateMap() {
  if (!state.map || !state.map.getLayer("cwa")) return;
  state.map.setPaintProperty("cwa", "fill-color", fillExpression());
  renderLegend();
  renderMapNotes();
}

/* Start ------------------------------------------------------------------- */
async function start() {
  fillSelect(el("split"), SPLITS);
  fillSelect(el("palette"), PALETTES);
  fillSelect(el("map-palette"), PALETTES.filter(p => p[1] !== "distinct"));

  const [questions, measures, geo] = await Promise.all([
    fetch("data/questions.json").then(r => r.json()),
    fetch("data/measures.json").then(r => r.json()),
    fetch("data/cwa.geojson").then(r => r.json())
  ]);

  state.questions = questions;
  state.measures = measures;
  state.geo = geo;
  state.areas = measures.areas;

  fillSelect(el("hazard-filter"),
    [["All surveys", ""]].concat(
      [...new Set(questions.map(q => q.hazard))].sort().map(h => [h, h])));
  fillSelect(el("kind-filter"),
    [["All types", ""]].concat(
      [...new Set(questions.map(q => q.kind))].sort().map(k => [k, k])));

  el("measure").innerHTML = measures.groups.map((g, i) =>
    `<optgroup label="${escapeHtml(g)}">` +
    measures.measures[i].map(m =>
      `<option value="${escapeHtml(m.measure)}">` +
      `${escapeHtml(m.label)}</option>`).join("") +
    "</optgroup>").join("");

  state.measure = measures.measures[0][0].measure;

  /* The bounds the map opens on, worked out from the geometry rather than
     hard-coded, so a change to the areas moves the view with them. */
  let west = 180, south = 90, east = -180, north = -90;
  geo.features.forEach(f => {
    const walk = c => Array.isArray(c[0]) ? c.forEach(walk) : (
      west = Math.min(west, c[0]), east = Math.max(east, c[0]),
      south = Math.min(south, c[1]), north = Math.max(north, c[1]));
    walk(f.geometry.coordinates);
  });
  state.bounds = [[west, south], [east, north]];

  /*
    Listeners are attached before anything that can fail. They used to be last,
    after buildMap(), which meant a map that threw - MapLibre blocked, a
    container with no size, anything - left the page rendered but inert: every
    control dead, and nothing on screen saying why.
  */
  document.querySelectorAll(".tab").forEach(t =>
    t.addEventListener("click", () => showTab(t.dataset.tab)));
  el("question-search").addEventListener("input", applyFilters);
  el("hazard-filter").addEventListener("change", applyFilters);
  el("kind-filter").addEventListener("change", applyFilters);
  el("prev-page").addEventListener("click", () => {
    state.page--; renderTable();
  });
  el("next-page").addEventListener("click", () => {
    state.page++; renderTable();
  });
  el("split").addEventListener("change", e => {
    state.split = e.target.value; renderChart();
  });
  el("palette").addEventListener("change", e => {
    state.palette = e.target.value; renderChart();
  });
  el("ci").addEventListener("change", e => {
    state.ci = e.target.checked; renderChart();
  });
  el("measure").addEventListener("change", e => {
    state.measure = e.target.value; updateMap();
  });
  el("map-palette").addEventListener("change", e => {
    state.mapPalette = e.target.value; updateMap();
  });

  /* Everything the print stylesheet needs is already on the page, so this only
     has to open the dialog. The reader chooses Save as PDF from there. */
  el("print-chart").addEventListener("click", () => window.print());
  el("print-map").addEventListener("click", () => window.print());

  /* The chart is sized from its container, so it has to be redrawn when the
     container changes. Trailing timeout so a drag-resize redraws once at the
     end rather than on every pixel. */
  let resizeTimer;
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { if (state.question) renderChart(); }, 150);
  });

  applyFilters();
  if (state.filtered.length) await selectQuestion(state.filtered[0].id);

  /* The map is the one part with an outside dependency, so it is allowed to
     fail on its own without taking the questions tab down with it. */
  try {
    if (typeof maplibregl === "undefined") {
      throw new Error(
        "MapLibre did not load. The map library is fetched from unpkg.com; " +
        "check that the network allows it, or vendor it next to app.js as " +
        "index.html describes.");
    }
    buildMap();
    renderMapNotes();
  } catch (err) {
    showError(err);
  }
}

/* Failures are put on the page rather than only in the console, so a problem
   can be read off the screen by someone who is not going to open devtools. */
function showError(err) {
  let box = document.getElementById("error-box");
  if (!box) {
    box = document.createElement("div");
    box.id = "error-box";
    box.style.cssText =
      "margin:12px 0;padding:10px 12px;border:1px solid #C4553B;" +
      "border-radius:4px;background:#FDF2EF;color:#7A2E1C;font-size:13px";
    document.body.insertBefore(box, document.body.children[1]);
  }
  box.textContent = "Something went wrong: " + (err && err.message ? err.message
                                                : String(err));
}

window.addEventListener("error", e => showError(e.error || e.message));
window.addEventListener("unhandledrejection", e => showError(e.reason));

start().catch(showError);
