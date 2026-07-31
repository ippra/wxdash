library(data.table)
library(tidyverse)
library(ipumsr)
library(tidycensus)
library(mipfp)
library(sf)

options(scipen = 999)
options(max.print = 99999)
"%ni%" <- Negate("%in%")

downloads <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!
ipums_file <- "/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/Joe Ripberger/acs_survey_weights/ipums_extracts/ACS 2024/usa_00016.xml" # define locally!!!

# Project Settings -------------------------
acs_year <- 2024 # ACS 5-year release
state_fips_exclude <- c("02", "15", "72") # Alaska, Hawaii, Puerto Rico
ipf_seed_constant <- 0.01
ipf_iterations <- 1000
ipf_tolerance <- 0.00000001
ipf_margin_tolerance <- 0.001

# Survey Categories -------------------------
age_levels <- c("(1) 18-29", "(2) 30-49", "(3) 50-64", "(4) 65+")
gender_levels <- c("(1) Male", "(2) Female")
race_levels <- c("(1) White", "(2) Black", "(3) Hispanic", "(4) Other")
educ_levels <- c("(1) HS or less", "(2) Some college / 2-yr degree", "(3) 4-yr / post-graduate degree")
income_levels <- c("(1) < $50,000", "(2) >= $50,000")

# Census API Key -------------------------
# census_api_key("YOUR KEY", install = TRUE)

# Cell Lookup -------------------------
cell_lookup <- expand_grid(
  AGE_GROUP = age_levels,
  GENDER_GROUP = gender_levels,
  RACE_GROUP = race_levels,
  EDUC_GROUP = educ_levels,
  INCOME_GROUP = income_levels
) %>%
  mutate(
    CELL = row_number(),
    .before = 1
  )

# 2. Donor Data -------------------------
ipums_ddi <- read_ipums_ddi(ipums_file)
ipums_data <- read_ipums_micro(ipums_ddi, verbose = TRUE)

eastern_fips <- c(9, 10, 11, 23, 24, 25, 33, 34, 36, 37, 39, 42, 44, 45, 50, 51, 54)
southern_fips <- c(1, 5, 12, 13, 22, 28, 35, 40, 47, 48)
central_fips <- c(8, 17, 18, 19, 20, 21, 26, 27, 29, 31, 38, 46, 55, 56)
western_fips <- c(4, 6, 16, 30, 32, 41, 49, 53)

# Use HHINCOME when it is included in the IPUMS extract. Otherwise,
# reconstruct household income from SERIAL and INCTOT.
if (!"HHINCOME" %in% names(ipums_data)) {

  household_income <- ipums_data %>%
    mutate(
      INCTOT_CLEAN = case_when(
        INCTOT %in% c(9999998, 9999999) ~ NA_real_,
        TRUE ~ as.numeric(INCTOT)
      )
    ) %>%
    group_by(SERIAL) %>%
    summarise(
      HHINCOME = ifelse(
        all(is.na(INCTOT_CLEAN)),
        NA_real_,
        sum(INCTOT_CLEAN, na.rm = TRUE)
      ),
      .groups = "drop"
    )

  ipums_data <- ipums_data %>%
    left_join(
      household_income,
      by = "SERIAL"
    )
}

ipums_data <- ipums_data %>%
  filter(AGE >= 18) %>%
  filter(STATEFIP %ni% c(2, 15)) %>%
  mutate(
    STATE = sprintf("%02d", STATEFIP),

    AGE_GROUP = case_when(
      AGE >= 18 & AGE <= 29 ~ "(1) 18-29",
      AGE >= 30 & AGE <= 49 ~ "(2) 30-49",
      AGE >= 50 & AGE <= 64 ~ "(3) 50-64",
      AGE >= 65             ~ "(4) 65+",
      TRUE                  ~ NA_character_
    ),

    GENDER_GROUP = case_when(
      SEX == 1 ~ "(1) Male",
      SEX == 2 ~ "(2) Female",
      TRUE     ~ NA_character_
    ),

    RACE_GROUP = case_when(
      HISPAN %in% 1:4 ~ "(3) Hispanic",
      RACE == 1       ~ "(1) White",
      RACE == 2       ~ "(2) Black",
      RACE %in% 3:9   ~ "(4) Other",
      TRUE            ~ NA_character_
    ),

    EDUC_GROUP = case_when(
      EDUCD %in% c(
        0, 1, 2, 10:17, 20:26,
        30, 40, 50, 60:64
      ) ~ "(1) HS or less",

      EDUCD %in% c(
        65, 70:71, 80:83, 90
      ) ~ "(2) Some college / 2-yr degree",

      EDUCD %in% c(
        100, 101, 110:116
      ) ~ "(3) 4-yr / post-graduate degree",

      TRUE ~ NA_character_
    ),

    INCOME_GROUP = case_when(
      is.na(HHINCOME)  ~ NA_character_,
      HHINCOME < 50000 ~ "(1) < $50,000",
      HHINCOME >= 50000 ~ "(2) >= $50,000",
      TRUE             ~ NA_character_
    ),

    NWS_REGION = case_when(
      STATEFIP %in% eastern_fips  ~ "(1) Eastern",
      STATEFIP %in% southern_fips ~ "(2) Southern",
      STATEFIP %in% central_fips  ~ "(3) Central",
      STATEFIP %in% western_fips  ~ "(4) Western",
      TRUE                        ~ NA_character_
    )
  ) %>%
  filter(
    !is.na(AGE_GROUP),
    !is.na(GENDER_GROUP),
    !is.na(RACE_GROUP),
    !is.na(EDUC_GROUP),
    !is.na(INCOME_GROUP),
    !is.na(NWS_REGION)
  ) %>%
  select(
    STATE,
    PERWT,
    AGE_GROUP,
    GENDER_GROUP,
    RACE_GROUP,
    EDUC_GROUP,
    INCOME_GROUP,
    NWS_REGION
  )

