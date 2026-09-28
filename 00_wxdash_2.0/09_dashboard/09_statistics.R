library(tidyverse)
library(srvyr)
library(sf)
library(jsonlite)

source(here::here("00_wxdash_2.0", "00_paths.R"))
require_roots()
source(here::here("00_wxdash_2.0", "09_dashboard", "09_rcode.R"))

# Statistics -------------------------------------------------------------------
# Every number the dashboard shows is computed here, and nowhere else. Sourced
# by 09_build_dashboard.R under --data; it is not run on its own.
#
# It reads the variable reference from 08, the pooled survey data from 05, the
# model estimates from 07 and the alert spans from 02, and writes
# 09_dashboard/data/ - the question files, the R that rebuilds each of their
# charts, the measure menu and the map. The assembly half then reads that
# directory and nothing else.
#
# That directory is committed, so assembly runs from a plain clone. This half
# does not: it needs both roots and the pipeline outputs, and it is the reason
# they are still required anywhere.
#
# The two halves are separate because they change on different cadences and
# cost three orders of magnitude apart: this one reads a 400 MB file and runs
# about 24,000 srvyr calls, and takes roughly fifteen minutes; assembly takes
# seconds. Iterating on the front end should not cost a coffee break, so the
# directory this writes is the boundary between them.

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
    )),
    # The two halves are also kept apart, because the stem is the same sentence
    # on every item of a battery and the item is what changes. The front ends
    # quiet the stem and show the item, so a row reads "Tornadoes" under the
    # question it answers rather than on its own.
    #
    # A question with no item of its own is one whose stem is the whole
    # question: it becomes the item, and there is no stem left above it.
    question_intro = if_else(is.na(question_text), NA_character_,
                             question_intro),
    question_text = coalesce(question_text, question)
  ) |>
  select(hazard, variable, question, question_intro, question_text, keywords,
         response_scale, response_options, n_options, experimental,
         graphic_shown)

# Split-Sample Questions -------------------------------------------------------
# Some questions were asked of everyone but not in the same words: the wording
# varied by a randomization variable the instrument records beside the answer.
# Those are estimated one version at a time, because pooling them averages
# across the treatment and reports a number nobody was asked.
#
# Two declarations, because they answer different questions and grow at
# different rates. question_arms.csv says which randomizer governs a question -
# one row per question, and the reference does not record this, so it is read
# off the instruments. arms.csv is the roster: the prompt above the menu and a
# label and order for each value, since the raw values are codes as often as
# they are words (`spc_high_ero_slight`, `1`).
#
# Read here rather than beside the loop that uses them, because a randomizer is
# not a charted question and would not otherwise survive the column selection
# below.
# `script_value` is the same version as the wave file spells it, for the rare
# column where that differs from the pooled table: the hour randomizers are
# "10:00:00" here and "10:00" there, because 05 parsed them as times on the way
# through. Left empty everywhere else, and nothing checks it directly - the
# generated script is run against the wave file and compared with the chart it
# claims to rebuild, so a wrong spelling fails as a script that matches no rows.
arms_roster <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "arms.csv"),
  col_types = cols(arm_order = col_integer(), .default = col_character())
) |>
  mutate(script_value = coalesce(script_value, value)) |>
  arrange(arm_variable, arm_order)

question_arms <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "question_arms.csv"),
  col_types = cols(.default = col_character())
)

# A prompt is a property of the randomizer, not of one of its values, so more
# than one would mean the menu says different things on different questions.
multi_prompt <- arms_roster |>
  summarise(n = n_distinct(prompt), .by = arm_variable) |>
  filter(n > 1)

if (nrow(multi_prompt) > 0) {
  print(multi_prompt)
  stop("Randomizers above carry more than one prompt in arms.csv.")
}

unrostered <- setdiff(question_arms$arm_variable, arms_roster$arm_variable)

if (length(unrostered) > 0) {
  print(unrostered)
  stop("Randomizers above are named in question_arms.csv but not in arms.csv.")
}

arm_columns <- unique(question_arms$arm_variable)

# Responses --------------------------------------------------------------------
response_columns <- names(read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  n_max = 0,
  show_col_types = FALSE
))

# The reference covers 11 instruments and the pipeline pools 22 waves, so some
# reference variables were never fielded in a wave 05 reads. Report the gap
# rather than letting the build fail on an empty column.
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

