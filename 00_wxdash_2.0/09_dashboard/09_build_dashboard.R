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
# outputs, no survey waves and no ~/.Renviron - the alternative is handing
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

# Which deployment this build is for. The beta on GitHub Pages is built with
# WXDASH_CHANNEL=beta, which labels the masthead and asks search engines not
# to index it, so the beta never competes with the production site in search.
# Unset, the build is production: the same site with neither.
channel <- Sys.getenv("WXDASH_CHANNEL", "production")
if (!channel %in% c("production", "beta")) {
  stop("WXDASH_CHANNEL is `", channel, "`; use `beta` or leave it unset.")
}

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

# The randomizer behind each split-sample question, keyed by question id, from
# the same declaration the data half used to split it.
question_arm_decl <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "question_arms.csv"),
  col_types = cols(.default = col_character())
)
arm_variables <- local({
  all_q <- read_json(paste0(data_dir, "questions.json"), simplifyVector = FALSE)
  key <- setNames(vapply(all_q, function(x) x$id, ""),
                  vapply(all_q, function(x) paste(x$hazard, x$variable), ""))
  ids <- key[paste(question_arm_decl$hazard, question_arm_decl$variable)]
  keep_rows <- !is.na(ids)
  as.list(setNames(question_arm_decl$arm_variable[keep_rows],
                   ids[keep_rows]))
})

# The words a version puts into the question, for randomizers whose value is a
# code rather than the text respondents read (`fcst_conf` is `high`, and the
# respondent read a sentence). Only randomizers with a `wording` column filled
# are carried, and for those an empty entry means the version added nothing.
arm_wording <- local({
  roster <- read_csv(
    here::here("00_wxdash_2.0", "09_dashboard", "arms.csv"),
    col_types = cols(.default = col_character())
  )
  worded <- roster |>
    filter(any(!is.na(wording)), .by = arm_variable) |>
    mutate(wording = coalesce(wording, ""))
  lapply(split(worded, worded$arm_variable),
         function(x) as.list(setNames(x$wording, x$value)))
})

# What a version put on the screen before the question rather than into it
# (`tor_em_rare` decided whether a definition came first). The question reads
# the same under every version, so without this the menu would change the
# chart and nothing a reader can see.
arm_shown <- local({
  roster <- read_csv(
    here::here("00_wxdash_2.0", "09_dashboard", "arms.csv"),
    col_types = cols(.default = col_character())
  ) |>
    filter(!is.na(shown_before))
  lapply(split(roster, roster$arm_variable),
         function(x) as.list(setNames(x$shown_before, x$value)))
})

# Hidden Questions -------------------------------------------------------------
# Questions Explore Survey Questions does not list, flagged in the browser with
# ?flag=1 and exported to hidden_questions.csv. `hide` takes a question off the
# list; `needs-context` only records it. The list is filtered here, not in the
# statistics: every question keeps its data and script files, so a change to
# the list needs no --data run and a question can come back without one.
hidden <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "hidden_questions.csv"),
  col_types = cols(.default = col_character())
)
dispositions <- c("hide", "needs-context")
question_list <- read_json(paste0(data_dir, "questions.json"),
                           simplifyVector = FALSE)
question_ids <- vapply(question_list, function(x) x$id, "")

# A stale entry is worse than no entry: it looks like the question is hidden
# while the question is on the page.
unknown_hidden <- setdiff(hidden$id, question_ids)
if (length(unknown_hidden) > 0) {
  print(unknown_hidden)
  stop("Ids above are listed in hidden_questions.csv but are not questions.")
}
bad_disposition <- setdiff(hidden$disposition, dispositions)
if (length(bad_disposition) > 0) {
  print(bad_disposition)
  stop("Dispositions above are not one of: ",
       paste(dispositions, collapse = ", "))
}
if (anyDuplicated(hidden$id)) {
  print(hidden$id[duplicated(hidden$id)])
  stop("Ids above are listed more than once in hidden_questions.csv.")
}

drop_ids <- hidden$id[hidden$disposition == "hide"]
writeLines(
  toJSON(question_list[!question_ids %in% drop_ids], auto_unbox = TRUE,
         null = "null", na = "null", digits = NA),
  paste0(out, "data/questions.json")
)
message("Hidden from Explore Survey Questions: ", length(drop_ids), "; ",
        sum(hidden$disposition == "needs-context"), " flagged as needing ",
        "context")

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
# Rank, percentile and median are precomputed here rather than derived in the
# browser: rank is 1 + the count of strictly greater values, percentile is the
# share strictly below, rounded to whole numbers.
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
# The choropleth reads a lighter copy: the data half's cwa.geojson carries
# every measure as properties at 07's resolution (~4 MB); the map needs only
# the outlines, simplified further, because the values ship in cwa_values.json
# above.
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
# colors, where it came from, authored here as HTML in a two-column layout.
# ippra.net is the institute's own domain; www.ou.edu/ippra still answers but
# is not the one it wants indexed.
INSTITUTE_LINK <- paste0(
  "<a href=\"https://ippra.net\">The University of Oklahoma's ",
  "Institute for Public Policy Research and Analysis</a>")
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
# that carry their own leading space would need two, so "Tornado alert days"
# would keep its suffix and a note would read "one VTEC-enabled tornado alert
# days watch".
hazard_of_label <- function(label) {
  str_to_lower(str_remove(label, paste0(
    "( warning (reception|comprehension|response)",
    "| risk perceptions| alert days)$")))
}

# Every measure's note has the same parts, in the same order: the measure as
# a heading, one sentence on what the map shows, what respondents were asked,
# how the answers become a score and how the colors are stretched, then
# where the estimates come from. Alert counts follow the same order in their
# own terms, since nobody was asked anything to produce them. Every number is
# read off the data, never typed.
about_estimates <- paste0(
  "<p><strong>About the estimates:</strong> Results are from the Extreme ",
  "Weather and Society Survey at the <a href=\"https://ippra.net\">University ",
  "of Oklahoma’s Institute for Public Policy Research and Analysis</a>. ",
  "Community estimates come from multilevel models fitted to survey ",
  "responses and reweighted to the adult population of each county, then ",
  "combined to the National Weather Service County Warning Area.</p>",
  "<p>Survey data: <a href=\"https://dataverse.harvard.edu/dataverse/",
  "wxsurvey\">Extreme Weather and Society Survey Dataverse</a></p>")

map_notes <- list()
for (m in menu) {
  code <- m$measure
  mv <- measure_values[[code]]
  lo <- mv$domain[[1]]
  hi <- mv$domain[[2]]
  label_lower <- str_to_lower(m$label)
  heading <- paste0("<p class=\"wx-lede\">", esc_html(m$label), "</p>")
  across <- paste0(" across the ", measures_meta$areas, " National Weather ",
                   "Service County Warning Areas in the contiguous United ",
                   "States.")

  if (isTRUE(m$alert)) {
    map_notes[[code]] <- paste0(
      heading,
      "<p class=\"wx-note-intro\">Counts show ", esc_html(label_lower),
      across, "</p>",
      "<div class=\"wx-note-cols\"><div>",
      "<p><strong>What is counted:</strong> The number of days from ",
      str_replace(m$span, " and ", " to "), " on which the National Weather ",
      "Service issued at least one VTEC-enabled ",
      esc_html(hazard_of_label(m$label)), " watch, warning, or advisory ",
      "anywhere in the area. Each day is counted once, regardless of how many ",
      "products were issued.</p></div><div>",
      "<p>The map colors span the observed range, from ", lo, " to ",
      format(hi, big.mark = ","), " alert days. This makes differences across ",
      "areas easier to see.</p>",
      "<p><strong>About the counts:</strong> Alert counts are observed data, ",
      "not survey estimates, from the ", MESONET_LINK, " archive. They are ",
      "used as measures of local alert exposure in the community models and ",
      "are shown here to provide context for the survey-based estimates.</p>",
      "</div></div>")
    next
  }

  items <- m$items
  if (length(items) == 0) {
    stop("No question wording for mapped measure ", code,
         " - measures.json is out of step.")
  }
  shared <- isTRUE(m$shared_intro)
  anchors <- scale_anchors(m$response_options)
  hazard_name <- if (!is.null(m$hazard) && !is.na(m$hazard))
    str_remove(m$hazard, " \\(..\\)$") else NULL
  from_survey <- if (!is.null(hazard_name))
    paste0(" from the ", hazard_name, " Survey") else ""

  bullets <- paste0("<li>", vapply(items, function(it) {
    txt <- if (shared) it$question_text else
      str_squish(paste(it$question_intro %||% "", it$question_text %||% ""))
    paste0(esc_html(txt),
           if (isTRUE(it$reverse_coded)) " <em>(reverse coded)</em>" else "")
  }, character(1)), "</li>", collapse = "")

  scored <- if (length(items) > 1) {
    paste0("Responses to these ", count_word(length(items)), " items",
           from_survey, " are averaged into a single score",
           if (!is.null(anchors)) paste0(" from ", anchors) else "", ".")
  } else if (!is.null(hazard_name)) {
    paste0("Responses to this item", from_survey, " run",
           if (!is.null(anchors)) paste0(" from ", anchors) else "", ".")
  } else {
    paste0("Responses to this item, pooled across the surveys that asked ",
           "it, run", if (!is.null(anchors)) paste0(" from ", anchors) else "",
           ".")
  }
  varies <- if (!is.null(m$n_intros) && m$n_intros > 1) paste0(
    " The introduction was worded ", count_word(m$n_intros), " slightly ",
    "different ways across the surveys that asked it; the most widely used ",
    "version is shown.") else ""

  map_notes[[code]] <- paste0(
    heading,
    "<p class=\"wx-note-intro\">Estimates show ", esc_html(label_lower),
    across, "</p>",
    "<div class=\"wx-note-cols\"><div>",
    "<p><strong>Respondents were asked:</strong>",
    if (shared) paste0(" &ldquo;", esc_html(m$intro), "&rdquo;") else "",
    "</p><ul>", bullets, "</ul></div><div>",
    "<p>", esc_html(scored), " Higher scores indicate greater ",
    esc_html(label_lower), ".", esc_html(varies), " The map colors span the ",
    "observed range of estimates, from ", lo, " to ", hi, ", rather than the ",
    "full 1-to-5 scale. This makes differences across areas easier to ",
    "see.</p>",
    about_estimates,
    "</div></div>")
}

# The Scan Sheet ---------------------------------------------------------------
# One area against all the others on every measure at once, under the map. The
# panel computes nothing: it draws the values, medians and percentiles already
# in cwa_values.json. What is authored here is the caution that makes the rows
# readable - each row is stretched to its own range, so a position is a
# standing among the areas, comparable within a row and not across rows.
is_alert_measure <- vapply(menu, function(m) isTRUE(m$alert), logical(1))

# The alert spans as one sentence, because the sheet lists every category at
# once and cannot carry the per-measure clause the notes below the map use.
# Written from the menu so a category whose coverage changes moves itself into
# or out of the exception rather than needing this prose re-edited.
alert_menu <- menu[is_alert_measure]
alert_spans <- vapply(alert_menu, function(m) m$span, character(1))
common_span <- names(sort(table(alert_spans), decreasing = TRUE))[1]
odd_alerts <- alert_menu[alert_spans != common_span]
as_range <- function(s) str_replace(s, " and ", "\u2013")

alert_span_sentence <- if (length(odd_alerts) == 0) {
  paste0("Alert counts cover ", as_range(common_span), ".")
} else {
  odd_labels <- vapply(odd_alerts, function(m) {
    str_to_lower(str_remove(m$label, " alert days$"))
  }, character(1))
  paste0(
    "Alert counts cover ", as_range(common_span), ", except ",
    paste(odd_labels, collapse = ", "), ", which covers ",
    as_range(odd_alerts[[1]]$span),
    " because the product did not exist before then."
  )
}

# "the other 115" is counted, one fewer than the areas on the map.
scan_lede <- paste0(
  "<p>Each row shows where this community falls relative to the other ",
  measures_meta$areas - 1, " forecast offices. Because measures use ",
  "different scales and ranges, compare the community&rsquo;s relative ",
  "position within each row, not the absolute position of dots across ",
  "different rows.</p>")

# The sheet's own note: how the estimates are made, how the alert counts
# differ from them, and where the survey data are.
scan_note <- paste0(
  "<p>Results are from the Extreme Weather and Society Survey at the ",
  "<a href=\"https://ippra.net\">University of Oklahoma\u2019s Institute for ",
  "Public Policy Research and Analysis</a>. Community estimates come from ",
  "multilevel models fitted to survey responses and reweighted to the adult ",
  "population of each county, then combined to the National Weather Service ",
  "County Warning Area. This allows us to estimate each measure for U.S. ",
  "adults across all ", measures_meta$areas, " areas, including places ",
  "where relatively few people were surveyed.</p>",
  "<p>Alert counts are observed data, not survey estimates. They represent ",
  "the number of days on which the National Weather Service issued at least ",
  "one VTEC-enabled watch, warning, or advisory of that type, using data from ",
  "the ", MESONET_LINK, " archive. These counts are also used as exposure ",
  "measures in the models. ", alert_span_sentence, "</p>",
  "<p>Survey data: <a href=\"https://dataverse.harvard.edu/dataverse/",
  "wxsurvey\">Extreme Weather and Society Survey Dataverse</a></p>")

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

