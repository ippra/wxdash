library(data.table)
library(tidyverse)

# psych is required. It is called as psych::alpha() rather than attached,
# because attaching it masks several dplyr and ggplot2 functions.

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Import Survey Data -----------------------------------------------------------
# The 22 built datasets come from the wxsurveys repository, which now derives
# SURVEY_YEAR, SURVEY_HAZARD and SURVEY_LANGUAGE itself. Twenty-two blocks that
# existed only to stamp those three columns are gone, and so are the per-wave
# date and rand_* coercions: END_DATE is POSIXct in every wave, WW25's
# end_date_utc is reconciled upstream, and the rand_* items are uniformly hms.
waves <- c(
  "WX17", "WX18", "WX19", "WX20", "WX21", "WX22", "WX23", "WX24", "WX25",
  "TC20", "TC21", "TC22", "TC23", "TC24", "TC25",
  "WW21", "WW22", "WW23", "WW24", "WW25",
  "FL24", "FL25"
)

read_wave <- function(wave) {
  read_csv(
    paste0(survey_files, wave, "_data_wtd.csv"),
    show_col_types = FALSE,
    guess_max = Inf
  ) |>
    mutate(P_ID = as.character(P_ID)) # WX17 alone stores it as a number
}

wave_data <- set_names(map(waves, read_wave), waves)

# WX17 asked the reception and response batteries on a 1-7 scale; 2018 onward
# use 1-5, so the WX17 columns are dropped rather than pooled.
wave_data <- wave_data |>
  modify_at(
    "WX17",
    ~select(.x, -c(rec_all:rec_time), -c(resp_ignore:resp_unsure))
  )

survey_data <- rbindlist(wave_data, fill = TRUE, ignore.attr = TRUE) |>
  as_tibble()

# Downstream names. FIPS and CWA are what 06 and 07 model on, and the ZIP_
# prefix upstream records that all three are derived from the respondent's zip
# rather than from anything self-reported.
survey_data <- survey_data |>
  rename(
    p_id = P_ID,
    FIPS = ZIP_FIPS,
    CWA = ZIP_CWA,
    STATE_NAME = ZIP_STATE,
    survey_hazard = SURVEY_HAZARD,
    survey_language = SURVEY_LANGUAGE
  ) |>
  mutate(survey_year = as.character(SURVEY_YEAR)) |>
  select(-SURVEY_YEAR)

survey_data |> summarise(n = n(), n_id = n_distinct(p_id))

# Alert Data -------------------------------------------------------------------
alert_hazards <- c("COLD", "FREEZE", "FIRE", "FLOOD", "HEAT", "HURR", "ICE",
                   "SNOW", "TORN", "WIND")

cwa_alert_data <- read_csv(paste0(outputs, "02_cwa_alert_counts.csv"),
                           show_col_types = FALSE) |>
  select(WFO, any_of(alert_hazards)) |>
  rename_with(~paste0("CWA_", .x), .cols = -WFO)

county_alert_data <- read_csv(
  paste0(outputs, "03_county_alert_counts.csv"),
  col_types = cols(GEOID = col_character(), .default = col_guess())
) |>
  select(GEOID, any_of(alert_hazards)) |>
  rename_with(~paste0("FIPS_", .x), .cols = -GEOID)

survey_data <- left_join(survey_data, cwa_alert_data, by = c("CWA" = "WFO"))
survey_data <- left_join(survey_data, county_alert_data, by = c("FIPS" = "GEOID"))

