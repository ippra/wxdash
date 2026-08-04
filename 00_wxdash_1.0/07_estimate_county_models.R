library(tidyverse)
library(lme4)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Survey Data -------------------------
survey_data <- read.csv(paste0(outputs, "base_survey_data.csv")) %>% tibble() # use read.csv because of a parsing issue

survey_data$scale_risk_heat <- scale(survey_data$risk_heat)
survey_data$scale_risk_drought <- scale(survey_data$risk_drought)
survey_data$scale_risk_cold <- scale(survey_data$risk_cold)
survey_data$scale_risk_snow <- scale(survey_data$risk_snow)
survey_data$scale_risk_tor <- scale(survey_data$risk_tor)
survey_data$scale_risk_flood <- scale(survey_data$risk_flood)
survey_data$scale_risk_hur <- scale(survey_data$risk_hur)
survey_data$scale_risk_fire <- scale(survey_data$risk_fire)
survey_data$FIPS_RPL_THEME1 <- scale(survey_data$FIPS_RPL_THEME1)
survey_data$FIPS_RPL_THEME2 <- scale(survey_data$FIPS_RPL_THEME2)
survey_data$FIPS_RPL_THEME3 <- scale(survey_data$FIPS_RPL_THEME3)
survey_data$FIPS_RPL_THEME4 <- scale(survey_data$FIPS_RPL_THEME4)

# Composite Scale Models - Already Run, Output Saved -------------------------
fips_to_recep_fit <- lmer(to_recep ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                           FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                         data = survey_data)
saveRDS(fips_to_recep_fit, paste0(outputs, "county_models/fips_to_recep_fit.Rds"))

fips_hu_recep_fit <- lmer(hu_recep ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                           FIPS_HURR + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                         data = survey_data)
saveRDS(fips_hu_recep_fit, paste0(outputs, "county_models/fips_hu_recep_fit.Rds"))

fips_to_subj_comp_fit <- lmer(to_subj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                               FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                             data = survey_data)
saveRDS(fips_to_subj_comp_fit, paste0(outputs, "county_models/fips_to_subj_comp_fit.Rds"))

fips_hu_subj_comp_fit <- lmer(hu_subj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                               FIPS_HURR + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                             data = survey_data)
saveRDS(fips_hu_subj_comp_fit, paste0(outputs, "county_models/fips_hu_subj_comp_fit.Rds"))

fips_to_obj_comp_fit <- lmer(to_obj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                              FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                            data = survey_data)
saveRDS(fips_to_obj_comp_fit, paste0(outputs, "county_models/fips_to_obj_comp_fit.Rds"))

fips_hu_obj_comp_fit <- lmer(hu_obj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                              FIPS_HURR + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                            data = survey_data)
saveRDS(fips_hu_obj_comp_fit, paste0(outputs, "county_models/fips_hu_obj_comp_fit.Rds"))

fips_to_resp_fit <- lmer(to_resp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                          FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                        data = survey_data)
saveRDS(fips_to_resp_fit, paste0(outputs, "county_models/fips_to_resp_fit.Rds"))

fips_hu_resp_fit <- lmer(hu_resp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                          FIPS_HURR + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                        data = survey_data)
saveRDS(fips_hu_resp_fit, paste0(outputs, "county_models/fips_hu_resp_fit.Rds"))

fips_to_eff_fit <- lmer(to_eff ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                         FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                       data = survey_data)
saveRDS(fips_to_eff_fit, paste0(outputs, "county_models/fips_to_eff_fit.Rds"))

# Risk Perception Models - Already Run, Output Saved -------------------------
fips_heat_fit <- lmer(scale_risk_heat ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_HEAT + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_heat_fit, paste0(outputs, "county_models/fips_heat_fit.Rds"))

fips_drought_fit <- lmer(scale_risk_drought ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                          FIPS_DROUGHT + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                        data = survey_data)
saveRDS(fips_drought_fit, paste0(outputs, "county_models/fips_drought_fit.Rds"))

fips_cold_fit <- lmer(scale_risk_cold ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_COLD + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_cold_fit, paste0(outputs, "county_models/fips_cold_fit.Rds"))

fips_snow_fit <- lmer(scale_risk_snow ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_SNOW + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_snow_fit, paste0(outputs, "county_models/fips_snow_fit.Rds"))

fips_torn_fit <- lmer(scale_risk_tor ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_TORN + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_torn_fit, paste0(outputs, "county_models/fips_torn_fit.Rds"))

fips_flood_fit <- lmer(scale_risk_flood ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                        FIPS_FLOOD + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                      data = survey_data)
saveRDS(fips_flood_fit, paste0(outputs, "county_models/fips_flood_fit.Rds"))

fips_hurr_fit <- lmer(scale_risk_hur ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_HURR + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_hurr_fit, paste0(outputs, "county_models/fips_hurr_fit.Rds"))

fips_fire_fit <- lmer(scale_risk_fire ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                       FIPS_FIRE + FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4,
                     data = survey_data)
saveRDS(fips_fire_fit, paste0(outputs, "county_models/fips_fire_fit.Rds"))

# Ready Models - Already Run, Output Saved -------------------------
fips_all_ready_fit <- lmer(all_ready ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|FIPS) + (1|MALE:AGE_GROUP) +
                            FIPS_HEAT + FIPS_DROUGHT + FIPS_COLD + FIPS_SNOW + FIPS_TORN + FIPS_FLOOD + FIPS_HURR + FIPS_FIRE + 
                            FIPS_RPL_THEME1 + FIPS_RPL_THEME2 + FIPS_RPL_THEME3 + FIPS_RPL_THEME4, 
                          data = survey_data)
saveRDS(fips_all_ready_fit, paste0(outputs, "county_models/fips_all_ready_fit.Rds"))
