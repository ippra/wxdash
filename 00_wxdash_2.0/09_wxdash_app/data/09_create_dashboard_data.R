library(tidyverse)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# The app reads what this script writes, not 05_survey_responses.csv. That file
# is 2,085 columns and 400 MB, most of it verbatim text the dashboard never
# shows; loading it at app startup takes minutes.

# Questions --------------------------------------------------------------------
# One row per hazard per variable, so a variable asked in more than one survey
# appears once for each, carrying the wording that survey used.
variable_reference <- read_csv(
  here::here("00_wxdash_2.0", "08_create_variable_reference",
             "variable_reference.csv"),
  show_col_types = FALSE
)

# Bar plot of response shares only makes sense for a closed set of options.
# Open text, drop-downs and randomization assignments are dropped by the option
# count; 11 is the cutoff the 1.0 dashboard used.
#
# question_focus keeps the dashboard to questions about weather. The background
# items - age, gender, race, income, education, household size, tenure,
# insurance holdings, numeracy, religion, health and the attention checks - are
# what the responses are split BY, so plotting their distributions would show
# the sample composition rather than anything the survey set out to measure.
plottable <- variable_reference |>
  filter(question_type == "question", n_options >= 2, n_options <= 11)

questions <- plottable |> filter(question_focus == "weather")

message("Questions: ", nrow(plottable), " plottable, ",
        sum(plottable$question_focus == "background"),
        " dropped as background, ", nrow(questions), " kept")

hazard_labels <- c(
  WX = "Severe Weather (WX)",
  TC = "Tropical Cyclone (TC)",
  WW = "Winter Weather (WW)",
  FL = "Flooding (FL)"
)

questions <- questions |>
  mutate(
    hazard = unname(hazard_labels[survey_hazard]),
    # Intro plus item, because neither is the question on its own: risk_tor's
    # text is the single word "Tornadoes", and long_years carries all of its
    # wording in the intro with no text at all. Both sides are coalesced before
    # pasting so a missing one does not print as the string "NA".
    question = str_squish(paste(
      coalesce(question_intro, ""), coalesce(question_text, "")
    ))
  ) |>
  select(hazard, variable, question, keywords, response_scale, response_options,
         n_options, experimental, graphic_shown)

# Responses --------------------------------------------------------------------
response_columns <- names(read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  n_max = 0,
  show_col_types = FALSE
))

# The reference covers 11 instruments and the pipeline pools 22 waves, so some
# reference variables were never fielded in a wave 05 reads. Report the gap
# rather than letting the app fail on an empty column.
missing <- setdiff(unique(questions$variable), response_columns)
message("Questions: ", nrow(questions), " rows, ",
        n_distinct(questions$variable), " variables, ",
        length(missing), " not present in 05_survey_responses.csv")

questions <- questions |> filter(variable %in% response_columns)

# The first five are the poststratification cells from 04, which are also the
# terms every model in 06 fits, so splitting on them cuts the data the same way
# the estimates do.
#
# CENSUS_REGION is the exception: 04 builds it as a county attribute rather than
# a cell dimension, and no model in 06 carries it as a fixed effect. It is
# offered because geography is the first thing anyone asks of these data, and it
# is complete for all 35,457 respondents. Read a regional split as description
# of who answered, not as the geographic signal - that lives in the CWA and
# county random effects, and 07 is where it comes out.
source_groups <- c("AGE_GROUP", "GENDER_GROUP", "RACE_GROUP", "EDUC_GROUP",
                   "INCOME_GROUP", "CENSUS_REGION")

# Splits built below from survey questions rather than read ready made, so they
# are named here and kept out of keep_columns.
derived_groups <- c("RURAL_GROUP", "TENURE_GROUP", "HOME_GROUP",
                    "CHILDREN_GROUP", "SALIENCE_GROUP")

group_columns <- c(source_groups, derived_groups)

# The background questions those five are built from. The question filter above
# drops background items from the question list, so each has to be named here to
# survive the read. All are asked in every wave from 2017 to 2025 and in all four
# hazards, at 98.7% coverage or better.
split_items <- c("rural", "rent", "home", "children", "follow", "plan_around")

# Instrument labels are a phrase each - "Urban lot in a densely populated area" -
# which is right in the reference sheet and unreadable in a plot legend, so each
# is cut to the words that distinguish it. Order follows the instrument coding.
community_labels <- c(
  "1" = "(1) Urban",
  "2" = "(2) Suburban",
  "3" = "(3) Rural"
)

tenure_labels <- c(
  "1" = "(1) Live with family",
  "2" = "(2) Rent",
  "3" = "(3) Own"
)