state_cell_counts <- ipums_data %>%
  group_by(
    STATE,
    AGE_GROUP,
    GENDER_GROUP,
    RACE_GROUP,
    EDUC_GROUP,
    INCOME_GROUP
  ) %>%
  summarise(
    DONOR_POP = sum(PERWT),
    .groups = "drop"
  ) %>%
  right_join(
    expand_grid(
      STATE = sort(unique(ipums_data$STATE)),
      CELL = cell_lookup$CELL
    ) %>%
      left_join(
        cell_lookup,
        by = "CELL"
      ),
    by = c(
      "STATE",
      "AGE_GROUP",
      "GENDER_GROUP",
      "RACE_GROUP",
      "EDUC_GROUP",
      "INCOME_GROUP"
    )
  ) %>%
  mutate(
    DONOR_POP = replace_na(DONOR_POP, 0)
  ) %>%
  select(
    STATE,
    CELL,
    DONOR_POP
  ) %>%
  arrange(
    STATE,
    CELL
  )

state_nws_region <- ipums_data %>%
  select(
    STATE,
    NWS_REGION
  ) %>%
  distinct()

# 3. County Totals -------------------------
acs_variables <- load_variables(
  acs_year,
  "acs5"
)

acs_age_gender <- get_acs(
  geography = "county",
  table = "B01001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
)

acs_race <- get_acs(
  geography = "county",
  table = "B03002",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
)

acs_educ <- get_acs(
  geography = "county",
  table = "B15001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
)

acs_income <- get_acs(
  geography = "county",
  table = "B19001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
)

acs_age_gender <- acs_age_gender %>%
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) %>%
  filter(STATE %ni% state_fips_exclude)

acs_race <- acs_race %>%
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) %>%
  filter(STATE %ni% state_fips_exclude)

acs_educ <- acs_educ %>%
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) %>%
  filter(STATE %ni% state_fips_exclude)

acs_income <- acs_income %>%
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) %>%
  filter(STATE %ni% state_fips_exclude)

# Map each B01001 cell to its sex and adult age group by reading the cell's
# label, so no cell numbers are hand-typed (same approach as educ_crosswalk /
# income_crosswalk below). The lower-bound age in the label sets the age group;
# cells under 18 drop out via the NA filter. Age/gender margins and ADULT_POP all
# derive from this one crosswalk, so they cannot drift apart.
age_gender_crosswalk <- acs_variables %>%
  filter(
    str_detect(name, "^B01001_[0-9]{3}$"),
    str_detect(label, "!!Male:|!!Female:"),
    str_detect(label, "years")
  ) %>%
  mutate(
    ACS_NAME = paste0(name, "E"),

    GENDER_GROUP = if_else(
      str_detect(label, "!!Male:"),
      "(1) Male",
      "(2) Female"
    ),

    AGE_LOW = as.integer(str_extract(str_extract(label, "[^!]+$"), "\\d+")),
    AGE_LOW = if_else(str_detect(label, "Under"), 0L, AGE_LOW),

    AGE_GROUP = case_when(
      AGE_LOW >= 18 & AGE_LOW <= 29 ~ "(1) 18-29",
      AGE_LOW >= 30 & AGE_LOW <= 49 ~ "(2) 30-49",
      AGE_LOW >= 50 & AGE_LOW <= 64 ~ "(3) 50-64",
      AGE_LOW >= 65                 ~ "(4) 65+",
      TRUE                          ~ NA_character_
    )
  ) %>%
  filter(!is.na(AGE_GROUP)) %>%
  select(
    ACS_NAME,
    GENDER_GROUP,
    AGE_GROUP
  )

