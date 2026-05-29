# library(ltm)
library(data.table)
library(readxl)
library(sf)
library(tidyverse)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Import Survey Data -----------------------------
WX17 <- read_csv(paste0(downloads, "WX17_data_wtd.csv")) %>% 
  mutate(survey_year = "2017", 
         survey_hazard = "WX",
         survey_language = "English",
         p_id = as.character(p_id),
         zip = as.numeric(zip),
         nws_region = case_when(
           region == 1 ~ "Eastern Region",
           region == 2 ~ "Southern Region",
           region == 3 ~ "Central Region",
           region == 4 ~ "Western Region")) %>% 
  select(-c(rec_all:rec_time)) %>%  # remove because scale changes form 1-7 to 1-5 in 2018/2019
  select(-c(resp_ignore:resp_unsure)) # remove because scale changes form 1-7 to 1-5 in 2018/2019
WX18 <- read_csv(paste0(downloads, "WX18_data_wtd.csv")) %>% 
  mutate(survey_year = "2018", 
         survey_hazard = "WX",
         survey_language = "English")
WX19 <- read_csv(paste0(downloads, "WX19_data_wtd.csv")) %>% 
  mutate(survey_year = "2019", 
         survey_hazard = "WX", 
         survey_language = "English")
WX20 <- read_csv(paste0(downloads, "WX20_data_wtd.csv")) %>% 
  mutate(survey_year = "2020", 
         survey_hazard = "WX",
         survey_language = "English", 
         zip = as.numeric(zip))
WX21 <- read_csv(paste0(downloads, "WX21_data_wtd.csv")) %>% 
  mutate(survey_year = "2021", 
         survey_hazard = "WX",
         survey_language = "English")
WX22 <- read_csv(paste0(downloads, "WX22_data_wtd.csv")) %>% 
  mutate(survey_year = "2022", 
         survey_hazard = "WX",
         survey_language = "English")
WX23 <- read_csv(paste0(downloads, "WX23_data_wtd.csv")) %>% 
  mutate(survey_year = "2023", 
         survey_hazard = "WX",
         survey_language = "English")
WX24 <- read_csv(paste0(downloads, "WX24_data_wtd.csv")) %>% 
  mutate(survey_year = "2024", 
         survey_hazard = "WX",
         survey_language = "English", 
         end_date = as.Date(end_date),
         rand_aft = as.character(rand_aft),
         rand_eve = as.character(rand_aft))
WX25 <- read_csv(paste0(downloads, "WX25_data_wtd.csv")) %>% 
  mutate(survey_year = "2025", 
         survey_hazard = "WX",
         survey_language = "English", 
         end_date = as.Date(end_date),
         rand_aft = as.character(rand_aft),
         rand_eve = as.character(rand_aft))

TC20 <- read_csv(paste0(downloads, "TC20_data_wtd.csv")) %>% 
  mutate(survey_year = "2020",
         survey_hazard = "TC",
         survey_language = "English")
TC21 <- read_csv(paste0(downloads, "TC21_data_wtd.csv")) %>% 
  mutate(survey_year = "2021",
         survey_hazard = "TC",
         survey_language = "English")
TC22 <- read_csv(paste0(downloads, "TC22_data_wtd.csv")) %>% 
  mutate(survey_year = "2022",
         survey_hazard = "TC",
         survey_language = "English")
TC23 <- read_csv(paste0(downloads, "TC23_data_wtd.csv")) %>% 
  mutate(survey_year = "2023",
         survey_hazard = "TC",
         survey_language = "English")
TC24 <- read_csv(paste0(downloads, "TC24_data_wtd.csv")) %>% 
  mutate(survey_year = "2024",
         survey_hazard = "TC",
         survey_language = "English", 
         end_date = as.Date(end_date))
TC25 <- read_csv(paste0(downloads, "TC25_data_wtd.csv")) %>% 
  mutate(survey_year = "2025",
         survey_hazard = "TC",
         survey_language = "English", 
         end_date = as.Date(end_date))