# Six residence types collapse to five. Boat, boathouse, ship or dock is 52
# respondents across nine waves, which in a single hazard is a bar drawn off a
# handful of people, so it joins Other. Mobile home stays on its own at 5.9%:
# it is the one category here that carries a known structural vulnerability to
# tornadoes and hurricanes, and nothing else in the split list isolates it.
home_labels <- c(
  "1" = "(1) House",
  "2" = "(2) Attached home",
  "3" = "(3) Apartment",
  "4" = "(4) Mobile home",
  "5" = "(5) Other",
  "6" = "(5) Other"
)

# Weather salience is how much attention someone pays to the weather. Two items
# in the opening battery measure it:
#
#   follow       I follow the weather very closely.
#   plan_around  I plan my daily routine around the weather.
#
# und_weather sits in the same battery and was tested with them. It does not
# belong: it correlates -0.04 with follow and +0.07 with plan_around, so
# reverse-coding cannot make it positive with both at once - reversing flips
# both signs together. It measures whether someone understands what causes
# extreme weather, which is knowledge rather than salience.
#
# The two kept items correlate 0.476, giving alpha 0.643, which is what two
# items of that correlation give and is the ceiling for a scale this short.
salience_items <- c("follow", "plan_around")

keep_columns <- c(
  "p_id", "survey_hazard", "survey_year", "PERSON_WEIGHT", source_groups,
  split_items, unique(questions$variable)
)

responses <- read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  col_select = any_of(keep_columns),
  col_types = cols(p_id = col_character(), .default = col_guess()),
  guess_max = Inf
) # guess_max because a question asked in one wave is empty in the other 21

needed <- c(source_groups, split_items)
if (!all(needed %in% names(responses))) {
  print(setdiff(needed, names(responses)))
  stop("Columns above are missing - the app would offer empty splits.")
}

# children arrives as text, not a number, so it is parsed rather than compared.
# Comparing it as text would read "00" and "01" as greater than "0" and count
# three respondents with no children as having some. Values above 20 are set
# aside: the instrument's drop-down stops at "More than 20", so 888, 100 and 99
# are sentinels or typing errors rather than counts. That is 12 respondents.
#
# Salience requires both items rather than one, because a one-item "scale" is a
# different quantity from the two-item mean, not a noisier version of it; 99.1%
# of respondents answer both. It is cut on the response scale rather than into
# equal thirds, so a group means the same thing in every wave and hazard - below
# the neutral point, neutral to mildly agree, and agree or stronger. The result
# is lopsided, with about half the sample in High, because people who answer a
# weather survey follow the weather. That is the finding rather than a binning
# error, and all three groups hold over 5,000 respondents.
responses <- responses |>
  mutate(
    kids = suppressWarnings(as.numeric(children)),
    kids = if_else(kids >= 0 & kids <= 20, kids, NA_real_),
    salience = if_else(
      rowSums(!is.na(pick(all_of(salience_items)))) == length(salience_items),
      rowMeans(pick(all_of(salience_items)), na.rm = TRUE),
      NA_real_
    ),
    RURAL_GROUP = unname(community_labels[as.character(rural)]),
    TENURE_GROUP = unname(tenure_labels[as.character(rent)]),
    HOME_GROUP = unname(home_labels[as.character(home)]),
    CHILDREN_GROUP = case_when(
      kids == 0 ~ "(1) No children",
      kids >= 1 ~ "(2) Has children"
    ),
    SALIENCE_GROUP = case_when(
      salience <  3 ~ "(1) Low",
      salience <  4 ~ "(2) Moderate",
      salience >= 4 ~ "(3) High"
    )
  ) |>
  select(-kids, -salience)

for (g in derived_groups) {
  counts <- table(responses[[g]])
  message(g, ": ",
          paste(names(counts), format(as.integer(counts), big.mark = ","),
                collapse = "; "),
          "; ", sum(is.na(responses[[g]])), " missing")
}

if (!all(hazard_labels %in% responses$survey_hazard)) {
  print(setdiff(hazard_labels, unique(responses$survey_hazard)))
  stop("Hazards above are in the reference but not the responses.")
}

# A question with no weighted responses would draw an empty plot. Drop those
# now, so every row the app lists is a row it can chart.
answered <- questions |>
  mutate(n = map2_int(variable, hazard, \(v, h) {
    sum(!is.na(responses[[v]][responses$survey_hazard == h]) &
          !is.na(responses$PERSON_WEIGHT[responses$survey_hazard == h]))
  }))

