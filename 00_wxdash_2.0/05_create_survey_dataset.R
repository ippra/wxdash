# library(ltm)
library(data.table)
library(readxl)
library(tidyverse)

# psych is required. It is called as psych::alpha() rather than attached,
# because attaching it masks several dplyr and ggplot2 functions.

downloads <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!
location_files <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/WX25/WX25 Raw Data/location_files/" # define locally!!!

# Import Survey Data -----------------------------------------------------------
WX17 <- read_csv(paste0(downloads, "WX17_data_wtd.csv")) |>
  mutate(
    survey_year = "2017",
    survey_hazard = "WX",
    survey_language = "English",
    p_id = as.character(p_id)) |>
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
survey_data <- as_tibble(survey_data)

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

# Add County and CWA -----------------------------------------------------------
# Temporary. This belongs in the individual compile files and will move there;
# it lives here for now so the older surveys do not have to be revisited. The
# methodology matches WX25/WX25 Raw Data/english_files/compile_dataset.R.
# zip is already padded to five characters above, so it is not re-padded here.
zip_to_county <- read_excel(
  paste0(location_files, "ZIP_COUNTY_122025.xlsx"),
  col_types = c("text", "text", "text", "text",
                "numeric", "numeric", "numeric", "numeric")
) |> # https://www.huduser.gov/portal/datasets/usps_crosswalk.html
  select(ZIP, FIPS = COUNTY, RES_RATIO) |>
  arrange(ZIP, -RES_RATIO) |>
  distinct(ZIP, .keep_all = TRUE)

survey_data <- survey_data |>
  left_join(zip_to_county |> select(-RES_RATIO), by = c("zip" = "ZIP"))

# A self-reported state that disagrees with the state implied by the zip is
# almost always a zip entry error, and would break county-within-state nesting
# in multilevel models. TC22 carries no state column, so a missing state means
# the check cannot be run rather than that it failed, and those respondents are
# kept. WX25's version has no such case and so does not need that condition.
state_fips_names <- c(
  "01" = "Alabama", "02" = "Alaska", "04" = "Arizona", "05" = "Arkansas",
  "06" = "California", "08" = "Colorado", "09" = "Connecticut", "10" = "Delaware",
  "11" = "Washington, D.C.", "12" = "Florida", "13" = "Georgia", "15" = "Hawaii",
  "16" = "Idaho", "17" = "Illinois", "18" = "Indiana", "19" = "Iowa",
  "20" = "Kansas", "21" = "Kentucky", "22" = "Louisiana", "23" = "Maine",
  "24" = "Maryland", "25" = "Massachusetts", "26" = "Michigan", "27" = "Minnesota",
  "28" = "Mississippi", "29" = "Missouri", "30" = "Montana", "31" = "Nebraska",
  "32" = "Nevada", "33" = "New Hampshire", "34" = "New Jersey", "35" = "New Mexico",
  "36" = "New York", "37" = "North Carolina", "38" = "North Dakota", "39" = "Ohio",
  "40" = "Oklahoma", "41" = "Oregon", "42" = "Pennsylvania", "44" = "Rhode Island",
  "45" = "South Carolina", "46" = "South Dakota", "47" = "Tennessee", "48" = "Texas",
  "49" = "Utah", "50" = "Vermont", "51" = "Virginia", "53" = "Washington",
  "54" = "West Virginia", "55" = "Wisconsin", "56" = "Wyoming")

survey_data <- survey_data |>
  mutate(state_from_zip = unname(
    state_fips_names[str_pad(substr(FIPS, 1, 2), 2, side = "left", pad = "0")]
  ))

survey_data |>
  filter(!is.na(state), !is.na(state_from_zip), state != state_from_zip) |>
  count(survey_hazard, state, state_from_zip)

survey_data <- survey_data |>
  filter(is.na(state) | is.na(state_from_zip) | state == state_from_zip) |>
  select(-state_from_zip)

county_to_cwa_data <- read_csv(
  paste0(outputs, "county_to_cwa_data.csv"),
  col_types = cols_only(GEOID = col_character(), CWA = col_character())
)

survey_data <- survey_data |>
  left_join(county_to_cwa_data, by = c("FIPS" = "GEOID"))

