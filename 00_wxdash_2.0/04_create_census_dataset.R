library(tidyverse)
library(ipumsr)
library(tidycensus)
library(mipfp)

options(scipen = 999)
options(max.print = 99999)
"%ni%" <- Negate("%in%")

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Project Settings -------------------------------------------------------------
acs_year <- 2024 # ACS 5-year release
state_fips_exclude <- c("02", "15", "72") # Alaska, Hawaii, Puerto Rico
ipf_seed_constant <- 0.01
ipf_iterations <- 1000
ipf_tolerance <- 0.00000001
ipf_margin_tolerance <- 0.001

# Survey Categories ------------------------------------------------------------
age_levels <- c("(1) 18-29", "(2) 30-49", "(3) 50-64", "(4) 65+")
gender_levels <- c("(1) Male", "(2) Female")
race_levels <- c("(1) White", "(2) Black", "(3) Hispanic", "(4) Other")
educ_levels <- c("(1) HS or less", "(2) Some college / 2-yr degree", "(3) 4-yr / post-graduate degree")
income_levels <- c("(1) < $50,000", "(2) >= $50,000")
region_levels <- c("(1) Northeast", "(2) Midwest", "(3) South", "(4) West") # county attribute, not a cell dimension

# Census API Key ---------------------------------------------------------------
# census_api_key("YOUR KEY", install = TRUE)

# Cell Lookup ------------------------------------------------------------------
cell_lookup <- expand_grid(
  AGE_GROUP = age_levels,
  GENDER_GROUP = gender_levels,
  RACE_GROUP = race_levels,
  EDUC_GROUP = educ_levels,
  INCOME_GROUP = income_levels
) |>
  mutate(CELL = row_number(), .before = 1)

# Donor Data -------------------------------------------------------------------
# set_ipums_api_key("59cba10d8a5da536fc06b59de4bf71e27eb2494ea72bf4880892a7d0", save = TRUE)
# extract <- define_extract_micro(
#   collection = "usa",
#   description = paste("ACS", acs_year, "Survey Benchmarks"),
#   samples = paste0("us", acs_year, "c"), # ACS 5-year
#   variables = c(
#     "YEAR",
#     "REGION",
#     "STATEFIP",
#     "COUNTYFIP",
#     "PERWT",
#     "AGE",
#     "SEX",
#     "RACE",
#     "HISPAN",
#     "EDUCD",
#     "HHINCOME"
#   )
# )
# submitted_extract <- submit_extract(extract)
# wait_for_extract(submitted_extract)
# download_extract(submitted_extract, download_dir = downloads)
# usa_00035 is the extract defined above: sample us2024c, the 2020-2024 ACS
# 5-year file, matching the acs5 county margins. Uncomment the block to rebuild
# it -- IPUMS assigns a new number each time, so update the path to match.
ipums_ddi <- read_ipums_ddi(paste0(downloads, "usa_00035.xml"))
ipums_data <- read_ipums_micro(ipums_ddi)

ipums_data <- ipums_data |>
  filter(AGE >= 18) |>
  filter(GQ %in% c(1, 2)) |> # households only, no group quarters
  filter(STATEFIP %ni% as.integer(state_fips_exclude)) |>
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
      EDUCD %in% c(0, 1, 2, 10:17, 20:26, 30, 40, 50, 60:64) ~ "(1) HS or less",

      EDUCD %in% c(65, 70:71, 80:83, 90) ~ "(2) Some college / 2-yr degree",

      EDUCD %in% c(100, 101, 110:116) ~ "(3) 4-yr / post-graduate degree",

      TRUE ~ NA_character_
    ),

    INCOME_GROUP = case_when(
      HHINCOME == 9999999 ~ NA_character_,
      HHINCOME < 50000    ~ "(1) < $50,000",
      HHINCOME >= 50000   ~ "(2) >= $50,000",
      TRUE                ~ NA_character_
    )
  ) |>
  filter(
    !is.na(AGE_GROUP),
    !is.na(GENDER_GROUP),
    !is.na(RACE_GROUP),
    !is.na(EDUC_GROUP),
    !is.na(INCOME_GROUP)
  ) |>
  select(
    STATE,
    PERWT,
    AGE_GROUP,
    GENDER_GROUP,
    RACE_GROUP,
    EDUC_GROUP,
    INCOME_GROUP
  )