message("Questions with no weighted responses: ", sum(answered$n == 0))

questions <- answered |> filter(n > 0) |> select(-n)

responses <- responses |>
  select(p_id, survey_hazard, survey_year, PERSON_WEIGHT, all_of(group_columns),
         all_of(unique(questions$variable)))

# These two land inside the app rather than in outputs/, which is the one place
# this pipeline departs from "every script writes to outputs". A deployed Shiny
# app is a copy of its own directory and nothing else: there is no WXDASH_LOCAL
# on the server, no repo around it, and no 00_paths.R to source. Anything the app
# needs at runtime has to sit beside app.R or it will not be in the bundle.
#
# They are small - 0.3 MB and 3.1 MB - which is what makes this reasonable. If
# either grows past a few tens of MB, the answer is a database or a pin, not a
# bigger file next to the app.
app_dir <- here::here("00_wxdash_2.0", "09_wxdash_app")
app_data <- file.path(app_dir, "data")

# Checked rather than created blind. dir.create() would happily build the
# directory at a path the app does not read, and the app would go on serving the
# copies it already has: a rebuild that reports success and changes nothing.
# Requiring app.R beside the target is what ties the two together.
if (!file.exists(file.path(app_dir, "app.R"))) {
  stop("No app.R in ", app_dir, " - the app directory moved or was renamed. ",
       "Point app_dir at it before writing data it will not read.")
}

dir.create(app_data, showWarnings = FALSE, recursive = TRUE)

write_csv(questions, file.path(app_data, "09_dashboard_questions.csv"))
write_rds(responses, file.path(app_data, "09_dashboard_responses.rds"),
          compress = "gz") # rds because the app re-reads it on every restart

# CWA Estimates ----------------------------------------------------------------
# Copied in rather than rebuilt. 07 already joins the estimates to simplified
# w_16ap26 geometry and checks that every estimate has a polygon; doing it again
# here is the second crosswalk that drifts from the first.
#
# These are model estimates, not weighted response shares like the two files
# above. The map tab says so, because the difference matters: every CWA has a
# number here, including the ones where few people were surveyed.
cwa_path <- paste0(outputs, "07_cwa_estimates_sf.rds")

if (!file.exists(cwa_path)) {
  stop("No 07_cwa_estimates_sf.rds in outputs - run 07 before this script.")
}

cwa_estimates <- read_rds(cwa_path)

# The app selects measures by name, so a rename in 07 has to fail here rather
# than leave the map tab with an empty drop-down.
# The ALERT_ columns 07 carries are the alert counts the models are fitted on,
# not predicted measures. They ride along to the app but are held out here: the
# check below requires every measure to have survey wording, and these have
# none - they come from the NWS archive, not from anything anyone was asked.
measure_columns <- setdiff(
  names(cwa_estimates),
  c("CWA", "CWA_NAME", "geometry",
    grep("^ALERT_", names(cwa_estimates), value = TRUE))
)

if (length(measure_columns) == 0 || !"CWA_NAME" %in% names(cwa_estimates)) {
  print(names(cwa_estimates))
  stop("07_cwa_estimates_sf.rds is missing CWA_NAME or carries no measures.")
}

alert_columns <- grep("^ALERT_", names(cwa_estimates), value = TRUE)

# The measure menu ---------------------------------------------------------
# What the map offers, what each entry is called, and the order it is listed
# in. Held as a spreadsheet beside app.R rather than as code, because it is the
# part that changes most often and it is read by three things: this script, the
# Shiny app, and the static site build. Adding a measure is a row here, in one
# place, in no language.
#
# It lives outside data/ because it is source, not output.
measure_menu <- read_csv(
  here::here("00_wxdash_2.0", "09_wxdash_app", "measures.csv"),
  col_types = cols(order = col_integer(), .default = col_character())
) |>
  arrange(order)

# Checked here so a typo fails at build time with a name, rather than in a
# browser as a map that paints nothing.
unknown <- setdiff(measure_menu$measure, c(measure_columns, alert_columns))

if (length(unknown) > 0) {
  print(unknown)
  stop("measures.csv lists measures above that 07 does not produce.")
}

# The other direction matters too: a measure produced but never listed is
# invisible in both dashboards, which looks like the model was never fitted.
unlisted <- setdiff(c(measure_columns, alert_columns), measure_menu$measure)

if (length(unlisted) > 0) {
  print(unlisted)
  stop("Measures above are produced by 07 but missing from measures.csv.")
}

if (anyDuplicated(measure_menu$measure) > 0 ||
    anyDuplicated(measure_menu$label) > 0) {
  stop("measures.csv has a duplicate measure or label.")
}