adult_population <- acs_age_gender %>%
  transmute(
    STATE,
    COUNTY,
    FIPS,
    NAME,
    ADULT_POP = rowSums(across(all_of(age_gender_crosswalk$ACS_NAME)))
  )

educ_crosswalk <- acs_variables %>%
  filter(
    str_detect(name, "^B15001_[0-9]{3}$")
  ) %>%
  mutate(
    ACS_NAME = paste0(name, "E"),

    LEVEL = case_when(
      str_detect(
        label,
        "Less than 9th grade|9th to 12th grade, no diploma|High school graduate"
      ) ~ "(1) HS or less",

      str_detect(
        label,
        "Some college, no degree|Associate's degree"
      ) ~ "(2) Some college / 2-yr degree",

      str_detect(
        label,
        "Bachelor's degree|Graduate or professional degree"
      ) ~ "(3) 4-yr / post-graduate degree",

      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(LEVEL)) %>%
  select(
    ACS_NAME,
    LEVEL
  )

income_crosswalk <- acs_variables %>%
  filter(
    str_detect(name, "^B19001_[0-9]{3}$")
  ) %>%
  mutate(
    ACS_NAME = paste0(name, "E"),

    LEVEL = case_when(
      str_detect(
        label,
        "Less than \\$10,000|\\$10,000 to \\$14,999|\\$15,000 to \\$19,999|\\$20,000 to \\$24,999|\\$25,000 to \\$29,999|\\$30,000 to \\$34,999|\\$35,000 to \\$39,999|\\$40,000 to \\$44,999|\\$45,000 to \\$49,999"
      ) ~ "(1) < $50,000",

      str_detect(
        label,
        "\\$50,000 to \\$59,999|\\$60,000 to \\$74,999|\\$75,000 to \\$99,999|\\$100,000 to \\$124,999|\\$125,000 to \\$149,999|\\$150,000 to \\$199,999|\\$200,000 or more"
      ) ~ "(2) >= $50,000",

      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(LEVEL)) %>%
  select(
    ACS_NAME,
    LEVEL
  )

county_totals <- bind_rows(

  # Age
  acs_age_gender %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      all_of(age_gender_crosswalk$ACS_NAME)
    ) %>%
    pivot_longer(
      cols = all_of(age_gender_crosswalk$ACS_NAME),
      names_to = "ACS_NAME",
      values_to = "MARGIN_POP"
    ) %>%
    left_join(
      age_gender_crosswalk,
      by = "ACS_NAME"
    ) %>%
    group_by(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      LEVEL = AGE_GROUP
    ) %>%
    summarise(
      MARGIN_POP = sum(MARGIN_POP),
      .groups = "drop"
    ) %>%
    mutate(
      VARIABLE = "AGE_GROUP"
    ),

  # Gender
  acs_age_gender %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      all_of(age_gender_crosswalk$ACS_NAME)
    ) %>%
    pivot_longer(
      cols = all_of(age_gender_crosswalk$ACS_NAME),
      names_to = "ACS_NAME",
      values_to = "MARGIN_POP"
    ) %>%
    left_join(
      age_gender_crosswalk,
      by = "ACS_NAME"
    ) %>%
    group_by(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      LEVEL = GENDER_GROUP
    ) %>%
    summarise(
      MARGIN_POP = sum(MARGIN_POP),
      .groups = "drop"
    ) %>%
    mutate(
      VARIABLE = "GENDER_GROUP"
    ),

  # Race
  acs_race %>%
    transmute(
      STATE,
      COUNTY,
      FIPS,
      NAME,

      `(1) White` = B03002_003E,
      `(2) Black` = B03002_004E,
      `(3) Hispanic` = B03002_012E,
      `(4) Other` =
        B03002_005E + B03002_006E + B03002_007E +
        B03002_008E + B03002_009E
    ) %>%
    pivot_longer(
      cols = all_of(race_levels),
      names_to = "LEVEL",
      values_to = "RAW_MARGIN_POP"
    ) %>%
    group_by(
      STATE,
      COUNTY,
      FIPS,
      NAME
    ) %>%
    mutate(
      MARGIN_PROP = RAW_MARGIN_POP / sum(RAW_MARGIN_POP)
    ) %>%
    ungroup() %>%
    left_join(
      adult_population %>%
        select(
          FIPS,
          ADULT_POP
        ),
      by = "FIPS"
    ) %>%
    mutate(
      MARGIN_POP = MARGIN_PROP * ADULT_POP,
      VARIABLE = "RACE_GROUP"
    ) %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      VARIABLE,
      LEVEL,
      MARGIN_POP
    ),

  # Education
  acs_educ %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      all_of(educ_crosswalk$ACS_NAME)
    ) %>%
    pivot_longer(
      cols = all_of(educ_crosswalk$ACS_NAME),
      names_to = "ACS_NAME",
      values_to = "RAW_MARGIN_POP"
    ) %>%
    left_join(
      educ_crosswalk,
      by = "ACS_NAME"
    ) %>%
    group_by(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      LEVEL
    ) %>%
    summarise(
      RAW_MARGIN_POP = sum(RAW_MARGIN_POP),
      .groups = "drop_last"
    ) %>%
    mutate(
      MARGIN_PROP = RAW_MARGIN_POP / sum(RAW_MARGIN_POP)
    ) %>%
    ungroup() %>%
    left_join(
      adult_population %>%
        select(
          FIPS,
          ADULT_POP
        ),
      by = "FIPS"
    ) %>%
    mutate(
      MARGIN_POP = MARGIN_PROP * ADULT_POP,
      VARIABLE = "EDUC_GROUP"
    ) %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      VARIABLE,
      LEVEL,
      MARGIN_POP
    ),

  # Income
  acs_income %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      all_of(income_crosswalk$ACS_NAME)
    ) %>%
    pivot_longer(
      cols = all_of(income_crosswalk$ACS_NAME),
      names_to = "ACS_NAME",
      values_to = "RAW_MARGIN_POP"
    ) %>%
    left_join(
      income_crosswalk,
      by = "ACS_NAME"
    ) %>%
    group_by(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      LEVEL
    ) %>%
    summarise(
      RAW_MARGIN_POP = sum(RAW_MARGIN_POP),
      .groups = "drop_last"
    ) %>%
    mutate(
      MARGIN_PROP = RAW_MARGIN_POP / sum(RAW_MARGIN_POP)
    ) %>%
    ungroup() %>%
    left_join(
      adult_population %>%
        select(
          FIPS,
          ADULT_POP
        ),
      by = "FIPS"
    ) %>%
    mutate(
      MARGIN_POP = MARGIN_PROP * ADULT_POP,
      VARIABLE = "INCOME_GROUP"
    ) %>%
    select(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      VARIABLE,
      LEVEL,
      MARGIN_POP
    )
) %>%
  select(
    STATE,
    COUNTY,
    FIPS,
    NAME,
    VARIABLE,
    LEVEL,
    MARGIN_POP
  ) %>%
  arrange(
    FIPS,
    factor(
      VARIABLE,
      levels = c(
        "AGE_GROUP",
        "GENDER_GROUP",
        "RACE_GROUP",
        "EDUC_GROUP",
        "INCOME_GROUP"
      )
    ),
    LEVEL
  )

