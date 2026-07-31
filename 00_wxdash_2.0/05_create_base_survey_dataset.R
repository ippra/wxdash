# library(ltm)
library(data.table)
library(tidyverse)

# psych is required. It is called as psych::alpha() rather than attached,
# because attaching it masks several dplyr and ggplot2 functions.

downloads <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Import Survey Data -----------------------------------------------------------
WX17 <- read_csv(paste0(downloads, "WX17_data_wtd.csv")) |>
  mutate(
    survey_year = "2017",
    survey_hazard = "WX",
    survey_language = "English",
    p_id = as.character(p_id),
    nws_region = case_when(
      region == 1 ~ "Eastern Region",
      region == 2 ~ "Southern Region",
      region == 3 ~ "Central Region",
      region == 4 ~ "Western Region"
    )
  ) |>
  select(-c(rec_all:rec_time)) |>  # remove because scale changes form 1-7 to 1-5 in 2018/2019
  select(-c(resp_ignore:resp_unsure)) # remove because scale changes form 1-7 to 1-5 in 2018/2019
WX18 <- read_csv(paste0(downloads, "WX18_data_wtd.csv")) |>
  mutate(
    survey_year = "2018",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX19 <- read_csv(paste0(downloads, "WX19_data_wtd.csv")) |>
  mutate(
    survey_year = "2019",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX20 <- read_csv(paste0(downloads, "WX20_data_wtd.csv")) |>
  mutate(
    survey_year = "2020",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX21 <- read_csv(paste0(downloads, "WX21_data_wtd.csv")) |>
  mutate(
    survey_year = "2021",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX22 <- read_csv(paste0(downloads, "WX22_data_wtd.csv")) |>
  mutate(
    survey_year = "2022",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX23 <- read_csv(paste0(downloads, "WX23_data_wtd.csv")) |>
  mutate(
    survey_year = "2023",
    survey_hazard = "WX",
    survey_language = "English"
  )
WX24 <- read_csv(paste0(downloads, "WX24_data_wtd.csv")) |>
  mutate(
    survey_year = "2024",
    survey_hazard = "WX",
    survey_language = "English",
    end_date = as.Date(end_date),
    rand_aft = as.character(rand_aft),
    rand_eve = as.character(rand_eve)
  )
WX25 <- read_csv(paste0(downloads, "WX25_data_wtd.csv")) |>
  mutate(
    survey_year = "2025",
    survey_hazard = "WX",
    survey_language = "English",
    end_date = as.Date(end_date),
    rand_aft = as.character(rand_aft),
    rand_eve = as.character(rand_eve)
  )

TC20 <- read_csv(paste0(downloads, "TC20_data_wtd.csv")) |>
  mutate(
    survey_year = "2020",
    survey_hazard = "TC",
    survey_language = "English"
  )
TC21 <- read_csv(paste0(downloads, "TC21_data_wtd.csv")) |>
  mutate(
    survey_year = "2021",
    survey_hazard = "TC",
    survey_language = "English"
  )
TC22 <- read_csv(paste0(downloads, "TC22_data_wtd.csv")) |>
  mutate(
    survey_year = "2022",
    survey_hazard = "TC",
    survey_language = "English"
  )
TC23 <- read_csv(paste0(downloads, "TC23_data_wtd.csv")) |>
  mutate(
    survey_year = "2023",
    survey_hazard = "TC",
    survey_language = "English"
  )
TC24 <- read_csv(paste0(downloads, "TC24_data_wtd.csv")) |>
  mutate(
    survey_year = "2024",
    survey_hazard = "TC",
    survey_language = "English",
    end_date = as.Date(end_date)
  )
TC25 <- read_csv(paste0(downloads, "TC25_data_wtd.csv")) |>
  mutate(
    survey_year = "2025",
    survey_hazard = "TC",
    survey_language = "English",
    end_date = as.Date(end_date)
  )

WW21 <- read_csv(paste0(downloads, "WW21_data_wtd.csv")) |>
  mutate(
    survey_year = "2021",
    survey_hazard = "WW",
    survey_language = "English"
  )
WW22 <- read_csv(paste0(downloads, "WW22_data_wtd.csv")) |>
  mutate(
    survey_year = "2022",
    survey_hazard = "WW",
    survey_language = "English"
  )
WW23 <- read_csv(paste0(downloads, "WW23_data_wtd.csv")) |>
  mutate(
    survey_year = "2023",
    survey_hazard = "WW",
    survey_language = "English"
  )
WW24 <- read_csv(paste0(downloads, "WW24_data_wtd.csv")) |>
  mutate(
    survey_year = "2024",
    survey_hazard = "WW",
    survey_language = "English",
    end_date = as.Date(end_date)
  )
WW25 <- read_csv(paste0(downloads, "WW25_data_wtd.csv")) |>
  mutate(
    survey_year = "2025",
    survey_hazard = "WW",
    survey_language = "English",
    end_date = as.Date(end_date_utc) # WW25 ships end_date_utc, not end_date
  )

FL24 <- read_csv(paste0(downloads, "FL24_data_wtd.csv")) |>
  mutate(
    survey_year = "2024",
    survey_hazard = "FL",
    survey_language = "English"
  )
FL25 <- read_csv(paste0(downloads, "FL25_data_wtd.csv")) |>
  mutate(
    survey_year = "2025",
    survey_hazard = "FL",
    survey_language = "English"
  )

survey_data <- rbindlist(list(WX17, WX18, WX19, WX20, WX21, WX22, WX23, WX24, WX25,
                              TC20, TC21, TC22, TC23, TC24, TC25,
                              WW21, WW22, WW23, WW24, WW25,
                              FL24, FL25), fill = TRUE, ignore.attr = TRUE)

# Ten of the source files store zip as a number, which drops the leading zero on
# every 0xxxx code (CT, MA, ME, NH, NJ, RI, VT). rbindlist coerces the mix to
# character, so repair to five digits here. US zips are always five digits, so a
# shorter value can only have lost leading zeros; str_sub trims the handful of
# respondents who typed zip+4.
survey_data <- survey_data |>
  mutate(
    zip = str_pad(str_sub(as.character(zip), 1, 5),
                  width = 5, side = "left", pad = "0")
  )

survey_data |> summarise(n = n(), n_id = n_distinct(p_id)) 

# Alert Data -------------------------------------------------------------------
cwa_alert_data <- read_csv(paste0(outputs, "base_cwa_alert_data.csv"))
county_alert_data <- read_csv(paste0(outputs, "base_county_alert_data.csv"))

cwa_alert_data <- cwa_alert_data |> rename_at(vars(FLOOD:HURR), ~paste0("CWA_", .))
county_alert_data <- county_alert_data |> rename_at(vars(COLD:TORN), ~paste0("FIPS_", .))

# survey_data <- left_join(survey_data, cwa_alert_data, by = c("CWA" = "WFO")) # waiting on this
# survey_data <- left_join(survey_data, county_alert_data, by = c("FIPS" = "GEOID")) # waiting on this

# Census Data ------------------------------------------------------------------
# cwa_census_data <- read_csv(paste0(outputs, "base_cwa_census_data.csv"))
# county_census_data <- read_csv(paste0(outputs, "base_county_census_data.csv"))

# cwa_svi_data <- cwa_census_data |>
#   select(CWA, CWA_EP_POV150:CWA_RPL_THEMES) |>
#   distinct(CWA, .keep_all = TRUE)

# county_svi_data <- county_census_data |>
#   select(FIPS, FIPS_EP_POV150:FIPS_RPL_THEMES) |>
#   distinct(FIPS, .keep_all = TRUE)

# survey_data <- left_join(survey_data, cwa_svi_data, by = "CWA")
# survey_data <- left_join(survey_data, county_svi_data, by = "FIPS")

# Measures for Models ----------------------------------------------------------
to_recep_data <- survey_data |>
  filter(survey_hazard == "WX", survey_year != "2017") |>
  select(p_id, rec_all, rec_soon, rec_miss, rec_area, rec_time) |>
  mutate(
    # rec_time is reversed here and NOT in the TC/WW/FL scales below, because the
    # item differs by survey. In WX it reads "Sometimes I am not sure what time
    # tornado warnings begin and end for my area" (negative); elsewhere it reads
    # "I receive new information about my location as soon as it is available"
    # (positive). Do not make the reverse-coding uniform across the four scales.
    across(c(rec_miss, rec_area, rec_time), ~6 - .),
    to_recep_scale = if_else(
      rowSums(!is.na(pick(rec_all, rec_soon, rec_miss, rec_area, rec_time))) >= 4,
      rowMeans(pick(rec_all, rec_soon, rec_miss, rec_area, rec_time), na.rm = TRUE),
      NA_real_))
cor(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
psych::alpha(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, to_recep_data |> select(p_id, to_recep_scale), by = "p_id")

hu_recep_data <- survey_data |>
  filter(survey_hazard == "TC") |>
  select(p_id, rec_most, rec_miss, rec_time, rec_screen) |>
  mutate(
    # rec_time is positively worded in TC/WW/FL, so it is not reversed here.
    across(c(rec_miss, rec_screen), ~6 - .),
    hu_recep_scale = if_else(
      rowSums(!is.na(pick(rec_most, rec_miss, rec_time, rec_screen))) >= 3,
      rowMeans(pick(rec_most, rec_miss, rec_time, rec_screen), na.rm = TRUE),
      NA_real_))
cor(hu_recep_data |> select(-p_id, -hu_recep_scale), use = "pairwise.complete.obs")
psych::alpha(hu_recep_data |> select(-p_id, -hu_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, hu_recep_data |> select(p_id, hu_recep_scale), by = "p_id")

ww_recep_data <- survey_data |>
  filter(survey_hazard == "WW") |>
  select(p_id, rec_most, rec_miss, rec_time, rec_screen) |>
  mutate(
    across(c(rec_miss, rec_screen), ~6 - .),
    ww_recep_scale = if_else(
      rowSums(!is.na(pick(rec_most, rec_miss, rec_time, rec_screen))) >= 3,
      rowMeans(pick(rec_most, rec_miss, rec_time, rec_screen), na.rm = TRUE),
      NA_real_))
cor(ww_recep_data |> select(-p_id, -ww_recep_scale), use = "pairwise.complete.obs")
psych::alpha(ww_recep_data |> select(-p_id, -ww_recep_scale), use = "pairwise.complete.obs")
survey_data <- left_join(survey_data, ww_recep_data |> select(p_id, ww_recep_scale), by = "p_id")

fl_recep_data <- survey_data |>
  filter(survey_hazard == "FL") |>
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

