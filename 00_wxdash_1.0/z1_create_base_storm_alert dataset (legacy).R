library(data.table)
library(tidyverse)
library(sf)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

cwa_alerts_data <- read_csv(paste0(downloads, "wwa_cwa_counts.csv"))
cnty_alerts_data <- read_csv(paste0(downloads, "wwa_county_counts.csv"))

cwa_alerts_data |> 
  pivot_longer(cols = TS:AQ, names_to = "ALERT_TYPE", values_to = "count") |> 
  mutate(hazard_group = case_when(
    ALERT_TYPE %in% c("EH", "HT") ~ "HEAT",
    ALERT_TYPE %in% c("WC", "WI", "WS", "ZF", "ZR", "HZ", "BZ", "IS", "LE", "SW") ~ "SNOW",
    ALERT_TYPE %in% c("FZ", "FR") ~ "COLD",
    ALERT_TYPE %in% c("TO") ~ "TORN",
    ALERT_TYPE %in% c("FA", "FF", "FL", "CF", "SU") ~ "FLOOD",
    ALERT_TYPE %in% c("HU", "LO", "TR", "MH", "TY", "TD", "TS") ~ "HURR",
    ALERT_TYPE %in% c("FW", "SM", "FR", "RW") ~ "FIRE",
    TRUE ~ "OTHER")) |> 
  group_by(WFO, hazard_group, name = "n_days") |> 
  count()

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