# Which years each alert category actually covers, from 02. Carried into the
# app rather than written down there, because a hardcoded "2010 to 2025" is
# wrong the day a 2026 archive is added and nothing would catch it.
alert_years <- read_csv(paste0(outputs, "02_alert_years.csv"),
                        show_col_types = FALSE) |>
  mutate(measure = paste0("ALERT_", CATEGORY)) |>
  filter(measure %in% alert_columns) |>
  select(measure, first_year, last_year)

missing_spans <- setdiff(alert_columns, alert_years$measure)

if (length(missing_spans) > 0) {
  print(missing_spans)
  stop("Alert measures above have no year span - rerun 02.")
}

message("CWA estimates: ", nrow(cwa_estimates), " areas, ",
        length(measure_columns), " measures, ",
        length(alert_columns), " alert counts spanning ",
        min(alert_years$first_year), "-", max(alert_years$last_year))

message("Measure menu: ", nrow(measure_menu), " entries in ",
        n_distinct(measure_menu$group), " groups")

write_rds(cwa_estimates, file.path(app_data, "09_dashboard_cwa.rds"),
          compress = "gz")

# Measure Questions ------------------------------------------------------------
# The exact wording behind each mapped estimate, so the map can say what was
# asked rather than paraphrase it.
#
# Composition comes from 05, which is the only place the item lists are defined.
# Wording comes from the reference, matched on the survey that asked it: the
# same item is worded differently between surveys, and rec_time is the reason
# this matters - it is negative in WX and positive in the other three.
scale_items <- read_csv(paste0(outputs, "05_scale_items.csv"),
                        show_col_types = FALSE)

reference_text <- variable_reference |>
  mutate(hazard = unname(hazard_labels[survey_hazard])) |>
  select(hazard, variable, question_intro, question_text, response_options)

scale_questions <- scale_items |>
  rename(hazard = survey_hazard) |>
  left_join(reference_text, by = c("hazard", "variable"))

# A scale item with no wording would print as a blank bullet under the map.
unmatched <- scale_questions |> filter(is.na(question_text))

if (nrow(unmatched) > 0) {
  print(unmatched |> select(measure, hazard, variable))
  stop("Scale items above have no wording in the variable reference.")
}

# The risk items are single questions rather than scales, and 06 pools all four
# surveys for them. The item text is identical across surveys - "Tornadoes" -
# but the intro is not, so the most widely used intro is carried along with a
# count of how many wordings exist, and the app says so when there is more
# than one.
risk_measures <- measure_columns[str_starts(measure_columns, "RISK_")]

risk_questions <- tibble(
  measure = risk_measures,
  variable = str_to_lower(risk_measures)
) |>
  left_join(
    reference_text |>
      filter(variable %in% str_to_lower(risk_measures)) |>
      group_by(variable) |>
      summarise(
        # Counted before question_intro is collapsed below. summarise() lets a
        # later expression see an earlier result, so putting these the other way
        # round counts the one surviving value and reports 1 every time.
        n_intros = n_distinct(question_intro),
        question_intro = names(sort(table(question_intro),
                                    decreasing = TRUE))[1],
        question_text = first(question_text),
        response_options = first(response_options),
        .groups = "drop"
      ),
    by = "variable"
  ) |>
  mutate(hazard = NA_character_, reverse_coded = FALSE, scale = NA_character_)

missing_risk <- risk_questions |> filter(is.na(question_text))

if (nrow(missing_risk) > 0) {
  print(missing_risk |> select(measure, variable))
  stop("Risk items above have no wording in the variable reference.")
}

measure_questions <- bind_rows(
  scale_questions |> mutate(n_intros = 1L),
  risk_questions
) |>
  select(measure, hazard, variable, question_intro, question_text,
         response_options, reverse_coded, n_intros)

# The map offers one entry per measure it carries, so anything without wording
# here would render a map with nothing said underneath it.
no_questions <- setdiff(measure_columns, measure_questions$measure)

if (length(no_questions) > 0) {
  print(no_questions)
  stop("Measures above are mapped but have no question wording.")
}

message("Measure questions: ", nrow(measure_questions), " items across ",
        n_distinct(measure_questions$measure), " measures")

write_csv(measure_questions,
          file.path(app_data, "09_dashboard_measure_questions.csv"))

write_csv(alert_years, file.path(app_data, "09_dashboard_alert_years.csv"))
write_csv(measure_menu, file.path(app_data, "09_dashboard_measures.csv"))

message("Wrote app data to ", app_data)
