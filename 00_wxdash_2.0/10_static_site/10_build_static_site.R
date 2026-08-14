library(tidyverse)
library(srvyr)
library(sf)
library(jsonlite)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Static Site ------------------------------------------------------------------
# Builds a copy of the dashboard that needs no R at run time: plain HTML, one
# JavaScript file and a folder of data. Upload the output directory to any web
# host and it works. There is no server process, no Shiny, no runtime R.
#
# Nothing in the dashboard is computed from user input - every view it can draw
# is one slice of a fixed set - so all of it is worked out here instead. The
# 915 questions across 45 split levels come to about 204,000 rows, which is
# small enough to ship as files.
#
# Why the numbers are computed with srvyr rather than a hand-rolled weighted
# proportion: they then come from the same estimator the Shiny app uses, so the
# two cannot disagree. It costs about 14 minutes for the full run, which is a
# price worth paying in a script nobody runs daily.
#
# This script and the site source live together in 10_static_site/. Run it from
# anywhere - the paths resolve with here::here() - for example:
#   Rscript 00_wxdash_2.0/10_static_site/10_build_static_site.R
#
# What this does NOT build, and would need lifting out of 09_wxdash_app/app.R
# rather than copying, is the PDF downloads. The chart PDF has 41,000 possible
# forms and cannot be pre-rendered; the map PDF and the CWA overview sheet could
# be, but their plotting code lives in app.R and a second copy of it here would
# drift from the first.
# This script sits in the same folder as the site source it copies, so the
# copy is filtered: everything in that folder is uploaded to a web server, and
# an R script served at /10_build_static_site.R is source nobody chose to
# publish. The filter is on extension rather than on a list of names, so a file
# added to the folder later is treated as site content unless it is R.
# Two halves that change on different cadences. The question files depend on 05
# and 09 and take about fifteen minutes; the map data and the site files take
# seconds. A change to the map does not touch a single question, so:
#
#   Rscript 00_wxdash_2.0/10_static_site/10_build_static_site.R --map-only
#
# rebuilds the map, the measure list and the HTML/CSS/JS and leaves the question
# files alone. Without the flag everything is rebuilt.
map_only <- "--map-only" %in% commandArgs(trailingOnly = TRUE)

site_dir <- paste0(outputs, "10_site/")
template_dir <- here::here("00_wxdash_2.0", "10_static_site")

app_data <- here::here("00_wxdash_2.0", "09_wxdash_app", "data")

needed <- file.path(app_data, c("09_dashboard_questions.csv",
                                "09_dashboard_responses.rds",
                                "09_dashboard_cwa.rds",
                                "09_dashboard_measure_questions.csv",
                                "09_dashboard_alert_years.csv",
                                "09_dashboard_measures.csv"))

if (!all(file.exists(needed))) {
  print(basename(needed[!file.exists(needed)]))
  stop("Files above are missing - run 09_create_dashboard_data.R first.")
}

if (!dir.exists(template_dir)) {
  stop("No template at ", template_dir, " - the site source moved.")
}

questions <- read_csv(needed[1], show_col_types = FALSE)
responses <- read_rds(needed[2])
cwa_estimates <- read_rds(needed[3])
alert_years <- read_csv(needed[5], show_col_types = FALSE)

# The same menu app.R reads, from the same file 09 wrote. It was declared in
# both files until now, identically and with nothing checking that.
measure_menu <- read_csv(needed[6], show_col_types = FALSE) |>
  arrange(order) |>
  mutate(group = fct_inorder(group))
measure_questions <- read_csv(needed[4], show_col_types = FALSE)

dir.create(paste0(site_dir, "data/q"), recursive = TRUE, showWarnings = FALSE)

# Splits -----------------------------------------------------------------------
# The same twelve the app offers, plus Everyone. Held here rather than read from
# app.R because app.R ends in shinyApp() and cannot be sourced.
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