state_cell_counts <- ipums_data |>
  group_by(
    STATE,
    AGE_GROUP,
    GENDER_GROUP,
    RACE_GROUP,
    EDUC_GROUP,
    INCOME_GROUP
  ) |>
  summarise(DONOR_POP = sum(PERWT), .groups = "drop") |>
  right_join(
    expand_grid(
      STATE = sort(unique(ipums_data$STATE)),
      CELL = cell_lookup$CELL
    ) |>
      left_join(cell_lookup, by = "CELL"),
    by = c(
      "STATE",
      "AGE_GROUP",
      "GENDER_GROUP",
      "RACE_GROUP",
      "EDUC_GROUP",
      "INCOME_GROUP"
    )
  ) |>
  mutate(DONOR_POP = replace_na(DONOR_POP, 0)) |>
  select(STATE, CELL, DONOR_POP) |>
  arrange(STATE, CELL)

# County Totals ----------------------------------------------------------------
acs_variables <- load_variables(acs_year, "acs5")

acs_age_gender <- get_acs(
  geography = "county",
  table = "B01001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
) |>
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) |>
  filter(STATE %ni% state_fips_exclude)

acs_race <- get_acs(
  geography = "county",
  table = "B03002",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
) |>
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) |>
  filter(STATE %ni% state_fips_exclude)

acs_educ <- get_acs(
  geography = "county",
  table = "B15001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
) |>
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) |>
  filter(STATE %ni% state_fips_exclude)

acs_income <- get_acs(
  geography = "county",
  table = "B19001",
  year = acs_year,
  survey = "acs5",
  output = "wide",
  geometry = FALSE
) |>
  mutate(
    STATE = substr(GEOID, 1, 2),
    COUNTY = substr(GEOID, 3, 5),
    FIPS = GEOID
  ) |>
  filter(STATE %ni% state_fips_exclude)

age_gender_crosswalk <- acs_variables |>
  filter(
    str_detect(name, "^B01001_[0-9]{3}$"),
    str_detect(label, "!!Male:|!!Female:"),
    str_detect(label, "years")
  ) |>
  mutate(
    ACS_NAME = paste0(name, "E"),
    GENDER_GROUP = if_else(str_detect(label, "!!Male:"), "(1) Male", "(2) Female"),
    AGE_LOW = if_else(
      str_detect(label, "Under"),
      0L,
      as.integer(str_extract(label, "\\d+"))
    ),
    AGE_GROUP = case_when(
      AGE_LOW >= 65 ~ "(4) 65+",
      AGE_LOW >= 50 ~ "(3) 50-64",
      AGE_LOW >= 30 ~ "(2) 30-49",
      AGE_LOW >= 18 ~ "(1) 18-29",
      TRUE          ~ NA_character_
    )
  ) |>
  filter(!is.na(AGE_GROUP)) |>
  select(ACS_NAME, GENDER_GROUP, AGE_GROUP)

educ_labels <- c(
  "Less than 9th grade"                         = "(1) HS or less",
  "9th to 12th grade, no diploma"               = "(1) HS or less",
  "High school graduate (includes equivalency)" = "(1) HS or less",
  "Some college, no degree"                     = "(2) Some college / 2-yr degree",
  "Associate's degree"                          = "(2) Some college / 2-yr degree",
  "Bachelor's degree"                           = "(3) 4-yr / post-graduate degree",
  "Graduate or professional degree"             = "(3) 4-yr / post-graduate degree"
)

educ_crosswalk <- acs_variables |>
  filter(str_detect(name, "^B15001_[0-9]{3}$")) |>
  mutate(
    ACS_NAME = paste0(name, "E"),
    LEVEL = unname(educ_labels[str_extract(label, "[^!]+$")])
  ) |>
  filter(!is.na(LEVEL)) |>
  select(ACS_NAME, LEVEL)

income_crosswalk <- tibble(
  ACS_NAME = sprintf("B19001_%03dE", 2:17),
  LEVEL = rep(income_levels, c(9, 7))
)