# The background questions those five are built from. The question filter
# above drops background items from the question list, so each has to be named
# here to survive the read. All are asked in every wave from 2017 to 2025 and
# in all four hazards, at 98.7% coverage or better.
split_items <- c("rural", "rent", "home", "children", "follow", "plan_around")

# Instrument labels are a phrase each - "Urban lot in a densely populated
# area" - which is right in the reference sheet and unreadable in a plot
# legend, so each is cut to the words that distinguish it. Order follows the
# instrument coding.
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
  split_items, arm_columns, unique(questions$variable)
)

# Randomization columns are read as text rather than guessed. `rand_aft` holds
# "10:00" in the wave file, which 05's guessing read parses as a time and
# writes back as "10:00:00"; guessing again here turns it into an hms whose
# distinct values come out as seconds since midnight. A version menu built on
# that would be labelled 36000.
arm_types <- set_names(rep(list(col_character()), length(arm_columns)),
                       arm_columns)

responses <- read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  col_select = any_of(keep_columns),
  col_types = do.call(cols, c(list(p_id = col_character()), arm_types,
                              list(.default = col_guess()))),
  guess_max = Inf
) # guess_max because a question asked in one wave is empty in the other 21

needed <- c(source_groups, split_items)
if (!all(needed %in% names(responses))) {
  print(setdiff(needed, names(responses)))
  stop("Columns above are missing - the site would offer empty splits.")
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
# now, so every row the question table lists is a row it can chart.
answered <- questions |>
  mutate(n = map2_int(variable, hazard, \(v, h) {
    sum(!is.na(responses[[v]][responses$survey_hazard == h]) &
          !is.na(responses$PERSON_WEIGHT[responses$survey_hazard == h]))
  }))

message("Questions with no weighted responses: ", sum(answered$n == 0))

questions <- answered |> filter(n > 0) |> select(-n)

responses <- responses |>
  select(p_id, survey_hazard, survey_year, PERSON_WEIGHT, all_of(group_columns),
         all_of(arm_columns), all_of(unique(questions$variable)))

# The landing page quotes the respondent total and the years covered, which no
# other output carries. Written here because this is where the table exists;
# counting it during assembly would mean reading the 400 MB file twice.
dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
# surveys is respondents per hazard and year: the landing page draws one dot
# per 50 of them, accumulating year on year.
surveys_count_data <- responses |>
  count(survey_hazard, survey_year = as.integer(survey_year)) |>
  arrange(survey_year, survey_hazard)

write_json(
  list(rows = nrow(responses),
       years = sort(unique(as.integer(responses$survey_year))),
       surveys = surveys_count_data),
  paste0(data_dir, "respondents.json"), auto_unbox = TRUE
)

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

# The map selects measures by name, so a rename in 07 has to fail here rather
# than leave the menu with an empty drop-down.
# The ALERT_ columns 07 carries are the alert counts the models are fitted on,
# not predicted measures. They ride along to the map but are held out here: the
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
# in. Held as a spreadsheet rather than as code, because it is the part that
# changes most often and both halves of the build read it. Adding a measure is
# a row here, in one place, in no language.
#
# It sits beside the build scripts rather than in outputs/, because it is
# source, not output.
measure_menu <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "measures.csv"),
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
# invisible on the map, which looks like the model was never fitted.
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
# count of how many wordings exist, and the page says so when there is more
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

# The map lists its groups in menu order rather than alphabetically, so the
# column is a factor in the order the file gives.
measure_menu <- measure_menu |> mutate(group = fct_inorder(group))


# Splits -----------------------------------------------------------------------
# The same twelve the front end offers, plus Everyone. Declared here and again
# in site/engine.js, which is the one duplication left in the split roster.
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
# One srvyr call per split, not two. Two estimators are in play - proportion =
# TRUE when intervals are shown and FALSE when they are not - but the second
# only dodges the logit warning on a cell at 0 or 100%; the point estimates are
# the same. Checked across 3,109 cells: the largest difference was 2.9e-09,
# which is eleven orders below the two decimal places the page prints.
#
# It matters because the second call is most of the build. With both, a full
# run took over an hour; with one it is about fifteen minutes.
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