# 4. County Poststratification -------------------------
estimate_county_cells <- function(fips_value) {

  county_info <- adult_population %>%
    filter(FIPS == fips_value)

  state_value <- county_info$STATE[1]
  county_value <- county_info$COUNTY[1]
  county_name <- county_info$NAME[1]
  adult_pop <- county_info$ADULT_POP[1]

  # array() fills column-major (first dimension varies fastest), so the seed
  # vector must be ordered AGE_GROUP-fastest ... INCOME_GROUP-slowest to line up
  # with the dimnames below. expand_grid()'s CELL order is the reverse of that,
  # so sort explicitly here rather than arranging by CELL.
  county_seed <- state_cell_counts %>%
    filter(STATE == state_value) %>%
    left_join(
      cell_lookup,
      by = "CELL"
    ) %>%
    arrange(
      factor(INCOME_GROUP, levels = income_levels),
      factor(EDUC_GROUP, levels = educ_levels),
      factor(RACE_GROUP, levels = race_levels),
      factor(GENDER_GROUP, levels = gender_levels),
      factor(AGE_GROUP, levels = age_levels)
    )

  seed_array <- array(
    county_seed$DONOR_POP + ipf_seed_constant,
    dim = c(
      length(age_levels),
      length(gender_levels),
      length(race_levels),
      length(educ_levels),
      length(income_levels)
    ),
    dimnames = list(
      AGE_GROUP = age_levels,
      GENDER_GROUP = gender_levels,
      RACE_GROUP = race_levels,
      EDUC_GROUP = educ_levels,
      INCOME_GROUP = income_levels
    )
  )

  this_county_totals <- county_totals %>%
    filter(FIPS == fips_value)

  # One totals vector per variable, ordered to match its dimension in
  # the seed array. The target.list dimensions below line up with these in order:
  # 1 = age, 2 = gender, 3 = race, 4 = education, 5 = income.
  totals_for <- function(variable_value, levels_value) {
    this_county_totals %>%
      filter(VARIABLE == variable_value) %>%
      mutate(LEVEL = factor(LEVEL, levels = levels_value)) %>%
      arrange(LEVEL) %>%
      pull(MARGIN_POP)
  }

  target_data <- list(
    totals_for("AGE_GROUP",    age_levels),
    totals_for("GENDER_GROUP", gender_levels),
    totals_for("RACE_GROUP",   race_levels),
    totals_for("EDUC_GROUP",   educ_levels),
    totals_for("INCOME_GROUP", income_levels)
  )

  ipf_fit <- Ipfp(
    seed = seed_array,
    target.list = list(1, 2, 3, 4, 5),
    target.data = target_data,
    iter = ipf_iterations,
    tol = ipf_tolerance,
    tol.margins = ipf_margin_tolerance,
    print = FALSE
  )

  as.data.frame.table(
    ipf_fit$x.hat,
    responseName = "DEMGRP_POP",
    stringsAsFactors = FALSE
  ) %>%
    as_tibble() %>%
    left_join(
      cell_lookup,
      by = c(
        "AGE_GROUP",
        "GENDER_GROUP",
        "RACE_GROUP",
        "EDUC_GROUP",
        "INCOME_GROUP"
      )
    ) %>%
    transmute(
      STATE = state_value,
      COUNTY = county_value,
      NAME = county_name,
      FIPS = fips_value,
      CELL,
      DEMGRP_POP,
      ADULT_POP = adult_pop,
      DEMGRP_PROP = DEMGRP_POP / adult_pop
    ) %>%
    arrange(CELL)
}