race_crosswalk <- tibble(
  ACS_NAME = c(
    "B03002_003E", # white alone, not hispanic
    "B03002_004E", # black alone, not hispanic
    "B03002_012E", # hispanic or latino, any race
    "B03002_005E", # american indian / alaska native
    "B03002_006E", # asian
    "B03002_007E", # native hawaiian / pacific islander
    "B03002_008E", # some other race
    "B03002_009E"  # two or more races
  ),
  LEVEL = c(race_levels[1:3], rep(race_levels[4], 5))
)

adult_population <- acs_age_gender |>
  transmute(
    STATE,
    COUNTY,
    FIPS,
    NAME,
    ADULT_POP = rowSums(across(all_of(age_gender_crosswalk$ACS_NAME)))
  )

# The survey side (WX25 compile_dataset.R) keys CENSUS_REGION off state names,
# so build the same names here. Census writes DC as "District of Columbia" while
# the survey writes "Washington, D.C.", so remap it or the two will not join.
# Region is a state attribute, which is why it belongs on the county file only:
# 13 of 116 CWAs span more than one census region.
state_regions <- acs_age_gender |>
  mutate(STATE_NAME = str_trim(str_extract(NAME, "[^,]+$"))) |>
  distinct(STATE, STATE_NAME) |>
  mutate(
    STATE_NAME = if_else(
      STATE_NAME == "District of Columbia",
      "Washington, D.C.",
      STATE_NAME
    ),
    CENSUS_REGION = case_when(
      STATE_NAME %in% c("Connecticut", "Maine", "Massachusetts", "New Hampshire",
                        "Rhode Island", "Vermont", "New Jersey", "New York",
                        "Pennsylvania") ~ region_levels[1],
      STATE_NAME %in% c("Illinois", "Indiana", "Michigan", "Ohio", "Wisconsin",
                        "Iowa", "Kansas", "Minnesota", "Missouri", "Nebraska",
                        "North Dakota", "South Dakota") ~ region_levels[2],
      STATE_NAME %in% c("Delaware", "Florida", "Georgia", "Maryland",
                        "North Carolina", "South Carolina", "Virginia",
                        "Washington, D.C.", "West Virginia", "Alabama",
                        "Kentucky", "Mississippi", "Tennessee", "Arkansas",
                        "Louisiana", "Oklahoma", "Texas") ~ region_levels[3],
      STATE_NAME %in% c("Arizona", "Colorado", "Idaho", "Montana", "Nevada",
                        "New Mexico", "Utah", "Wyoming", "California", "Oregon",
                        "Washington") ~ region_levels[4],
      TRUE ~ NA_character_
    )
  )

if (any(is.na(state_regions$CENSUS_REGION))) {
  print(state_regions |> filter(is.na(CENSUS_REGION)))
  stop("States above have no CENSUS_REGION.")
}

county_margin <- function(acs_data, crosswalk, variable_name) {
  acs_data |>
    select(STATE, COUNTY, FIPS, NAME, all_of(crosswalk$ACS_NAME)) |>
    pivot_longer(
      cols = all_of(crosswalk$ACS_NAME),
      names_to = "ACS_NAME",
      values_to = "RAW_MARGIN_POP"
    ) |>
    left_join(crosswalk, by = "ACS_NAME") |>
    group_by(STATE, COUNTY, FIPS, NAME, LEVEL) |>
    summarise(RAW_MARGIN_POP = sum(RAW_MARGIN_POP), .groups = "drop_last") |>
    mutate(MARGIN_PROP = RAW_MARGIN_POP / sum(RAW_MARGIN_POP)) |>
    ungroup() |>
    left_join(adult_population |> select(FIPS, ADULT_POP), by = "FIPS") |>
    transmute(
      STATE,
      COUNTY,
      FIPS,
      NAME,
      VARIABLE = variable_name,
      LEVEL,
      MARGIN_POP = MARGIN_PROP * ADULT_POP
    )
}

county_totals <- bind_rows(
  county_margin(
    acs_age_gender,
    age_gender_crosswalk |> select(ACS_NAME, LEVEL = AGE_GROUP),
    "AGE_GROUP"
  ),
  county_margin(
    acs_age_gender,
    age_gender_crosswalk |> select(ACS_NAME, LEVEL = GENDER_GROUP),
    "GENDER_GROUP"
  ),
  county_margin(acs_race,   race_crosswalk,   "RACE_GROUP"),
  county_margin(acs_educ,   educ_crosswalk,   "EDUC_GROUP"),
  county_margin(acs_income, income_crosswalk, "INCOME_GROUP")
) |>
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