# The other direction: a pairing naming an alert layer the menu does not
# offer leaves the second map with nothing to draw, and the front end has
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
# Prompts are fixed; answer keys and reveal numbers are read off the question
# files' distributions, so a data refresh recomputes them and they always
# agree with what the explorer shows. Guards halt the build when the fixed
# prose stops being true of the data, naming the sentence to re-write.
q_data <- function(id) {
  path <- paste0(data_dir, "q/", id, ".json")
  if (!file.exists(path))
    stop("Quiz needs question ", id, " — not in ", data_dir)
  read_json(path, simplifyVector = FALSE)
}
split_rows <- function(q, split, arm = NULL) {
  # A split-sample question nests its splits under the version, and is read
  # only for a version named here: a quiz answer drawn from one arm is a claim
  # about the people who saw that version, so the prompt has to show that
  # version's wording. Without one it is refused rather than pooled.
  if (length(q$arms) > 0) {
    if (is.null(arm)) {
      stop("Quiz question ", q$id, " is split-sampled - name the version ",
           "its prompt shows.")
    }
    if (is.null(q$splits[[arm]])) {
      stop("Quiz question ", q$id, " has no version ", arm, ".")
    }
    q <- list(splits = q$splits[[arm]])
  } else if (!is.null(arm)) {
    stop("Quiz question ", q$id, " is not split-sampled, so has no ", arm, ".")
  }
  rows <- q$splits[[split]]
  if (is.null(rows)) stop("Quiz needs split ", split, " on ", q$id, ".")
  rows
}
# Share answering within codes, per group. Carried at full precision: the
# guards below measure how far apart two groups really are, and a share
# rounded first can gain or lose a point on the way, which is enough to walk
# an answer past a margin it does not clear.
share_of <- function(id, codes, split = "All", arm = NULL) {
  rows <- split_rows(q_data(id), split, arm)
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
# the runner-up by more than the confidence intervals the explorer puts on the
# same numbers - those run about 1.6 points on a share - or the answer is a coin
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
# Bars run highest first where the categories have no order of their own
# (sources, hazards, regions); an ordered split keeps its order, since the
# answer there is a trend along it.
cmp_chart <- function(values, y_label, fmt = function(v) v,
                      highest_first = TRUE) {
  if (highest_first) values <- values[order(values, decreasing = TRUE)]
  list(
    rows = unname(Map(
      function(nm, v) list(group = "All", category = nm, value = v,
                           label = fmt(v)),
      names(values), values)),
    y_label = y_label)
}

# What each reveal chart highlights: the response codes the answer adds up,
# the group it names, or, on a comparison chart, the bar that wins. Codes go
# as a list so a single code stays an array in the JSON.
highlight <- function(resp = NULL, group = NULL, category = NULL) {
  compact(list(resp = if (!is.null(resp)) as.list(unname(resp)), group = group,
               category = category))
}

# The wording behind a comparison chart, which draws on several survey
# questions: the stem they share and each item, read off the question files
# so the reveal quotes what respondents actually read.
asked_of <- function(ids) {
  qs <- lapply(ids, q_data)
  stems <- unique(vapply(qs, function(q) q$question_intro %||% "", ""))
  check_prose(length(stems) == 1,
              paste0("the compared questions (", paste(ids, collapse = ", "),
                     ") no longer share one stem"))
  list(stem = stems, items = as.list(unname(vapply(qs, function(q)
    q$question_text %||% "", ""))))
}

# A follow-up's reveal chart shows the one number per group its answer rests
# on - the share giving the named responses, or the mean - rather than every
# response for every group, with the survey page's two-line note under it.
# Everything in it is read off the question file: the group values the
# answer is computed from, the counts and years, the response labels.
quoted_labels <- function(q, codes, end = TRUE) {
  labels <- vapply(codes, function(k) {
    hit <- keep(q$options, function(o) as.numeric(o$value) == k)
    if (length(hit) == 0) stop("Quiz: no label for code ", k, " on ", q$id)
    hit[[1]]$label
  }, "")
  labels <- paste0("\u201c", labels, "\u201d")
  n <- length(labels)
  # A sentence's closing period sits inside the last quotation mark.
  if (end) labels[n] <- str_replace(labels[n], "\u201d$", ".\u201d")
  if (n == 1) return(labels)
  if (n == 2) return(paste(labels[1], "or", labels[2]))
  labels[-n] <- str_replace(labels[-n], "\u201d$", ",\u201d")
  paste0(paste(labels[-n], collapse = " "), " or ", labels[n])
}
split_chart <- function(id, split, values, y_label, fmt, bars,
                        relabel = NULL) {
  q <- q_data(id)
  s <- q$summaries[[split]]
  if (is.null(s)) stop("Quiz: no summary for ", split, " on ", id)
  survey <- str_remove(q$hazard, "\\s*\\([A-Z]+\\)$")
  smallest <- relabel[s$smallest] %|% s$smallest
  smallest <- switch(split,
    AGE_GROUP = paste0("ages ", str_replace(smallest, "-", "\u2013")),
    CENSUS_REGION = paste0("the ", smallest),
    EDUC_GROUP = paste0(str_to_lower(str_sub(smallest, 1, 1)),
                        str_sub(smallest, 2)),
    smallest)
  list(
    chart = cmp_chart(values, y_label, fmt,
                      highest_first = split == "CENSUS_REGION"),
    asked = asked_of(id),
    caption = list(
      meta = paste0(format(s$n, big.mark = ","), " U.S. adults \u00b7 ",
                    survey, " Survey \u00b7 ",
                    str_replace_all(s$years, "-", "\u2013")),
      bars = paste0("Bars show the weighted ", bars, " The smallest ",
                    if (split == "survey_year") "year" else "group", ", ",
                    smallest, ", includes ",
                    format(s$smallest_n, big.mark = ","), " respondents.")))
}
# The same note under a chart that compares several questions. Each bar has
# its own count, a few apart where someone skipped an item, so the line gives
# the range rather than one count that belongs to no bar.
compare_caption <- function(ids, bars) {
  qs <- lapply(ids, q_data)
  s <- lapply(qs, function(q) q$summaries[["All"]])
  surveys <- unique(vapply(qs, function(q)
    str_remove(q$hazard, "\\s*\\([A-Z]+\\)$"), ""))
  years <- unique(vapply(s, function(x) x$years, ""))
  check_prose(length(surveys) == 1 && length(years) == 1,
              paste0("the compared questions (", paste(ids, collapse = ", "),
                     ") no longer share one survey and span of years"))
  n <- range(vapply(s, function(x) x$n, double(1)))
  n <- unique(format(n, big.mark = ","))
  list(meta = paste0(paste(n, collapse = "\u2013"), " U.S. adults \u00b7 ",
                     surveys, " Survey \u00b7 ",
                     str_replace_all(years, "-", "\u2013")),
       bars = paste("Bars show the weighted", bars))
}
pct_fmt <- function(v) paste0(v, "%")
mean_fmt <- function(v) sprintf("%.1f", v)
`%|%` <- function(x, y) if (length(x) == 1 && !is.na(x)) unname(x) else y

quiz <- local({
  q1_all <- share_of("WX_alert_und", c(4, 5))[["All"]]
  # Age ranges are set with an en dash wherever the quiz shows them.
  en_dash <- function(x) setNames(x, str_replace(names(x), "-", "\u2013"))
  q1_by <- share_of("WX_alert_und", c(4, 5), "AGE_GROUP") |> en_dash()
  q1_opts <- c("About 40%", "About 60%", "About 80%")
  q1_ans <- pct_band(q1_all, c(40, 60, 80))
  # "About 8 in 10": the miss headings that name a share in words.
  in_ten <- function(x) paste("About", round(x / 10), "in 10")
  q1_top <- gradient(q1_by, "Q1 reveal: understanding rises with age")
  # The top two age groups sit about a point apart, too close to name one
  # "most likely"; the youngest group trails the next by several points.
  q1_low <- decisive(q1_by, "Q3 follow-up least-understanding age group",
                     low = TRUE)

  # The latest survey year, read from the data so the question moves with
  # each new wave.
  latest_year <- max(names(
    q_data("WX_wx_info7")$summaries$survey_year$group_n
  ))

  # The whole battery in the latest year, so the chart shows every source
  # respondents rated; the options are the five rated highest that year.
  source_vars <- c(`Automated phone alerts` = "WX_wx_info7",
                   `Outdoor warning sirens` = "WX_wx_info8",
                   `Internet web pages` = "WX_wx_info4",
                   Television = "WX_wx_info3",
                   `Weather radio` = "WX_wx_info2",
                   `Broadcast radio` = "WX_wx_info1",
                   `Word of mouth` = "WX_wx_info6",
                   `Social media` = "WX_wx_info5")
  source_latest <- vapply(source_vars, function(v)
    share_of(v, c(4, 5), "survey_year")[[latest_year]], double(1))
  source_top <- decisive(source_latest, "Q1 most-relied source, latest year")
  source_offered <- names(sort(source_latest, decreasing = TRUE))[1:5]
  # Offered in a fixed order, not ranked, so the order gives nothing away.
  source_offered <- intersect(c("Television", "Automated phone alerts",
                                "Weather radio", "Outdoor warning sirens",
                                "Internet web pages", "Broadcast radio",
                                "Word of mouth", "Social media"),
                              source_offered)
  # Every other offered source, highest first, so no option goes unanswered.
  source_others <- source_latest[setdiff(source_offered,
                                         names(source_vars)[source_top])]
  source_others <- source_others[order(-shown_pct(source_others))]
  source_rest <- paste0(shown_pct(source_others), "% for ",
                        str_to_lower(names(source_others)))
  source_rest <- paste0(
    paste(source_rest[-length(source_rest)], collapse = ", "), ", and ",
    source_rest[length(source_rest)]
  )
  # The sample behind a single year: each item's own count that year.
  year_n <- range(vapply(source_vars, function(v)
    q_data(v)$summaries$survey_year$group_n[[latest_year]], double(1)))
  year_n <- unique(format(year_n, big.mark = ","))

  # The follow-up asks the same of the Winter Weather survey, whose channel
  # battery is asked "when winter weather threatens": a hazard people see
  # coming, where the forecast matters more than the alert. That survey asks
  # about sources (the NWS, local TV) and channels (the internet, phone
  # alerts) as two questions; the channels are the ones comparable with the
  # main question's list.
  winter_vars <- c(`Internet weather websites` = "WW_rely_int",
                   Television = "WW_rely_tv",
                   `Automated phone alerts` = "WW_rely_phone",
                   `Broadcast radio` = "WW_rely_bdrad",
                   `Word of mouth` = "WW_rely_wom",
                   `Weather radio` = "WW_rely_wxrad",
                   `Social media` = "WW_rely_soc")
  winter_year <- max(names(
    q_data("WW_rely_int")$summaries$survey_year$group_n
  ))
  winter_latest <- vapply(winter_vars, function(v)
    share_of(v, c(4, 5), "survey_year")[[winter_year]], double(1))
  winter_top <- decisive(winter_latest, "Q1 follow-up top winter channel")
  winter_offered <- c("Television", "Automated phone alerts",
                      "Internet weather websites", "Weather radio",
                      "Social media")
  check_prose(all(names(sort(winter_latest, decreasing = TRUE))[1:3] %in%
                    winter_offered),
              "Q1 follow-up no longer offers the three most-relied sources")
  winter_second <- sort(winter_latest[-winter_top], decreasing = TRUE)[1]
  winter_phone_rank <- rank(-winter_latest)[["Automated phone alerts"]]
  winter_n <- range(vapply(winter_vars, function(v)
    q_data(v)$summaries$survey_year$group_n[[winter_year]], double(1)))
  winter_n <- unique(format(winter_n, big.mark = ","))
  ordinal <- c("first", "second", "third", "fourth", "fifth", "sixth",
               "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth")
  number_words <- c("one", "two", "three", "four", "five", "six", "seven",
                    "eight", "nine", "ten", "eleven", "twelve")

  # Four format questions, two surveys, one design: a single most likely
  # value (code 1) against a range (code 2) for the same forecast.
  format_vars <- c(`Snow amount` = "WW_amount_format",
                   `Storm surge amount` = "TC_amount_format",
                   `Snow timing` = "WW_time_format",
                   `Hurricane wind timing` = "TC_time_format")
  format_qs <- lapply(format_vars, q_data)
  # The amount items were split on the amount shown, 4 or 12 inches; the
  # quiz quotes and scores the 12-inch version, the larger storm.
  format_arm <- "12"
  arm_of <- function(q) if (length(q$arms) > 0) format_arm else NULL
  summary_of <- function(q) {
    if (length(q$arms) > 0) q$summaries[[format_arm]]$All else q$summaries$All
  }
  check_prose(all(vapply(format_qs, function(q)
    str_detect(q$options[[1]]$label, "most likely") &&
      str_detect(q$options[[2]]$label, "between"), logical(1))),
    "a format question's codes no longer mean single value / range")
  format_range <- vapply(format_vars, function(v)
    share_of(v, 2, arm = arm_of(q_data(v)))[["All"]], double(1))
  # "Most prefer a range" has to hold in every example, clearly enough that
  # "no preference" is not the better answer.
  check_prose(all(format_range >= 55),
              "a format example no longer shows a clear preference for ranges")
  format_n <- range(vapply(format_qs, function(q) summary_of(q)$n, 1))
  format_n <- unique(format(format_n, big.mark = ","))
  format_years <- unlist(str_extract_all(
    vapply(format_qs, function(q) summary_of(q)$years, ""), "\\d{4}"
  ))
  format_years <- unique(range(format_years))
  # What respondents actually compared. Every option opens with the same
  # sentence, which the table states once; the amount items carry the
  # instrument's randomization note in place of the number, which is filled
  # with the version the quiz scores, and read whole for the note below.
  format_lead <- "There is still uncertainty, but the forecast suggests that "
  format_opts <- lapply(format_qs, function(q)
    vapply(q$options, function(o) o$label, ""))
  check_prose(all(vapply(format_opts, function(o)
    all(str_starts(o, fixed(format_lead))), logical(1))),
    "a format question's options no longer share their opening sentence")
  arm <- str_match(
    format_opts[["Snow amount"]][2],
    paste0("(\\d+) and (\\d+) if amount_format_rand1 = (\\d+), or ",
           "(\\d+) and (\\d+) if amount_format_rand1 = (\\d+)")
  )
  check_prose(!is.na(arm[1]) && arm[7] == format_arm,
              "the snow amount item's randomization note no longer parses")
  fill_arm <- function(x) {
    x |>
      str_replace("\\[amount_format_rand1:[^\\]]*\\]", arm[7]) |>
      str_replace("\\[amount_format_rand2:[^\\]]*\\]",
                  paste(arm[5], "and", arm[6]))
  }
  format_filled <- lapply(format_opts, fill_arm)
  check_prose(!any(str_detect(unlist(format_filled), fixed("["))),
              "a format option still carries a randomization note")
  format_table <- list(
    lead = paste0("Each option began \u201c", str_trim(format_lead),
                  "\u2026\u201d"),
    head = list("Example", "Single most likely value", "Range"),
    rows = unname(Map(function(nm, o) list(
      nm, str_remove(str_remove(o[1], fixed(format_lead)), "\\.$"),
      str_remove(str_remove(o[2], fixed(format_lead)), "\\.$")),
      names(format_filled), format_filled))
  )
  format_arm_note <- paste0(
    "Amounts were randomized: respondents saw either ", arm[4],
    " inches against ", arm[2], "\u2013", arm[3], " or ", arm[7],
    " against ", arm[5], "\u2013", arm[6], ". The two amount examples ",
    "show those who saw ", arm[7], " inches.")
  format_surveys <- unique(vapply(format_qs, function(q)
    str_remove(q$hazard, "\\s*\\([A-Z]+\\)$"), ""))

  # The follow-up: two 2024 snowstorm scenarios, each offering five formats.
  # Code 1 is the widest range at 80%; codes 2 and 4 are a middle range at
  # 50%, codes 3 and 5 a narrow one at 30% (4 and 5 add the full span in a
  # second sentence). The question asks which single format was picked
  # most, so code 1 has to beat every other single code in both scenarios.
  spread_vars <- c(larger = "WW_range10_nozero", smaller = "WW_range10_zero")
  spread_qs <- lapply(spread_vars, q_data)
  check_prose(all(vapply(spread_qs, function(q) {
    labels <- vapply(q$options, function(o) o$label, "")
    length(labels) == 5 && str_detect(labels[1], "80% chance") &&
      all(str_detect(labels[c(2, 4)], "50% chance")) &&
      all(str_detect(labels[c(3, 5)], "30% chance"))
  }, logical(1))), "the 2024 range formats no longer carry 80/50/30%")
  spread_shares <- lapply(spread_vars, function(v)
    vapply(1:5, function(k) share_of(v, k)[["All"]], double(1)))
  for (sc in names(spread_shares)) {
    decisive(setNames(spread_shares[[sc]], 1:5),
             paste("Q6 follow-up, widest format in the", sc, "scenario"))
    check_prose(which.max(spread_shares[[sc]]) == 1,
                paste("Q6 follow-up: the widest format no longer leads the",
                      sc, "scenario"))
  }
  spread_year <- unique(vapply(spread_qs, function(q)
    q$summaries$All$years, ""))
  check_prose(length(spread_year) == 1,
              "the two 2024 range scenarios no longer share one year")
  spread_range <- vapply(spread_qs, function(q)
    str_replace(str_extract(q$options[[1]]$label, "\\d+-\\d+"), "-",
                "\u2013"), "")
  # Every option's full text, ranges set with an en dash.
  spread_text <- lapply(spread_qs, function(q)
    vapply(q$options, function(o)
      str_replace_all(o$label, "(\\d)-(\\d)", "\\1\u2013\\2"), ""))
  # The three plain formats, labelled with the numbers respondents read.
  spread_plain <- lapply(spread_qs, function(q)
    vapply(q$options[1:3], function(o) {
      paste0(str_replace(str_extract(o$label, "\\d+-\\d+"), "-", "\u2013"),
             " inches, ", str_extract(o$label, "\\d+% chance"))
    }, ""))

  # The education groups spelled out, for the options and for the reveal,
  # which names the winning group as a phrase.
  educ_labels <- c(`HS or less` = "High school or less",
                   `Some college / 2-yr degree` =
                     "Some college / 2-year degree",
                   `4-yr / post-graduate degree` =
                     "4-year / postgraduate degree")
  educ_prose <- c(`HS or less` = "a high school education or less",
                  `Some college / 2-yr degree` =
                    "some college or a 2-year degree",
                  `4-yr / post-graduate degree` =
                    "a 4-year or postgraduate degree")

  wep_shares <- vapply(1:3, function(k)
    share_of("TC_wep_rec", k)[["All"]], double(1))
  q3_opts <- c("Numbers", "Words", "A combination of both")
  wep_top <- decisive(setNames(wep_shares, q3_opts), "Q3 numbers/words/both")
  wep_phrase <- c("numbers alone", "words alone",
                  "a combination of numbers and words")
  wep_others <- order(wep_shares[-wep_top], decreasing = TRUE)
  wep_others <- setdiff(1:3, wep_top)[wep_others]
  check_prose(wep_top == 3,
              "Q7's miss heading says most prefer numbers and words together")

  # Top risk by region, asked as a series: the same six hazards offered for
  # each census region in turn. Where hazards sit within five points of a
  # region's top, the data cannot rank them, so each of them counts as right
  # and the reveal says they are close.
  region_vars <- c(`Extreme heat` = "WX_risk_heat",
                   `Extreme cold` = "WX_risk_cold", Snow = "WX_risk_snow",
                   Drought = "WX_risk_drought", Wildfires = "WX_risk_fire",
                   Tornadoes = "WX_risk_tor")
  # The rest of the battery asked in every year, to check that no hazard
  # the options leave out belongs among a region's top answers.
  unoffered_vars <- c(`High winds` = "WX_risk_wind",
                      `Excessive rain` = "WX_risk_rain",
                      Floods = "WX_risk_flood", Hurricanes = "WX_risk_hur")
  regions <- c("Northeast", "Midwest", "South", "West")
  close_margin <- 5
  region_shares <- function(vars) vapply(vars, function(v)
    share_of(v, c(4, 5), "CENSUS_REGION")[regions], double(length(regions)))
  risk_offered <- region_shares(region_vars)
  risk_unoffered <- region_shares(unoffered_vars)
  rownames(risk_offered) <- rownames(risk_unoffered) <- regions
  risk_years <- str_replace_all(
    q_data("WX_risk_heat")$summaries$All$years, "-", "\u2013"
  )
  risk_region_part <- function(r, first) {
    v <- risk_offered[r, ]
    top <- max(v)
    check_prose(max(risk_unoffered[r, ]) < top - close_margin,
                paste("Q10: a hazard the options leave out is among the",
                      "top answers in the", r))
    # A hazard within a point of the cut could fall either side of it.
    check_prose(all(v == top | abs(v - (top - close_margin)) >= 1),
                paste("Q10: a hazard in the", r, "sits on the cut between",
                      "right and wrong"))
    accepted <- which(v >= top - close_margin)
    accepted <- accepted[order(-v[accepted])]
    # The runner-up comes from the whole battery, offered or not, so the
    # reveal never skips a hazard that sits between.
    ordered <- sort(c(v, risk_unoffered[r, ]), decreasing = TRUE)
    names_lc <- str_to_lower(names(v))
    listed <- paste0(names_lc[accepted], " (", shown_pct(v[accepted]), "%)")
    listed <- if (length(listed) == 2) paste(listed, collapse = " and ") else
      paste0(paste(listed[-length(listed)], collapse = ", "), ", and ",
             listed[length(listed)])
    n <- range(vapply(region_vars, function(x)
      q_data(x)$summaries$CENSUS_REGION$group_n[[r]], double(1)))
    list(
      prompt = if (first) paste0("Which hazard do adults in the ", r,
                                 " most often rate as a high or extreme ",
                                 "risk where they live?")
               else paste0("And in the ", r, "?"),
      tag = r,
      lead = "Next Region \u2192",
      options = names(region_vars),
      answer = which.max(v) - 1L,
      accept = as.list(unname(accepted) - 1L),
      reveal = if (length(accepted) == 1)
        paste0(shown_pct(top), "% of adults in the ", r, " rate ",
               names_lc[which.max(v)], " as a high or extreme risk, ahead ",
               "of ", str_to_lower(names(ordered)[2]), " at ",
               shown_pct(ordered[[2]]), "%.")
      else paste0("Adults in the ", r, " rate ", listed, " as their top ",
                  "risks, close enough that ",
                  if (length(accepted) == 2) "either" else "any of them",
                  " counts."),
      result = str_to_lower(names(v)[which.max(v)]),
      miss = if (length(accepted) == 1)
        paste(names(v)[which.max(v)], "is the top risk in the", r)
      else paste0(str_to_sentence(listed |> str_remove_all(" \\(\\d+%\\)")),
                  " are nearly tied in the ", r),
      chart = cmp_chart(shown_pct(v), "High or extreme risk (%)", pct_fmt),
      asked = asked_of(region_vars),
      caption = list(
        meta = paste0(paste(unique(format(n, big.mark = ",")),
                            collapse = "\u2013"),
                      " U.S. adults in the ", r,
                      " \u00b7 Severe Weather Survey \u00b7 ", risk_years),
        bars = paste0("Bars show the weighted percentage of adults in the ",
                      r, " rating each hazard ",
                      quoted_labels(q_data("WX_risk_heat"), c(4, 5)),
                      " Hazards within ", close_margin, " points of the ",
                      "top count as correct answers.")),
      explore = list(href = "#survey",
                     params = list(q = region_vars[[which.max(v)]],
                                   grouping = "CENSUS_REGION")),
      highlight = highlight(category = names(v)[accepted])
    )
  }
  risk_parts <- Map(risk_region_part, regions, seq_along(regions) == 1)

  q5_all <- share_of("WX_rec_all", c(4, 5))[["All"]]
  q5_opts <- c("About 30%", "About 50%", "About 70%")
  q5_ans <- pct_band(q5_all, c(30, 50, 70))
  check_prose(abs(q5_all - 50) <= 5,
              "Q2's miss heading says about half receive every warning")
  # Asked by region rather than by community type: urban, suburban and rural
  # sit within three points of each other on this item, which is inside the
  # intervals the reveal chart draws, so an answer by type would be one the
  # reader could not see. Tornado warnings are rare in the West, and that
  # shows here.
  q5_by <- share_of("WX_rec_all", c(4, 5), "CENSUS_REGION")
  q5_low <- decisive(q5_by, "Q5 lowest-reception region", low = TRUE)

  trust_vars <- c(`National Weather Service` = "WX_nws_trust",
                  `Local TV stations` = "WX_lotv_trust",
                  `National TV stations` = "WX_natv_trust",
                  `Emergency managers` = "WX_em_trust",
                  `Family and friends` = "WX_fam_trust")
  trust_shares <- vapply(trust_vars, function(v)
    share_of(v, c(4, 5))[["All"]], double(1))
  trust_top <- decisive(trust_shares, "Q6 most-trusted source")
  # Each source as it reads mid-sentence.
  trust_prose <- c(`National Weather Service` = "the National Weather Service",
                   `Local TV stations` = "local TV stations",
                   `National TV stations` = "national TV stations",
                   `Emergency managers` = "emergency managers",
                   `Family and friends` = "family and friends")
  # The other sources, highest first, for the reveal's comparison.
  trust_others <- sort(trust_shares[-trust_top], decreasing = TRUE)
  trust_rest <- paste0(shown_pct(trust_others), "% for ",
                       trust_prose[names(trust_others)])
  trust_rest <- paste0(
    paste(trust_rest[-length(trust_rest)], collapse = ", "), ", and ",
    trust_rest[length(trust_rest)]
  )
  trust_name <- trust_prose[[names(trust_vars)[trust_top]]]
  q6_by <- share_of("WX_nws_trust", c(4, 5), "AGE_GROUP") |> en_dash()
  q6_top <- gradient(q6_by, "Q6 reveal: NWS trust rises with age")

  check_prose(str_detect(q_data("TC_resp_always")$hazard, "\\(TC\\)"),
              "Q12's prompt names hurricanes; the item left the TC survey")
  q7_all <- share_of("TC_resp_always", c(4, 5))[["All"]]
  q7_opts <- c("About 20%", "About 40%", "About 60%", "About 80%")
  q7_ans <- pct_band(q7_all, c(20, 40, 60, 80))
  # Weather salience is the mean of how closely people follow the weather
  # and how much they plan around it (09_statistics.R); the options name the
  # groups by it, since "High" alone does not say high what.
  salience_labels <- c(Low = "Low weather salience",
                       Moderate = "Moderate weather salience",
                       High = "High weather salience")
  q7_by <- share_of("TC_resp_always", c(4, 5), "SALIENCE_GROUP")
  check_prose(setequal(names(q7_by), names(salience_labels)),
              "Q7's salience groups no longer match their labels")
  q7_top <- gradient(q7_by, "Q7 reveal: following advice rises with salience")
  check_prose(q7_top == length(q7_by),
              "Q12's miss heading says agreement rises with salience")
  q7_by <- setNames(q7_by, salience_labels[names(q7_by)])

  # Each half of the Flooding sample read one NWS definition - a flood
  # warning or a flash flood warning - and named it (a random split, so no
  # one saw both). Code 1 is FLOOD warning, code 2 FLASH FLOOD warning.
  fw_q <- q_data("FL_flood_warn")
  q8_q <- q_data("FL_flash_warn")
  check_prose(all(vapply(list(fw_q, q8_q), function(q)
    q$options[[1]]$label == "FLOOD warning" &&
      q$options[[2]]$label == "FLASH FLOOD warning", logical(1))),
    "the flood warning items' codes no longer mean flood / flash flood")
  fw_all <- share_of("FL_flood_warn", 1)[["All"]]
  fw_opts <- c("About 30%", "About 50%", "About 70%", "Nearly 100%")
  fw_ans <- pct_band(fw_all, c(30, 50, 70, 100))
  # "About 6 in 10" would sit oddly beside an answer of "About 70%", so the
  # miss heading says two-thirds, and has to stay near it.
  check_prose(abs(fw_all - 200 / 3) <= 4,
              "Q5's miss heading says about two-thirds identified it")
  q8_all <- share_of("FL_flash_warn", 2)[["All"]]
  q8_flood <- share_of("FL_flash_warn", 1)[["All"]]
  q8_opts <- c("About 30%", "About 40%", "About 60%", "About 80%")
  q8_ans <- pct_band(q8_all, c(30, 40, 60, 80))


  # Code 1 is the answer that matches the product: a tornado warning means
  # a tornado is imminent, so the time left is under an hour.
  q10_q <- q_data("WX_warn_time")
  check_prose(q10_q$options[[1]]$label == "less than 1 hour" &&
                q10_q$options[[2]]$label == "1 to 24 hours",
              paste("WX_warn_time's first two codes no longer mean",
                    "< 1 and 1-24 hours"))
  q10_all <- share_of("WX_warn_time", 1)[["All"]]
  q10_day <- share_of("WX_warn_time", 2)[["All"]]
  q10_opts <- c("About 35%", "About 55%", "About 75%", "About 95%")
  q10_ans <- pct_band(q10_all, c(35, 55, 75, 95))
  check_prose(abs(q10_all - 50) <= 7,
              "Q4's miss heading says only about half know the answer")
  q10_by <- share_of("WX_warn_time", 1, "CENSUS_REGION")
  q10_top <- decisive(q10_by, "Q10 region most often right on warning time")
  # Every region showing the lowest share, so a tie reads as one.
  q10_lowest <- names(q10_by)[shown_pct(q10_by) == shown_pct(min(q10_by))]
  q10_lowest <- paste(q10_lowest, collapse = " and the ")

  # "Your community", closing the Risk section: the reader picks a forecast
  # office and guesses its top-rated hazard, scored against the modeled
  # perceived-risk estimates Explore Communities maps (cwa_values.json); the
  # page only orders them. Hazards within `tie` of the top all count as
  # right: 48 of the 116 areas have their top two that close on the 1-5
  # scale.
  risk_menu <- keep(menu, function(m) str_starts(m$measure, "RISK_"))
  check_prose(length(risk_menu) >= 10,
              "the community look-up no longer finds the risk measures")
  risk_noun <- c(Tornado = "Tornadoes", Hurricane = "Hurricanes",
                 Flood = "Flooding", Wildfire = "Wildfires")
  community_measures <- lapply(risk_menu, function(m) {
    short <- str_remove(m$label, " risk perceptions$")
    list(code = m$measure,
         label = if (short %in% names(risk_noun)) risk_noun[[short]]
                 else short)
  })
  risk_scale <- vapply(q_data("WX_risk_heat")$options, function(o) o$label,
                       "")

  # What people did at their most recent tornado warning. Asked only of those
  # who remembered one received at home, work, school or a business. The
  # three sheltering responses are one action for the quiz's purpose, so
  # they are charted together; codes are checked before they are combined.
  act_q <- q_data("WX_last_act")
  act_labels <- vapply(act_q$options, function(o) o$label, "")
  check_prose(str_detect(act_labels[1], "^Nothing") &&
                str_detect(act_labels[2], "^Monitored") &&
                all(str_detect(act_labels[3:5], "^Moved to")) &&
                str_detect(act_labels[6], "^Left the building"),
              "WX_last_act's codes no longer mean nothing/monitor/shelter/left")
  act_shares <- c(
    `Monitored, but did not shelter` = share_of("WX_last_act", 1)[["All"]],
    `Moved to shelter` = share_of("WX_last_act", 2:4)[["All"]],
    `Nothing; continued activities` = share_of("WX_last_act", 0)[["All"]],
    `Left the area` = share_of("WX_last_act", 5)[["All"]],
    `Something else or don't recall` = share_of("WX_last_act", 6:7)[["All"]]
  )
  act_top <- decisive(act_shares, "Q13 most common action at last warning")
  check_prose(act_top == 1, "Q13's answer is no longer monitoring")
  act_by <- share_of("WX_last_act", 1, "AGE_GROUP") |> en_dash()
  act_by_top <- gradient(act_by, "Q13 follow-up: monitoring rises with age")
  check_prose(act_by_top == length(act_by),
              "Q13's follow-up heading says monitoring rises with age")

  # The 2017 trade-off questions. Each one's stem explains the trade-off
  # before asking, and the first two codes lean toward the side named.
  fa_q <- q_data("WX_mi_fa_should")
  lt_q <- q_data("WX_leadtime_should")
  check_prose(str_detect(fa_q$options[[1]]$label, "tornado will occur") &&
                str_detect(fa_q$options[[2]]$label, "tornado will occur") &&
                str_detect(lt_q$options[[1]]$label, "lead time") &&
                str_detect(lt_q$options[[2]]$label, "lead time"),
              "the trade-off items' first two codes no longer mean the same")
  fa_warn <- share_of("WX_mi_fa_should", c(1, 2))[["All"]]
  fa_year <- fa_q$summaries$All$years
  # The question offers "most lean one way", "most lean the other" and
  # "about evenly divided", and one rule decides between them: a side is
  # "most" when it is 5 or more points past half. A share within a point
  # and a half of that line stops the build, since either answer would then
  # be arguable.
  lean_answer <- function(share, what) {
    check_prose(abs(abs(share - 50) - 5) >= 1.5,
                paste0(what, " sits on the line between a lean and a split"))
    if (abs(share - 50) < 5) 2L else if (share > 50) 0L else 1L
  }
  fa_opts <- c("Most lean toward avoiding missed tornadoes",
               "Most lean toward avoiding false alarms",
               "Views are about evenly divided")
  fa_ans <- lean_answer(fa_warn, "Q8 false alarms")
  lt_lead <- share_of("WX_leadtime_should", c(1, 2))[["All"]]
  check_prose(lt_q$summaries$All$years == fa_year,
              "the two trade-off questions no longer come from one wave")
  # The lead-time split (about 54/46) sits on that line, so the follow-up
  # offers only the two sides, and the reveal gives both shares so the
  # closeness shows. It still needs a side past half by a margin.
  lt_opts <- c("More lean toward lead time",
               "More lean toward precision and accuracy")
  check_prose(abs(lt_lead - 50) >= 2,
              "Q8 lead time is too close to half to name a side")
  lt_ans <- if (lt_lead > 50) 0L else 1L

  questions <- list(
    list(
      part1 = list(
        prompt = paste0("About what percentage of U.S. adults say ",
                        "they understand the difference between a tornado ",
                        "WATCH and a tornado WARNING?"),
        options = q1_opts, answer = q1_ans,
        reveal = paste0(shown_pct(q1_all), "% say they probably or ",
                        "definitely ",
                        "understand the difference."),
        result = paste0(shown_pct(q1_all), "%"),
        miss = paste(in_ten(q1_all), "say they understand the difference"),
        chart_note = paste("Highlighted bars indicate the responses used to",
                           "calculate the quiz answer."),
        highlight = highlight(resp = c(4, 5))),
      part2 = list(
        prompt = paste0("Which age group is least likely to say they ",
                        "understand the difference between watches and ",
                        "warnings?"),
        options = names(q1_by), answer = q1_low - 1L,
        reveal = paste0(shown_pct(q1_by[[q1_low]]), "% of adults ages ",
                        names(q1_by)[q1_low], " say they probably or ",
                        "definitely understand the difference, compared ",
                        "with ", shown_pct(max(q1_by)), "% of adults ",
                        names(q1_by)[which.max(q1_by)], "."),
        result = names(q1_by)[q1_low],
        miss = paste("Adults ages", names(q1_by)[q1_low], "report the",
                     "lowest understanding"),
        highlight = highlight(category = names(q1_by)[q1_low])) |>
        c(split_chart("WX_alert_und", "AGE_GROUP", shown_pct(q1_by),
          "Probably or definitely yes (%)", pct_fmt,
          paste("percentage in each age group reporting",
                quoted_labels(q_data("WX_alert_und"), c(4, 5))))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_alert_und",
                                   grouping = "AGE_GROUP"))),
    list(
      part1 = list(
        prompt = paste0("Which source did U.S. adults rely on most for ",
                        "severe weather information in ", latest_year, "?"),
        options = source_offered,
        answer = match(names(source_vars)[source_top], source_offered) - 1L,
        reveal = paste0(shown_pct(source_latest[[source_top]]), "% of U.S. ",
                        "adults relied ",
                        "on ", str_to_lower(names(source_vars)[source_top]),
                        " much or a great deal in ", latest_year,
                        ", compared with ", source_rest, "."),
        chart = cmp_chart(shown_pct(source_latest),
                          "Much or a great deal (%)", pct_fmt),
        asked = asked_of(source_vars),
        caption = list(
          meta = paste0(paste(year_n, collapse = "\u2013"),
                        " U.S. adults \u00b7 Severe Weather Survey \u00b7 ",
                        latest_year),
          bars = paste0("Bars show the weighted percentage reporting ",
                        quoted_labels(q_data("WX_wx_info7"), c(4, 5),
                                      end = FALSE),
                        " for each source.")),
        result = str_to_lower(names(source_vars)[source_top]),
        miss = paste(names(source_vars)[source_top], "have the highest",
                     "reported reliance"),
        grouping = "survey_year",
        highlight = highlight(category = names(source_vars)[source_top])),
      part2 = list(
        setup = "Does that change for winter weather?",
        prompt = paste0("Which channel did U.S. adults rely on most when ",
                        "winter weather threatened in ", winter_year, "?"),
        options = winter_offered,
        answer = match(names(winter_vars)[winter_top], winter_offered) - 1L,
        reveal = paste0(shown_pct(winter_latest[[winter_top]]), "% relied ",
                        "on ", str_to_lower(names(winter_vars)[winter_top]),
                        " very much or extensively when winter weather ",
                        "threatened, compared with ",
                        shown_pct(winter_second), "% for ",
                        str_to_lower(names(winter_second)), ". Automated ",
                        "phone alerts ranked ",
                        ordinal[winter_phone_rank], ", at ",
                        shown_pct(winter_latest[["Automated phone alerts"]]),
                        "%."),
        chart = cmp_chart(shown_pct(winter_latest),
                          "Very much or extensively (%)", pct_fmt),
        asked = asked_of(winter_vars),
        caption = list(
          meta = paste0(paste(winter_n, collapse = "\u2013"),
                        " U.S. adults \u00b7 Winter Weather Survey \u00b7 ",
                        winter_year),
          bars = paste0("Bars show the weighted percentage reporting ",
                        quoted_labels(q_data("WW_rely_int"), c(4, 5),
                                      end = FALSE),
                        " for each channel.")),
        result = str_to_lower(names(winter_vars)[winter_top]),
        miss = paste(names(winter_vars)[winter_top], "have the highest",
                     "reported reliance"),
        # This part charts another survey, so its explorer link does too.
        explore = list(href = "#survey",
                       params = list(q = "WW_rely_int",
                                     grouping = "survey_year")),
        highlight = highlight(category = names(winter_vars)[winter_top])),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_wx_info7",
                                   grouping = "survey_year"))),
    list(
      part1 = list(
        prompt = paste0("When getting information from forecasters, what do ",
                        "most people prefer: numbers, words, or both?"),
        options = q3_opts, answer = wep_top - 1L,
        reveal = paste0(shown_pct(wep_shares[wep_top]), "% prefer ",
                        wep_phrase[wep_top], ", compared with ",
                        shown_pct(wep_shares[wep_others[1]]),
                        "% who prefer ", wep_phrase[wep_others[1]], " and ",
                        shown_pct(wep_shares[wep_others[2]]),
                        "% who prefer ", wep_phrase[wep_others[2]], "."),
        result = q3_opts[wep_top],
        miss = "Most people prefer numbers and words together",
        chart_note = paste("The highlighted bar indicates the most preferred",
                           "format. Percentages may not sum to 100 because",
                           "of rounding."),
        highlight = highlight(resp = wep_top)),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "TC_wep_rec",
                                   grouping = "EDUC_GROUP"))),
    list(
      part1 = list(
        setup = paste0("Respondents saw two versions of the same forecast ",
                       "and picked the one they preferred. For example:"),
        quotes = list(
          list(label = "A", text = format_filled[["Snow amount"]][1]),
          list(label = "B", text = format_filled[["Snow amount"]][2])),
        prompt = paste0("When a forecast is uncertain, which format do most ",
                        "U.S. adults prefer?"),
        options = c("A single most likely value",
                    "A range of possible values",
                    "No preference between the two"),
        answer = 1L,
        reveal = paste0("Across ", number_words[length(format_vars)],
                        " forecast examples, ",
                        shown_pct(min(format_range)), "\u2013",
                        shown_pct(max(format_range)), "% of U.S. adults ",
                        "preferred a range of possible values rather than a ",
                        "single most likely value."),
        chart = cmp_chart(shown_pct(format_range), "Prefer a range (%)",
                          pct_fmt),
        asked = c(asked_of(format_vars), list(table = format_table)),
        caption = list(
          meta = paste0(paste(format_n, collapse = "\u2013"),
                        " U.S. adults \u00b7 ",
                        paste(format_surveys, collapse = " and "),
                        " Surveys \u00b7 ",
                        paste(format_years, collapse = "\u2013")),
          bars = paste("Bars show the weighted percentage preferring a",
                       "range rather than a single most likely value.",
                       "Respondents chose between the two formats; the",
                       "survey did not offer \u201cNo preference.\u201d",
                       format_arm_note)),
        result = "a range of possible values",
        miss = "Most people prefer a range"),
      part2 = list(
        # The three plain formats the options name, quoted as respondents
        # read them (the survey writes ranges with a hyphen).
        setup = paste0("In an experiment, respondents saw several forecasts ",
                       "for the same snowstorm and picked the one they ",
                       "preferred. Three of them:"),
        quotes = unname(Map(function(k, lab) list(label = lab,
          text = spread_text[["larger"]][k]), 1:3, c("A", "B", "C"))),
        prompt = "Which one did the most people prefer?",
        options = c("A narrow range, even if confidence is low",
                    "A middle-sized range with moderate confidence",
                    "A wider range with higher confidence"),
        answer = 2L,
        reveal = paste0("The most popular option was the widest, ",
                        "highest-confidence range. For the larger snowfall ",
                        "scenario, ",
                        shown_pct(spread_shares$larger[1]), "% preferred a ",
                        spread_range[["larger"]], " inch range with an 80% ",
                        "chance that snowfall would fall within it. For the ",
                        "smaller scenario, ",
                        shown_pct(spread_shares$smaller[1]), "% preferred a ",
                        spread_range[["smaller"]], " inch range with an 80% ",
                        "chance."),
        result = "a wider range with higher confidence",
        miss = paste("The wider, higher-confidence range was the single",
                     "most popular format"),
        # The three formats the options name, from the larger scenario; the
        # two that added the full span to the middle and narrow ranges are
        # reported in the note rather than merged into a size they share.
        chart = cmp_chart(
          setNames(shown_pct(spread_shares$larger[1:3]),
                   spread_plain[["larger"]]),
          "Chose this format (%)", pct_fmt, highest_first = FALSE),
        asked = c(asked_of(spread_vars[["larger"]]), list(table = list(
          lead = paste("All five options offered in the larger snowfall",
                       "scenario, with the share choosing each:"),
          head = list("", "Option", "Chose it"),
          rows = unname(Map(function(lab, txt, v)
            list(lab, txt, paste0(shown_pct(v), "%")),
            LETTERS[1:5], spread_text[["larger"]],
            spread_shares$larger))))),
        caption = list(
          meta = paste0(format(spread_qs$larger$summaries$All$n,
                               big.mark = ","),
                        " U.S. adults \u00b7 Winter Weather Survey \u00b7 ",
                        spread_year),
          bars = paste0("Bars show the weighted percentage selecting each ",
                        "format in the larger snowfall scenario. Two other ",
                        "formats, the middle and narrow ranges with the ",
                        "full span noted, drew ",
                        shown_pct(spread_shares$larger[4]), "% and ",
                        shown_pct(spread_shares$larger[5]), "%. The ",
                        "highlighted bar indicates the most preferred ",
                        "format.")),
        explore = list(href = "#survey",
                       params = list(q = "WW_range10_nozero",
                                     grouping = "All")),
        highlight = highlight(category = spread_plain[["larger"]][1])),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WW_amount_format",
                                   grouping = "All", arm = format_arm))),
    list(
      part1 = risk_parts[[1]],
      part2 = risk_parts[[2]],
      more = unname(risk_parts[3:4]),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_risk_heat",
                                   grouping = "CENSUS_REGION"))),
    list(
      part1 = list(
        prompt = paste0("About what percentage of U.S. adults agree that ",
                        "they receive all tornado warnings issued for their ",
                        "area?"),
        options = q5_opts, answer = q5_ans,
        reveal = paste0(shown_pct(q5_all), "% agree that they receive all ",
                        "tornado warnings issued for their area."),
        result = paste0(shown_pct(q5_all), "%"),
        miss = "About half say they receive every tornado warning",
        chart_note = paste("Highlighted bars indicate the responses used to",
                           "calculate the quiz answer."),
        highlight = highlight(resp = c(4, 5))),
      part2 = list(
        prompt = paste0("Which census region is least likely to say they ",
                        "receive all tornado warnings?"),
        options = names(q5_by), answer = q5_low - 1L,
        reveal = paste0(shown_pct(q5_by[[q5_low]]), "% of adults in the ",
                        names(q5_by)[q5_low], " agree that they receive all ",
                        "tornado warnings, compared with ",
                        shown_pct(max(q5_by)), "% in the ",
                        names(q5_by)[which.max(q5_by)], "."),
        result = paste0("the ", names(q5_by)[q5_low]),
        miss = paste("Warning reception is lowest in the",
                     names(q5_by)[q5_low]),
        highlight = highlight(category = names(q5_by)[q5_low])) |>
        c(split_chart("WX_rec_all", "CENSUS_REGION", shown_pct(q5_by),
          "Agree or strongly agree (%)", pct_fmt,
          paste("percentage in each census region reporting",
                quoted_labels(q_data("WX_rec_all"), c(4, 5))))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_rec_all",
                                   grouping = "CENSUS_REGION"))),
    list(
      part1 = list(
        prompt = paste0("Which source do U.S. adults trust most for ",
                        "information about severe weather?"),
        options = names(trust_vars), answer = trust_top - 1L,
        reveal = paste0(shown_pct(trust_shares[[trust_top]]), "% of U.S. ",
                        "adults report high or complete trust in ",
                        trust_name, ", compared with ", trust_rest, "."),
        chart = cmp_chart(shown_pct(trust_shares),
                          "High or complete trust (%)", pct_fmt),
        asked = asked_of(trust_vars),
        caption = compare_caption(trust_vars, paste(
          "percentage reporting",
          quoted_labels(q_data("WX_nws_trust"), c(4, 5), end = FALSE),
          "in each source.")),
        result = trust_name,
        miss = paste(str_replace(trust_name, "^the ", "The "),
                     "has the highest reported trust"),
        highlight = highlight(category = names(trust_vars)[trust_top])),
      part2 = list(
        prompt = paste0("Which age group reports the most trust in the ",
                        "National Weather Service?"),
        options = names(q6_by), answer = q6_top - 1L,
        reveal = paste0(shown_pct(q6_by[[q6_top]]), "% of adults ",
                        names(q6_by)[q6_top], " report high or complete ",
                        "trust in the National Weather Service, compared ",
                        "with ", shown_pct(min(q6_by)), "% of adults ages ",
                        names(q6_by)[which.min(q6_by)], "."),
        result = names(q6_by)[q6_top],
        miss = paste("Adults", names(q6_by)[q6_top], "report the highest",
                     "trust in the National Weather Service"),
        highlight = highlight(category = names(q6_by)[q6_top])) |>
        c(split_chart("WX_nws_trust", "AGE_GROUP", shown_pct(q6_by),
          "High or complete trust (%)", pct_fmt,
          paste("percentage in each age group reporting",
                quoted_labels(q_data("WX_nws_trust"), c(4, 5))))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_nws_trust",
                                   grouping = "AGE_GROUP"))),
    list(
      part1 = list(
        # The statement names no hazard; it was asked in the hurricane
        # survey, so the setup says so, and the statement is quoted from
        # the question file as respondents read it.
        setup = "In the hurricane survey, respondents rated this statement:",
        quote = q_data("TC_resp_always")$question_text,
        prompt = "About what percentage of U.S. adults agreed?",
        options = q7_opts, answer = q7_ans,
        reveal = paste0(shown_pct(q7_all), "% agree that they almost always ",
                        "take the protective actions officials suggest, ",
                        "even when those actions are difficult."),
        result = paste0(shown_pct(q7_all), "%"),
        miss = paste(in_ten(q7_all), "say they almost always take",
                     "recommended protective action"),
        chart_note = paste("Highlighted bars indicate the responses used to",
                           "calculate the quiz answer."),
        highlight = highlight(resp = c(4, 5))),
      part2 = list(
        setup = paste0("Weather salience describes how closely people ",
                       "follow the weather and plan around it."),
        prompt = paste0("Which group is most likely to agree that they ",
                        "almost always take the protective actions ",
                        "officials suggest?"),
        options = names(q7_by), answer = q7_top - 1L,
        reveal = paste0(shown_pct(q7_by[[q7_top]]), "% of adults with ",
                        str_to_lower(names(q7_by)[q7_top]), " agree that ",
                        "they almost always take the protective actions ",
                        "officials suggest, compared with ",
                        shown_pct(min(q7_by)),
                        "% of adults with ",
                        str_to_lower(names(q7_by)[which.min(q7_by)]), "."),
        result = names(q7_by)[q7_top],
        miss = "Agreement rises with weather salience",
        highlight = highlight(category = names(q7_by)[q7_top])) |>
        c(split_chart("TC_resp_always", "SALIENCE_GROUP", shown_pct(q7_by),
          "Agree or strongly agree (%)", pct_fmt,
          paste("percentage in each weather salience group reporting",
                quoted_labels(q_data("TC_resp_always"), c(4, 5))),
          relabel = str_to_lower(salience_labels) |>
            setNames(names(salience_labels)))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "TC_resp_always",
                                   grouping = "SALIENCE_GROUP"))),
    list(
      part1 = list(
        # Set in three layers: the setup quietly, the definition as a
        # quotation (read from the question file, as respondents read it),
        # and only the question itself as the heading.
        setup = paste0("In a set of questions designed to test whether ",
                       "people can distinguish between flood and flash flood ",
                       "warnings, respondents were shown this description:"),
        quote = fw_q$question_text,
        prompt = paste0("About what percentage of U.S. adults correctly ",
                        "identified this as a FLOOD warning?"),
        options = fw_opts, answer = fw_ans,
        reveal = paste0(shown_pct(fw_all), "% correctly identified the ",
                        "description as a flood warning."),
        result = paste0(shown_pct(fw_all), "%"),
        miss = "About two-thirds correctly identified a flood warning",
        chart_note = "The highlighted bar indicates the correct response.",
        highlight = highlight(resp = 1)),
      part2 = list(
        setup = paste0("The other half of respondents were shown a ",
                       "description of a different type of flood warning:"),
        quote = q8_q$question_text,
        prompt = paste0("About what percentage correctly identified this as ",
                        "a FLASH FLOOD warning?"),
        options = q8_opts, answer = q8_ans,
        reveal = paste0(shown_pct(q8_all), "% correctly identified the ",
                        "description as a flash flood warning, while ",
                        shown_pct(q8_flood), "% identified it as a flood ",
                        "warning."),
        result = paste0(shown_pct(q8_all), "%"),
        miss = paste(in_ten(q8_all), "correctly identified a flash flood",
                     "warning"),
        chart_note = "The highlighted bar indicates the correct response.",
        # The other half's item, so the chart and link go to its file.
        explore = list(href = "#survey",
                       params = list(q = "FL_flash_warn", grouping = "All")),
        highlight = highlight(resp = 2)),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "FL_flood_warn", grouping = "All"))),
    list(
      id = "community_risk",
      part1 = list(
        kind = "community",
        setup = paste0("Now guess for your own community: choose your ",
                       "National Weather Service forecast office, then pick ",
                       "a hazard."),
        prompt = "Which hazard do people there rate as the highest risk?",
        choose = "Choose a forecast office",
        measures = community_measures,
        tie = 0.1,
        # {place}, {top}, {value}, {second}, {second_value} and {tied} are
        # filled on the page from the office picked.
        reveal_one = paste0("In the {place} area, people rate {top} as the ",
                            "highest risk ({value} on a 1\u20135 scale), ",
                            "ahead of {second} ({second_value})."),
        reveal_tied = paste0("In the {place} area, people rate {tied} about ",
                             "equally as the highest risks, so {either} ",
                             "counts."),
        miss_one = "{Top} is the highest-rated risk in the {place} area",
        miss_tied = "{Tied} are nearly tied in the {place} area",
        meta = "Modeled estimates \u00b7 {place} forecast area",
        bars = paste0("Bars show each hazard's estimated average rating on ",
                      "the survey's scale from 1 (\u201c", risk_scale[1],
                      "\u201d) to 5 (\u201c", risk_scale[5], "\u201d). ",
                      "Estimates combine survey responses with the area's ",
                      "population characteristics, the same estimates ",
                      "Explore Communities maps. Hazards within 0.1 of the ",
                      "top are treated as tied."),
        map_link = "See {place} on the map \u2192"),
      explore = list(href = "#map",
                     label = "Explore communities on the map",
                     params = list(measure = "RISK_HEAT"))),
    list(
      part1 = list(
        prompt = paste0("About what percentage of U.S. adults correctly say ",
                        "a tornado warning generally gives them less than an ",
                        "hour before the tornado arrives?"),
        options = q10_opts, answer = q10_ans,
        reveal = paste0(shown_pct(q10_all), "% correctly say they have less ",
                        "than an hour, while ", shown_pct(q10_day),
                        "% think they have 1 to 24 hours, even though ",
                        shown_pct(q1_all), "% say they understand the ",
                        "difference between a tornado watch and a tornado ",
                        "warning."),
        result = paste0(shown_pct(q10_all), "%"),
        miss = paste("Only about half know tornado warnings generally",
                     "provide less than an hour"),
        chart_note = "The highlighted bar indicates the correct response.",
        highlight = highlight(resp = 1)),
      part2 = list(
        prompt = paste0("Which census region is most likely to correctly ",
                        "say a tornado warning gives them less than an ",
                        "hour?"),
        options = names(q10_by), answer = q10_top - 1L,
        reveal = paste0(shown_pct(q10_by[[q10_top]]), "% of adults in the ",
                        names(q10_by)[q10_top], " correctly say a tornado ",
                        "warning gives them less than an hour, compared ",
                        "with ",
                        shown_pct(min(q10_by)), "% in the ",
                        q10_lowest, "."),
        result = paste0("the ", names(q10_by)[q10_top]),
        miss = paste("Correct understanding is highest in the",
                     names(q10_by)[q10_top]),
        highlight = highlight(category = names(q10_by)[q10_top])) |>
        c(split_chart("WX_warn_time", "CENSUS_REGION", shown_pct(q10_by),
          "Less than 1 hour (%)", pct_fmt,
          paste("percentage in each census region reporting",
                quoted_labels(q10_q, 1) |>
                  str_replace("\u201cless", "\u201cLess")))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_warn_time",
                                   grouping = "CENSUS_REGION"))),
    list(
      part1 = list(
        prompt = paste0("How do U.S. adults think forecasters should ",
                        "balance false alarms against the risk of a ",
                        "tornado occurring without a warning?"),
        options = fa_opts, answer = fa_ans,
        reveal = paste0(shown_pct(fa_warn),
                        "% wanted forecasters to lean ",
                        "toward avoiding missed tornadoes, even at the cost ",
                        "of more false alarms, while ",
                        shown_pct(100 - fa_warn), "% leaned toward avoiding ",
                        "false alarms."),
        result = str_to_lower(fa_opts[fa_ans + 1]),
        miss = str_replace(fa_opts[fa_ans + 1], "^Most ", "Most people "),
        # The four responses as the two sides the question asks about.
        chart = cmp_chart(shown_pct(c(`Avoiding missed tornadoes` = fa_warn,
                                      `Avoiding false alarms` = 100 - fa_warn)),
                          "Lean this way (%)", pct_fmt,
                          highest_first = FALSE),
        asked = asked_of("WX_mi_fa_should"),
        caption = compare_caption("WX_mi_fa_should", paste(
          "percentage leaning toward avoiding missed tornadoes or avoiding",
          "false alarms.")),
        highlight = if (fa_ans == 2) NULL else highlight(
          category = c("Avoiding missed tornadoes",
                       "Avoiding false alarms")[fa_ans + 1])),
      part2 = list(
        prompt = paste0("How do U.S. adults think forecasters should ",
                        "balance lead time against the precision and ",
                        "accuracy of a tornado warning?"),
        options = lt_opts, answer = lt_ans,
        reveal = paste0(shown_pct(lt_lead),
                        "% wanted forecasters to lean toward more lead ",
                        "time, while ", shown_pct(100 - lt_lead),
                        "% leaned toward greater precision and accuracy."),
        result = str_to_lower(lt_opts[lt_ans + 1]),
        # The split is close (about 54/46), and the heading says so.
        miss = paste0("Slightly more lean toward ",
                      c("lead time", "precision and accuracy")[lt_ans + 1]),
        chart = cmp_chart(shown_pct(c(`More lead time` = lt_lead,
                                      `Greater precision and accuracy` =
                                        100 - lt_lead)),
                          "Lean this way (%)", pct_fmt,
                          highest_first = FALSE),
        asked = asked_of("WX_leadtime_should"),
        caption = compare_caption("WX_leadtime_should", paste(
          "percentage leaning toward more lead time or greater precision",
          "and accuracy.")),
        explore = list(href = "#survey",
                       params = list(q = "WX_leadtime_should",
                                     grouping = "All")),
        highlight = highlight(category = c("More lead time",
          "Greater precision and accuracy")[lt_ans + 1])),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_mi_fa_should",
                                   grouping = "All"))),
    list(
      part1 = list(
        setup = paste0("Asked of U.S. adults who remember receiving a ",
                       "tornado warning."),
        prompt = paste0("What did people most often do the last time they ",
                        "got one?"),
        options = c("Moved to shelter",
                    "Monitored the situation, but did not move to shelter",
                    "Did nothing and continued their activities",
                    "Left the area"),
        answer = 1L,
        reveal = paste0(shown_pct(act_shares[[1]]), "% monitored the ",
                        "situation but did not move to shelter, compared ",
                        "with ", shown_pct(act_shares[[2]]), "% who moved ",
                        "to shelter and ", shown_pct(act_shares[[3]]),
                        "% who did nothing."),
        result = "monitored the situation",
        miss = paste("Monitoring, not sheltering, was the most common",
                     "response"),
        chart = cmp_chart(shown_pct(act_shares), "Share of respondents (%)",
                          pct_fmt, highest_first = FALSE),
        asked = asked_of("WX_last_act"),
        caption = list(
          meta = paste0(format(act_q$summaries$All$n, big.mark = ","),
                        " U.S. adults \u00b7 Severe Weather Survey \u00b7 ",
                        str_replace_all(act_q$summaries$All$years, "-",
                                        "\u2013")),
          bars = paste("Bars show the weighted percentage giving each",
                       "response. \u201cMoved to shelter\u201d combines",
                       "the three sheltering responses. Asked of those who",
                       "remembered a tornado warning received at home, work,",
                       "school, or a business.")),
        highlight = highlight(category = names(act_shares)[1])),
      part2 = list(
        prompt = paste0("Which age group was most likely to monitor the ",
                        "situation rather than move to shelter?"),
        options = names(act_by), answer = act_by_top - 1L,
        reveal = paste0(shown_pct(act_by[[act_by_top]]), "% of adults ",
                        names(act_by)[act_by_top], " monitored without ",
                        "moving to shelter at their most recent warning, ",
                        "compared with ", shown_pct(min(act_by)),
                        "% of adults ages ", names(act_by)[which.min(act_by)],
                        "."),
        result = names(act_by)[act_by_top],
        miss = "Monitoring rather than sheltering rises with age",
        highlight = highlight(category = names(act_by)[act_by_top])) |>
        c(split_chart("WX_last_act", "AGE_GROUP", shown_pct(act_by),
          "Monitored, did not shelter (%)", pct_fmt,
          paste("percentage in each age group reporting",
                quoted_labels(act_q, 1)))),
      explore = list(href = "#survey",
                     label = "Explore this question in the data",
                     params = list(q = "WX_last_act",
                                   grouping = "AGE_GROUP")))
  )

  # The quiz follows a warning along its path: whether it reaches people,
  # whether they understand it, whether they believe it, how they weigh the
  # risk, and what they do. Each question is placed by the survey item its
  # explorer link names, and the theme shows beside its number.
  running_order <- c(
    WX_wx_info7 = "Receiving", WX_rec_all = "Receiving",
    WX_alert_und = "Understanding", WX_warn_time = "Understanding",
    FL_flood_warn = "Understanding", WW_amount_format = "Understanding",
    TC_wep_rec = "Understanding",
    WX_nws_trust = "Trust", WX_mi_fa_should = "Warning Decisions",
    WX_risk_heat = "Risk", community_risk = "Risk",
    TC_resp_always = "Responding", WX_last_act = "Responding"
  )
  ids <- vapply(questions, function(q) q$id %||% q$explore$params$q, "")
  check_prose(setequal(ids, names(running_order)) && !anyDuplicated(ids),
              "the running order no longer names every quiz question once")
  lapply(names(running_order), function(id) {
    c(questions[[which(ids == id)]], theme = unname(running_order[[id]]))
  })
})

