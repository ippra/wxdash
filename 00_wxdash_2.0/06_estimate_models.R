library(tidyverse)
library(lme4)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Survey Data ------------------------------------------------------------------
survey_data <- read.csv(paste0(outputs, "base_survey_data_NEW.csv")) |> tibble() # use read.csv because of a parsing issue

# survey_data$scale_risk_heat <- scale(survey_data$risk_heat)
# survey_data$scale_risk_drought <- scale(survey_data$risk_drought)
# survey_data$scale_risk_cold <- scale(survey_data$risk_cold)
# survey_data$scale_risk_snow <- scale(survey_data$risk_snow)
# survey_data$scale_risk_tor <- scale(survey_data$risk_tor)
# survey_data$scale_risk_flood <- scale(survey_data$risk_flood)
# survey_data$scale_risk_hur <- scale(survey_data$risk_hur)
# survey_data$scale_risk_fire <- scale(survey_data$risk_fire)
# survey_data$CWA_RPL_THEME1 <- scale(survey_data$CWA_RPL_THEME1)
# survey_data$CWA_RPL_THEME2 <- scale(survey_data$CWA_RPL_THEME2)
# survey_data$CWA_RPL_THEME3 <- scale(survey_data$CWA_RPL_THEME3)

# Model Design -----------------------------------------------------------------
# One model per outcome, covering both geographies, replacing the old split
# between CWA models here and county models in 07.
#
# FIPS is globally unique, so (1 | CWA) + (1 | FIPS) is already a nested
# hierarchy: the county term is a deviation from its CWA, not a competing
# effect. A county with two respondents therefore shrinks toward its CWA
# (median 80 respondents) rather than toward the national mean, which is what
# fitting (1 | FIPS) alone in 07 did.
#
# Predict once from these fits, for every poststrat cell x county, then
# aggregate to county and to CWA from that same prediction set. Aggregating
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

# Composite Scale Models -------------------------------------------------------
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

# Output Models ----------------------------------------------------------------
# 07 reads these rather than refitting, so the published estimates stay tied to
# the fits reviewed above and 07 stays cheap to re-run.
dir.create(paste0(outputs, "models"), showWarnings = FALSE)

write_rds(to_recep_fit, paste0(outputs, "models/to_recep_fit.rds"))
write_rds(hu_recep_fit, paste0(outputs, "models/hu_recep_fit.rds"))
write_rds(ww_recep_fit, paste0(outputs, "models/ww_recep_fit.rds"))
write_rds(fl_recep_fit, paste0(outputs, "models/fl_recep_fit.rds"))
