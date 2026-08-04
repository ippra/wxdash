library(tidyverse)
library(lme4)

outputs <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Model Fits -------------------------------------------------------------------
# Saved by 06. Reading them rather than refitting keeps these estimates tied to
# the models that were reviewed there.
to_recep_fit <- read_rds(paste0(outputs, "models/to_recep_fit.rds"))
hu_recep_fit <- read_rds(paste0(outputs, "models/hu_recep_fit.rds"))
ww_recep_fit <- read_rds(paste0(outputs, "models/ww_recep_fit.rds"))
fl_recep_fit <- read_rds(paste0(outputs, "models/fl_recep_fit.rds"))

# Poststratification Frame -----------------------------------------------------
# The table from 04 carries demographics and population but none of the area
# covariates, which are county- and CWA-level and would repeat across all 192
# cells of a county. They join on here instead of being stored 192 times over.
#
# Only the five hazards the models use are taken from each alert file. Selecting
# them explicitly avoids the leftover hazard columns arriving unprefixed, which
# is what happens in 05 where COLD, FIRE and WIND fall outside the rename range.
poststrat_data <- read_csv(
  paste0(outputs, "base_county_poststrat_data_2024.csv"),
  col_types = cols(
    STATE = col_character(),
    COUNTY = col_character(),
    FIPS = col_character(),
    CWA = col_character(),
    .default = col_guess()
  )
)

county_alert_data <- read_csv(
  paste0(outputs, "base_county_alert_data.csv"),
  col_types = cols(GEOID = col_character(), .default = col_guess())
) |>
  select(FIPS = GEOID, TORN, HURR, SNOW, ICE, FLOOD) |>
  rename_with(~paste0("FIPS_", .x), .cols = -FIPS)

cwa_alert_data <- read_csv(
  paste0(outputs, "base_cwa_alert_data.csv"),
  col_types = cols(WFO = col_character(), .default = col_guess())
) |>
  select(CWA = WFO, TORN, HURR, SNOW, ICE, FLOOD) |>
  rename_with(~paste0("CWA_", .x), .cols = -CWA)

county_covariates <- read_csv(
  paste0(outputs, "base_county_covariates.csv"),
  col_types = cols(FIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) |> # guess_max as in 04: four NRI *_EVNTS columns start empty
  select(FIPS, SVI_RPL_THEMES)

poststrat_data <- poststrat_data |>
  left_join(county_alert_data, by = "FIPS") |>
  left_join(cwa_alert_data, by = "CWA") |>
  left_join(county_covariates, by = "FIPS")

# A cell missing any predictor predicts NA, and its county would then drop from
# the estimates with nothing said. Check before predicting, not after.
predictor_na <- poststrat_data |>
  summarise(
    across(
      c(FIPS_TORN, CWA_TORN, FIPS_HURR, CWA_HURR, FIPS_SNOW, FIPS_ICE,
        CWA_SNOW, CWA_ICE, FIPS_FLOOD, CWA_FLOOD, SVI_RPL_THEMES),
      ~sum(is.na(.x))
    )
  ) |>
  pivot_longer(everything(), names_to = "predictor", values_to = "missing") |>
  filter(missing > 0)

if (nrow(predictor_na) > 0) {
  print(predictor_na)
  stop("Predictors above are missing - their counties would drop out silently.")
}

message("Poststrat frame: ", format(nrow(poststrat_data), big.mark = ","),
        " cells; ", n_distinct(poststrat_data$FIPS), " counties; ",
        n_distinct(poststrat_data$CWA), " CWAs")

# Cell Predictions -------------------------------------------------------------
# re.form keeps the CWA and county effects and drops (1 | survey_year), so each
# estimate describes an average year rather than whichever years that outcome
# happened to be fielded in -- tornado ran 2017-2025, flood only 2024-2025.
#
# allow.new.levels covers counties and CWAs with no respondents. Their random
# effect is zero, leaving demographic composition plus the area covariates.
year_free <- ~ (1 | CWA) + (1 | FIPS)

predict_cells <- function(fit) {
  predict(
    fit,
    newdata = poststrat_data,
    re.form = year_free,
    allow.new.levels = TRUE
  )
}

cell_predictions <- poststrat_data |>
  mutate(
    TO_RECEP = predict_cells(to_recep_fit),
    HU_RECEP = predict_cells(hu_recep_fit),
    WW_RECEP = predict_cells(ww_recep_fit),
    FL_RECEP = predict_cells(fl_recep_fit)
  ) |>
  pivot_longer(
    c(TO_RECEP, HU_RECEP, WW_RECEP, FL_RECEP),
    names_to = "measure",
    values_to = "cell_estimate"
  )

# County Estimates -------------------------------------------------------------
# DEMGRP_PROP is a cell's share of its county's adults and sums to exactly 1
# within a county, so this is a population-weighted mean over the 192 cells.
county_estimates <- cell_predictions |>
  group_by(STATE_NAME, NAME, FIPS, CWA, measure) |>
  summarise(estimate = sum(cell_estimate * DEMGRP_PROP), .groups = "drop")

# CWA Estimates ----------------------------------------------------------------
# Aggregated from the same cell predictions rather than fitted separately. That
# is what makes the two levels agree, and the check below proves it: weighting a
# CWA's county estimates by their adult populations returns this same number.
cwa_estimates <- cell_predictions |>
  group_by(CWA, measure) |>
  summarise(
    estimate = weighted.mean(cell_estimate, DEMGRP_POP),
    .groups = "drop"
  )

county_populations <- poststrat_data |>
  distinct(FIPS, CWA, ADULT_POP)

agreement_check <- county_estimates |>
  left_join(county_populations, by = c("FIPS", "CWA")) |>
  group_by(CWA, measure) |>
  summarise(rebuilt = weighted.mean(estimate, ADULT_POP), .groups = "drop") |>
  left_join(cwa_estimates, by = c("CWA", "measure")) |>
  mutate(gap = abs(rebuilt - estimate))

message("CWA agreement: max gap between direct and rebuilt estimates ",
        format(max(agreement_check$gap), scientific = TRUE, digits = 3))

if (max(agreement_check$gap) > 1e-8) {
  print(agreement_check |> slice_max(gap, n = 10))
  stop("CWA estimates do not match aggregation from their counties.")
}

# Output Data ------------------------------------------------------------------
# Long format, one row per area per measure, matching what the previous
# generation of prediction scripts produced.
write_csv(county_estimates, paste0(outputs, "base_county_estimates.csv"))
write_csv(cwa_estimates, paste0(outputs, "base_cwa_estimates.csv"))