WW21 <- read_csv(paste0(downloads, "WW21_data_wtd.csv")) %>% 
  mutate(survey_year = "2021",
         survey_hazard = "WW",
         survey_language = "English")
WW22 <- read_csv(paste0(downloads, "WW22_data_wtd.csv")) %>% 
  mutate(survey_year = "2022",
         survey_hazard = "WW",
         survey_language = "English")
WW23 <- read_csv(paste0(downloads, "WW23_data_wtd.csv")) %>% 
  mutate(survey_year = "2023",
         survey_hazard = "WW",
         survey_language = "English")
WW24 <- read_csv(paste0(downloads, "WW24_data_wtd.csv")) %>% 
  mutate(survey_year = "2024",
         survey_hazard = "WW",
         survey_language = "English", 
         end_date = as.Date(end_date))
WW25 <- read_csv(paste0(downloads, "WW25_data_wtd.csv")) %>% 
  mutate(survey_year = "2025",
         survey_hazard = "WW",
         survey_language = "English", 
         end_date = as.Date(end_date_utc))

FL24 <- read_csv(paste0(downloads, "FL24_data_wtd.csv")) %>% 
  mutate(survey_year = "2024",
         survey_hazard = "FL",
         survey_language = "English")
FL25 <- read_csv(paste0(downloads, "FL25_data_wtd.csv")) %>% 
  mutate(survey_year = "2025",
         survey_hazard = "FL",
         survey_language = "English")

survey_data <- rbindlist(list(WX17, WX18, WX19, WX20, WX21, WX22, WX23, WX24, WX25,
                              TC20, TC21, TC22, TC23, TC24, TC25,
                              WW21, WW22, WW23, WW24, WW25,
                              FL24, FL25), fill = TRUE, ignore.attr = TRUE)

# Quick map of zipcode centroids in survey_data
zip_centroids <- tigris::zctas(year = 2020) %>%
  st_centroid() %>%
  mutate(zip = ZCTA5CE20) %>%
  filter(zip %in% unique(survey_data$zip))

ggplot() +
  borders("state", colour = "gray50", fill = NA) +
  geom_sf(data = zip_centroids, size = 1, alpha = 0.5, color = "steelblue") +
  coord_sf(xlim = c(-125, -66), ylim = c(24, 50)) +
  theme_minimal() +
  labs(title = "Survey Respondent Zipcode Centroids")


# Identify respondent FIPS, CWA, and Region ------------------
zip_to_county <- read_excel(paste0(downloads, "ZIP_COUNTY_032025.xlsx"), 
                            col_types = c("text", "text", "text", "text", "numeric", "numeric", "numeric", "numeric")) # https://www.huduser.gov/portal/datasets/usps_crosswalk.html
zip_to_county <- zip_to_county %>% 
  select(ZIP, FIPS = COUNTY, RES_RATIO) %>% 
  arrange(ZIP, -RES_RATIO) %>% 
  distinct(ZIP, .keep_all = TRUE)

survey_data$zip <- str_pad(survey_data$zip, 5, side = "left", pad = 0)
survey_data <- left_join(survey_data, zip_to_county, by = c("zip" = "ZIP")) 
survey_data <- drop_na(survey_data, FIPS) # drops 121 respondents (invalid zipcodes)

county_to_cwa_data <- read_sf(paste0(outputs, "county_to_cwa_data.csv"))
survey_data <- left_join(survey_data, county_to_cwa_data %>% select(FIPS = GEOID, CWA), by = "FIPS")

# Recode/Rename Variables -----------------------------
survey_data <- survey_data %>%
  mutate(
    MALE = factor(gend),
    AGE = age,
    AGE_GROUP = factor(case_when(
      age >= 18 & age <= 34 ~ 1,
      age >= 35 & age <= 59 ~ 2,
      age >= 60 & age <= 110 ~ 3,
      TRUE ~ NA_real_)),
    HISP = factor(hisp),
    RACE_GROUP = factor(case_when(
      race == 1 ~ 1,
      race == 2 ~ 2,
      TRUE ~ 3)))

