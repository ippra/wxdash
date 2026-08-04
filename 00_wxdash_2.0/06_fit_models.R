
library(tidyverse)
library(lme4)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Survey Data ------------------------------------------------------------------
survey_data <- read.csv(paste0(outputs, "05_survey_responses.csv")) |> tibble() # use read.csv because of a parsing issue

# Model Design -----------------------------------------------------------------
# Twelve models: three constructs (reception, comprehension, response) for each
# of four hazards. Every model has the same form, differing only in the outcome
# and in which hazard's warning counts are carried.
#
# FIPS is globally unique, so (1 | CWA) + (1 | FIPS) is already a nested
# hierarchy: the county term is a deviation from its CWA, not a competing
# effect. A county with two respondents therefore shrinks toward its CWA
# (median 80 respondents) rather than toward the national mean.
#
# 07 predicts once from these fits, for every poststrat cell x county, then
# aggregates to county and to CWA from that same prediction set. Aggregating
# rather than fitting separately is what makes the two levels agree: population
# weighting the county estimates within a CWA recovers the CWA estimate.
#
# Note that 42-75% of counties have no respondents, depending on outcome. Their
# county effect shrinks to zero, so their estimate is demographic composition
# plus the CWA effect plus county-level covariates. Real, but not measured.

# Area-level covariates are county-level only. CWA-level SVI and risk are close
# to population-weighted averages of their counties, so carrying both levels
# would repeat the collinearity that flattened every weather term in the winter
# model. County level is also where the payoff is: 42-75% of counties have no
# respondents, and county covariates are the only thing distinguishing them from
# their CWA. One SVI index rather than several -- RPL_THEME1 correlates with
# RPL_THEMES at 0.96. FEMA risk was tested and dropped: none of the six risk
# terms reached |t| > 1.4, and they cost 14-55% of each model's sample. Every
# SVI and NRI field is still joined in 05 under SVI_ and NRI_ if wanted later.

# Reception Models -------------------------------------------------------------
to_recep_fit <- lmer(
  to_recep_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_TORN) +
    scale(CWA_TORN) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(to_recep_fit)

hu_recep_fit <- lmer(
  hu_recep_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HURR) +
    scale(CWA_HURR) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(hu_recep_fit)

ww_recep_fit <- lmer(
  ww_recep_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_SNOW) +
    scale(FIPS_ICE) +
    scale(CWA_SNOW) +
    scale(CWA_ICE) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(ww_recep_fit)

fl_recep_fit <- lmer(
  fl_recep_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_FLOOD) +
    scale(CWA_FLOOD) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(fl_recep_fit)

# Comprehension Models ---------------------------------------------------------
to_subj_comp_fit <- lmer(
  to_subj_comp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_TORN) +
    scale(CWA_TORN) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(to_subj_comp_fit)

hu_subj_comp_fit <- lmer(
  hu_subj_comp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HURR) +
    scale(CWA_HURR) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(hu_subj_comp_fit)

ww_subj_comp_fit <- lmer(
  ww_subj_comp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_SNOW) +
    scale(FIPS_ICE) +
    scale(CWA_SNOW) +
    scale(CWA_ICE) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(ww_subj_comp_fit)

fl_subj_comp_fit <- lmer(
  fl_subj_comp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_FLOOD) +
    scale(CWA_FLOOD) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(fl_subj_comp_fit)

# Response Models --------------------------------------------------------------
to_resp_fit <- lmer(
  to_resp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_TORN) +
    scale(CWA_TORN) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(to_resp_fit)

hu_resp_fit <- lmer(
  hu_resp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HURR) +
    scale(CWA_HURR) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(hu_resp_fit)

ww_resp_fit <- lmer(
  ww_resp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_SNOW) +
    scale(FIPS_ICE) +
    scale(CWA_SNOW) +
    scale(CWA_ICE) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(ww_resp_fit)

fl_resp_fit <- lmer(
  fl_resp_scale ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_FLOOD) +
    scale(CWA_FLOOD) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(fl_resp_fit)

# Risk Perception Models -------------------------------------------------------
# Single survey items, not composite scales: each asks how the respondent rates
# the risk of one hazard where they live, 1 no risk to 5 extreme risk.
#
# Only the items with a direct alert category are fitted. Correlations with
# their own category, at CWA level: hurricane .57, tornado .42, ice .39,
# snow .38, cold .34, fire .29, surge .23, heat .20, flood .15.
#
# Five items are deliberately absent. risk_wind has a matching category but
# correlates .02 with it, because the WIND bucket is mostly severe thunderstorm
# warnings and those are near-universal. risk_hail and risk_lignt have no
# category at all -- NWS folds both into severe thunderstorm -- and risk_drought
# and risk_rain likewise. Fitting those on a proxy alert would attribute a
# geographic pattern to a hazard the counts do not measure.
#
# risk_surge uses HURR because storm surge warnings (SS) sit in that bucket.
risk_tor_fit <- lmer(
  risk_tor ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_TORN) +
    scale(CWA_TORN) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_tor_fit)

risk_hur_fit <- lmer(
  risk_hur ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HURR) +
    scale(CWA_HURR) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_hur_fit)