# County Poststratification ----------------------------------------------------
estimate_county_cells <- function(fips_value) {
  county_info <- adult_population |>
    filter(FIPS == fips_value)
  state_value <- county_info$STATE[1]
  county_value <- county_info$COUNTY[1]
  county_name <- county_info$NAME[1]
  adult_pop <- county_info$ADULT_POP[1]
  # array() fills column-major (first dimension varies fastest), so the seed
  # vector must be ordered AGE_GROUP-fastest ... INCOME_GROUP-slowest to line up
  # with the dimnames below. expand_grid()'s CELL order is the reverse of that,
  # so sort explicitly here rather than arranging by CELL. Sorting by CELL
  # instead puts only 2 of the 192 cells in the right place, silently.
  county_seed <- state_cell_counts |>
    filter(STATE == state_value) |>
    left_join(cell_lookup, by = "CELL") |>
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
  this_county_totals <- county_totals |>
    filter(FIPS == fips_value)
  totals_for <- function(variable_value, levels_value) {
    this_county_totals |>
      filter(VARIABLE == variable_value) |>
      mutate(LEVEL = factor(LEVEL, levels = levels_value)) |>
      arrange(LEVEL) |>
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
  ) |>
    as_tibble() |>
    left_join(
      cell_lookup,
      by = c(
        "AGE_GROUP",
        "GENDER_GROUP",
        "RACE_GROUP",
        "EDUC_GROUP",
        "INCOME_GROUP"
      )
    ) |>
    transmute(
      STATE = state_value,
      COUNTY = county_value,
      NAME = county_name,
      FIPS = fips_value,
      CELL,
      DEMGRP_POP,
      ADULT_POP = adult_pop,
      DEMGRP_PROP = DEMGRP_POP / adult_pop,
      CONVERGED = ipf_fit$conv,
      MARGIN_ERROR = max(ipf_fit$error.margins)
    ) |>
    arrange(CELL)
}

county_cell_estimates <- map_dfr(
  sort(adult_population$FIPS),
  estimate_county_cells
)

# Ipfp() reports conv = TRUE even when it silently rescales to proportions
# because the targets were inconsistent, so check the fitted totals too: the
# cells must sum back to ADULT_POP, not to 1.
ipf_check <- county_cell_estimates |>
  group_by(FIPS) |>
  summarise(
    CONVERGED = first(CONVERGED),
    MARGIN_ERROR = first(MARGIN_ERROR),
    POP_ERROR = abs(sum(DEMGRP_POP) - first(ADULT_POP)) / first(ADULT_POP),
    PROP_ERROR = abs(sum(DEMGRP_PROP) - 1),
    .groups = "drop"
  )

message(
  "IPF: ", sum(!ipf_check$CONVERGED), " of ", nrow(ipf_check), " counties failed to converge; ",
  "max margin error ", signif(max(ipf_check$MARGIN_ERROR), 3), "; ",
  "max population error ", signif(max(ipf_check$POP_ERROR), 3), "; ",
  "max proportion error ", signif(max(ipf_check$PROP_ERROR), 3)
)

if (any(!ipf_check$CONVERGED) || max(ipf_check$POP_ERROR) > 1e-6) {
  print(ipf_check |> filter(!CONVERGED | POP_ERROR > 1e-6))
  stop("IPF failed for one or more counties - see the table above.")
}

county_cell_estimates <- county_cell_estimates |>
  select(STATE, COUNTY, NAME, FIPS, CELL, DEMGRP_POP, ADULT_POP, DEMGRP_PROP)

# CWA Poststratification -------------------------------------------------------
cwa_county_crosswalk <- read_csv(
  paste0(outputs, "county_to_cwa_data.csv"),
  col_types = cols_only(GEOID = col_character(), CWA = col_character())
) |>
  rename(FIPS = GEOID)

county_cell_estimates <- county_cell_estimates |>
  left_join(cwa_county_crosswalk, by = "FIPS")

