library(tidyverse)
library(sf)
library(jsonlite)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Dashboard Assembly -----------------------------------------------------------
# The whole dashboard, from 08 to the deployable site. Two halves that change
# on different cadences and cost three orders of magnitude apart:
#
#   Rscript 00_wxdash_2.0/09_dashboard/09_build_dashboard.R --data
#
# computes every statistic — 09_statistics.R, about fifteen minutes — and
# writes 09_dashboard/data/. Without the flag,
#
#   Rscript 00_wxdash_2.0/09_dashboard/09_build_dashboard.R
#
# assembles the site from that directory plus the hand-edited source in site/,
# in seconds. Front-end work is the common case and should not cost a coffee
# break, so the data directory is the boundary between them. Run --data when
# the survey data, the models or the measure menu change; without it for
# anything else.
#
# Assembly calculates NO statistics. Every percentage, confidence interval and
# estimate is read from 09_dashboard/data/ verbatim, so the two halves cannot
# disagree — a property that is true by construction rather than enforced by a
# harness. A calculation moved into this half gives that up.
#
# What assembly adds is presentation: the site/ front end (themes, landing
# page, quiz, alert-history comparison, PDF export), the config.json that front
# end reads, place ranks and medians precomputed from the map values,
# simplified geometry, and a quiz whose answer keys are derived from the
# distributions at build time.
#
# The data half's output is committed, so only that half needs WXDASH_LOCAL,
# WXSURVEYS_ROOT and the 02/05/07 pipeline outputs. Assembly runs from a plain
# clone with none of them.
#
# Writes outputs/09_site/ under WXDASH_LOCAL, or 09_dashboard/_site/ without
# one — plain static files either way; upload the directory to any web host.
# Preview the second with:
#   python3 -m http.server --directory 00_wxdash_2.0/09_dashboard/_site

# The data half writes here and the assembly half reads here, and the directory
# is committed. That is what lets a clone build the site with no pipeline
# outputs, no survey waves and no ~/.Renviron - the alternative was handing
# every collaborator 69 MB by side channel and trusting the copies to agree.
data_dir <- paste0(here::here("00_wxdash_2.0", "09_dashboard", "data"), "/")

# The built site is regenerable, so it stays out of the repo. It goes under
# WXDASH_LOCAL where there is one, so the deploy rsync keeps its path; a clone
# without one gets _site/ beside the source rather than a stop.
out <- if (wxdash_local == "") {
  paste0(here::here("00_wxdash_2.0", "09_dashboard", "_site"), "/")
} else {
  paste0(outputs, "09_site/")
}

site_src <- here::here("00_wxdash_2.0", "09_dashboard", "site")

if ("--data" %in% commandArgs(trailingOnly = TRUE)) {
  source(here::here("00_wxdash_2.0", "09_dashboard", "09_statistics.R"))
}

# Checked rather than assumed: this half reads a directory it did not write,
# and the alternative to saying so is a site that serves a map and an empty
# question table. In a clone these files are committed, so their absence means
# a partial checkout rather than a missing build.
needed <- paste0(data_dir, c("questions.json", "measures.json", "cwa.geojson",
                             "respondents.json"))
if (!all(file.exists(needed))) {
  print(basename(needed[!file.exists(needed)]))
  stop("Files above are missing from ", data_dir,
       " — restore them, or rebuild them with --data.")
}

if (!dir.exists(site_src)) {
  stop("No site source at ", site_src, " — the site/ directory moved.")
}

# Rebuilt from scratch each run: a question dropped upstream must not survive
# here as a stale file.
unlink(out, recursive = TRUE)
for (d in c("data/q", "data/rcode", "data/map", "data/geo"))
  dir.create(paste0(out, d), recursive = TRUE, showWarnings = FALSE)

wjson <- function(x, path, pretty = FALSE) {
  write_json(x, paste0(out, path), pretty = pretty, auto_unbox = TRUE,
             na = "null", digits = NA)
}
r2 <- function(x) round(x, 2)

# Question Data ----------------------------------------------------------------
# Copied through unchanged — these ARE the statistics, and they stay the data
# half's.
q_files <- list.files(paste0(data_dir, "q"), full.names = TRUE)
if (length(q_files) == 0) stop("No question files in ", data_dir, "q.")
invisible(file.copy(q_files, paste0(out, "data/q/")))
invisible(file.copy(paste0(data_dir, "questions.json"),
                    paste0(out, "data/questions.json")))

# The R that rebuilds each chart, generated alongside the numbers it
# reproduces. Carried over the same way and for the same reason: a script
# written here would be a second account of how the estimate was made.
r_files <- list.files(paste0(data_dir, "rcode"), full.names = TRUE)
if (length(r_files) != length(q_files)) {
  stop(data_dir, " has ", length(q_files), " questions but ", length(r_files),
       " script files — the Download R code button would 404.")
}
invisible(file.copy(r_files, paste0(out, "data/rcode/")))
message("Questions carried over: ", length(q_files),
        ", with reproduction scripts for each")

# Map Values -------------------------------------------------------------------
# 10 ships the estimates as geojson properties and lets its page derive rank,
# percentile and median in the browser. This front end shows the same numbers
# but precomputes them here, using the same formulas 10's app.js uses: rank is
# 1 + the count of strictly greater values, percentile is the share strictly
# below, rounded to whole numbers.
cwa <- read_sf(paste0(data_dir, "cwa.geojson"))
measures_meta <- read_json(paste0(data_dir, "measures.json"),
                           simplifyVector = FALSE)
menu <- purrr::flatten(measures_meta$measures)

offered <- map_chr(menu, "measure")
absent <- setdiff(offered, names(cwa))
if (length(absent) > 0) {
  print(absent)
  stop("Measures above are in measures.json but not on the map file.")
}

df <- st_drop_geometry(cwa)

# Checked before the rank arithmetic below, which reads an NA as the best value
# in the country: sum(v > NA, na.rm = TRUE) is 0, so the area would ship as
# rank 1 at the 0th percentile rather than as missing.
incomplete <- offered[vapply(offered, function(m) anyNA(df[[m]]), logical(1))]
if (length(incomplete) > 0) {
  print(incomplete)
  stop("Measures above have areas with no value - 07 dropped a CWA.")
}