# The explorer opens a linked question only if it is on the list, and falls
# back to the first question otherwise, so a quiz link to a hidden question
# would open the wrong chart under "Open in the survey explorer".
quiz_links <- unique(unlist(lapply(quiz, function(q) {
  parts <- c(list(q), list(q$part1, q$part2), q$more)
  lapply(parts, function(p) p$explore$params$q)
})))
linked_hidden <- intersect(quiz_links, drop_ids)
if (length(linked_hidden) > 0) {
  print(linked_hidden)
  stop("Quiz links above point at hidden questions - the explorer would ",
       "open a different question.")
}

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

# Project At A Glance ----------------------------------------------------------
# The landing page's four figures and the dot field beside its title, counted
# off the data half's output so they move with every --data run rather than
# being typed and left to go stale. A survey is one hazard fielded in one
# year; respondents.json carries each one's respondent count.
if (is.null(respondents$surveys)) {
  stop("respondents.json has no per-survey counts - rerun with --data.")
}
surveys_data <- as_tibble(respondents$surveys)

if (sum(surveys_data$n) != respondents$rows ||
    !setequal(surveys_data$survey_year, respondents$years)) {
  stop("Per-survey counts in respondents.json do not add up to its total ",
       "or its years.")
}

# Hazards in the order they joined the program; the code in parentheses is
# the table's, not the reader's.
hazards_data <- surveys_data |>
  group_by(survey_hazard) |>
  summarize(first_year = min(survey_year), .groups = "drop") |>
  arrange(first_year, survey_hazard) |>
  mutate(name = str_remove(survey_hazard, "\\s*\\([A-Z]+\\)$"))