# Census Margin Categories -----------------------------------------------------
# Temporary, as above. Cells and labels match get_margins.R in acs_survey_weights
# and the poststrat tables written by 04, so the survey and the census margins
# share the same cells and can be joined for raking and MRP.
survey_data <- survey_data |>
  mutate(
    AGE_GROUP = case_when(
      between(age, 18, 29) ~ "(1) 18-29",
      between(age, 30, 49) ~ "(2) 30-49",
      between(age, 50, 64) ~ "(3) 50-64",
      age >= 65            ~ "(4) 65+",
      .default = NA_character_
    ),
    EDUC_GROUP = case_when(
      edu %in% 1:2 ~ "(1) HS or less",
      edu %in% 3:5 ~ "(2) Some college / 2-yr degree",
      edu %in% 6:8 ~ "(3) 4-yr / post-graduate degree",
      .default = NA_character_
    ),
    GENDER_GROUP = case_when(
      gend == 1 ~ "(1) Male",
      gend == 0 ~ "(2) Female",
      .default = NA_character_
    ),
    INCOME_GROUP = case_when(
      income == 1 ~ "(1) < $50,000",
      income >= 2 ~ "(2) >= $50,000",
      .default = NA_character_
    ),
    # Other spans race 3:7, not WX25's 3:6. The pre-2023 instruments carry a
    # seventh race category that was renumbered to 6 later; without the 7 the
    # recode would silently drop 86 respondents across eleven surveys.
    RACE_GROUP = case_when(
      hisp == 1                 ~ "(3) Hispanic",
      hisp == 0 & race == 1     ~ "(1) White",
      hisp == 0 & race == 2     ~ "(2) Black",
      hisp == 0 & race %in% 3:7 ~ "(4) Other",
      .default = NA_character_
    ),
    # Taken from FIPS rather than the self-reported state WX25 uses, because
    # TC22 has no state column. The two agree wherever both exist, since the
    # check above dropped the cases where they disagreed. Alaska and Hawaii are
    # left NA because the ACS benchmarks are CONUS only.
    STATE_NAME = unname(
      state_fips_names[str_pad(substr(FIPS, 1, 2), 2, side = "left", pad = "0")]
    ),
    CENSUS_REGION = case_when(
      STATE_NAME %in% c("Connecticut", "Maine", "Massachusetts", "New Hampshire",
                        "Rhode Island", "Vermont", "New Jersey", "New York",
                        "Pennsylvania") ~ "(1) Northeast",
      STATE_NAME %in% c("Illinois", "Indiana", "Michigan", "Ohio", "Wisconsin",
                        "Iowa", "Kansas", "Minnesota", "Missouri", "Nebraska",
                        "North Dakota", "South Dakota") ~ "(2) Midwest",
      STATE_NAME %in% c("Delaware", "Florida", "Georgia", "Maryland",
                        "North Carolina", "South Carolina", "Virginia",
                        "Washington, D.C.", "West Virginia", "Alabama",
                        "Kentucky", "Mississippi", "Tennessee", "Arkansas",
                        "Louisiana", "Oklahoma", "Texas") ~ "(3) South",
      STATE_NAME %in% c("Arizona", "Colorado", "Idaho", "Montana", "Nevada",
                        "New Mexico", "Utah", "Wyoming", "California", "Oregon",
                        "Washington") ~ "(4) West",
      .default = NA_character_
    )
  )

# Alert Data -------------------------------------------------------------------
cwa_alert_data <- read_csv(paste0(outputs, "base_cwa_alert_data.csv"))
county_alert_data <- read_csv(paste0(outputs, "base_county_alert_data.csv"))

cwa_alert_data <- cwa_alert_data |> rename_at(vars(FLOOD:HURR), ~paste0("CWA_", .))
county_alert_data <- county_alert_data |> rename_at(vars(COLD:TORN), ~paste0("FIPS_", .))

survey_data <- left_join(survey_data, cwa_alert_data, by = c("CWA" = "WFO")) # waiting on this
survey_data <- left_join(survey_data, county_alert_data, by = c("FIPS" = "GEOID")) # waiting on this

# County Covariates ------------------------------------------------------------
# Social vulnerability and hazard risk, the full SVI and NRI county tables built
# by 04, so any of the 507 fields can be called in later models.
#
# This replaces four earlier joins -- base_cwa_census_data, base_county_census_data,
# base_cwa_risk_data and base_county_risk_data. Those were orphans: no script in
# this directory rebuilt them, so they could not be regenerated if the crosswalk
# changed. They were also narrower versions of what is read here. The census
# pair carried SVI 2020 bolted onto the old poststrat table, superseded by SVI
# 2022; the risk pair was 14 hand-renamed columns from the same NRI download 04
# now reads in full.
#
# The loss is CWA-level SVI and risk, which this lookup does not carry. No model
# used them. To get them back, aggregate county to CWA weighted by DEMGRP_POP
# from the poststrat table -- the same aggregation the MRP predictions use, so
# the two stay consistent rather than coming from separate sources.
county_covariates <- read_csv(
  paste0(outputs, "base_county_covariates.csv"),
  col_types = cols(FIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) # guess_max as in 04: four NRI *_EVNTS columns are empty for thousands of rows

survey_data <- left_join(survey_data, county_covariates, by = "FIPS")

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

write_csv(survey_data, paste0(outputs, "base_survey_data_NEW.csv"))