measure_values <- setNames(lapply(menu, function(m) {
  code <- m$measure
  is_alert <- isTRUE(m$alert)
  v <- df[[code]]
  fmt <- if (is_alert) function(x) round(x) else r2
  vals <- fmt(v)
  rank <- vapply(v, function(x) sum(v > x, na.rm = TRUE) + 1L, integer(1))
  pct <- vapply(v, function(x) round(100 * sum(v < x, na.rm = TRUE) /
                                       sum(!is.na(v))), double(1))
  list(
    values = setNames(as.list(vals), df$CWA),
    rank = setNames(as.list(rank), df$CWA),
    pct = setNames(as.list(pct), df$CWA),
    domain = c(min(vals, na.rm = TRUE), max(vals, na.rm = TRUE)),
    median = fmt(median(v, na.rm = TRUE)),
    alert = is_alert,
    span = if (is_alert) m$span else NA
  )
}), offered)

places <- setNames(lapply(df$CWA_DISPLAY, function(l) list(label = l)), df$CWA)
wjson(list(places = places, measures = measure_values,
           areas = measures_meta$areas), "data/map/cwa_values.json")

# Geometry ---------------------------------------------------------------------
# The choropleth reads a simplified copy: 10's file carries full-resolution
# polygons plus every measure as properties (~4 MB); the map needs neither,
# because the values ship in cwa_values.json above.
simplified <- cwa |>
  select(CWA, CWA_DISPLAY) |>
  st_simplify(dTolerance = 500, preserveTopology = TRUE)
geojson_path <- paste0(out, "data/geo/cwa.geojson")
if (file.exists(geojson_path)) unlink(geojson_path)
st_write(simplified, geojson_path, driver = "GeoJSON", quiet = TRUE)

# State outlines (the only basemap) ship with the site source under assets/
# and arrive via the site-files copy below — geometry only, no data-refresh
# dependency, so they are not part of data/.

# Meta -------------------------------------------------------------------------
# The landing page quotes the respondent total and the years covered. Counted
# by the data half, where the response table exists: counting it here would
# mean reading the 400 MB file a second time to print one number.
respondents <- read_json(paste0(data_dir, "respondents.json"),
                         simplifyVector = TRUE)
wjson(list(
  rows = respondents$rows,
  years = respondents$years,
  compiled = format(Sys.time(), "%Y-%m-%d %H:%M"),
  # shQuote because system2 hands the command to a shell when stderr is
  # redirected, and the repo path can contain spaces.
  sha = tryCatch(
    system2("git", c("-C", shQuote(here::here()), "rev-parse", "--short",
                     "HEAD"), stdout = TRUE, stderr = FALSE)[1],
    error = function(e) "unknown")
), "data/meta.json")

# Measure Notes ----------------------------------------------------------------
# The prose under the map: what was asked, how it is scored, how to read the
# colors, where it came from. Same content 10's page derives in the browser
# from measures.json, authored here as HTML in a two-column note layout.
# ippra.net is the institute's own domain; www.ou.edu/ippra still answers but
# is not the one it wants indexed.
INSTITUTE_LINK <- paste0(
  "<a href=\"https://ippra.net\">The University of Oklahoma's ",
  "Institute for Public Policy Research and Analysis</a>")
ARCHIVE_LINK <- paste0(
  "<a href=\"https://dataverse.harvard.edu/dataverse/wxsurvey\">",
  "dataverse.harvard.edu/dataverse/wxsurvey</a>")
MESONET_LINK <- paste0(
  "<a href=\"https://mesonet.agron.iastate.edu/request/gis/watchwarn.phtml\">",
  "Iowa Environmental Mesonet</a>")

esc_html <- function(s) {
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  gsub(">", "&gt;", s, fixed = TRUE)
}
count_word <- function(n) {
  words <- c("one", "two", "three", "four", "five", "six", "seven", "eight",
             "nine")
  if (n >= 1 && n <= length(words)) words[n] else as.character(n)
}
scale_anchors <- function(options) {
  if (is.null(options) || is.na(options) || options == "") return(NULL)
  parts <- str_match(str_split(options, fixed(" | "))[[1]],
                     "^\\s*(.+?)\\s*=\\s*(.*)$")
  parts <- parts[!is.na(parts[, 1]), , drop = FALSE]
  if (nrow(parts) == 0) return(NULL)
  paste0(parts[1, 2], " (", str_to_lower(parts[1, 3]), ") to ",
         parts[nrow(parts), 2], " (",
         str_to_lower(parts[nrow(parts), 3]), ")")
}
# The space belongs inside the group: with it outside, the two alternatives
# that carry their own leading space needed two, so "Tornado alert days" kept
# its suffix and the note read "one VTEC-enabled tornado alert days watch".
hazard_of_label <- function(label) {
  str_to_lower(str_remove(label, paste0(
    "( warning (reception|comprehension|response)",
    "| risk perceptions| alert days)$")))
}

provenance_note <- paste0(
  "<p>From the <em>Extreme Weather and Society Survey</em>, run by ",
  INSTITUTE_LINK, ". Estimates come from multilevel models fitted to survey ",
  "responses and reweighted to the adult population of each county, then ",
  "combined to the County Warning Area, so they describe US adults in each ",
  "area rather than only the people surveyed. The survey data behind them ",
  "is available at ", ARCHIVE_LINK, ".</p>")

