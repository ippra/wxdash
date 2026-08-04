library(data.table)
library(tidyverse)
library(sf)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

storm_data <- list.files(path = downloads, pattern = "StormEvents_details", full.names = TRUE) %>%
  map_dfr(~read_csv(.x, show_col_types = FALSE, 
                    col_types = cols(TOR_OTHER_CZ_FIPS = col_character()))) %>% # fixes inconsistent data types in this column
  mutate(BEGIN_DATE = str_sub(BEGIN_DATE_TIME, 1, 9))

storm_data <- storm_data %>%
  mutate(EVENT_TYPE_REC = case_when(
    str_detect(EVENT_TYPE, regex("Heat", ignore_case = TRUE)) ~ "HEAT",
    str_detect(EVENT_TYPE, regex("Cold", ignore_case = TRUE)) ~ "COLD",
    str_detect(EVENT_TYPE, regex("Snow|Blizzard|Winter|Ice", ignore_case = TRUE)) ~ "SNOW",
    str_detect(EVENT_TYPE, regex("Tornado", ignore_case = TRUE)) ~ "TORN",
    str_detect(EVENT_TYPE, regex("Flood|Surge", ignore_case = TRUE)) ~ "FLOOD",
    str_detect(EVENT_TYPE, regex("Hurricane|Depression|Tropical Storm", ignore_case = TRUE)) ~ "HURR",
    str_detect(EVENT_TYPE, regex("Wildfire", ignore_case = TRUE)) ~ "FIRE",
    TRUE ~ NA_character_))

storm_data <- storm_data %>%
  mutate(
    ST_FIPS = str_pad(STATE_FIPS, width = 2, side = "left", pad = "0"),
    CNTY_FIPS = if_else(CZ_TYPE == "C", str_pad(CZ_FIPS, width = 3, side = "left", pad = "0"), NA),
    FIPS = if_else(CZ_TYPE == "C", str_c(ST_FIPS, CNTY_FIPS), NA),
    ZONE_NUM = if_else(CZ_TYPE == "Z", str_pad(CZ_FIPS, width = 3, side = "left", pad = "0"), NA),
    STATE_ABB = state.abb[match(str_to_title(STATE), state.name)],
    ZONE_ID = if_else(CZ_TYPE == "Z", str_c(STATE_ABB, "Z", ZONE_NUM), NA))

n_years <- storm_data %>%
  summarize(n_years = n_distinct(YEAR)) %>%
  pull(n_years) #25  years in dataset (2000-2024)

cwa_storm_data_counts <- storm_data %>%
  filter(!is.na(EVENT_TYPE_REC)) %>%
  distinct(WFO, EVENT_TYPE_REC, BEGIN_DATE) %>%
  count(WFO, EVENT_TYPE_REC, name = "n_days") %>%
  mutate(EVENT_DAYS = n_days / n_years) %>%
  select(CWA = WFO, EVENT_TYPE_REC, EVENT_DAYS) %>%
  pivot_wider(names_from = EVENT_TYPE_REC, values_from = EVENT_DAYS)

cwa_cnty_shp <- read_sf(paste0(downloads, "c_18mr25"), "c_18mr25")
cwa_zone_shp <- read_sf(paste0(downloads, "z_18mr25"), "z_18mr25")
cwa_zone_shp <- st_transform(cwa_zone_shp, crs = st_crs(cwa_cnty_shp))
zone_to_county_join <- st_join(cwa_zone_shp, cwa_cnty_shp %>% select(FIPS), join = st_intersects, left = TRUE)
zone_to_county_table <- zone_to_county_join %>% 
  st_drop_geometry() %>% 
  select(STATE, CWA, ZONE, FIPS) %>% 
  mutate(ZONE_ID = str_c(STATE, "Z", ZONE)) # maybe use this file: https://www.weather.gov/source/gis/Shapefiles/County/bp18mr25.dbx

county_storm_data_counts <- storm_data %>%
  filter(!is.na(EVENT_TYPE_REC)) %>%
  distinct(FIPS, EVENT_TYPE_REC, BEGIN_DATE) %>%
  count(FIPS, EVENT_TYPE_REC, name = "n_days") %>%
  mutate(EVENT_DAYS = n_days / n_years) %>%
  select(FIPS, EVENT_TYPE_REC, EVENT_DAYS) %>%
  pivot_wider(names_from = EVENT_TYPE_REC, values_from = EVENT_DAYS)