narrow_for <- function(variable, hazard, arm_variable = NA_character_) {
  d <- responses |> filter(survey_hazard == hazard)
  if (is.na(arm_variable)) {
    d |> select(resp = all_of(variable), all_of(split_columns), survey_year,
                PERSON_WEIGHT)
  } else {
    d |> select(resp = all_of(variable), arm = all_of(arm_variable),
                all_of(split_columns), survey_year, PERSON_WEIGHT)
  }
}

# Checked against the data rather than trusted: a pairing that names a column
# no wave carries, or whose values never appear, would draw an empty menu.
for (v in arm_columns) {
  if (!v %in% names(responses)) {
    stop("`", v, "` is declared in question_arms.csv but is not a column in ",
         "the survey data.")
  }
  declared <- arms_roster$value[arms_roster$arm_variable == v]
  seen <- unique(na.omit(responses[[v]]))
  absent <- setdiff(seen, declared)
  if (length(absent) > 0) {
    print(absent)
    stop("`", v, "` takes the values above in the data, and arms.csv does not ",
         "list them - they would vanish from the menu.")
  }
}

missing_pairs <- question_arms |>
  anti_join(questions, by = c("hazard", "variable"))

if (nrow(missing_pairs) > 0) {
  print(missing_pairs)
  stop("Questions above are paired with a randomizer but are not charted.")
}

message("Split-sample questions: ", nrow(question_arms), " across ",
        n_distinct(question_arms$arm_variable), " randomizers")

# The versions a question offers, in roster order, keeping only those its own
# respondents actually fall into.
arms_for <- function(variable, hazard, narrow) {
  v <- question_arms$arm_variable[question_arms$variable == variable &
                                    question_arms$hazard == hazard]
  if (length(v) == 0) return(NULL)
  roster <- arms_roster |> filter(arm_variable == v)
  present <- unique(na.omit(narrow$arm[!is.na(narrow$resp)]))
  roster <- roster |> filter(value %in% present)
  if (nrow(roster) < 2) return(NULL)   # one version is not an experiment
  list(variable = v, prompt = roster$prompt[1], roster = roster)
}

# Reproduction Scripts ---------------------------------------------------------
# The wave files the generated scripts send a reader to. Their headers are read
# here so a script naming a column its wave file does not carry is caught now
# rather than by whoever runs it - a reader cannot tell a generator bug from
# their own mistake.
wave_codes <- responses |>
  distinct(survey_hazard, survey_year) |>
  transmute(wave = wave_of(survey_hazard, survey_year)) |>
  pull(wave) |>
  sort()

wave_paths <- paste0(survey_files, wave_codes, "_data_wtd.csv")

if (!all(file.exists(wave_paths))) {
  print(basename(wave_paths)[!file.exists(wave_paths)])
  stop("Wave files above are missing - the generated scripts would name them.")
}

wave_headers <- map(set_names(wave_paths, wave_codes),
                    ~names(read_csv(.x, n_max = 0, show_col_types = FALSE)))

script_columns <- c(
  "PERSON_WEIGHT",
  setdiff(split_columns, c(names(derive_sources), "survey_year")),
  unlist(derive_sources, use.names = FALSE)
)

absent_columns <- imap(wave_headers, ~setdiff(script_columns, .x)) |>
  keep(~length(.x) > 0)

if (length(absent_columns) > 0) {
  print(absent_columns)
  stop("Wave files above lack columns above - a script would name them anyway.")
}

# WX17 asked the reception and response batteries on a 1-7 scale, so 05 drops
# those columns rather than pooling them. A generated script that reads WX18
# onward for a question WX17 plainly asked owes the reader that sentence.
wx17_columns <- if ("WX17" %in% wave_codes) wave_headers[["WX17"]] else
  character(0)

# Hidden Questions -------------------------------------------------------------
# Questions the dashboard should not list. Flagged in the browser with `?flag=1`
# and exported from there, so triage happens where the problem is visible rather
# than against a list of variable names.
#
# Only `hide` drops a question. The other dispositions are notes kept beside it
# - a question that needs context it does not have, or one that belongs on a
# page built for experiments - so one pass through the site does not have to be
# made twice.
hidden <- read_csv(
  here::here("00_wxdash_2.0", "09_dashboard", "hidden_questions.csv"),
  col_types = cols(.default = col_character())
)

dispositions <- c("hide", "needs-context", "experiments-page")
question_ids <- question_id(questions$variable, questions$hazard)

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
  stop("Dispositions above are not one of: ", paste(dispositions,
                                                    collapse = ", "))
}