county_cell_estimates <- map_dfr(
  sort(adult_population$FIPS),
  estimate_county_cells
) %>%
  left_join(
    state_nws_region,
    by = "STATE"
  ) %>%
  select(
    STATE,
    COUNTY,
    NAME,
    FIPS,
    NWS_REGION,
    CELL,
    DEMGRP_POP,
    ADULT_POP,
    DEMGRP_PROP
  )

# 5. CWA Poststratification -------------------------
cwa_county_crosswalk <- read_sf(
  paste0(downloads, "c_18mr25"),
  "c_18mr25"
) %>%
  st_drop_geometry() %>%
  as_tibble() %>%
  select(
    CWA,
    FIPS
  ) %>%
  mutate(
    FIPS = str_pad(
      as.character(FIPS),
      width = 5,
      side = "left",
      pad = "0"
    ),
    CWA = substr(CWA, 1, 3),
    CWA = ifelse(
      FIPS == "12087",
      "KEY",
      CWA
    )
  ) %>%
  distinct(
    FIPS,
    .keep_all = TRUE
  ) %>%
  filter(
    CWA %ni% c(
      "PPG",
      "SJU",
      "GUM",
      "HFO",
      "AFC",
      "AFG",
      "AJK"
    )
  )

county_cell_estimates <- county_cell_estimates %>%
  left_join(
    cwa_county_crosswalk,
    by = "FIPS"
  )

cwa_cell_estimates <- county_cell_estimates %>%
  filter(!is.na(CWA)) %>%
  group_by(
    CWA,
    CELL
  ) %>%
  summarise(
    DEMGRP_POP = sum(DEMGRP_POP),
    .groups = "drop"
  ) %>%
  group_by(CWA) %>%
  mutate(
    ADULT_POP = sum(DEMGRP_POP),
    DEMGRP_PROP = DEMGRP_POP / ADULT_POP
  ) %>%
  ungroup() %>%
  arrange(
    CWA,
    CELL
  )

# Output Data -------------------------
# write_csv(
#   cell_lookup,
#   paste0(
#     outputs,
#     "base_poststrat_cell_lookup_",
#     acs_year,
#     ".csv"
#   )
# )

# write_csv(
#   county_totals,
#   paste0(
#     outputs,
#     "base_county_poststrat_margins_",
#     acs_year,
#     ".csv"
#   )
# )

# write_csv(
#   county_cell_estimates,
#   paste0(
#     outputs,
#     "base_county_poststrat_data_",
#     acs_year,
#     ".csv"
#   )
# )

# write_csv(
#   cwa_cell_estimates,
#   paste0(
#     outputs,
#     "base_cwa_poststrat_data_",
#     acs_year,
#     ".csv"
#   )
# )
