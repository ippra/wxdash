library(data.table)
library(tidyverse)
library(sf)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)//Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)//Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# FEMA NRI Data ------------------------- 
# data: https://hazards.fema.gov/nri/data-resources
# details: https://www.fema.gov/sites/default/files/documents/fema_national-risk-index_technical-documentation.pdf
fema_data <- read_csv(paste0(downloads, "NRI_Table_Counties/NRI_Table_Counties.csv"))
fema_data$FIPS <- paste0(fema_data$STATEFIPS, fema_data$COUNTYFIPS)

# Join With County Shapefile (c_03mr20) -------------------------
cwa_cnty_shp <- read_sf(paste0(downloads, "c_03mr20"), "c_03mr20") %>% as_tibble() %>% select(CWA, FIPS)
cwa_cnty_shp$CWA <- substr(cwa_cnty_shp$CWA, start = 1, stop = 3) # Only keep first CWA in counties that span multiple CWAs
cwa_cnty_shp$CWA <- ifelse(cwa_cnty_shp$FIPS == "12087", "KEY", cwa_cnty_shp$CWA) # Fix KEY (assign FIPS 12087 to KEY alone, not KEY and MFL)
cwa_cnty_shp <- cwa_cnty_shp %>% distinct(FIPS, .keep_all = TRUE) # Remove duplicate FIPS codes (counties that span multiple CWAs)
cwa_cnty_shp <- cwa_cnty_shp %>% filter(!CWA %in% c("PPG", "SJU", "GUM", "HFO", "AFC", "AFG", "AJK")) # No census data

cnty_fema_data <- cwa_cnty_shp %>% 
  select(FIPS, CWA) %>% 
  left_join(., fema_data, by = "FIPS") %>% 
  group_by(CWA) %>% 
  mutate(TOT_POP_PROP_CWA = POPULATION / sum(POPULATION)) %>% 
  select(FIPS:POPULATION,
         TOT_POP_PROP_CWA,
         SOVI = SOVI_SCORE, 
         COLD = CWAV_AFREQ, 
         DROUGHT = DRGT_AFREQ, 
         HAIL = HAIL_AFREQ, 
         LIGHT = LTNG_AFREQ, 
         WIND = SWND_AFREQ, 
         HEAT = HWAV_AFREQ, 
         HURR = HRCN_AFREQ,
         ICE = ISTM_AFREQ, 
         COST_FLOOD = CFLD_AFREQ,
         RVR_FLOOD = RFLD_AFREQ, 
         TORN = TRND_AFREQ, 
         FIRE = WFIR_AFREQ, 
         SNOW = WNTW_AFREQ)

cwa_fema_data <- cnty_fema_data %>% 
  mutate_at(vars(SOVI:SNOW), list(~ . * TOT_POP_PROP_CWA)) %>% 
  group_by(CWA) %>% 
  summarise_at(vars(SOVI:SNOW), list(sum))

cnty_fema_data <- cnty_fema_data %>% rename_at(vars(SOVI:SNOW), ~paste0("FIPS_", .))
cwa_fema_data <- cwa_fema_data %>% rename_at(vars(SOVI:SNOW), ~paste0("CWA_", .))

# Standardize -------------------------
cwa_data <- cwa_fema_data %>% 
  select(CWA, CWA_SOVI:CWA_SNOW) %>% 
  mutate_at(vars(-CWA), list(~scale(.) %>% as.vector))

county_data <- cnty_fema_data %>%
  ungroup() %>%
  select(FIPS, FIPS_SOVI:FIPS_SNOW) %>%
  mutate_at(vars(-c(FIPS)), list(~scale(.) %>% as.vector)) %>%
  mutate(FIPS_TORN = ifelse(FIPS_TORN > 2, 2, FIPS_TORN))

# county_data %>%
#   select(FIPS_SOVI:FIPS_SNOW) %>%
#   pivot_longer(FIPS_SOVI:FIPS_SNOW) %>%
#   ggplot(., aes(x = value)) +
#   geom_density() +
#   facet_wrap(~name, scales = "free")

# cwa_cnty_shp <- read_sf(paste0(downloads, "c_03mr20"), "c_03mr20")
# cwa_cnty_shp <- cwa_cnty_shp %>% filter(!CWA %in% c("PPG", "SJU", "GUM", "HFO", "AFC", "AFG", "AJK")) # No census data
# cwa_cnty_shp <- cwa_cnty_shp %>% left_join(., county_data, by = "FIPS")
# cwa_cnty_shp <- rmapshaper::ms_simplify(cwa_cnty_shp)
# ggplot() + geom_sf(data = cwa_cnty_shp, aes(fill = FIPS_WIND), size = 0.1) + scale_fill_viridis_c()

# Output Data -------------------------
write_csv(cwa_data, paste0(outputs, "base_cwa_risk_data.csv"))
write_csv(county_data, paste0(outputs, "base_county_risk_data.csv"))