year_span <- range(respondents$years)
n_years <- diff(year_span) + 1

landing_stats <- list(
  list(value = format(respondents$rows, big.mark = ","),
       label = "Survey responses"),
  list(value = paste(n_years, "years"),
       label = paste0("of data collection, ", year_span[1], " to ",
                      year_span[2])),
  list(value = paste(nrow(hazards_data), "hazards"),
       label = paste(hazards_data$name, collapse = " · ")),
  list(value = paste(nrow(surveys_data), "surveys"),
       label = "National surveys")
)
message("Landing: ", paste(map_chr(landing_stats, "value"), collapse = ", "))

# Respondents per survey, for the dot field, with each hazard numbered in
# the order it joined the program so its color is fixed by that order. A
# year with no survey would be a gap in the program, drawn as a column that
# does not grow, so the field is given every year in the span.
growth_data <- surveys_data |>
  left_join(hazards_data |> mutate(hazard = row_number()) |>
              select(survey_hazard, hazard),
            by = "survey_hazard") |>
  arrange(survey_year, hazard) |>
  select(year = survey_year, hazard, n)

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
# heading. The opening paragraph is the reason
# the project exists, so it is set as the lede rather than under a heading.
# Figures in it - the alert years, the count of areas - are read from the
# data like everywhere else.
alert_common <- as_range(common_span)
alert_exceptions <- if (length(odd_alerts) == 0) "" else paste0(
  " ", str_to_sentence(paste(vapply(odd_alerts, function(m)
    str_to_lower(str_remove(m$label, " alert days$")), ""), collapse = ", ")),
  " counts cover ", as_range(odd_alerts[[1]]$span), " because the relevant ",
  "product did not exist before then."
)
n_areas <- length(places)