risk_surge_fit <- lmer(
  risk_surge ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HURR) +
    scale(CWA_HURR) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_surge_fit)

risk_snow_fit <- lmer(
  risk_snow ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_SNOW) +
    scale(CWA_SNOW) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_snow_fit)

risk_ice_fit <- lmer(
  risk_ice ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_ICE) +
    scale(CWA_ICE) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_ice_fit)

risk_cold_fit <- lmer(
  risk_cold ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_COLD) +
    scale(CWA_COLD) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_cold_fit)

risk_heat_fit <- lmer(
  risk_heat ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_HEAT) +
    scale(CWA_HEAT) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_heat_fit)

risk_flood_fit <- lmer(
  risk_flood ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_FLOOD) +
    scale(CWA_FLOOD) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_flood_fit)

risk_fire_fit <- lmer(
  risk_fire ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(FIPS_FIRE) +
    scale(CWA_FIRE) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_fire_fit)

# The three below carry a FEMA NRI annualized frequency instead of an alert
# count, because NWS issues no warning for these hazards -- hail and lightning
# fold into severe thunderstorm, and drought has no VTEC product at all. The NRI
# frequencies correlate .37 (drought), .30 (hail) and .30 (lightning) with their
# items, better than several hazards that do have alert counts, and cost 0.4% of
# the sample.
#
# There is no CWA term here: the covariate lookup 04 builds is county-level, so
# CWA variation is left to its random intercept. NRI was not added to the models
# above it -- against their own alert counts it correlates .92 (cold) and .93
# (hurricane), which is duplication rather than a second measurement.
risk_drought_fit <- lmer(
  risk_drought ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(NRI_DRGT_AFREQ) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_drought_fit)

risk_hail_fit <- lmer(
  risk_hail ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(NRI_HAIL_AFREQ) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_hail_fit)

risk_lignt_fit <- lmer(
  risk_lignt ~
    GENDER_GROUP +
    AGE_GROUP +
    RACE_GROUP +
    EDUC_GROUP +
    INCOME_GROUP +
    scale(NRI_LTNG_AFREQ) +
    scale(SVI_RPL_THEMES) +
    (1 | CWA) +
    (1 | FIPS) +
    (1 | survey_year),
  data = survey_data
)
summary(risk_lignt_fit)

# Output Models ----------------------------------------------------------------
# 07 reads these rather than refitting, so the published estimates stay tied to
# the fits reviewed above and 07 stays cheap to re-run.
dir.create(paste0(outputs, "06_models"), showWarnings = FALSE)

write_rds(to_recep_fit, paste0(outputs, "06_models/to_recep_fit.rds"))
write_rds(hu_recep_fit, paste0(outputs, "06_models/hu_recep_fit.rds"))
write_rds(ww_recep_fit, paste0(outputs, "06_models/ww_recep_fit.rds"))
write_rds(fl_recep_fit, paste0(outputs, "06_models/fl_recep_fit.rds"))

write_rds(to_subj_comp_fit, paste0(outputs, "06_models/to_subj_comp_fit.rds"))
write_rds(hu_subj_comp_fit, paste0(outputs, "06_models/hu_subj_comp_fit.rds"))
write_rds(ww_subj_comp_fit, paste0(outputs, "06_models/ww_subj_comp_fit.rds"))
write_rds(fl_subj_comp_fit, paste0(outputs, "06_models/fl_subj_comp_fit.rds"))

write_rds(to_resp_fit, paste0(outputs, "06_models/to_resp_fit.rds"))
write_rds(hu_resp_fit, paste0(outputs, "06_models/hu_resp_fit.rds"))
write_rds(ww_resp_fit, paste0(outputs, "06_models/ww_resp_fit.rds"))
write_rds(fl_resp_fit, paste0(outputs, "06_models/fl_resp_fit.rds"))

write_rds(risk_tor_fit, paste0(outputs, "06_models/risk_tor_fit.rds"))
write_rds(risk_hur_fit, paste0(outputs, "06_models/risk_hur_fit.rds"))
write_rds(risk_surge_fit, paste0(outputs, "06_models/risk_surge_fit.rds"))
write_rds(risk_snow_fit, paste0(outputs, "06_models/risk_snow_fit.rds"))
write_rds(risk_ice_fit, paste0(outputs, "06_models/risk_ice_fit.rds"))
write_rds(risk_cold_fit, paste0(outputs, "06_models/risk_cold_fit.rds"))
write_rds(risk_heat_fit, paste0(outputs, "06_models/risk_heat_fit.rds"))
write_rds(risk_flood_fit, paste0(outputs, "06_models/risk_flood_fit.rds"))
write_rds(risk_fire_fit, paste0(outputs, "06_models/risk_fire_fit.rds"))

write_rds(risk_drought_fit, paste0(outputs, "06_models/risk_drought_fit.rds"))
write_rds(risk_hail_fit, paste0(outputs, "06_models/risk_hail_fit.rds"))
write_rds(risk_lignt_fit, paste0(outputs, "06_models/risk_lignt_fit.rds"))
