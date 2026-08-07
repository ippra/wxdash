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
questions <- variable_reference |>
  filter(question_type == "question", n_options >= 2, n_options <= 11)

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
  select(hazard, variable, question, response_scale, response_options,
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

# The five groups the app splits by are the poststratification cells from 04,
# which are also the terms every model in 06 fits. Splitting on anything else
# would show the app cutting the data one way and the estimates another.
group_columns <- c("AGE_GROUP", "GENDER_GROUP", "RACE_GROUP", "EDUC_GROUP",
                   "INCOME_GROUP")

keep_columns <- c(
  "p_id", "survey_hazard", "survey_year", "PERSON_WEIGHT", group_columns,
  unique(questions$variable)
)

responses <- read_csv(
  paste0(outputs, "05_survey_responses.csv"),
  col_select = any_of(keep_columns),
  col_types = cols(p_id = col_character(), .default = col_guess()),
  guess_max = Inf
) # guess_max because a question asked in one wave is empty in the other 21

if (!all(group_columns %in% names(responses))) {
  print(setdiff(group_columns, names(responses)))
  stop("Grouping columns above are missing - the app would offer empty splits.")
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

write_csv(questions, paste0(outputs, "09_dashboard_questions.csv"))
write_rds(responses, paste0(outputs, "09_dashboard_responses.rds"),
          compress = "gz") # rds because the app re-reads it on every restart
