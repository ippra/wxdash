library(tidyverse)
library(lme4)
library(sf)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Model Fits -------------------------------------------------------------------
# Saved by 06. Reading them rather than refitting keeps these estimates tied to
# the models that were reviewed there.
risk_drought_fit <- read_rds(paste0(outputs, "06_models/risk_drought_fit.rds"))
risk_hail_fit <- read_rds(paste0(outputs, "06_models/risk_hail_fit.rds"))
risk_lignt_fit <- read_rds(paste0(outputs, "06_models/risk_lignt_fit.rds"))

to_recep_fit <- read_rds(paste0(outputs, "06_models/to_recep_fit.rds"))
hu_recep_fit <- read_rds(paste0(outputs, "06_models/hu_recep_fit.rds"))
ww_recep_fit <- read_rds(paste0(outputs, "06_models/ww_recep_fit.rds"))
fl_recep_fit <- read_rds(paste0(outputs, "06_models/fl_recep_fit.rds"))

to_subj_comp_fit <- read_rds(paste0(outputs, "06_models/to_subj_comp_fit.rds"))
hu_subj_comp_fit <- read_rds(paste0(outputs, "06_models/hu_subj_comp_fit.rds"))
ww_subj_comp_fit <- read_rds(paste0(outputs, "06_models/ww_subj_comp_fit.rds"))
fl_subj_comp_fit <- read_rds(paste0(outputs, "06_models/fl_subj_comp_fit.rds"))

to_resp_fit <- read_rds(paste0(outputs, "06_models/to_resp_fit.rds"))
hu_resp_fit <- read_rds(paste0(outputs, "06_models/hu_resp_fit.rds"))
ww_resp_fit <- read_rds(paste0(outputs, "06_models/ww_resp_fit.rds"))
fl_resp_fit <- read_rds(paste0(outputs, "06_models/fl_resp_fit.rds"))

risk_tor_fit <- read_rds(paste0(outputs, "06_models/risk_tor_fit.rds"))
risk_hur_fit <- read_rds(paste0(outputs, "06_models/risk_hur_fit.rds"))
risk_surge_fit <- read_rds(paste0(outputs, "06_models/risk_surge_fit.rds"))
risk_snow_fit <- read_rds(paste0(outputs, "06_models/risk_snow_fit.rds"))
risk_ice_fit <- read_rds(paste0(outputs, "06_models/risk_ice_fit.rds"))
risk_cold_fit <- read_rds(paste0(outputs, "06_models/risk_cold_fit.rds"))
risk_heat_fit <- read_rds(paste0(outputs, "06_models/risk_heat_fit.rds"))
risk_flood_fit <- read_rds(paste0(outputs, "06_models/risk_flood_fit.rds"))
risk_fire_fit <- read_rds(paste0(outputs, "06_models/risk_fire_fit.rds"))

# Poststratification Frame -----------------------------------------------------
# The table from 04 carries demographics and population but none of the area
# covariates, which are county- and CWA-level and would repeat across all 192
# cells of a county. They join on here instead of being stored 192 times over.
#
# Only the hazards the models use are taken from each alert file. Selecting
# them explicitly avoids the leftover hazard columns arriving unprefixed, which
# is what happens in 05 where COLD, FIRE and WIND fall outside the rename range.
poststrat_data <- read_csv(
  paste0(outputs, "04_county_poststrat_2024.csv"),
  col_types = cols(
    STATE = col_character(),
    COUNTY = col_character(),
    FIPS = col_character(),
    CWA = col_character(),
    .default = col_guess()
  )
)

model_hazards <- c(
  "COLD", "FIRE", "FLOOD", "HEAT", "HURR", "ICE", "SNOW", "SURG", "TORN"
)

county_alert_data <- read_csv(
  paste0(outputs, "03_county_alert_counts.csv"),
  col_types = cols(GEOID = col_character(), .default = col_guess())
) |>
  select(FIPS = GEOID, all_of(model_hazards)) |>
  rename_with(~paste0("FIPS_", .x), .cols = -FIPS)

cwa_alert_data <- read_csv(
  paste0(outputs, "02_cwa_alert_counts.csv"),
  col_types = cols(WFO = col_character(), .default = col_guess())
) |>
  select(CWA = WFO, all_of(model_hazards)) |>
  rename_with(~paste0("CWA_", .x), .cols = -CWA)