# Every CONUS county must carry a CWA, because CWA estimates are produced by
# aggregating county predictions rather than from a separate CWA table. A county
# that failed to match the crosswalk would silently drop out of those aggregates
# -- which is how Connecticut went missing when this script built its own
# crosswalk.
cwa_unmatched <- county_cell_estimates |>
  filter(is.na(CWA)) |>
  distinct(FIPS, NAME)

if (nrow(cwa_unmatched) > 0) {
  print(cwa_unmatched)
  stop("Counties above have no CWA - they would be dropped from the CWA aggregates.")
}

# County Covariates ------------------------------------------------------------
# Full CDC SVI and FEMA National Risk Index, kept as a county-level lookup
# rather than joined into the poststrat table. That table carries 192 rows per
# county, so joining 507 columns there would store every county value 192 times
# and take the file from ~106 MB to ~3.5 GB. Prediction joins this by FIPS.
#
# Identifier columns are dropped because the two sources duplicate each other
# and the poststrat table (both carry STATE and COUNTY). Everything else is kept
# and prefixed so SVI and NRI stay distinguishable.
svi_identifiers <- c("ST", "STATE", "ST_ABBR", "STCNTY", "COUNTY", "LOCATION")

nri_identifiers <- c(
  "OID_", "NRI_ID", "STATE", "STATEABBRV", "STATEFIPS", "COUNTY",
  "COUNTYTYPE", "COUNTYFIPS"
)

# guess_max = Inf because several NRI hazard columns are empty for thousands of
# rows before their first value. Guessing from the default 1,000-row window
# types those logical and then silently drops every real number as NA, which
# costs LNDS_EVNTS 78 values.
svi_data <- read_csv(
  paste0(downloads, "SVI_2022_US_county.csv"),
  col_types = cols(FIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) |>
  select(-any_of(svi_identifiers)) |>
  rename_with(~paste0("SVI_", .x), .cols = -FIPS)

nri_data <- read_csv(
  paste0(downloads, "NRI_Table_Counties/NRI_Table_Counties.csv"),
  col_types = cols(STCOFIPS = col_character(), .default = col_guess()),
  guess_max = Inf
) |>
  select(-any_of(nri_identifiers)) |>
  rename(FIPS = STCOFIPS) |>
  rename_with(~paste0("NRI_", .x), .cols = -FIPS)

county_covariates <- full_join(svi_data, nri_data, by = "FIPS")

if (any(duplicated(county_covariates$FIPS))) {
  stop("county_covariates has duplicate FIPS - joins downstream would fan out.")
}

county_covariates |>
  summarise(
    counties = n(),
    columns = ncol(county_covariates),
    poststrat_covered = sum(unique(county_cell_estimates$FIPS) %in% FIPS)
  )

# Output Data ------------------------------------------------------------------
# Two files: the poststrat table and the county covariate lookup that keys into
# it. One poststrat table, at county level. CWA estimates come from aggregating
# county predictions, weighted by DEMGRP_POP, so a separate CWA table is not
# needed -- and could not be used anyway, since the models carry county-level
# terms that a CWA-level table cannot supply. The county file carries CWA, so
# the aggregation is a group_by away.
#
# cell_lookup is joined so each row names its demographic cell rather than
# carrying a bare CELL number, and state_regions so STATE_NAME and CENSUS_REGION
# match what the survey side builds.
write_csv(
  county_cell_estimates |>
    left_join(cell_lookup, by = "CELL") |>
    left_join(state_regions, by = "STATE") |>
    select(
      STATE,
      STATE_NAME,
      COUNTY,
      NAME,
      FIPS,
      CENSUS_REGION,
      CWA,
      CELL,
      AGE_GROUP,
      GENDER_GROUP,
      RACE_GROUP,
      EDUC_GROUP,
      INCOME_GROUP,
      DEMGRP_POP,
      ADULT_POP,
      DEMGRP_PROP
    ),
  paste0(outputs, "base_county_poststrat_data_", acs_year, ".csv")
)

# The covariates go out separately, keyed on FIPS, so both the poststrat table
# and the survey data can pick up whichever of the 507 fields a model needs. No
# year suffix: the vintages are fixed by the source files (SVI 2022, NRI), not
# by acs_year.
write_csv(county_covariates, paste0(outputs, "base_county_covariates.csv"))