map_notes <- list()
for (m in menu) {
  code <- m$measure
  mv <- measure_values[[code]]
  lo <- mv$domain[[1]]
  hi <- mv$domain[[2]]
  lede <- paste0(
    "<p class=\"wx-lede\">", esc_html(m$label), " across the ",
    measures_meta$areas, " National Weather Service County Warning Areas of ",
    "the contiguous United States.</p>")

  if (isTRUE(m$alert)) {
    map_notes[[code]] <- paste0(
      lede,
      "<div class=\"wx-note-cols\"><div>",
      "<p>Each value is the number of days on which the National Weather ",
      "Service issued at least one VTEC-enabled ",
      esc_html(hazard_of_label(m$label)),
      " watch, warning, or advisory event anywhere in the area, between ",
      m$span, ". Days are counted once however many products were issued on ",
      "them. Colors are stretched over ", lo, " to ",
      format(hi, big.mark = ","), ", the range these counts actually ",
      "take.</p></div><div>",
      "<p>Counts come from the ", MESONET_LINK, " archive of National ",
      "Weather Service watch, warning, and advisory events. These are the ",
      "same exposure measures the survey models are fitted on, which is why ",
      "they are shown here beside the estimates they help explain. They are ",
      "observed counts rather than survey estimates: no one was asked ",
      "anything to produce them.</p></div></div>")
    next
  }

  items <- m$items
  if (length(items) == 0) {
    stop("No question wording for mapped measure ", code,
         " — measures.json is out of step.")
  }
  shared <- isTRUE(m$shared_intro)
  anchors <- scale_anchors(m$response_options)
  hazard_name <- if (!is.null(m$hazard) && !is.na(m$hazard))
    str_remove(m$hazard, " \\(..\\)$") else NULL

  bullets <- paste0("<li>", vapply(items, function(it) {
    txt <- if (shared) it$question_text else
      str_squish(paste(it$question_intro %||% "", it$question_text %||% ""))
    paste0(esc_html(txt),
           if (isTRUE(it$reverse_coded)) " <em>(reverse coded)</em>" else "")
  }, character(1)), "</li>", collapse = "")

  scored <- if (length(items) > 1) paste0(
    "The ", count_word(length(items)), " answers",
    if (!is.null(hazard_name)) paste0(", all from the ", hazard_name,
                                      " survey,") else "",
    " are averaged into one score",
    if (!is.null(anchors)) paste0(" from ", anchors) else "", ".")
  else paste0("Answers run",
              if (!is.null(anchors)) paste0(" from ", anchors) else "", ".")
  varies <- if (!is.null(m$n_intros) && m$n_intros > 1) paste0(
    " The introduction was worded ", count_word(m$n_intros), " slightly ",
    "different ways across the surveys that asked it; the most widely used ",
    "version is shown.") else ""

  map_notes[[code]] <- paste0(
    lede,
    "<div class=\"wx-note-cols\"><div>",
    "<p><strong>Respondents were asked:</strong>",
    if (shared) paste0(" &ldquo;", esc_html(m$intro), "&rdquo;") else "",
    "</p><ul>", bullets, "</ul></div><div>",
    "<p>", esc_html(scored), esc_html(varies), " Colors are stretched over ",
    lo, " to ", hi, " rather than the full 1 to 5, so areas are compared ",
    "against each other rather than against the ends of the scale.</p>",
    provenance_note,
    "</div></div>")
}

# The Scan Sheet ---------------------------------------------------------------
# One area against all the others on every measure at once, under the map. The
# panel computes nothing: it draws the values, medians and percentiles already
# in cwa_values.json. What is authored here is the caution that makes the rows
# readable - each row is stretched to its own range, so equal positions mean
# equal standing and not equal differences. The three widths are measured off
# the data rather than asserted, because that claim is what the stretch trades
# on and it moves with every refresh.
measure_span <- function(code) {
  d <- measure_values[[code]]$domain
  d[[2]] - d[[1]]
}
is_alert_measure <- vapply(menu, function(m) isTRUE(m$alert), logical(1))
alert_codes <- offered[is_alert_measure]
risk_codes <- offered[!is_alert_measure & startsWith(offered, "RISK_")]
warning_codes <- setdiff(offered[!is_alert_measure], risk_codes)

widest_warning <- sprintf("%.2f", max(vapply(warning_codes, measure_span, 0)))
widest_risk <- sprintf("%.1f", max(vapply(risk_codes, measure_span, 0)))
widest_alert <- format(round(max(vapply(alert_codes, measure_span, 0))),
                       big.mark = ",")

# The alert spans as one sentence, because the sheet lists every category at
# once and cannot carry the per-measure clause the notes below the map use.
# Written from the menu so a category whose coverage changes moves itself into
# or out of the exception rather than needing this prose re-edited.
alert_menu <- menu[is_alert_measure]
alert_spans <- vapply(alert_menu, function(m) m$span, character(1))
common_span <- names(sort(table(alert_spans), decreasing = TRUE))[1]
odd_alerts <- alert_menu[alert_spans != common_span]
as_range <- function(s) str_replace(s, " and ", " to ")

alert_span_sentence <- if (length(odd_alerts) == 0) {
  paste0("All cover ", as_range(common_span), ".")
} else {
  odd_labels <- vapply(odd_alerts, function(m) {
    str_to_lower(str_remove(m$label, " alert days$"))
  }, character(1))
  paste0(
    "All cover ", as_range(common_span), " except ",
    paste(odd_labels, collapse = ", "), ", which covers ",
    as_range(odd_alerts[[1]]$span),
    " because the product did not exist before then."
  )
}

scan_lede <- paste0(
  "<p>Each row is one measure. Every row is stretched to its own range across ",
  "the ", measures_meta$areas, " areas, so a dot at the right of one row and ",
  "a dot at the right of another mean the same standing, not the same size of ",
  "difference &mdash; the widest warning scale spans ", widest_warning,
  " of a point, the widest risk item ", widest_risk, ", and the widest alert ",
  "count ", widest_alert, " days. The numbers at the ends of a row are that ",
  "measure&rsquo;s own lowest and highest value across the areas.</p>")

scan_note <- paste0(
  provenance_note,
  "<p>The alert counts are not estimates. They are days on which the National ",
  "Weather Service issued at least one VTEC-enabled watch, warning, or ",
  "advisory event of that kind, taken from the ", MESONET_LINK, " archive, ",
  "and they are the exposure measures the models are fitted on. ",
  alert_span_sentence, "</p>")