# Alert Data -------------------------
cwa_alert_data <- read_csv(paste0(outputs, "base_cwa_alert_data.csv"))
county_alert_data <- read_csv(paste0(outputs, "base_county_alert_data.csv"))

cwa_alert_data <- cwa_alert_data %>% rename_at(vars(FLOOD:HURR), ~paste0("CWA_", .))
county_alert_data <- county_alert_data %>% rename_at(vars(COLD:TORN), ~paste0("FIPS_", .))

survey_data <- left_join(survey_data, cwa_alert_data, by = c("CWA" = "WFO"))
survey_data <- left_join(survey_data, county_alert_data, by = c("FIPS" = "GEOID"))

# Risk Data (from FEMA) -------------------------
cwa_risk_data <- read_csv(paste0(outputs, "base_cwa_risk_data.csv"))
county_risk_data <- read_csv(paste0(outputs, "base_county_risk_data.csv"))

cwa_risk_data <- cwa_risk_data %>% rename_at(vars(CWA_SOVI:CWA_SNOW), ~paste0("FEMA_", .))
county_risk_data <- county_risk_data %>% rename_at(vars(FIPS_SOVI:FIPS_SNOW), ~paste0("FIPS_", .))

survey_data <- left_join(survey_data, cwa_risk_data, by = "CWA")
survey_data <- left_join(survey_data, county_risk_data, by = "FIPS")

# Census Data -------------------------
cwa_census_data <- read_csv(paste0(outputs, "base_cwa_census_data.csv"))
county_census_data <- read_csv(paste0(outputs, "base_county_census_data.csv"))

cwa_svi_data <- cwa_census_data %>% 
  select(CWA, CWA_EP_POV150:CWA_RPL_THEMES) %>% 
  distinct(CWA, .keep_all = TRUE)

county_svi_data <- county_census_data %>% 
  select(FIPS, FIPS_EP_POV150:FIPS_RPL_THEMES) %>% 
  distinct(FIPS, .keep_all = TRUE)

survey_data <- left_join(survey_data, cwa_svi_data, by = "CWA")
survey_data <- left_join(survey_data, county_svi_data, by = "FIPS")

# Measures for Models -------------------------
to_recep_data <- survey_data %>%
  filter(survey_hazard == "WX" & !survey_year == 2017) %>%
  select(p_id, rec_all, rec_most, rec_soon, rec_sleep, rec_driving, rec_work, rec_store, rec_small_group, rec_large_group, rec_morn, rec_aft, rec_eve)