# Publications using the survey, as supplied, each linked to the DOI Crossref
# returns for its exact title. One format for every entry: the title as the
# link, then "Authors (Year). Journal, detail." with only the journal in
# italics; grouped by year, newest first.
pub <- function(year, title, authors, journal, detail, doi) {
  list(year = year, title = title, authors = authors, journal = journal,
       detail = detail, doi = doi)
}
publications <- list(
  pub(2026, paste0("Offering an Evidence-Based Recommendation for Improving ",
                   "the Storm Prediction Center\u2019s Categorical Outlook"),
      paste0("Ernst, S., Krocak, M. J., Bitterman, A., Rosen, Z., Fellman, ",
             "B., Wanless, A., Hogg, D., Ripberger, J. T., & Jenkins-Smith, ",
             "H. C."),
      "Weather, Climate, and Society", ". Early Online Release",
      "10.1175/WCAS-D-25-0146.1"),
  pub(2026, paste0("The Color of Weather: Examining Associations for Color ",
                   "in Forecast Graphics"),
      paste0("Rosen, Z., Bitterman, A., Ripberger, J. T., Krocak, M. J., ",
             "Wanless, A., & Meister, E."),
      "Visual Communication Quarterly", ", 1\u201318",
      "10.1080/15551393.2025.2605093"),
  pub(2025, paste0("Linguistic Challenges in Severe Weather Communication: ",
                   "Comparing English- and Spanish-Speaking Populations"),
      paste0("Gaviria Pab\u00f3n, A. R., Krocak, M. J., Ripberger, J. T., & ",
             "Trujillo-Falc\u00f3n, J. E."),
      "Bulletin of the American Meteorological Society",
      ", 106(9), E1940\u2013E1954", "10.1175/BAMS-D-24-0199.1"),
  pub(2025, paste0("Modeling the Predictors of Extreme Weather Affective ",
                   "Experience and Its Influence on Extreme Weather ",
                   "Decision-Making"),
      paste0("Ernst, S., Allan, J. N., Wehde, W., Ripberger, J. T., Krocak, ",
             "M. J., & Rosen, Z."),
      "Weather, Climate, and Society", ", 17(2), 193\u2013203",
      "10.1175/WCAS-D-24-0086.1"),
  pub(2025, paste0("Investigating How NWS Meteorologists, Emergency ",
                   "Managers, and the Public Interpret Conditional ",
                   "Intensity Forecasts for Severe Weather"),
      paste0("Ernst, S., Fellman, B. J., Rosen, Z., Krocak, M. J., Jirak, ",
             "I. L., Ripberger, J. T., & Jenkins-Smith, H. C."),
      "Weather and Forecasting", ", 40(3), 507\u2013524",
      "10.1175/WAF-D-24-0109.1"),
  pub(2024, paste0("The Changing Weather Information Landscape: ",
                   "Observations, Conjectures, and Thoughts About the ",
                   "Future"),
      paste0("Krocak, M. J., Ripberger, J. T., Berry, K., Silva, C. L., & ",
             "Jenkins-Smith, H. C."),
      "Bulletin of the American Meteorological Society",
      ", 105(9), E1755\u2013E1761", "10.1175/BAMS-D-24-0041.1"),
  pub(2023, paste0("Assessing Public Interpretation of Original and ",
                   "Linguist-Suggested SPC Risk Categories in Spanish"),
      paste0("Bitterman, A., Krocak, M. J., Ripberger, J. T., Ernst, S., ",
             "Trujillo-Falc\u00f3n, J. E., Gaviria Pab\u00f3n, A. R., ",
             "Silva, C. L., & Jenkins-Smith, H. C."),
      "Weather and Forecasting", ", 38(7), 1095\u20131106",
      "10.1175/WAF-D-22-0110.1"),
  pub(2023, paste0("Public Information Priorities Across Weather Hazards ",
                   "and Time Scales"),
      paste0("Krocak, M. J., Ripberger, J. T., Ernst, S., Silva, C. L., ",
             "Jenkins-Smith, H. C., & Bitterman, A."),
      "Bulletin of the American Meteorological Society",
      ", 104(4), E768\u2013E780", "10.1175/BAMS-D-22-0190.1"),
  pub(2022, paste0("\u00bfAviso o Alerta? Developing Effective, Inclusive, ",
                   "and Consistent Watch and Warning Translations for U.S. ",
                   "Spanish Speakers"),
      paste0("Trujillo-Falc\u00f3n, J. E., Gaviria Pab\u00f3n, A. R., ",
             "Ripberger, J. T., Bitterman, A., Thornton, J. B., Krocak, ",
             "M. J., Ernst, S. R., Obeso, E. C., & Lipski, J."),
      "Bulletin of the American Meteorological Society",
      ", 103(12), E2791\u2013E2803", "10.1175/BAMS-D-22-0050.1"),
  pub(2022, paste0("Exploring the Differences in SPC Convective Outlook ",
                   "Interpretation Using Categorical and Numeric ",
                   "Information"),
      paste0("Krocak, M. J., Ripberger, J. T., Ernst, S., Silva, C. L., & ",
             "Jenkins-Smith, H. C."),
      "Weather and Forecasting", ", 37(2), 303\u2013311",
      "10.1175/WAF-D-21-0123.1"),
  pub(2021, paste0("Colorful Language: Investigating Public Interpretation ",
                   "of the Storm Prediction Center Convective Outlook"),
      paste0("Ernst, S., Ripberger, J. T., Krocak, M. J., Jenkins-Smith, ",
             "H. C., & Silva, C. L."),
      "Weather and Forecasting", ", 36(5), 1785\u20131797",
      "10.1175/WAF-D-21-0001.1"),
  pub(2021, paste0("An Analysis of Tornado Warning Reception and Response ",
                   "Across Time: Leveraging Respondents\u2019 Confidence ",
                   "and a Nocturnal Tornado Climatology"),
      paste0("Krocak, M. J., Allan, J. N., Ripberger, J. T., Silva, C. L., & ",
             "Jenkins-Smith, H. C."),
      "Weather and Forecasting", ", 36(5), 1649\u20131660",
      "10.1175/WAF-D-20-0207.1"),
  pub(2021, paste0("Public Willingness to Pay for Continuous and ",
                   "Probabilistic Hazard Information"),
      paste0("Wehde, W., Ripberger, J. T., Jenkins-Smith, H. C., Jones, ",
             "B. A., Allan, J. N., & Silva, C. L."),
      "Natural Hazards Review", ", 22(2), 04021004",
      "10.1061/(ASCE)NH.1527-6996.0000444"),
  pub(2020, paste0("Thinking Outside the Polygon: A Study of Tornado ",
                   "Warning Perception Outside of Warning Polygon Bounds"),
      paste0("Krocak, M. J., Ernst, S., Allan, J. N., Wehde, W., Ripberger, ",
             "J. T., Silva, C. L., & Jenkins-Smith, H. C."),
      "Natural Hazards", ", 102, 1351\u20131368",
      "10.1007/s11069-020-03970-5"),
  pub(2020, paste0("How Likely Is That Chance of Thunderstorms? A Study of ",
                   "How National Weather Service Forecast Offices Use ",
                   "Words of Estimative Probability and What They Mean to ",
                   "the Public"),
      paste0("Lenhardt, E. D., Cross, R. N., Krocak, M. J., Ripberger, J. T., ",
             "Ernst, S. R., Silva, C. L., & Jenkins-Smith, H. C."),
      "Journal of Operational Meteorology", ", 8(5)",
      "10.15191/nwajom.2020.0805"),
  pub(2020, paste0("Geographic Distributions of Extreme Weather Risk ",
                   "Perceptions in the United States"),
      paste0("Allan, J. N., Ripberger, J. T., Wehde, W., Krocak, M. J., ",
             "Silva, C. L., & Jenkins-Smith, H. C."),
      "Risk Analysis", ", 40(12), 2498\u20132508", "10.1111/risa.13569"),
  pub(2020, paste0("Exploring Community Differences in Tornado Warning ",
                   "Reception, Comprehension, and Response Across the ",
                   "United States"),
      paste0("Ripberger, J. T., Silva, C. L., Jenkins-Smith, H. C., Allan, ",
             "J. N., Krocak, M. J., Wehde, W., & Ernst, S."),
      "Bulletin of the American Meteorological Society",
      ", 101(6), E936\u2013E948", "10.1175/BAMS-D-19-0064.1"),
  pub(2019, paste0("Measuring Tornado Warning Reception, Comprehension, and ",
                   "Response in the United States"),
      paste0("Ripberger, J. T., Krocak, M. J., Wehde, W. W., Allan, J. N., ",
             "Silva, C. L., & Jenkins-Smith, H. C."),
      "Weather, Climate, and Society", ", 11(4), 863\u2013880",
      "10.1175/WCAS-D-19-0015.1"),
  pub(2019, paste0("The Impact of Hours of Advance Notice on Protective ",
                   "Action in Response to Tornadoes"),
      paste0("Krocak, M. J., Ripberger, J. T., Jenkins-Smith, H. C., & ",
             "Silva, C. L."),
      "Weather, Climate, and Society", ", 11(4), 881\u2013888",
      "10.1175/WCAS-D-19-0023.1")
)
pub_years <- vapply(publications, function(x) x$year, double(1))
if (is.unsorted(rev(pub_years))) {
  stop("Publications are not listed newest first; keep the list in order.")
}
pub_html <- function(x) {
  paste0("<p class=\"wx-pub\"><a class=\"wx-pub-title\" ",
         "href=\"https://doi.org/", x$doi, "\">", x$title, "</a>",
         "<span class=\"wx-pub-cite\">", x$authors, " (", x$year, "). <em>",
         x$journal, "</em>", x$detail, ".</span></p>")
}
publications_html <- paste0(unlist(lapply(unique(pub_years), function(y)
  c(paste0("<h4 class=\"wx-pub-year\">", y, "</h4>"),
    vapply(publications[pub_years == y], pub_html, "")))), collapse = "")