# Comparison Pairing -----------------------------------------------------------
# The map can pair a measure with ONE thing: the alert-day history its
# model is fitted on (06_fit_models.R). WW pairs to SNOW by default with ICE
# offered in the dropdown. Drought, hail and lightning have no NWS alert
# product — 06 fits them on FEMA NRI frequencies — so their pairing is NA and
# the page says so instead of faking one.
compare_pairing <- c(
  TO_RECEP = "ALERT_TORN", TO_SUBJ_COMP = "ALERT_TORN", TO_RESP = "ALERT_TORN",
  HU_RECEP = "ALERT_HURR", HU_SUBJ_COMP = "ALERT_HURR", HU_RESP = "ALERT_HURR",
  WW_RECEP = "ALERT_SNOW", WW_SUBJ_COMP = "ALERT_SNOW", WW_RESP = "ALERT_SNOW",
  FL_RECEP = "ALERT_FLOOD", FL_SUBJ_COMP = "ALERT_FLOOD",
  FL_RESP = "ALERT_FLOOD",
  RISK_TOR = "ALERT_TORN", RISK_HUR = "ALERT_HURR", RISK_SURGE = "ALERT_SURG",
  RISK_FLOOD = "ALERT_FLOOD", RISK_SNOW = "ALERT_SNOW",
  RISK_ICE = "ALERT_ICE", RISK_COLD = "ALERT_COLD", RISK_HEAT = "ALERT_HEAT",
  RISK_FIRE = "ALERT_FIRE",
  RISK_DROUGHT = NA, RISK_HAIL = NA, RISK_LIGNT = NA
)

unpaired <- offered[!startsWith(offered, "ALERT_") &
                      !offered %in% names(compare_pairing)]
if (length(unpaired) > 0) {
  print(unpaired)
  stop("Measures above are new in the menu and have no compare_default — ",
       "decide their alert pairing (see 06_fit_models.R) and add it.")
}

# The other direction: a pairing naming an alert layer the menu no longer
# offers leaves the second map with nothing to draw, and the front end has
# no values for it either — cwa_values.json is keyed by the menu.
dangling <- setdiff(compare_pairing[!is.na(compare_pairing)], offered)
if (length(dangling) > 0) {
  print(unname(dangling))
  stop("Alert layers above are paired to a measure but are not in the menu.")
}

catalog <- lapply(menu, function(m) list(
  code = m$measure, label = m$label, group = m$group,
  kind = if (isTRUE(m$alert)) "alert" else "estimate",
  compare_default = unname(compare_pairing[m$measure])
))

# Quiz -------------------------------------------------------------------------
# Prompts are fixed; answer keys and reveal numbers are read off 10's own
# distributions, so a data refresh recomputes them and they always agree with
# what the explorer shows. Guards halt the build when the fixed prose stops
# being true of the data, naming the sentence to re-write.
q_data <- function(id) {
  path <- paste0(data_dir, "q/", id, ".json")
  if (!file.exists(path))
    stop("Quiz needs question ", id, " — not in ", data_dir)
  read_json(path, simplifyVector = FALSE)
}
split_rows <- function(q, split) {
  # A split-sample question nests its splits under the version, so its rows are
  # not where this expects them. Refused rather than read wrong: a quiz answer
  # drawn from one arm of an experiment is a claim about the people who saw
  # that version, not about US adults, and the prompt does not say so.
  if (length(q$arms) > 0) {
    stop("Quiz question ", q$id, " is split-sampled — its versions cannot be ",
         "pooled into one answer.")
  }
  rows <- q$splits[[split]]
  if (is.null(rows)) stop("Quiz needs split ", split, " on ", q$id, ".")
  rows
}
# Share answering within codes, per group. Carried at full precision: the
# guards below measure how far apart two groups really are, and a share
# rounded first can gain or lose a point on the way, which is enough to walk
# an answer past a margin it does not clear.
share_of <- function(id, codes, split = "All") {
  rows <- split_rows(q_data(id), split)
  groups <- unique(map_chr(rows, "group"))
  out <- vapply(groups, function(g) {
    sum(map_dbl(rows, function(r)
      if (r$group == g && as.numeric(r$resp) %in% codes) r$p else 0))
  }, double(1))
  setNames(out, groups)
}
# Weighted mean of the response codes, per group: the shares are weighted, so
# sum(code * p) / sum(p) IS the weighted mean of the item.
mean_of <- function(id, split = "All") {
  rows <- split_rows(q_data(id), split)
  groups <- unique(map_chr(rows, "group"))
  out <- vapply(groups, function(g) {
    gr <- keep(rows, function(r) r$group == g)
    sum(map_dbl(gr, function(r) as.numeric(r$resp) * r$p)) /
      sum(map_dbl(gr, "p"))
  }, double(1))
  setNames(out, groups)
}
# Written into prose and chart labels at the precision the explorer shows:
# whole percentage points for a share, one decimal for a 1-5 mean.
shown_pct <- function(x) round(x)
shown_mean <- function(x) round(x, 1)
check_prose <- function(ok, what) {
  if (!ok) stop("Quiz prose drifted: ", what, " — re-word that question in ",
                "09_build_dashboard.R before shipping.")
}
# The nearest offered band, guarded so that "nearest" means something: the
# tolerance is half the narrowest gap between bands, so a share sitting
# between two of them halts rather than being rounded into the lower one.
pct_band <- function(share, options_pcts) {
  tol <- min(diff(sort(options_pcts))) / 2
  check_prose(min(abs(options_pcts - share)) < tol,
              paste0("computed share ", share, "% is not within ", tol,
                     " points of one offered band (",
                     paste(options_pcts, collapse = "/"), ")"))
  which.min(abs(options_pcts - share)) - 1L
}
no_tie <- function(x, what) {
  check_prose(sum(x == max(x)) == 1, paste0(what, " has a tie for first"))
}
# A quiz answer has to be one the reader can see for themselves in the chart
# the reveal draws, and the two kinds of answer here are true in different
# ways.
#
# decisive() is for a single winner among unordered choices. It has to clear
# the runner-up by more than the confidence intervals 10 puts on the same
# numbers - those run about 1.6 points on a share - or the answer is a coin
# flip the reader is told they lost. Means on the 1-5 scale take margin = 0.2.
#
# gradient() is for ordered splits, where the reveal claims a direction rather
# than a winner: understanding rises with age, reliance on social media falls
# with it. The claim is the whole run, so the guard is that it still runs one
# way end to end; adjacent groups are allowed to sit close together, which is
# why age survives here on a 1.7-point top pair.
decisive <- function(x, what, low = FALSE, margin = 3) {
  o <- order(x, decreasing = !low)
  gap <- abs(x[[o[1]]] - x[[o[2]]])
  check_prose(gap >= margin, paste0(
    what, ": ", names(x)[o[1]], " and ", names(x)[o[2]], " are ", round(gap, 2),
    " apart, under the ", margin, " the intervals on the same numbers can ",
    "separate - re-word it or ask a different group"))
  o[1]
}
gradient <- function(x, what, low = FALSE) {
  steps <- diff(unname(x))
  check_prose(all(steps >= 0) || all(steps <= 0), paste0(
    what, ": the run across the groups no longer goes one way (",
    paste(round(x, 2), collapse = ", "), ")"))
  no_tie(if (low) -x else x, what)
  if (low) which.min(x) else which.max(x)
}
# Q2 and Q4 open by comparing four separate survey variables, so no single
# data/q file matches the prompt; these rows ARE the comparison the prompt
# makes, and the front end charts them instead of the explore target's file.
cmp_chart <- function(values, y_label, fmt = function(v) v) list(
  rows = unname(Map(
    function(nm, v) list(group = "All", category = nm, value = v,
                         label = fmt(v)),
    names(values), values)),
  y_label = y_label)