drop_ids <- hidden$id[hidden$disposition == "hide"]
questions <- questions[!question_ids %in% drop_ids, ]

if (nrow(hidden) > 0) {
  message("Hidden questions: ", length(drop_ids), " dropped, ",
          nrow(hidden) - length(drop_ids), " flagged without dropping")
}

rcode <- new_rcode_tally()

# Which scripts get run. Every hazard by every split is checked once - each
# derived grouping writes its own case_when, so an error in one would not show
# up in another - and then one Everyone script per response scale, which is
# where a levels/labels pairing would drift. Running all ~11,900 would add
# hours for no more coverage than this.
checked_shape <- character(0)
checked_scale <- character(0)

# Emptied rather than written over, for the reason assembly rebuilds the site
# from scratch: a question dropped upstream would otherwise survive as a file
# nothing writes and nothing removes. This directory is committed, so a
# survivor would be permanent.
for (d in c("q", "rcode")) {
  unlink(paste0(data_dir, d), recursive = TRUE)
  dir.create(paste0(data_dir, d), recursive = TRUE, showWarnings = FALSE)
}

message("Building ", nrow(questions), " questions x ", length(groups),
        " splits. This takes about 15 minutes.")

index <- vector("list", nrow(questions))
written <- 0

for (i in seq_len(nrow(questions))) {
  row <- questions[i, ]
  id <- question_id(row$variable, row$hazard)

  arm_var <- question_arms$arm_variable[
    question_arms$variable == row$variable & question_arms$hazard == row$hazard]
  narrow <- narrow_for(row$variable, row$hazard,
                       if (length(arm_var) == 1) arm_var else NA_character_)
  arms <- arms_for(row$variable, row$hazard, narrow)

  # One pass per version, or a single pooled pass where the question was asked
  # the same way of everyone. A version is estimated on its own: pooling would
  # average across the treatment and report a number nobody was asked.
  arm_keys <- if (is.null(arms)) NA_character_ else arms$roster$value
  per_arm <- list()

  for (ak in arm_keys) {
    nar <- if (is.na(ak)) narrow else filter(narrow, arm == ak)
    s <- list()
    su <- list()
    for (g in groups) {
      d <- suppressWarnings(distribution(nar, g))
      if (is.null(d) || nrow(d) == 0) next
      s[[g]] <- d
      su[[g]] <- respondent_summary(nar, g)
    }
    if (length(s) == 0) next
    per_arm[[if (is.na(ak)) "all" else ak]] <- list(splits = s, summaries = su)
  }

  # A question with nothing to draw under any split is dropped rather than
  # listed and then failing to open. So is a split-sample question left with
  # one version, which is no longer a comparison.
  if (length(per_arm) == 0) next
  if (!is.null(arms) && length(per_arm) < 2) next

  armed <- !is.null(arms) && length(per_arm) >= 2

  splits <- if (armed) map(per_arm, "splits") else per_arm[["all"]]$splits
  summaries <- if (armed) map(per_arm, "summaries") else
    per_arm[["all"]]$summaries

  # The R that rebuilds each of these charts, written by the script that just
  # computed them. Keyed by split the same way the splits themselves are, so
  # the front ends do a lookup and compose nothing.
  q_options <- option_labels(row$response_options)
  years <- sort(unique(narrow$survey_year[!is.na(narrow$resp)]))
  waves <- wave_of(row$hazard, years)

  # A code the instrument does not document is drawn as itself on the page, so
  # the script labels it as itself rather than dropping it to NA. Taken across
  # every version, so a code only one version elicited still gets a label.
  # Sorted as a number where it is one: as text, 10 sorts between 1 and 2.
  seen_resp <- unique(unlist(map(per_arm, ~ .x$splits[["All"]]$resp)))
  extra <- setdiff(seen_resp, q_options$value)
  extra <- extra[order(suppressWarnings(as.numeric(extra)), extra)]
  resp_levels <- tibble(value = c(q_options$value, extra),
                        label = c(q_options$label, extra))

  wx17_note <- row$hazard == "Severe Weather (WX)" &&
    !("2017" %in% years) && row$variable %in% wx17_columns

  # One script per (version, split), keyed the way the splits are: nested under
  # the version for a split-sample question, flat for every other, so the front
  # end reads whichever shape the question file already told it to expect.
  scripts <- list()
  checks <- list()

  for (ak in names(per_arm)) {
    arm_row <- if (armed) arms$roster |> filter(value == ak) else NULL
    per_split <- list()
    for (g in names(per_arm[[ak]]$splits)) {
      # Instrument order, which is what the prefixes in the data encode, rather
      # than the alphabetical order a plain sort would give. Levels a split has
      # in the data but not in this question's rows are dropped, so the legend
      # is the groups the chart actually draws.
      group_levels <- if (g == "All") NULL else {
        lv <- str_remove(sort(unique(na.omit(as.character(narrow[[g]])))),
                         "^\\(\\d+\\) ")
        lv[lv %in% per_arm[[ak]]$splits[[g]]$group]
      }
      per_split[[g]] <- r_script(
        question = row$question, variable = row$variable, hazard = row$hazard,
        waves = waves, years = years, split = g,
        split_label = names(groups)[match(g, groups)],
        level_values = resp_levels$value, level_labels = resp_levels$label,
        group_order = group_levels, wx17_note = wx17_note,
        arm_column = if (armed) arms$variable else NULL,
        arm_value = if (armed) arm_row$script_value else NULL,
        arm_label = if (armed) arm_row$label else NULL
      )
      checks[[paste(ak, g)]] <- list(arm = ak, split = g)
    }
    if (armed) scripts[[ak]] <- per_split else scripts <- per_split
  }

  rcode$scripts <- rcode$scripts + length(checks)
  write_json(scripts, paste0(data_dir, "rcode/", id, ".json"),
             auto_unbox = TRUE, na = "null")

  script_at <- function(ak, g) if (armed) scripts[[ak]][[g]] else scripts[[g]]

  for (k in names(checks)) {
    ak <- checks[[k]]$arm
    g <- checks[[k]]$split
    # Every version of a split-sample question is checked: the arm filter is
    # the one line the generator writes that nothing else exercises.
    shape <- if (armed) paste(row$hazard, g, ak) else paste(row$hazard, g)
    scale_key <- if (g == "All") coalesce(row$response_scale, "(none)") else NA
    if (!armed && shape %in% checked_shape &&
        (is.na(scale_key) || scale_key %in% checked_scale)) next
    verify_r_code(script_at(ak, g), per_arm[[ak]]$splits[[g]], resp_levels,
                  paste(id, k), rcode)
    checked_shape <- c(checked_shape, shape)
    if (!is.na(scale_key)) checked_scale <- c(checked_scale, scale_key)
  }

  q_json <- list(
    id = id,
    variable = row$variable,
    hazard = row$hazard,
    hazard_phrase = unname(hazard_phrases[row$hazard]),
    question = row$question,
    # The stem and the item apart, so the heading can quiet the sentence
    # every item of a battery shares. `question` stays as the one string
    # anything needing a whole question uses - the PDF title, the search,
    # the title of the R script that rebuilds this chart.
    question_intro = row$question_intro,
    question_text = row$question_text,
    response_scale = row$response_scale,
    options = q_options,
    has_r_code = length(checks) > 0
  )

  # Added rather than set to NULL, because `list(arms = NULL)` serialises as
  # "arms":{} and every question in the dashboard would then carry an empty
  # key. Presence is the signal the front end reads, so it has to be absent.
  if (armed) {
    q_json$arms <- arms$roster |> select(id = value, label)
    q_json$arm_prompt <- arms$prompt
  }

  q_json$splits <- splits
  q_json$summaries <- summaries

  write_json(q_json, paste0(data_dir, "q/", id, ".json"),
             auto_unbox = TRUE, na = "null", digits = 4)

  written <- written + 1
  index[[i]] <- tibble(
    id = id,
    hazard = row$hazard,
    question = row$question,
    question_intro = row$question_intro,
    question_text = row$question_text,
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
message("Reproduction scripts: ", rcode$scripts, " written, ", rcode$checks,
        " run and checked against the chart they rebuild")

if (nrow(index) == 0) stop("No questions were written - nothing to serve.")

write_json(index, paste0(data_dir, "questions.json"),
           auto_unbox = TRUE, na = "null")

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

geojson_path <- paste0(data_dir, "cwa.geojson")
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
  paste0(data_dir, "measures.json"),
  auto_unbox = TRUE, na = "null", digits = 4
)

message("Statistics written to ", data_dir)