# The two methods papers, in the same format as the list.
methods_pubs <- keep(publications, function(x)
  x$doi %in% c("10.1175/WCAS-D-19-0015.1", "10.1175/BAMS-D-19-0064.1"))
methods_pubs <- methods_pubs[order(vapply(methods_pubs, function(x) x$year,
                                          double(1)))]

about_html <- paste0(
  "<p class=\"wx-about-lede\">Effective weather risk communication requires ",
  "information about both the weather and the people and communities ",
  "receiving forecasts and warnings. Forecasters, emergency managers, ",
  "broadcast meteorologists, and other partners have access to tremendous ",
  "amounts of data about atmospheric and climate conditions, but far less ",
  "systematic social and behavioral data about the people they serve.</p>",
  "<p>The Extreme Weather and Society Project works to help fill that gap by ",
  "building a long-term evidence base on how people receive, understand, ",
  "trust, and respond to weather information. The project combines recurring ",
  "national surveys, experiments, community-level estimates, and interactive ",
  "tools designed to make these data accessible and useful to researchers and ",
  "members of the weather community.</p>",

  "<hr>",
  "<h3>The survey</h3>",
  "<p>The Extreme Weather and Society Survey is a long-running series of ",
  "national surveys of U.S. adults conducted by the University of ",
  "Oklahoma\u2019s <a href=\"https://ippra.net\">Institute for Public ",
  "Policy Research and Analysis</a> (IPPRA). The ",
  "surveys cover severe weather, tropical cyclones, winter weather, flooding, ",
  "and other weather hazards.</p>",
  "<p>Many questions are repeated across survey waves, allowing us to ",
  "establish baselines and track changes over time. Other questions and ",
  "experiments are added to address emerging research questions and ",
  "communication needs. Together, the surveys measure topics including ",
  "forecast and warning reception, understanding, trust, information use, ",
  "risk perceptions, preparedness, communication preferences, and protective ",
  "action.</p>",
  "<p>Survey weights adjust each wave to American Community Survey benchmarks ",
  "for age, gender, race, education, income, and region. Sample sizes, survey ",
  "years, question wording, and other information needed to interpret ",
  "individual results are provided throughout the site.</p>",

  "<hr>",
  "<h3>Interpreting survey results</h3>",
  "<p>Most results on this site describe what survey respondents report ",
  "knowing, believing, preferring, or doing. They should not necessarily be ",
  "interpreted as direct observations of behavior. Some questions measure ",
  "knowledge more directly by asking respondents to identify or interpret ",
  "specific forecast and warning information.</p>",
  "<p>The surveys use non-probability online samples. Weighting improves ",
  "correspondence with the U.S. adult population on important demographic and ",
  "geographic characteristics, but it does not eliminate all possible sources ",
  "of survey error or bias. Results should therefore be interpreted as ",
  "weighted estimates of the U.S. adult population and with the uncertainty ",
  "appropriate for survey research.</p>",
  "<p>Percentages may not sum to exactly 100 because of rounding. Sample ",
  "sizes can also vary across questions because not every question ",
  "appears in every survey wave and because some respondents may not ",
  "answer every ",
  "question.</p>",

  "<hr>",
  "<h3>Community estimates</h3>",
  "<p>The Explore Communities section extends the national survey data to ",
  "National Weather Service County Warning Areas. These values are modeled ",
  "community estimates, not direct survey estimates calculated separately ",
  "from respondents in each area.</p>",
  "<p>Community estimates are produced using multilevel regression and ",
  "poststratification (MRP). The models combine survey responses with U.S. ",
  "Census population data to estimate measures for the adult population of ",
  "each county and then combine those estimates to the County Warning Area. ",
  "This approach allows us to produce comparable estimates for all ", n_areas,
  " National Weather Service County Warning Areas in the contiguous United ",
  "States, including areas where relatively few people were surveyed.</p>",
  "<p>Because these values are model-based estimates, they are subject to ",
  "uncertainty and should be used primarily to examine broad patterns and ",
  "differences across communities rather than as exact measurements of any ",
  "individual community.</p>",

  "<hr>",
  "<h3>Alert history</h3>",
  "<p>The alert-day counts shown in Explore Communities are observed records, ",
  "not survey estimates. They represent the number of days on which the ",
  "National Weather Service issued at least one relevant VTEC-enabled watch, ",
  "warning, or advisory within a County Warning Area.</p>",
  "<p>Alert records come from the ", MESONET_LINK, " archive. Most alert ",
  "counts cover ", alert_common, ".", alert_exceptions, " A day is counted ",
  "once regardless of how many qualifying products were issued on that ",
  "day.</p>",
  "<p>These counts provide information about the warning and alert ",
  "environments experienced by different communities. They are also used as ",
  "exposure measures in the models used to produce the community ",
  "estimates.</p>",

  "<hr>",
  "<h3>Using this site</h3>",
  "<div class=\"wx-about-links\">",
  about_link("survey", "Explore Survey Questions", paste0(
    "Browse survey questions and results across hazards, years, demographic ",
    "groups, and other characteristics. Select a question to see national ",
    "results or compare responses across different groups.")),
  about_link("map", "Explore Communities", paste0(
    "Explore how warning reception, understanding, response, risk ",
    "perceptions, and other measures vary across National Weather Service ",
    "forecast offices. Select a community to see its estimates across ",
    "measures or compare survey-based estimates with local alert history.")),
  about_link("quiz", "Test Your Knowledge", paste0(
    "Test your assumptions about how people receive, understand, trust, and ",
    "respond to weather information. Make your best guess, then see what the ",
    "survey data show.")),
  "</div>",

  "<hr>",
  "<h3>Data and reproducibility</h3>",
  "<p>Survey data, questionnaires, metadata, and other supporting materials ",
  "are available through the ",
  "<a href=\"https://dataverse.harvard.edu/dataverse/wxsurvey\">Extreme ",
  "Weather and Society Dataverse</a>. Individual results throughout the site ",
  "also link back to the underlying survey data where appropriate.</p>",
  "<p>The code that builds this site, including the statistics it shows ",
  "and the question wording read from each survey instrument, is available ",
  "in the <a href=\"https://github.com/ippra/wxdash\">WxDash GitHub ",
  "repository</a>. Each chart on Explore Survey Questions also offers ",
  "Download R code, a script that rebuilds that chart from the public survey ",
  "data.</p>",
  "<p>The project is designed around transparency, consistent measurement, ",
  "and continued data collection. As new survey waves are completed, they ",
  "provide additional observations for tracking established measures and ",
  "opportunities to add new questions and experiments.</p>",

  "<hr>",
  "<h3>Methods</h3>",
  "<p>More detailed information about the measurement and ",
  "community-estimation approaches is available in the following ",
  "publications:</p>",
  paste(vapply(methods_pubs, pub_html, ""), collapse = ""),
  "<p>These publications provide additional information about survey ",
  "measurement, multilevel regression and poststratification, validation of ",
  "community estimates, and the development of the community-level data used ",
  "in this site.</p>",

  "<hr>",
  "<h3>Publications using the Extreme Weather and Society Survey</h3>",
  "<p>The Extreme Weather and Society Survey is designed not only as a ",
  "long-term data collection effort, but also as a resource for research on ",
  "weather risk communication and decision-making. Data from the survey have ",
  "supported peer-reviewed research on forecast and warning reception, ",
  "understanding and response, risk perceptions, information use, ",
  "uncertainty, forecast graphics, language, and other topics.</p>",
  "<div class=\"wx-pubs\">", publications_html, "</div>",
  "<p>Have you published research using these data? We would like to include ",
  "it here. Please contact <a href=\"mailto:jtr@ou.edu\">Joe Ripberger</a> at ",
  "OU IPPRA.</p>",

  "<hr>",
  "<h3>Support</h3>",
  "<p>The University of Oklahoma, the U.S. Weather Program Office (WPO), and ",
  "the National Weather Service (NWS) have supported the development of this ",
  "project and continue to support data collection, analysis, programming, ",
  "and maintenance.</p>",
  "<p>The survey findings and community estimates presented on this site are ",
  "research products of the Extreme Weather and Society Project and should ",
  "not be interpreted as official National Weather Service findings or ",
  "positions.</p>",

  "<hr>",
  "<h3>Contact</h3>",
  "<p>Questions about the project, survey data, methods, community estimates, ",
  "or use of the data are welcome.</p>",
  "<p class=\"wx-about-contact\"><a href=\"mailto:jtr@ou.edu\">Joe ",
  "Ripberger</a><br>Institute for Public Policy Research and Analysis<br>",
  "University of Oklahoma</p>"
)