quiz <- local({
  q1_all <- share_of("WX_alert_und", c(4, 5))[["All"]]
  q1_by <- share_of("WX_alert_und", c(4, 5), "AGE_GROUP")
  q1_opts <- c("About 40%", "About 60%", "About 80%", "Nearly 100%")
  q1_ans <- pct_band(q1_all, c(40, 60, 80, 98))
  q1_top <- gradient(q1_by, "Q1 reveal: understanding rises with age")

  rely_vars <- c(Television = "WX_wx_info3", `Social media` = "WX_wx_info5",
                 `Weather radio` = "WX_wx_info2",
                 `Word of mouth` = "WX_wx_info6")
  rely_means <- vapply(rely_vars, function(v) mean_of(v)[["All"]], double(1))
  rely_top <- decisive(rely_means, "Q2 most-relied source", margin = 0.2)
  q2_by <- mean_of("WX_wx_info5", "AGE_GROUP")
  q2_top <- gradient(q2_by, "Q2 reveal: social-media reliance falls with age")

  wep_shares <- vapply(1:3, function(k)
    share_of("TC_wep_rec", k)[["All"]], double(1))
  q3_opts <- c("Numbers", "Words", "A combination of both")
  wep_top <- decisive(setNames(wep_shares, q3_opts), "Q3 numbers/words/both")
  q3_by <- share_of("TC_wep_rec", 1, "EDUC_GROUP")
  q3_top <- gradient(q3_by, "Q3 reveal: numbers-only rises with education")
  check_prose(all(q3_by < 50),
              "Q3 reveal calls numbers-only a minority in every group")

  risk_vars <- c(Tornadoes = "WX_risk_tor", Hurricanes = "WX_risk_hur",
                 `Extreme heat waves` = "WX_risk_heat",
                 Flooding = "WX_risk_flood")
  risk_shares <- vapply(risk_vars, function(v)
    share_of(v, c(4, 5))[["All"]], double(1))
  risk_top <- decisive(risk_shares, "Q4 highest-rated risk")
  q4_by <- share_of("WX_risk_flood", c(4, 5), "CENSUS_REGION")
  q4_top <- decisive(q4_by, "Q4 highest-flood-risk region")

  q5_all <- share_of("WX_rec_all", c(4, 5))[["All"]]
  q5_opts <- c("About 30%", "About 50%", "About 70%", "About 90%")
  q5_ans <- pct_band(q5_all, c(30, 50, 70, 90))
  # Asked by region rather than by community type: urban, suburban and rural
  # sit within three points of each other on this item, which is inside the
  # intervals the reveal chart draws, so the answer was one the reader could
  # not see. Tornado warnings are rare in the West, and that shows here.
  q5_by <- share_of("WX_rec_all", c(4, 5), "CENSUS_REGION")
  q5_low <- decisive(q5_by, "Q5 lowest-reception region", low = TRUE)

  list(
    list(
      part1 = list(
        prompt = paste0("Approximately what percentage of U.S. adults say ",
                        "they understand the difference between a tornado ",
                        "WATCH and a tornado WARNING?"),
        options = q1_opts, answer = q1_ans,
        reveal = paste0(shown_pct(q1_all), "% say they probably or ",
                        "definitely ",
                        "understand the difference.")),
      part2 = list(
        prompt = "Which age group reports the highest understanding?",
        options = names(q1_by), answer = q1_top - 1L,
        reveal = paste0(names(q1_by)[q1_top], " — ",
                        shown_pct(q1_by[[q1_top]]), "% say so, against ",
                        shown_pct(min(q1_by)), "% of the lowest group.")),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_alert_und",
                                   grouping = "AGE_GROUP"))),
    list(
      part1 = list(
        prompt = "What source do people rely on most for weather information?",
        options = names(rely_vars), answer = rely_top - 1L,
        reveal = paste0(names(rely_vars)[rely_top], " — ",
                        shown_mean(rely_means[[rely_top]]),
                        " on the 1–5 reliance scale."),
        chart = cmp_chart(shown_mean(rely_means),
                          "Mean reliance (1–5 scale)")),
      part2 = list(
        prompt = paste0("Which age group relies most on social media for ",
                        "weather information?"),
        options = names(q2_by), answer = q2_top - 1L,
        reveal = paste0(names(q2_by)[q2_top], " (",
                        shown_mean(q2_by[[q2_top]]),
                        " of 5). Reliance falls with age — the lowest group ",
                        "averages ", shown_mean(min(q2_by)), ".")),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_wx_info5",
                                   grouping = "AGE_GROUP"))),
    list(
      part1 = list(
        prompt = paste0("When getting information from forecasters, what do ",
                        "most people prefer: numbers, words, or both?"),
        options = q3_opts, answer = wep_top - 1L,
        reveal = paste0("Numbers alone: ", shown_pct(wep_shares[1]),
                        "%. Words alone: ", shown_pct(wep_shares[2]),
                        "%. A combination of both: ",
                        shown_pct(wep_shares[3]), "%.")),
      part2 = list(
        prompt = paste0("Which education group is most likely to prefer ",
                        "numbers only?"),
        options = names(q3_by), answer = q3_top - 1L,
        reveal = paste0(names(q3_by)[q3_top], " (",
                        shown_pct(q3_by[[q3_top]]),
                        "%) — though numbers-only is a minority preference ",
                        "in every group.")),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "TC_wep_rec",
                                   grouping = "EDUC_GROUP"))),
    list(
      part1 = list(
        prompt = paste0("Which hazard do the most Americans rate as a high ",
                        "or extreme risk where they live?"),
        options = names(risk_vars), answer = risk_top - 1L,
        reveal = paste0(names(risk_vars)[risk_top], " — ",
                        shown_pct(risk_shares[[risk_top]]),
                        "% rate it high or extreme."),
        chart = cmp_chart(shown_pct(risk_shares),
                          "Rate it high or extreme (%)",
                          function(v) paste0(v, "%"))),
      part2 = list(
        prompt = paste0("Which census region reports the highest perceived ",
                        "flood risk?"),
        options = names(q4_by), answer = q4_top - 1L,
        reveal = paste0("The ", names(q4_by)[q4_top], " — ",
                        shown_pct(q4_by[[q4_top]]),
                        "% rate flood risk high or extreme, against ",
                        shown_pct(min(q4_by)), "% in the lowest region.")),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_risk_flood",
                                   grouping = "CENSUS_REGION"))),
    list(
      part1 = list(
        prompt = paste0("What share of people agree they receive all ",
                        "tornado warnings issued for their area?"),
        options = q5_opts, answer = q5_ans,
        reveal = paste0(shown_pct(q5_all), "% — meaning many people are ",
                        "not confident they get every warning.")),
      part2 = list(
        prompt = paste0("Which census region is LEAST likely to say they ",
                        "receive all tornado warnings?"),
        options = names(q5_by), answer = q5_low - 1L,
        reveal = paste0("The ", names(q5_by)[q5_low], " — ",
                        shown_pct(q5_by[[q5_low]]),
                        "% agree they receive them all, against ",
                        shown_pct(max(q5_by)), "% in the ",
                        names(q5_by)[which.max(q5_by)], ".")),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_rec_all",
                                   grouping = "CENSUS_REGION")))
  )
})