# The three NRI frequencies carry the risk models for hazards NWS does not warn
# on -- drought, hail and lightning.
county_covariates <- read_csv(
  paste0(outputs, "04_county_covariates.csv"),
  col_types = cols(FIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) |> # guess_max as in 04: four NRI *_EVNTS columns start empty
  select(FIPS, SVI_RPL_THEMES, NRI_DRGT_AFREQ, NRI_HAIL_AFREQ, NRI_LTNG_AFREQ)

poststrat_data <- poststrat_data |>
  left_join(county_alert_data, by = "FIPS") |>
  left_join(cwa_alert_data, by = "CWA") |>
  left_join(county_covariates, by = "FIPS")

# A cell missing any predictor predicts NA, and its county would then drop from
# the estimates with nothing said. Check before predicting, not after.
predictor_na <- poststrat_data |>
  summarise(
    across(
      c(starts_with("FIPS_"), starts_with("CWA_"), SVI_RPL_THEMES,
        NRI_DRGT_AFREQ, NRI_HAIL_AFREQ, NRI_LTNG_AFREQ),
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
# happened to be fielded in -- tornado ran 2018-2025, flood only 2024-2025.
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
    FL_RECEP = predict_cells(fl_recep_fit),

    TO_SUBJ_COMP = predict_cells(to_subj_comp_fit),
    HU_SUBJ_COMP = predict_cells(hu_subj_comp_fit),
    WW_SUBJ_COMP = predict_cells(ww_subj_comp_fit),
    FL_SUBJ_COMP = predict_cells(fl_subj_comp_fit),

    TO_RESP = predict_cells(to_resp_fit),
    HU_RESP = predict_cells(hu_resp_fit),
    WW_RESP = predict_cells(ww_resp_fit),
    FL_RESP = predict_cells(fl_resp_fit),

    RISK_TOR = predict_cells(risk_tor_fit),
    RISK_HUR = predict_cells(risk_hur_fit),
    RISK_SURGE = predict_cells(risk_surge_fit),
    RISK_SNOW = predict_cells(risk_snow_fit),
    RISK_ICE = predict_cells(risk_ice_fit),
    RISK_COLD = predict_cells(risk_cold_fit),
    RISK_HEAT = predict_cells(risk_heat_fit),
    RISK_FLOOD = predict_cells(risk_flood_fit),
    RISK_FIRE = predict_cells(risk_fire_fit),
    RISK_DROUGHT = predict_cells(risk_drought_fit),
    RISK_HAIL = predict_cells(risk_hail_fit),
    RISK_LIGNT = predict_cells(risk_lignt_fit)
  ) |>
  pivot_longer(
    c(TO_RECEP:FL_RECEP, TO_SUBJ_COMP:FL_SUBJ_COMP, TO_RESP:FL_RESP,
      RISK_TOR:RISK_LIGNT),
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
write_csv(county_estimates, paste0(outputs, "07_county_estimates.csv"))
write_csv(cwa_estimates, paste0(outputs, "07_cwa_estimates.csv"))

# Mapped Estimates -------------------------------------------------------------
# The join to geometry happens once here rather than on every dashboard start.
#
# Written as sf .rds rather than shapefile for two reasons. A shapefile's DBF
# caps field names at 10 characters, which would silently shorten RISK_DROUGHT
# and the four *_SUBJ_COMP measures. And these are written wide, one row per
# area, because the long form would repeat every polygon 24 times over -- 74,616
# county geometries for the same 3,109 shapes.
#
# County geometry is cb_2025_us_county_20m, the file 03 already counts alerts
# against, so FIPS keys to GEOID directly. The NWS county file c_16ap26 is the
# wrong vintage for this: it predates Connecticut's planning regions, so joining
# to it leaves nine holes in Connecticut. 01 uses it for the CWA assignment only
# and patches those regions by hand.
#
# CWA geometry is w_16ap26, the authoritative NWS boundary. Note that it is not
# exactly the union of the counties aggregated into each CWA estimate: 01
# assigns a county spanning two CWAs wholly to the first, so the two disagree
# along those few borders.
county_shapes <- st_read(paste0(downloads, "cb_2025_us_county_20m"),
                         quiet = TRUE) |>
  select(FIPS = GEOID) |>
  st_transform(4326) # 4326 because web maps require it and ggplot accepts it

cwa_shapes <- st_read(paste0(downloads, "w_16ap26"), quiet = TRUE) |>
  select(CWA) |>
  st_transform(4326)

# Check before joining, not after. An estimate whose geometry is missing would
# vanish from the map with nothing said, which reads as a county that was never
# surveyed rather than one that was dropped.
missing_county <- setdiff(unique(county_estimates$FIPS), county_shapes$FIPS)
missing_cwa <- setdiff(unique(cwa_estimates$CWA), cwa_shapes$CWA)

if (length(missing_county) > 0 || length(missing_cwa) > 0) {
  print(missing_county)
  print(missing_cwa)
  stop("Areas above have estimates but no geometry - they would not be drawn.")
}

county_map <- county_estimates |>
  pivot_wider(names_from = measure, values_from = estimate) |>
  left_join(county_shapes, by = "FIPS") |>
  st_as_sf()

cwa_map <- cwa_estimates |>
  pivot_wider(names_from = measure, values_from = estimate) |>
  left_join(cwa_shapes, by = "CWA") |>
  st_as_sf()

# The CWA boundaries are 27 MB at full resolution, which a dashboard redraws on
# every input; they come out at 1.4 MB here. ms_simplify rather than
# st_simplify: it simplifies shared borders once rather than once per polygon,
# so adjacent areas still meet and the choropleth has no slivers between them.
# keep_shapes holds on to the small coastal and island polygons that carry the
# surge estimates.
county_map <- rmapshaper::ms_simplify(county_map, keep = 0.05,
                                      keep_shapes = TRUE)
cwa_map <- rmapshaper::ms_simplify(cwa_map, keep = 0.05, keep_shapes = TRUE)

# Simplification drops vertices, not features. Losing one would lose an area
# from the map, so check rather than assume.
if (nrow(county_map) != n_distinct(county_estimates$FIPS) ||
    nrow(cwa_map) != n_distinct(cwa_estimates$CWA)) {
  stop("Simplification changed the number of areas.")
}

write_rds(county_map, paste0(outputs, "07_county_estimates_sf.rds"))
write_rds(cwa_map, paste0(outputs, "07_cwa_estimates_sf.rds"))