config <- list(
  schema_version = 3,
  project = list(
    slug = "wxdash",
    title = "WxDash — Extreme Weather and Society Dashboard",
    nav_title = "WxDash",
    nav_subtitle = "Extreme Weather & Society Project",
    beta = channel == "beta"
  ),
  theme = list(default = "wxdash", allow_viewer_switch = TRUE),
  groupings = groupings_cfg,
  # The note under each chart, in four parts: who and when as one line of
  # facts, what the bars are, where the data come from, and the handles a
  # reader needs to find the question again. Every {token} is filled from
  # the question file, so no line states a figure the data does not carry.
  explore_caption = list(
    meta = "{n} U.S. adults \u00b7 {survey} Survey \u00b7 {years}",
    bars = "Bars show the weighted percentage selecting each response.",
    bars_split = paste0("Bars show the weighted percentage of each ",
                        "{group_phrase} selecting each response."),
    smallest = paste0(" The smallest group, {smallest}, includes ",
                      "{smallest_n} respondents."),
    provenance = paste0(
      "Results are from the Extreme Weather and Society Survey at the ",
      "<a href=\"https://ippra.net\">University of Oklahoma\u2019s ",
      "Institute for Public Policy Research and Analysis</a>. Survey weights ",
      "adjust each wave to American Community Survey benchmarks for age, ",
      "gender, race, education, income, and region."),
    reference = paste0(
      "Variable: <code>{variable}</code>{randomization} \u00b7 Data: ",
      "<a href=\"https://dataverse.harvard.edu/dataverse/wxsurvey\">",
      "Extreme Weather and Society Survey Dataverse</a>"),
    # Said in words for readers; the survey variable behind the variation is
    # named in the reference line, which is where variable names belong.
    randomized = paste0(" Respondents were randomly assigned one version; ",
                        "the menu above shows each."),
    varied = " Wording in brackets varied between respondents.",
    randomization = " \u00b7 Randomization: <code>{names}</code>",
    piped = " \u00b7 Wording varies with: <code>{names}</code>"
  ),
  # Which survey variable decides each split-sample question's version, so
  # the page can put the version shown into the question's wording and name
  # the randomization in the note.
  arm_variables = arm_variables,
  arm_wording = arm_wording,
  arm_shown = arm_shown,
  arm_shown_label = "Shown on the screen before this question:",
  # Placeholders in question wording that are not a version menu's own
  # variable, in words a reader can follow. Anything not listed here reads
  # "[varied between respondents]".
  placeholders = list(
    state = "the respondent\u2019s state",
    ice_thrsh = "the amount the respondent gave earlier",
    snow_thrsh = "the amount the respondent gave earlier",
    cold_thrsh = "the temperature the respondent gave earlier",
    range_max = "an upper amount that varied",
    .default = "varied between respondents"
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
  pages = list(
    list(id = "home", component = "wx_landing", label = "Home",
         hero = list(
           eyebrow = paste0("Extreme Weather and Society Project \u00b7 ",
                            "University of Oklahoma"),
           # Two lines, broken where the phrase breaks; a narrow screen
           # wraps each line on its own.
           headline = list("Building a Long-Term Evidence Base",
                           "for Weather Risk Communication"),
           intro = paste0("Effective weather risk communication requires ",
                          "information about both the weather and the ",
                          "people receiving forecasts and warnings."),
           statement = list(
             paste0("We have tremendous amounts of data about the ",
                    "atmosphere."),
             paste0("We have far less systematic data about the people on ",
                    "the other end of the forecast.")),
           description = paste0(
             "The Extreme Weather and Society Survey is a long-term effort ",
             "to help fill this gap. Through recurring national surveys and ",
             "experiments, the project collects consistent data on what ",
             "people know, what they misunderstand, which sources they use ",
             "and trust, and how they interpret and respond to weather ",
             "information."),
           # Set in bold after the paragraph: what the effort adds up to.
           description_close = paste0(
             "The result is a growing evidence base that informs research, ",
             "risk communication, and decision support across the weather ",
             "community.")),
         growth = list(years = seq(year_span[1], year_span[2]),
                       surveys = growth_data,
                       hazards = hazards_data$name,
                       per_dot = 50,
                       title = "A growing evidence base",
                       caption = paste0("Each dot represents 50 survey ",
                                        "respondents, accumulated across ",
                                        "surveys from ", year_span[1], " to ",
                                        year_span[2], ".")),
         stats = landing_stats,
         sections = list(
           list(columns = list(
             list(lead = "Why understanding the public matters",
                  body = paste0(
                    "Forecasts and warnings only work if people receive ",
                    "them, understand what they mean, and know what to do ",
                    "with the information. But people differ in what they ",
                    "know, where they get information, which sources they ",
                    "trust, and how they understand and respond to risk. ",
                    "Understanding these differences provides forecasters, ",
                    "emergency managers, and other partners with better ",
                    "information about the people and communities they ",
                    "serve.")),
             list(lead = "Why long-term data matter",
                  body = paste0(
                    "One survey provides a snapshot. Consistent data ",
                    "collected over time allow us to establish baselines, ",
                    "track changes in public knowledge and behavior, compare ",
                    "groups and communities, and examine how people respond ",
                    "as forecasts, warnings, technologies, and communication ",
                    "practices change. Recurring measures provide ",
                    "continuity, while new questions and experiments allow ",
                    "the project to address emerging challenges."))))),
         explore = list(
           heading = "Explore the Data",
           intro = paste0("Explore survey questions and results, examine ",
                          "differences across communities, or test what you ",
                          "know about the people receiving weather ",
                          "information."),
           cards = list(
             list(page = "survey", label = "Explore Survey Questions",
                  body = paste0("Browse questions and results across ",
                                "hazards, years, demographic groups, and ",
                                "other characteristics."),
                  cta = "Explore the Survey \u2192"),
             list(page = "map", label = "Explore Communities",
                  body = paste0("See how people receive, understand, and ",
                                "respond to warnings, and how they perceive ",
                                "risk, across National Weather Service ",
                                "forecast office areas, beside each area's ",
                                "alert history."),
                  cta = "Explore Communities \u2192"),
             list(page = "quiz", label = "Test Your Knowledge",
                  body = paste0("How well do you know the people receiving ",
                                "forecasts and warnings? Test your ",
                                "assumptions against the survey data."),
                  cta = "Take the Quiz \u2192")))),
    list(id = "survey", component = "explore",
         label = "Explore Survey Questions",
         title = "Explore Survey Questions",
         questions = "data/questions.json", default_grouping = "All",
         # The count is read, not typed: rounded down to the hundred below
         # it, so "more than" stays true as questions are added or hidden.
         intro = paste0("Explore what Americans know, believe, and do when ",
                        "it comes to extreme weather. Browse more than ",
                        floor((length(q_files) - 1) / 100) * 100, " survey ",
                        "questions across severe weather, tropical weather, ",
                        "winter weather, and flooding. Select any question ",
                        "to see national results or compare responses ",
                        "across different groups."),
         # No title on the response axis: its labels are the answers.
         chart = list(y_label = "Respondents (%)"),
         blurb = blurbs$survey),
    list(id = "map", component = "wx_map_explorer",
         label = "Explore Communities",
         title = "Explore Communities",
         default_measure = "TO_RECEP",
         # The count is read off the map data, so it stays true if 07's
         # geography changes.
         intro = list(
           paste0("Explore how people understand and respond to weather ",
                  "information across National Weather Service forecast ",
                  "offices. Compare survey-based estimates across ",
                  "communities and examine how those patterns relate to ",
                  "local weather and warning experience."),
           paste0("These are modeled community estimates, not local survey ",
                  "samples alone. Estimates combine survey data with ",
                  "population characteristics to provide comparable ",
                  "measures for all ", measures_meta$areas,
                  " National Weather Service forecast offices in the ",
                  "contiguous United States.")),
         blurb = blurbs$map),
    list(id = "quiz", component = "wx_quiz", label = "Test Your Knowledge",
         title = "Test Your Knowledge",
         intro = paste0("How well do you know the people receiving ",
                        "forecasts and warnings? Test your assumptions about ",
                        "how people receive, understand, trust, and respond ",
                        "to weather information. Make your best guess, then ",
                        "see what the survey data show. Keep in mind that ",
                        "most results reflect what people say they know, ",
                        "prefer, or do rather than directly observed ",
                        "behavior."),
         blurb = blurbs$quiz,
         questions = quiz),
    list(id = "about", component = "static_page", label = "About",
         title = "About the Extreme Weather and Society Project",
         html = about_html)
  ),
  # The footer names the programme rather than the site, so it reads the
  # same at the foot of every page as the headline does on the home page.
  footer = list(
    name = "Extreme Weather and Society Project",
    tagline = paste0("Building a Long-Term Evidence Base for Weather Risk ",
                     "Communication"),
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
index_html <- gsub("__BUILD__", BUILD,
                   readLines(file.path(site_src, "index.html")))
if (channel == "beta") {
  viewport <- grep("name=\"viewport\"", index_html, fixed = TRUE)
  if (length(viewport) != 1) stop("index.html has no single viewport line.")
  index_html <- append(index_html,
                       "<meta name=\"robots\" content=\"noindex, nofollow\">",
                       after = viewport)
  writeLines(c("User-agent: *", "Disallow: /"), paste0(out, "robots.txt"))
}
writeLines(index_html, paste0(out, "index.html"))

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

if (!identical(readLines(paste0(out, "index.html")), index_html)) {
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
