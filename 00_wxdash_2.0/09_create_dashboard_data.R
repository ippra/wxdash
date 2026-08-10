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
         n_options)

# Responses --------------------------------------------------------------------
response_columns <- names(read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  n_max = 0,
  show_col_types = FALSE
))

# The reference covers 6 instruments and the pipeline pools 22 waves, so some
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
app_data <- here::here("00_wxdash_2.0", "10_wxdash_app", "data")
dir.create(app_data, showWarnings = FALSE, recursive = TRUE)

write_csv(questions, file.path(app_data, "09_dashboard_questions.csv"))
write_rds(responses, file.path(app_data, "09_dashboard_responses.rds"),
          compress = "gz") # rds because the app re-reads it on every restart

message("Wrote app data to ", app_data)
