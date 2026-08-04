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
survey_data$CWA_RPL_THEME1 <- scale(survey_data$CWA_RPL_THEME1)
survey_data$CWA_RPL_THEME2 <- scale(survey_data$CWA_RPL_THEME2)
survey_data$CWA_RPL_THEME3 <- scale(survey_data$CWA_RPL_THEME3)
survey_data$CWA_RPL_THEME4 <- scale(survey_data$CWA_RPL_THEME4)

# Composite Scale Models - Already Run, Output Saved -------------------------
cwa_to_recep_fit <- lmer(to_recep ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                             CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                    data = survey_data)
saveRDS(cwa_to_recep_fit, paste0(outputs, "cwa_models/cwa_to_recep_fit.Rds"))

cwa_hu_recep_fit <- lmer(hu_recep ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                           CWA_HURR + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                         data = survey_data)
saveRDS(cwa_hu_recep_fit, paste0(outputs, "cwa_models/cwa_hu_recep_fit.Rds"))

cwa_to_subj_comp_fit <- lmer(to_subj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                                 CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                   data = survey_data)
saveRDS(cwa_to_subj_comp_fit, paste0(outputs, "cwa_models/cwa_to_subj_comp_fit.Rds"))

cwa_hu_subj_comp_fit <- lmer(hu_subj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                               CWA_HURR + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                             data = survey_data)
saveRDS(cwa_hu_subj_comp_fit, paste0(outputs, "cwa_models/cwa_hu_subj_comp_fit.Rds"))

cwa_to_obj_comp_fit <- lmer(to_obj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                                CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                   data = survey_data)
saveRDS(cwa_to_obj_comp_fit, paste0(outputs, "cwa_models/cwa_to_obj_comp_fit.Rds"))

cwa_hu_obj_comp_fit <- lmer(hu_obj_comp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                              CWA_HURR + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                            data = survey_data)
saveRDS(cwa_hu_obj_comp_fit, paste0(outputs, "cwa_models/cwa_hu_obj_comp_fit.Rds"))

cwa_to_resp_fit <- lmer(to_resp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                           CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                         data = survey_data)
saveRDS(cwa_to_resp_fit, paste0(outputs, "cwa_models/cwa_to_resp_fit.Rds"))

cwa_hu_resp_fit <- lmer(hu_resp ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                           CWA_HURR + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                         data = survey_data)
saveRDS(cwa_hu_resp_fit, paste0(outputs, "cwa_models/cwa_hu_resp_fit.Rds"))

cwa_to_eff_fit <- lmer(to_eff ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                          CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                        data = survey_data)
saveRDS(cwa_to_eff_fit, paste0(outputs, "cwa_models/cwa_to_eff_fit.Rds"))

# Risk Perception Models - Already Run, Output Saved -------------------------
cwa_heat_fit <- lmer(scale_risk_heat ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_HEAT + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_heat_fit, paste0(outputs, "cwa_models/cwa_heat_fit.Rds"))

cwa_drought_fit <- lmer(scale_risk_drought ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                               CWA_DROUGHT + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                             data = survey_data)
saveRDS(cwa_drought_fit, paste0(outputs, "cwa_models/cwa_drought_fit.Rds"))

cwa_cold_fit <- lmer(scale_risk_cold ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_COLD + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_cold_fit, paste0(outputs, "cwa_models/cwa_cold_fit.Rds"))

cwa_snow_fit <- lmer(scale_risk_snow ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_SNOW + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_snow_fit, paste0(outputs, "cwa_models/cwa_snow_fit.Rds"))

cwa_torn_fit <- lmer(scale_risk_tor ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_TORN + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_torn_fit, paste0(outputs, "cwa_models/cwa_torn_fit.Rds"))

cwa_flood_fit <- lmer(scale_risk_flood ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                             CWA_FLOOD + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                           data = survey_data)
saveRDS(cwa_flood_fit, paste0(outputs, "cwa_models/cwa_flood_fit.Rds"))

cwa_hurr_fit <- lmer(scale_risk_hur ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_HURR + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_hurr_fit, paste0(outputs, "cwa_models/cwa_hurr_fit.Rds"))

cwa_fire_fit <- lmer(scale_risk_fire ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                            CWA_FIRE + CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4,
                          data = survey_data)
saveRDS(cwa_fire_fit, paste0(outputs, "cwa_models/cwa_fire_fit.Rds"))

# Ready Models - Already Run, Output Saved -------------------------
cwa_all_ready_fit <- lmer(all_ready ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) +
                              CWA_HEAT + CWA_DROUGHT + CWA_COLD + CWA_SNOW + CWA_TORN + CWA_FLOOD + CWA_HURR + CWA_FIRE + 
                              CWA_RPL_THEME1 + CWA_RPL_THEME2 + CWA_RPL_THEME3 + CWA_RPL_THEME4, 
                           data = survey_data)
saveRDS(cwa_all_ready_fit, paste0(outputs, "cwa_models/cwa_all_ready_fit.Rds"))