# Config -----------------------------------------------------------------------
# Everything the front end reads that is not question or map data: pages,
# themes, split roster with caption phrases, popover texts, the caption and
# popup templates ({tokens} filled at render time), and the quiz above.
groups <- c(
  "Everyone" = "All",
  "Age" = "AGE_GROUP",
  "Gender" = "GENDER_GROUP",
  "Race and ethnicity" = "RACE_GROUP",
  "Education" = "EDUC_GROUP",
  "Income" = "INCOME_GROUP",
  "Census region" = "CENSUS_REGION",
  "Urban, suburban, rural" = "RURAL_GROUP",
  "Housing tenure" = "TENURE_GROUP",
  "Residence type" = "HOME_GROUP",
  "Children in household" = "CHILDREN_GROUP",
  "Weather salience" = "SALIENCE_GROUP",
  "Survey year" = "survey_year"
)
group_phrases <- c(
  AGE_GROUP = "age group",
  GENDER_GROUP = "gender",
  RACE_GROUP = "race and ethnicity group",
  EDUC_GROUP = "education group",
  INCOME_GROUP = "income group",
  CENSUS_REGION = "census region",
  RURAL_GROUP = "community type",
  TENURE_GROUP = "housing tenure",
  HOME_GROUP = "residence type",
  CHILDREN_GROUP = "children-in-household group",
  SALIENCE_GROUP = "weather salience group",
  survey_year = "survey year's respondents"
)
groupings_cfg <- lapply(seq_along(groups), function(i) {
  id <- unname(groups[i])
  list(id = id, label = names(groups)[i],
       phrase = if (id == "All") NULL else unname(group_phrases[id]))
})

# The landing page, the About page and the menu all describe the three
# working pages, so each description is written once here.
blurbs <- list(
  survey = paste0("Browse every survey question across hazards, ",
                  "demographic groups, and other characteristics."),
  map = paste0("Compare estimates across National Weather Service ",
               "forecast offices, beside the alert history that helps ",
               "explain them."),
  quiz = paste0("Challenge your assumptions about how people receive, ",
                "understand, trust, and respond to weather forecasts and ",
                "warnings.")
)

about_link <- function(id, name, body) {
  paste0(
    "<a class=\"wx-about-link\" href=\"#", id, "\">",
    "<span class=\"wx-about-link-name\">", name, "</span>",
    "<span class=\"wx-about-link-body\">", body, "</span></a>"
  )
}