to_recep_fit <- grm(to_recep_data %>% select(-p_id))
to_recep_scores <- tibble(to_recep_data %>% select(p_id), 
                          to_recep = ltm::factor.scores(to_recep_fit, resp.patterns = to_recep_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, to_recep_scores, by = "p_id")

hu_recep_data <- survey_data %>%
  filter(survey_hazard == "TC") %>%
  select(p_id, rec_most, rec_time)
hu_recep_fit <- grm(hu_recep_data %>% select(-p_id))
hu_recep_scores <- tibble(hu_recep_data %>% select(p_id),
                          hu_recep = ltm::factor.scores(hu_recep_fit, resp.patterns = hu_recep_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, hu_recep_scores, by = "p_id")

to_subj_comp_data <- survey_data %>%
  filter(survey_hazard == "WX" & !survey_year == 2017) %>%
  select(p_id, alert_und, tor_watchwarn_und, tor_map_und, tor_radar_und, svr_watchwarn_und)
to_subj_comp_fit <- grm(to_subj_comp_data %>% select(-p_id))
to_subj_comp_scores <- tibble(to_subj_comp_data  %>% select(p_id), 
                              to_subj_comp = ltm::factor.scores(to_subj_comp_fit, resp.patterns = to_subj_comp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, to_subj_comp_scores, by = "p_id")

hu_subj_comp_data <- survey_data %>%
  filter(survey_hazard == "TC") %>%
  select(p_id, alert_und, huralerts, hur_map_und, tor_watchwarn_und, flood_watchwarn_und, flood_srg_und)
hu_subj_comp_fit <- grm(hu_subj_comp_data %>% select(-p_id))
hu_subj_comp_scores <- tibble(hu_subj_comp_data %>% select(p_id),
                          hu_subj_comp = ltm::factor.scores(hu_subj_comp_fit, resp.patterns = hu_subj_comp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, hu_subj_comp_scores, by = "p_id")

survey_data <- survey_data %>% 
  mutate(to_watch_warn_group = case_when(
    survey_hazard == "WX" & is.na(torwatch) == FALSE ~ "watch",
    survey_hazard == "WX" & is.na(torwarn) == FALSE ~ "warn")) %>% 
  mutate(to_watch_warn_correct = case_when(
    to_watch_warn_group == "watch"  & torwatch == 1 ~ 1,
    to_watch_warn_group == "watch"  & torwatch != 1 ~ 0,
    to_watch_warn_group == "warn"  & torwarn == 2 ~ 1,
    to_watch_warn_group == "warn"  & torwarn != 2 ~ 0)) %>% 
  mutate(to_warn_time_correct = ifelse(warn_time == 1 & warn_time_minutes < 30, 1, 0)) %>% 
  mutate(to_watch_time_correct = ifelse(watch_time == 2 & watch_time_hours >= 1 & watch_time_hours <= 3, 1, 0)) %>% 
  mutate(to_warn_size_correct = ifelse(warn_size == 1 | warn_size == 2, 1, 0)) %>% # not including these for now
  mutate(to_watch_size_correct = ifelse(watch_size == 3 | watch_size == 4 | watch_size == 5, 1, 0)) # not including these for now
to_obj_comp_data <- survey_data %>%
  filter(survey_hazard == "WX" & !survey_year == 2017) %>%
  select(p_id, to_watch_warn_correct, to_warn_time_correct, to_watch_time_correct)
to_obj_comp_fit <- ltm(to_obj_comp_data %>% select(-p_id) ~ z1)
to_obj_comp_scores <- tibble(to_obj_comp_data  %>% select(p_id), 
                              to_obj_comp = ltm::factor.scores(to_obj_comp_fit, resp.patterns = to_obj_comp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, to_obj_comp_scores, by = "p_id")

survey_data <- survey_data %>% 
  mutate(hu_watch_warn_group = case_when(
    survey_hazard == "TC" & is.na(hurwatch) == FALSE ~ "hurwatch",
    survey_hazard == "TC" & is.na(hurwarn) == FALSE ~ "hurwarn")) %>% 
  mutate(hu_watch_warn_correct = case_when(
    hu_watch_warn_group == "watch" & hurwatch == 1 ~ 1,
    hu_watch_warn_group == "watch" & hurwatch != 1 ~ 0,
    hu_watch_warn_group == "warn" & hurwarn == 2 ~ 1,
    hu_watch_warn_group == "warn" & hurwarn != 2 ~ 0)) %>% 
  mutate(ts_warn_time_correct = ifelse(ts_warn_time == 3, 1, 0)) %>% 
  mutate(hur_warn_time_correct = ifelse(hur_warn_time == 3, 1, 0)) %>% 
  mutate(srg_warn_time_correct = ifelse(srg_warn_time == 3, 1, 0)) %>% 
  mutate(ts_watch_time_correct = ifelse(ts_watch_time == 4, 1, 0)) %>% 
  mutate(hur_watch_time_correct = ifelse(hur_watch_time == 4, 1, 0)) %>% 
  mutate(srg_watch_time_correct = ifelse(srg_watch_time == 4, 1, 0))
hu_obj_comp_data <- survey_data %>%
  filter(survey_hazard == "TC") %>%
  select(p_id, hu_watch_warn_correct, ts_warn_time_correct, hur_warn_time_correct, srg_warn_time_correct, 
         ts_watch_time_correct, hur_watch_time_correct, srg_watch_time_correct)
hu_obj_comp_fit <- ltm(hu_obj_comp_data %>% select(-p_id) ~ z1)
hu_obj_comp_scores <- tibble(hu_obj_comp_data  %>% select(p_id), 
                             hu_obj_comp = ltm::factor.scores(hu_obj_comp_fit, resp.patterns = hu_obj_comp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, hu_obj_comp_scores, by = "p_id")

to_resp_data <- survey_data %>%
  filter(survey_hazard == "WX" & !survey_year == 2017) %>%
  select(p_id, resp_prot, resp_sleep, resp_driving, resp_work, resp_store, resp_small_group, resp_large_group, resp_morn, resp_aft, resp_eve)
to_resp_fit <- grm(to_resp_data %>% select(-p_id))
to_resp_scores <- tibble(to_resp_data %>% select(p_id), 
                          to_resp = ltm::factor.scores(to_resp_fit, resp.patterns = to_resp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, to_resp_scores, by = "p_id")

hu_resp_data <- survey_data %>%
  filter(survey_hazard == "TC") %>%
  select(p_id, resp_always, resp_ignore) %>% 
  mutate(resp_ignore = (resp_ignore * -1) + 6)
hu_resp_fit <- grm(hu_resp_data %>% select(-p_id))
hu_resp_scores <- tibble(hu_resp_data %>% select(p_id),
                          hu_resp = ltm::factor.scores(hu_resp_fit, resp.patterns = hu_resp_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, hu_resp_scores, by = "p_id")

all_trust_data <- survey_data %>% 
  select(p_id, nws_trust, lotv_trust, natv_trust, em_trust)
all_trust_fit <- grm(all_trust_data %>% select(-p_id))
all_trust_scores <- tibble(all_trust_data %>% select(p_id),
                         all_trust = ltm::factor.scores(all_trust_fit, resp.patterns = all_trust_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, all_trust_scores, by = "p_id")

all_ready_data <- survey_data %>%
  select(p_id, rq_4:rq_8) %>% 
  mutate_at(vars(rq_4:rq_8), list(~ifelse(. == 1, 1, 0)))
all_ready_fit <- ltm(all_ready_data %>% select(-p_id) ~ z1)
all_ready_scores <- tibble(all_ready_data %>% select(p_id),
                           all_ready = ltm::factor.scores(all_ready_fit, resp.patterns = all_ready_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, all_ready_scores, by = "p_id")

to_eff_data <- survey_data %>%
  filter(survey_hazard == "WX", survey_year == 2018) %>%
  select(p_id, tor_eff1, tor_eff2, tor_eff3, tor_eff4, tor_eff5, tor_eff6, tor_eff7, tor_eff8)
to_eff_fit <- grm(to_eff_data %>% select(-p_id))
to_eff_scores <- tibble(to_eff_data %>% select(p_id), 
                         to_eff = ltm::factor.scores(to_eff_fit, resp.patterns = to_eff_data %>% select(-p_id))$score.dat$z1)
survey_data <- left_join(survey_data, to_eff_scores, by = "p_id")

# survey_data$myth_tall_correct <- ifelse(survey_data$myth_tall == 0, 1, 0)
# survey_data$myth_mtns_correct <- ifelse(survey_data$myth_mtns == 1, 1, 0)
# survey_data$myth_brdg_correct <- ifelse(survey_data$myth_brdge == 1, 1, 0)
# survey_data$myth_open_correct <- ifelse(survey_data$myth_open == 0, 1, 0)
# myth_data <- survey_data %>%
#   filter(survey_year == 2017) %>%
#   select(myth_tall_correct, myth_mtns_correct, myth_brdg_correct, myth_open_correct)
# myth_fit <- ltm(myth_data ~ z1)
# myth_scores <- tibble(p_id = filter(survey_data, survey_year == 2017)$p_id, myth = ltm::factor.scores(myth_fit, resp.patterns = myth_data)$score.dat$z1)
# survey_data <- left_join(survey_data, myth_scores, by = "p_id")


# Write Data -----------------------------
write_csv(survey_data, paste0(outputs, "base_survey_data.csv"))
