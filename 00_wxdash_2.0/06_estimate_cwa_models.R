library(tidyverse)
library(lme4)

downloads <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Survey Data -------------------------
survey_data <- read.csv(paste0(outputs, "base_survey_data_NEW.csv")) %>% tibble() # use read.csv because of a parsing issue

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

# Composite Scale Models -------------------------
cwa_to_recep_fit <- lmer(to_recep ~ 1 + MALE + AGE_GROUP + HISP + RACE_GROUP + (1|CWA) + (1|MALE:AGE_GROUP) + CWA_TORN, data = survey_data)

names(survey_data) |> tibble() |> print(n = Inf)