# The About page is one column of prose in sections, each under an eyebrow
# heading, as the fusion dashboard's is. The opening paragraph is the reason
# the platform exists, so it is set as the lede rather than under a heading.
about_html <- paste0(
  "<p class=\"wx-about-lede\">Members of the weather enterprise, including ",
  "National Weather Service (NWS) forecasters, emergency managers, broadcast ",
  "meteorologists, and private partners have many responsibilities, ranging ",
  "from the issuance of forecasts and warnings during high impact weather ",
  "events to outreach and public education campaigns during less turbulent ",
  "periods. Effective education and risk communication across this range of ",
  "responsibilities requires knowledge of the communities that enterprise ",
  "members serve. Enterprise members often have access to a wide variety of ",
  "data about atmospheric and climate conditions, but relatively little data ",
  "on the populations they serve. This platform works to close that gap.</p>",

  "<hr>",
  "<h3>The survey</h3>",
  "<p>The Extreme Weather and Society Survey is a yearly survey of US adults ",
  "run by ", INSTITUTE_LINK, ", covering severe weather, tropical cyclones, ",
  "winter weather, and flooding. Every wave is raked to American Community ",
  "Survey benchmarks for age, gender, race, education, income and region, so ",
  "weighted percentages describe US adults rather than only the people ",
  "surveyed.</p>",

  "<hr>",
  "<h3>Community estimates</h3>",
  "<p>Place-level estimates are produced with multilevel regression and ",
  "poststratification (MRP), which combines the survey with US Census ",
  "population data \u2014 every County Warning Area gets an estimate, ",
  "including places where few people were surveyed. Alert-day counts shown ",
  "beside them are observed National Weather Service records from the ",
  MESONET_LINK, " archive. For more information see:</p>",
  "<ul>",
  "<li><a href=\"https://doi.org/10.1175/WCAS-D-19-0015.1\">Measuring ",
  "Tornado Warning Reception, Comprehension, and Response in the United ",
  "States</a></li>",
  "<li><a href=\"https://doi.org/10.1175/BAMS-D-19-0064.1\">Exploring ",
  "Community Differences in Tornado Warning Reception, Comprehension, and ",
  "Response Across the United States</a></li>",
  "<li><a href=\"https://doi.org/10.1111/risa.13569\">Geographic ",
  "Distributions of Extreme Weather Risk Perceptions in the United ",
  "States</a></li>",
  "</ul>",

  "<hr>",
  "<h3>Using this site</h3>",
  "<div class=\"wx-about-links\">",
  about_link("survey", "Explore Survey Questions", blurbs$survey),
  about_link("map", "Explore Communities", blurbs$map),
  about_link("quiz", "Test Your Knowledge", blurbs$quiz),
  "</div>",

  "<hr>",
  "<h3>Data and support</h3>",
  "<p>All of the survey data and metadata are available at the ",
  "<a href=\"https://dataverse.harvard.edu/dataverse/wxsurvey\">Extreme ",
  "Weather and Society Dataverse</a>.</p>",
  "<p>The University of Oklahoma provides support for data collection. The ",
  "US Weather Program Office (WPO) and National Weather Service (NWS) provide ",
  "support for data analysis, programming, and maintenance.</p>",
  "<p>Contact <a href=\"mailto:jtr@ou.edu\">Joe Ripberger</a> or ",
  "<a href=\"mailto:mjkrocak@ou.edu\">Makenzie Krocak</a> at OU IPPRA.</p>",

  "<div class=\"wx-about-note\">",
  "<p class=\"wx-about-note-label\">Caution</p>",
  "<p class=\"wx-about-note-body\">These data, like most survey data, come ",
  "from non-probability samples that are not necessarily representative of ",
  "the entire US population. Use caution when making inferences and drawing ",
  "conclusions.</p>",
  "</div>"
)

config <- list(
  schema_version = 3,
  project = list(
    slug = "wxdash",
    title = "WxDash — Extreme Weather and Society Dashboard",
    nav_title = "WxDash",
    nav_subtitle = "Extreme Weather & Society Project"
  ),
  theme = list(default = "wxdash", allow_viewer_switch = TRUE),
  groupings = groupings_cfg,
  explore_caption = list(
    answered = paste0("{n} US adults answered this question about ",
                      "{hazard_phrase} {waves}. Bars show the weighted ",
                      "percentage{split_clause} giving each answer."),
    waves_one = "in the {years} wave",
    waves_many = "across the {years} waves",
    split_clause = " of each {group_phrase}",
    smallest = " The smallest group, {smallest}, has {smallest_n} respondents.",
    provenance = paste0("From the Extreme Weather and Society Survey, run ",
                        "by ", INSTITUTE_LINK, ". Every wave is raked to ",
                        "American Community Survey benchmarks for age, ",
                        "gender, race, education, income and region, so the ",
                        "percentages describe US adults rather than only the ",
                        "people surveyed. This question is stored as ",
                        "<code>{variable}</code>; the survey data is ",
                        "available at ", ARCHIVE_LINK, ".")
  ),
  catalog = catalog,
  map = list(
    notes = map_notes,
    scan = list(lede = scan_lede, note = scan_note),
    popup = list(
      estimate = paste0("The estimate for this area is {value} out of 5 for ",
                        "{quantity}. The median estimate across the {n} ",
                        "County Warning Areas is {median}. This area ",
                        "{standing}, at the {percentile} percentile."),
      alert = paste0("The National Weather Service issued {quantity} on ",
                     "{value} days in this area between {span}. The median ",
                     "across the {n} County Warning Areas is {median} days. ",
                     "This area {standing}, at the {percentile} percentile.")
    ),
    quantities = list(
      ALERT = "{hazard} watch, warning, and advisory events",
      RECEP = paste0("agreement that people receive the {hazard} warnings ",
                     "issued for their area"),
      RESP = paste0("agreement that people take protective action when ",
                    "{hazard} warnings are issued"),
      SUBJ_COMP = "how well people say they understand {hazard} warnings",
      RISK = "how people rate their risk from {hazard}"
    )
  ),
  explainers = list(
    about_estimates = paste0(
      "<p>WxDash shows estimates from the Extreme Weather and Society ",
      "Survey, a yearly national survey run by OU IPPRA. Because no ",
      "national sample includes enough people from every community, ",
      "place-level estimates are produced with multilevel regression and ",
      "poststratification (MRP), which combines the survey with US Census ",
      "population data.</p><p>Alert-day counts are different: they are ",
      "observed National Weather Service records, not estimates. Methods ",
      "and publications are on the About page.</p>"),
    weighted_pct = paste0("Percentages are weighted so results represent US ",
                          "adults as a whole, not just the people who ",
                          "happened to take the survey.")
  ),
  pages = list(
    list(id = "home", component = "wx_landing", label = "Home",
         hero = list(
           eyebrow = paste0("Extreme Weather and Society Project — ",
                            "University of Oklahoma"),
           headline = paste0("How do people receive, understand, trust, and ",
                             "respond to your forecasts and warnings?"),
           sub = paste0("Explore nationally representative survey data ",
                        "measuring the human dimensions of the forecast and ",
                        "warning process."),
           cta_label = "Explore the survey questions",
           question = "WX_alert_und")),
    list(id = "survey", component = "explore",
         label = "Explore Survey Questions",
         title = "Survey questions",
         questions = "data/questions.json", default_grouping = "All",
         intro = paste0("Click a survey question in the table below to see ",
                        "the weighted distribution of responses, split by ",
                        "the group you choose. Questions come from four ",
                        "yearly surveys — severe weather (WX), tropical ",
                        "cyclones (TC), winter weather (WW), and flooding ",
                        "(FL)."),
         chart = list(x_label = "Response", y_label = "Respondents (%)"),
         blurb = blurbs$survey),
    list(id = "map", component = "wx_map_explorer",
         label = "Explore Communities",
         title = "Communities by forecast office",
         default_measure = "TO_RECEP",
         sidebar_lead = paste0("These are model estimates, not raw survey ",
                               "responses — every area gets a value, ",
                               "including places where few people were ",
                               "surveyed. Hover an area to read its value; ",
                               "click it for the full story, and for a scan ",
                               "of every measure estimated there."),
         blurb = blurbs$map),
    list(id = "quiz", component = "wx_quiz", label = "Test Your Knowledge",
         title = "How well do you know the public?",
         intro = paste0("Challenge your assumptions about how people ",
                        "receive, understand, trust, and respond to weather ",
                        "forecasts and warnings. Guess first — then open ",
                        "the real data."),
         blurb = blurbs$quiz,
         questions = quiz),
    list(id = "about", component = "static_page", label = "About",
         title = "About WxDash", html = about_html)
  ),
  footer = list(
    tagline = paste0("Nationally representative survey data measuring the ",
                     "human dimensions of the forecast and warning process."),
    links_html = paste0(
      "<a href=\"#about\">About & methods</a>",
      "<a href=\"https://dataverse.harvard.edu/dataverse/wxsurvey\">",
      "Survey data (Dataverse)</a>",
      "<a href=\"https://ippra.net\">OU IPPRA</a>",
      "<a href=\"mailto:jtr@ou.edu\">Contact</a>"),
    funding = paste0("Supported by the University of Oklahoma, the US ",
                     "Weather Program Office (WPO), and the National ",
                     "Weather Service (NWS).")
  )
)
wjson(config, "config.json", pretty = TRUE)

