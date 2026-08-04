library(tidyverse)
library(robustbase)
library(sf)
library(rmapshaper)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Census Data -------------------------
census_data <- read_csv(paste0(outputs, "base_cwa_census_data.csv"))

census_data$CWA_RPL_THEME1 <- scale(census_data$CWA_RPL_THEME1)
census_data$CWA_RPL_THEME2 <- scale(census_data$CWA_RPL_THEME2)
census_data$CWA_RPL_THEME3 <- scale(census_data$CWA_RPL_THEME3)
census_data$CWA_RPL_THEME4 <- scale(census_data$CWA_RPL_THEME4)

# Load Models  -------------------------
cwa_to_recep_fit <- readRDS(paste0(outputs, "cwa_models/cwa_to_recep_fit.Rds"))
cwa_hu_recep_fit <- readRDS(paste0(outputs, "cwa_models/cwa_hu_recep_fit.Rds"))
cwa_to_subj_comp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_to_subj_comp_fit.Rds"))
cwa_hu_subj_comp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_hu_subj_comp_fit.Rds"))
cwa_to_obj_comp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_to_obj_comp_fit.Rds"))
cwa_hu_obj_comp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_hu_obj_comp_fit.Rds"))
cwa_to_resp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_to_resp_fit.Rds"))
cwa_hu_resp_fit <- readRDS(paste0(outputs, "cwa_models/cwa_hu_resp_fit.Rds"))
cwa_to_eff_fit <- readRDS(paste0(outputs, "cwa_models/cwa_to_eff_fit.Rds"))
cwa_heat_fit <- readRDS(paste0(outputs, "cwa_models/cwa_heat_fit.Rds"))
cwa_drought_fit <- readRDS(paste0(outputs, "cwa_models/cwa_drought_fit.Rds"))
cwa_cold_fit <- readRDS(paste0(outputs, "cwa_models/cwa_cold_fit.Rds"))
cwa_snow_fit <- readRDS(paste0(outputs, "cwa_models/cwa_snow_fit.Rds"))
cwa_torn_fit <- readRDS(paste0(outputs, "cwa_models/cwa_torn_fit.Rds"))
cwa_flood_fit <- readRDS(paste0(outputs, "cwa_models/cwa_flood_fit.Rds"))
cwa_hurr_fit <- readRDS(paste0(outputs, "cwa_models/cwa_hurr_fit.Rds"))
cwa_fire_fit <- readRDS(paste0(outputs, "cwa_models/cwa_fire_fit.Rds"))
cwa_all_ready_fit <- readRDS(paste0(outputs, "cwa_models/cwa_all_ready_fit.Rds"))

# CWA Estimates -------------------------
to_recep_predictions <- census_data %>%
  mutate(person_z = predict(cwa_to_recep_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "TO_RECEP")

hu_recep_predictions <- census_data %>%
  mutate(person_z = predict(cwa_hu_recep_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "HU_RECEP")

to_subj_comp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_to_subj_comp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "TO_SUB_COM")

hu_subj_comp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_hu_subj_comp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "HU_SUB_COM")

to_obj_comp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_to_obj_comp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "TO_OBJ_COM")

hu_obj_comp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_hu_obj_comp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "HU_OBJ_COM")

to_resp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_to_resp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "TO_RESP")