# County Covariates ------------------------------------------------------------
county_covariates <- read_csv(
  paste0(outputs, "04_county_covariates.csv"),
  col_types = cols(FIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) # guess_max as in 04: four NRI *_EVNTS columns are empty for thousands of rows

survey_data <- left_join(survey_data, county_covariates, by = "FIPS")

# Reception Scales -------------------------------------------------------------
to_recep_data <- survey_data |>
  filter(survey_hazard == "Severe Weather (WX)", survey_year != "2017") |>
  select(p_id, rec_all, rec_soon, rec_miss, rec_area, rec_time) |>
  mutate(
    # rec_time is reversed here and NOT in the TC/WW/FL scales below, because the
    # item differs by survey. In WX it reads "Sometimes I am not sure what time
    # tornado warnings begin and end for my area" (negative); elsewhere it reads
    # "I receive new information about my location as soon as it is available"
    # (positive). Do not make the reverse-coding uniform across the four scales.
    across(c(rec_miss, rec_area, rec_time), ~6 - .),
    to_recep_scale = if_else(
      rowSums(!is.na(pick(rec_all, rec_soon, rec_miss, rec_area, rec_time))) >= 2,
      rowMeans(pick(rec_all, rec_soon, rec_miss, rec_area, rec_time), na.rm = TRUE),
      NA_real_))
cor(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
psych::alpha(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, to_recep_data |> select(p_id, to_recep_scale), by = "p_id")

hu_recep_data <- survey_data |>
  filter(survey_hazard == "Tropical Cyclone (TC)") |>
  select(p_id, rec_most, rec_miss, rec_time, rec_screen) |>
  mutate(
    # rec_time is positively worded in TC/WW/FL, so it is not reversed here.
    across(c(rec_miss, rec_screen), ~6 - .),
    hu_recep_scale = if_else(
      rowSums(!is.na(pick(rec_most, rec_miss, rec_time, rec_screen))) >= 2,
      rowMeans(pick(rec_most, rec_miss, rec_time, rec_screen), na.rm = TRUE),
      NA_real_))
cor(hu_recep_data |> select(-p_id, -hu_recep_scale), use = "pairwise.complete.obs")
psych::alpha(hu_recep_data |> select(-p_id, -hu_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, hu_recep_data |> select(p_id, hu_recep_scale), by = "p_id")

ww_recep_data <- survey_data |>
  filter(survey_hazard == "Winter Weather (WW)") |>
  select(p_id, rec_most, rec_miss, rec_time, rec_screen) |>
  mutate(
    across(c(rec_miss, rec_screen), ~6 - .),
    ww_recep_scale = if_else(
      rowSums(!is.na(pick(rec_most, rec_miss, rec_time, rec_screen))) >= 2,
      rowMeans(pick(rec_most, rec_miss, rec_time, rec_screen), na.rm = TRUE),
      NA_real_))
cor(ww_recep_data |> select(-p_id, -ww_recep_scale), use = "pairwise.complete.obs")
psych::alpha(ww_recep_data |> select(-p_id, -ww_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, ww_recep_data |> select(p_id, ww_recep_scale), by = "p_id")

fl_recep_data <- survey_data |>
  filter(survey_hazard == "Flooding (FL)") |>
  select(p_id, rec_most_fl, rec_miss_fl, rec_time) |>
  mutate(
    across(c(rec_miss_fl), ~6 - .),
    fl_recep_scale = if_else(
      rowSums(!is.na(pick(rec_most_fl, rec_miss_fl, rec_time))) >= 2,
      rowMeans(pick(rec_most_fl, rec_miss_fl, rec_time), na.rm = TRUE),
      NA_real_))
cor(fl_recep_data |> select(-p_id, -fl_recep_scale), use = "pairwise.complete.obs")
psych::alpha(fl_recep_data |> select(-p_id, -fl_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, fl_recep_data |> select(p_id, fl_recep_scale), by = "p_id")

# Comprehension Scales ---------------------------------------------------------

to_subj_comp_data <- survey_data |>
  filter(survey_hazard == "Severe Weather (WX)", survey_year != "2017") |>
  select(p_id, alert_und, tor_watchwarn_und, tor_map_und, tor_radar_und, svr_watchwarn_und) |>
  mutate(
    to_subj_comp_scale = if_else(
      rowSums(!is.na(pick(alert_und, tor_watchwarn_und, tor_map_und, tor_radar_und, svr_watchwarn_und))) >= 2,
      rowMeans(pick(alert_und, tor_watchwarn_und, tor_map_und, tor_radar_und, svr_watchwarn_und), na.rm = TRUE),
      NA_real_))
cor(to_subj_comp_data |> select(-p_id, -to_subj_comp_scale), use = "pairwise.complete.obs")
psych::alpha(to_subj_comp_data |> select(-p_id, -to_subj_comp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, to_subj_comp_data |> select(p_id, to_subj_comp_scale), by = "p_id")

hu_subj_comp_data <- survey_data |>
  filter(survey_hazard == "Tropical Cyclone (TC)") |>
  select(p_id, alert_und, huralerts, hur_map_und, tor_watchwarn_und, flood_watchwarn_und, flood_srg_und) |>
  mutate(
    hu_subj_comp_scale = if_else(
      rowSums(!is.na(pick(alert_und, huralerts, hur_map_und, tor_watchwarn_und, flood_watchwarn_und, flood_srg_und))) >= 2,
      rowMeans(pick(alert_und, huralerts, hur_map_und, tor_watchwarn_und, flood_watchwarn_und, flood_srg_und), na.rm = TRUE),
      NA_real_))
cor(hu_subj_comp_data |> select(-p_id, -hu_subj_comp_scale), use = "pairwise.complete.obs")
psych::alpha(hu_subj_comp_data |> select(-p_id, -hu_subj_comp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, hu_subj_comp_data |> select(p_id, hu_subj_comp_scale), by = "p_id")

ww_subj_comp_data <- survey_data |>
  filter(survey_hazard == "Winter Weather (WW)") |>
  select(p_id, wwalerts, ice_warn_und, bliz_warn_und, cold_warn_und, squall_warn_und) |>
  mutate(
    ww_subj_comp_scale = if_else(
      rowSums(!is.na(pick(wwalerts, ice_warn_und, bliz_warn_und, cold_warn_und, squall_warn_und))) >= 2,
      rowMeans(pick(wwalerts, ice_warn_und, bliz_warn_und, cold_warn_und, squall_warn_und), na.rm = TRUE),
      NA_real_))
cor(ww_subj_comp_data |> select(-p_id, -ww_subj_comp_scale), use = "pairwise.complete.obs")
psych::alpha(ww_subj_comp_data |> select(-p_id, -ww_subj_comp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, ww_subj_comp_data |> select(p_id, ww_subj_comp_scale), by = "p_id")

fl_subj_comp_data <- survey_data |>
  filter(survey_hazard == "Flooding (FL)") |>
  select(p_id, alert_und, flood_wwa_und, flash_wwa_und, flood_srg_und, flood_map_und) |>
  mutate(
    fl_subj_comp_scale = if_else(
      rowSums(!is.na(pick(alert_und, flood_wwa_und, flash_wwa_und, flood_srg_und, flood_map_und))) >= 2,
      rowMeans(pick(alert_und, flood_wwa_und, flash_wwa_und, flood_srg_und, flood_map_und), na.rm = TRUE),
      NA_real_))
cor(fl_subj_comp_data |> select(-p_id, -fl_subj_comp_scale), use = "pairwise.complete.obs")
psych::alpha(fl_subj_comp_data |> select(-p_id, -fl_subj_comp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, fl_subj_comp_data |> select(p_id, fl_subj_comp_scale), by = "p_id")

# Response Scales --------------------------------------------------------------

to_resp_data <- survey_data |>
  filter(survey_hazard == "Severe Weather (WX)", survey_year != "2017") |>
  select(p_id, resp_ignore, resp_prot, resp_busy, resp_unsure) |>
  mutate(
    across(c(resp_ignore, resp_busy, resp_unsure), ~6 - .),
    to_resp_scale = if_else(
      rowSums(!is.na(pick(resp_ignore, resp_prot, resp_busy, resp_unsure))) >= 2,
      rowMeans(pick(resp_ignore, resp_prot, resp_busy, resp_unsure), na.rm = TRUE),
      NA_real_))
cor(to_resp_data |> select(-p_id, -to_resp_scale), use = "pairwise.complete.obs")
psych::alpha(to_resp_data |> select(-p_id, -to_resp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, to_resp_data |> select(p_id, to_resp_scale), by = "p_id")

hu_resp_data <- survey_data |>
  filter(survey_hazard == "Tropical Cyclone (TC)") |>
  select(p_id, resp_ignore, resp_usually, resp_more) |>
  mutate(
    across(c(resp_ignore, resp_usually, resp_more), ~6 - .),
    hu_resp_scale = if_else(
      rowSums(!is.na(pick(resp_ignore, resp_usually, resp_more))) >= 2,
      rowMeans(pick(resp_ignore, resp_usually, resp_more), na.rm = TRUE),
      NA_real_))
cor(hu_resp_data |> select(-p_id, -hu_resp_scale), use = "pairwise.complete.obs")
psych::alpha(hu_resp_data |> select(-p_id, -hu_resp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, hu_resp_data |> select(p_id, hu_resp_scale), by = "p_id")

ww_resp_data <- survey_data |>
  filter(survey_hazard == "Winter Weather (WW)") |>
  select(p_id, resp_ignore, resp_always, resp_more) |>
  mutate(
    across(c(resp_ignore, resp_more), ~6 - .),
    ww_resp_scale = if_else(
      rowSums(!is.na(pick(resp_ignore, resp_always, resp_more))) >= 2,
      rowMeans(pick(resp_ignore, resp_always, resp_more), na.rm = TRUE),
      NA_real_))
cor(ww_resp_data |> select(-p_id, -ww_resp_scale), use = "pairwise.complete.obs")
psych::alpha(ww_resp_data |> select(-p_id, -ww_resp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, ww_resp_data |> select(p_id, ww_resp_scale), by = "p_id")

fl_resp_data <- survey_data |>
  filter(survey_hazard == "Flooding (FL)") |>
  select(p_id, resp_ignore_fl, resp_always_fl, resp_know_fl) |>
  mutate(
    across(c(resp_ignore_fl, resp_know_fl), ~6 - .),
    fl_resp_scale = if_else(
      rowSums(!is.na(pick(resp_ignore_fl, resp_always_fl, resp_know_fl))) >= 2,
      rowMeans(pick(resp_ignore_fl, resp_always_fl, resp_know_fl), na.rm = TRUE),
      NA_real_))
cor(fl_resp_data |> select(-p_id, -fl_resp_scale), use = "pairwise.complete.obs")
psych::alpha(fl_resp_data |> select(-p_id, -fl_resp_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, fl_resp_data |> select(p_id, fl_resp_scale), by = "p_id")

write_csv(survey_data, paste0(outputs, "05_survey_responses.csv"))