# Site Files -------------------------------------------------------------------
# Everything under site/ is copied through: it is the hand-edited source, kept
# editable as itself rather than generated from R strings. index.html is the
# one exception — the __BUILD__ stamp is filled in so asset URLs bust
# long-lived host caches on every deploy.
BUILD <- format(Sys.time(), "%Y%m%d%H%M%S")
invisible(file.copy(list.files(site_src, full.names = TRUE), out,
                    recursive = TRUE, overwrite = TRUE))
index_html <- readLines(file.path(site_src, "index.html"))
writeLines(gsub("__BUILD__", BUILD, index_html), paste0(out, "index.html"))

# list.files() skips dotfiles at the top of site/, but the copy above descends
# into assets/ as whole directories, so macOS's .DS_Store rides along and is
# published. Dropped here rather than filtered on the way in, because the trap
# is anything hidden, not that one filename.
copied <- list.files(out, recursive = TRUE, all.files = TRUE,
                     full.names = TRUE)
unlink(copied[startsWith(basename(copied), ".")])

# Checked byte for byte, because outputs/ lives in Dropbox. A sync racing the
# rebuild restores the previous engine.js under its own name and files the new
# one as a "conflicted copy" beside it, which publishes stale JavaScript with
# fresh data - a site that loads, draws, and is wrong. index.html is compared
# with the stamp filled in, since that is the one line the builder rewrites.
carried <- setdiff(list.files(site_src, recursive = TRUE), "index.html")
same_bytes <- function(a, b) {
  file.exists(b) && identical(readBin(a, "raw", file.size(a)),
                              readBin(b, "raw", file.size(b)))
}

stale <- carried[!map_lgl(carried, ~same_bytes(file.path(site_src, .x),
                                               paste0(out, .x)))]

if (!identical(readLines(paste0(out, "index.html")),
               gsub("__BUILD__", BUILD, index_html))) {
  stale <- c(stale, "index.html")
}

if (length(stale) > 0) {
  print(stale)
  stop("Files above are not what site/ holds - a sync raced the build. ",
       "Let Dropbox settle, then run again.")
}

conflicted <- list.files(out, pattern = "conflicted copy", recursive = TRUE)

if (length(conflicted) > 0) {
  print(head(conflicted, 20))
  stop(length(conflicted), " conflicted copies reached the built site - ",
       "Dropbox resolved a sync against the build. Delete outputs/09_site, ",
       "let it settle, then run again.")
}

# Guarded rather than trusted: nothing under site/ should be R, but a script
# saved there by mistake would otherwise become readable source on a public
# URL.
published_r <- list.files(out, pattern = "\\.[Rr]$", recursive = TRUE)
if (length(published_r) > 0) {
  print(published_r)
  stop("R sources above reached the built site — they must not be uploaded.")
}

required <- c("index.html", "engine.js", "engine.css", "config.json",
              "data/questions.json", "data/map/cwa_values.json",
              "data/geo/cwa.geojson", "assets/geo/states.geojson",
              "data/meta.json")
absent <- required[!file.exists(paste0(out, required))]
if (length(absent) > 0) {
  print(absent)
  stop("Files above are missing from the built site.")
}

size_mb <- sum(file.size(list.files(out, recursive = TRUE,
                                    full.names = TRUE))) / 1024^2
message("Site written to ", out)
message("  build ", BUILD, ", ", length(q_files), " questions, ",
        measures_meta$areas, " areas, ", round(size_mb, 1), " MB total")