hu_resp_predictions <- census_data %>%
  mutate(person_z = predict(cwa_hu_resp_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "HU_RESP")

to_eff_predictions <- census_data %>%
  mutate(person_z = predict(cwa_to_eff_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "TO_EFFICAC")

heat_predictions <- census_data %>%
  mutate(person_z = predict(cwa_heat_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_HEA")

drought_predictions <- census_data %>%
  mutate(person_z = predict(cwa_drought_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_DRO")

cold_predictions <- census_data %>%
  mutate(person_z = predict(cwa_cold_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_COL")

snow_predictions <- census_data %>%
  mutate(person_z = predict(cwa_snow_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_SNO")

tornado_predictions <- census_data %>%
  mutate(person_z = predict(cwa_torn_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_TOR")

flood_predictions <- census_data %>%
  mutate(person_z = predict(cwa_flood_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_FLO")

hurricane_predictions <- census_data %>%
  mutate(person_z = predict(cwa_hurr_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_HUR")

fire_predictions <- census_data %>%
  mutate(person_z = predict(cwa_fire_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "PER_FIR")

all_ready_predictions <- census_data %>%
  mutate(person_z = predict(cwa_all_ready_fit, newdata = ., allow.new.levels = TRUE)) %>%
  mutate(person_z = person_z * DEMGRP_PROP) %>%
  group_by(CWA) %>%
  summarise(person_z = sum(person_z)) %>%
  mutate(measure = "ALL_READY")

# Make Shapefile ----------------------------------------
all_predictions <- bind_rows(to_recep_predictions, hu_recep_predictions, to_subj_comp_predictions, hu_subj_comp_predictions, 
                             to_obj_comp_predictions, hu_obj_comp_predictions, to_resp_predictions, hu_resp_predictions,
                             to_eff_predictions, heat_predictions, drought_predictions, cold_predictions, snow_predictions, 
                             tornado_predictions, flood_predictions, hurricane_predictions, fire_predictions, all_ready_predictions) %>%
  pivot_wider(names_from = measure, values_from = person_z) # only person z-scores

cwa_shp <- read_sf(paste0(downloads, "w_03mr20"), "w_03mr20")
cwa_shp <- cwa_shp %>% 
  filter(CWA %in% all_predictions$CWA) # no predictions for 7 CWAs (AFC, AFG, GUM, HFO, PPG, SJU, AJK)

cwa_shp <- left_join(cwa_shp, all_predictions, by = "CWA")

# Include SVI Data ----------------------------------------
svi_data <- census_data %>%
  select(CWA, 
         POV = CWA_EP_POV150,
         UNEMP = CWA_EP_UNEMP,
         HBURD = CWA_EP_HBURD,
         NOHSDP = CWA_EP_NOHSDP,
         UNINSUR = CWA_EP_UNINSUR,
         AGE65 = CWA_EP_AGE65,
         AGE17 = CWA_EP_AGE17,
         DISABL = CWA_EP_DISABL,
         SNGPNT = CWA_EP_SNGPNT,
         LIMENG = CWA_EP_LIMENG,
         MINRTY = CWA_EP_MINRTY,
         MUNIT = CWA_EP_MUNIT,
         MOBILE = CWA_EP_MOBILE,
         CROWD = CWA_EP_CROWD,
         NOVEH = CWA_EP_NOVEH,
         GROUPQ = CWA_EP_GROUPQ,
         NOINT = CWA_EP_NOINT,
         AFAM = CWA_EP_AFAM,
         HISP = CWA_EP_HISP,
         ASIAN = CWA_EP_ASIAN,
         AIAN = CWA_EP_AIAN,
         NHPI = CWA_EP_NHPI,
         TWOMORE = CWA_EP_TWOMORE,
         OTHERRACE = CWA_EP_OTHERRACE,
         THEME1 = CWA_RPL_THEME1,
         THEME2 = CWA_RPL_THEME2,
         THEME3 = CWA_RPL_THEME3,
         THEME4 = CWA_RPL_THEME4,
         THEMES = CWA_RPL_THEMES) %>% 
  mutate(THEME1 = c(THEME1),
         THEME2 = c(THEME2),
         THEME3 = c(THEME3),
         THEME4 = c(THEME4)) %>% 
  distinct(CWA, .keep_all = TRUE)
cwa_shp <- left_join(cwa_shp, svi_data, by = "CWA")

# Include Event Data ----------------------------------------
cwa_storm_data <- read_csv(paste0(outputs, "base_cwa_storm_data.csv"))
cwa_shp <- left_join(cwa_shp, cwa_storm_data, by = "CWA")
cwa_shp <- cwa_shp %>% select(CWA, everything())

# Write Shapefile ----------------------------------------
cwa_shp <- ms_simplify(cwa_shp, keep = 0.05)
st_write(cwa_shp, paste0(outputs, "cwa_estimates"), "cwa_estimates", driver = "ESRI Shapefile", append = FALSE)