# FIX NECESSARY: Many events are reported by forecast zone (CZ_TYPE of "Z") rather than county (CZ_TYPE of "C")
# For these events, the CNTY_FIPS is likely incorrect; need to overlay forecast zone shapefile with county shapefile to create a crosswalk

drought_data <- list.files(downloads, pattern = "dm_export", full.names = TRUE) %>%
  map_dfr(~read_csv(.x, show_col_types = FALSE))

drought_data <- drought_data %>%
  mutate(drought = if_else(D1 > 0 | D2 > 0 | D3 > 0 | D4 > 0, 1, 0),
         YEAR = as.numeric(str_sub(MapDate, 1, 4)),
         FIPS = str_pad(FIPS, width = 5, side = "left", pad = "0"))

drought_data <- left_join(drought_data, storm_data %>% select(CWA = WFO, FIPS) %>% distinct(FIPS, .keep_all = TRUE), by = "FIPS") # add WFO to drought data

cwa_drought_data_counts <- drought_data %>% 
  filter(drought == 1) %>%
  distinct(MapDate, CWA, .keep_all = TRUE) %>% 
  count(CWA, name = "n_days") %>%
  mutate(DROUGHT = n_days / n_years) %>% 
  select(CWA, DROUGHT)

county_drought_data_counts <- drought_data %>% 
  filter(drought == 1) %>%
  count(FIPS, name = "n_days") %>%
  mutate(DROUGHT = n_days / n_years) %>%
  select(FIPS, DROUGHT)

cwa_data <- left_join(cwa_storm_data_counts, cwa_drought_data_counts, by = "CWA")
county_data <- left_join(county_storm_data_counts, county_drought_data_counts, by = "FIPS")

nrow(cwa_data) # 125 CWAs
nrow(county_data) # 5883 FIPS codes (many are incorrect, see fix note above)

# Join With County Shapefile (c_03mr20) -------------------------
cwa_cnty_shp <- read_sf(paste0(downloads, "c_03mr20"), "c_03mr20") %>% as_tibble() %>% select(CWA, FIPS)
cwa_cnty_shp$CWA <- substr(cwa_cnty_shp$CWA, start = 1, stop = 3) # Only keep first CWA in counties that span multiple CWAs
cwa_cnty_shp$CWA <- ifelse(cwa_cnty_shp$FIPS == "12087", "KEY", cwa_cnty_shp$CWA) # Fix KEY (assign FIPS 12087 to KEY alone, not KEY and MFL)
cwa_cnty_shp <- cwa_cnty_shp %>% distinct(FIPS, .keep_all = TRUE) # Remove duplicate FIPS codes (counties that span multiple CWAs)
cwa_cnty_shp <- cwa_cnty_shp %>% filter(!CWA %in% c("PPG", "SJU", "GUM", "HFO", "AFC", "AFG", "AJK")) # No census data

cwa_data <- cwa_cnty_shp %>% 
  select(CWA, FIPS) %>% 
  distinct(CWA, .keep_all = FALSE) %>% 
  left_join(., cwa_data, by = "CWA") 
cwa_data[is.na(cwa_data)] <- 0 # Change all NAs to 0
nrow(cwa_data) # 116 CWAs, removes ASO, EYW, GUA

county_data <- cwa_cnty_shp %>% 
  left_join(., county_data, by = "FIPS")
county_data[is.na(county_data)] <- 0 # Change all NAs to 0
nrow(county_data) # 3108 FIPS codes, removes incorrect FIPS codes from forecast zones

# Standardize -------------------------
cwa_data <- cwa_data %>% 
  select(CWA, COLD:DROUGHT) %>% 
  mutate_at(vars(-CWA), list(~scale(.) %>% as.vector))

county_data <- county_data %>% 
  select(FIPS, COLD:DROUGHT) %>% 
  mutate_at(vars(-FIPS), list(~scale(.) %>% as.vector))

# Output Data -------------------------
write_csv(cwa_data, paste0(outputs, "base_cwa_storm_data.csv"))
write_csv(county_data, paste0(outputs, "base_county_storm_data.csv"))