hazard_phrases <- c(
  "Severe Weather (WX)" = "severe weather",
  "Tropical Cyclone (TC)" = "tropical cyclones",
  "Winter Weather (WW)" = "winter weather",
  "Flooding (FL)" = "flooding"
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

# Years are collapsed into runs so a caption reads "2018-2021, 2024" rather than
# listing nine of them. The gaps are the informative part.
year_runs <- function(years) {
  y <- sort(unique(as.integer(years)))
  ends <- c(which(diff(y) != 1), length(y))
  starts <- c(1, head(ends, -1) + 1)
  runs <- if_else(y[starts] == y[ends], as.character(y[starts]),
                  paste0(y[starts], "-", y[ends]))
  paste(runs, collapse = ", ")
}

option_labels <- function(x) {
  if (is.na(x) || x == "") return(tibble(value = character(),
                                         label = character()))
  parts <- str_split(x, fixed(" | "))[[1]]
  matches <- str_match(parts, "^\\s*(.+?)\\s*=\\s*(.*)$")
  tibble(value = matches[, 2], label = matches[, 3]) |> drop_na()
}

# A file name that survives any web server: the hazard code and the variable,
# with anything else replaced. Two questions can share a variable across
# hazards, which is why the code is part of it.
question_id <- function(variable, hazard) {
  paste0(str_extract(hazard, "(?<=\\()..(?=\\))"), "_",
         str_replace_all(variable, "[^A-Za-z0-9_]", "-"))
}

# Weighted Percentages ---------------------------------------------------------
# One srvyr call per split, not two. The app makes two - proportion = TRUE when
# intervals are shown and FALSE when they are not - but only to dodge the logit
# warning on a cell at 0 or 100%; the point estimates are the same. Checked
# across 3,109 cells here: the largest difference was 2.9e-09, which is eleven
# orders below the two decimal places the page prints.
#
# It matters because the second call is most of the build. With both, a full run
# took over an hour; with one it is about fifteen minutes.
distribution <- function(narrow, grouping) {
  d <- narrow |>
    transmute(
      resp,
      group = if (grouping == "All") "All" else as.character(.data[[grouping]]),
      PERSON_WEIGHT
    ) |>
    drop_na(resp, group, PERSON_WEIGHT)

  if (nrow(d) == 0) return(NULL)

  d |>
    as_survey_design(ids = 1, weights = PERSON_WEIGHT) |>
    group_by(group, resp) |>
    summarize(p = survey_prop(proportion = TRUE, vartype = "ci"),
              .groups = "drop") |>
    mutate(across(c(p, p_low, p_upp), ~round(.x * 100, 2)),
           group = str_remove(as.character(group), "^\\(\\d+\\) "),
           resp = as.character(resp))
}

# The respondent counts the caption quotes, which are the rows the question
# actually rests on rather than the whole wave.
respondent_summary <- function(narrow, grouping) {
  d <- narrow |>
    transmute(
      resp,
      group = if (grouping == "All") "All" else as.character(.data[[grouping]]),
      survey_year, PERSON_WEIGHT
    ) |>
    drop_na(resp, group, PERSON_WEIGHT)

  if (nrow(d) == 0) return(NULL)

  counts <- table(d$group)
  list(
    n = nrow(d),
    years = year_runs(d$survey_year),
    smallest = str_remove(names(counts)[which.min(counts)], "^\\(\\d+\\) "),
    smallest_n = as.integer(min(counts))
  )
}

# The columns every split needs, cut out of the 778-column table once per
# question rather than on each of the thirteen passes over it. Subsetting the
# wide table costs 0.03s a time, which is small until it happens 24,000 times.
split_columns <- unname(groups[groups != "All"])

narrow_for <- function(variable, hazard) {
  responses |>
    filter(survey_hazard == hazard) |>
    select(resp = all_of(variable), all_of(split_columns), survey_year,
           PERSON_WEIGHT)
}

# --map-only is only safe if a previous full run left the question files and
# their index behind. Checked, because the alternative is a site that serves a
# map and an empty question table.
if (map_only && !file.exists(paste0(site_dir, "data/questions.json"))) {
  stop("--map-only needs a previous full build; no data/questions.json found.")
}

if (map_only) {
  message("Map only: reusing the question files already in ", site_dir)
  index <- read_json(paste0(site_dir, "data/questions.json"),
                     simplifyVector = TRUE)
  written <- nrow(index)
} else {

message("Building ", nrow(questions), " questions x ", length(groups),
        " splits. This takes about 15 minutes.")

index <- vector("list", nrow(questions))
written <- 0

for (i in seq_len(nrow(questions))) {
  row <- questions[i, ]
  id <- question_id(row$variable, row$hazard)

  narrow <- narrow_for(row$variable, row$hazard)

  splits <- list()
  summaries <- list()

  for (g in groups) {
    d <- suppressWarnings(distribution(narrow, g))
    if (is.null(d) || nrow(d) == 0) next
    splits[[g]] <- d
    summaries[[g]] <- respondent_summary(narrow, g)
  }

  # A question with nothing to draw under any split is dropped rather than
  # listed and then failing to open.
  if (length(splits) == 0) next

  write_json(
    list(
      id = id,
      variable = row$variable,
      hazard = row$hazard,
      hazard_phrase = unname(hazard_phrases[row$hazard]),
      question = row$question,
      response_scale = row$response_scale,
      options = option_labels(row$response_options),
      splits = splits,
      summaries = summaries
    ),
    paste0(site_dir, "data/q/", id, ".json"),
    auto_unbox = TRUE, na = "null", digits = 4
  )

  written <- written + 1
  index[[i]] <- tibble(
    id = id,
    hazard = row$hazard,
    question = row$question,
    variable = row$variable,
    response_scale = row$response_scale,
    keywords = row$keywords,
    kind = case_when(
      row$experimental & row$graphic_shown ~ "Experiment, graphic",
      row$experimental ~ "Experiment",
      row$graphic_shown ~ "Graphic",
      TRUE ~ "Standard"
    )
  )

  if (i %% 100 == 0) cat("  ", i, "of", nrow(questions), "\n")
}

index <- list_rbind(compact(index))

message("Questions written: ", written, " of ", nrow(questions))

if (nrow(index) == 0) stop("No questions were written - nothing to serve.")

write_json(index, paste0(site_dir, "data/questions.json"),
           auto_unbox = TRUE, na = "null")

}

# Map Data ---------------------------------------------------------------------
# GeoJSON because that is what MapLibre reads directly, with the estimates as
# feature properties so the page needs one request rather than two.
# ALERT_ columns are the alert counts 07 carries: the exposure the models are
# fitted on, not predicted measures. Held out of measure_columns because the
# check below requires survey wording for every measure and these have none.
all_columns <- names(st_drop_geometry(cwa_estimates))
alert_columns <- grep("^ALERT_", all_columns, value = TRUE)
measure_columns <- setdiff(all_columns,
                           c("CWA", "CWA_NAME", "geometry", alert_columns))

cwa_site <- cwa_estimates |>
  mutate(CWA_DISPLAY = paste0(
    "NWS ",
    gsub(" ([A-Za-z]{2})(?=/|$)", ", \\U\\1\\E", CWA_NAME, perl = TRUE)
  )) |>
  select(CWA, CWA_DISPLAY, all_of(measure_columns), all_of(alert_columns))

geojson_path <- paste0(site_dir, "data/cwa.geojson")
if (file.exists(geojson_path)) unlink(geojson_path)
st_write(cwa_site, geojson_path, driver = "GeoJSON", quiet = TRUE)

map_measures <- measure_menu |>
  group_by(group) |>
  group_map(~set_names(.x$measure, .x$label)) |>
  set_names(levels(measure_menu$group))


measures <- imap(map_measures, function(x, group) {
  imap(set_names(unname(x), names(x)), function(measure, label) {
    if (str_starts(measure, "ALERT_")) {
      return(list(
        measure = measure, label = label, group = group, alert = TRUE,
        # From 02 by way of 09, not written here: a literal is wrong the
        # day a 2026 archive is added and nothing would notice.
        span = alert_years |>
          filter(measure == .env$measure) |>
          transmute(s = paste(first_year, "and", last_year)) |>
          pull(s),
        hazard = NA_character_, response_options = NA_character_,
        n_intros = 1L, shared_intro = FALSE, intro = NA_character_,
        items = tibble(question_intro = character(),
                       question_text = character(),
                       reverse_coded = logical())
      ))
    }

    items <- measure_questions |> filter(measure == .env$measure)
    list(
      alert = FALSE,
      measure = measure,
      label = label,
      group = group,
      hazard = items$hazard[1],
      response_options = items$response_options[1],
      n_intros = items$n_intros[1],
      shared_intro = n_distinct(items$question_intro) == 1 &&
        !is.na(items$question_intro[1]),
      intro = items$question_intro[1],
      items = items |> select(question_intro, question_text, reverse_coded)
    )
  }) |> unname()
})

# Offered but absent from the data would be an empty map with no error.
offered <- unlist(map_measures, use.names = FALSE)
missing_measures <- setdiff(offered, c(measure_columns, alert_columns))

if (length(missing_measures) > 0) {
  print(missing_measures)
  stop("Measures above are on the menu but not in the estimates.")
}

write_json(
  list(groups = names(map_measures), measures = unname(measures),
       areas = nrow(cwa_site)),
  paste0(site_dir, "data/measures.json"),
  auto_unbox = TRUE, na = "null", digits = 4
)

# Site Files -------------------------------------------------------------------
# Copied rather than written from here, so the HTML, CSS and JavaScript stay
# editable as themselves under 10_static_site/ instead of inside R strings.
site_files <- list.files(template_dir, full.names = TRUE)
site_files <- site_files[!grepl("\\.[Rr]$", site_files)]

copied <- file.copy(site_files, site_dir, recursive = TRUE, overwrite = TRUE)

if (!all(copied)) {
  print(basename(site_files)[!copied])
  stop("Template files above did not copy.")
}

# Checked rather than trusted: the filter above is the only thing standing
# between the build script and a public URL.
published_r <- list.files(site_dir, pattern = "\\.[Rr]$", recursive = TRUE)

if (length(published_r) > 0) {
  print(published_r)
  stop("R sources above reached the built site - they must not be uploaded.")
}

# Anything the page asks for that is not on disk is a blank panel in a browser
# with no message, so it is checked here instead.
required <- c("index.html", "app.js", "styles.css",
              "data/questions.json", "data/measures.json", "data/cwa.geojson")
absent <- required[!file.exists(paste0(site_dir, required))]

if (length(absent) > 0) {
  print(absent)
  stop("Files above are missing from the built site.")
}

size_mb <- sum(file.size(list.files(site_dir, recursive = TRUE,
                                    full.names = TRUE))) / 1024^2

message("Site written to ", site_dir)
message("  ", written, " question files, ", nrow(cwa_site), " areas, ",
        round(size_mb, 1), " MB total")
message("Upload the contents of that directory to any web host, or preview ",
        "with: python3 -m http.server --directory '", site_dir, "'")
