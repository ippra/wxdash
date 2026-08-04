library(data.table)
library(tidyverse)
library(sf)

options(scipen = 999)
options(max.print = 99999)
"%ni%" <- Negate("%in%")

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Census Data ------------------------- 
# Codebook: https://www2.census.gov/programs-surveys/popest/technical-documentation/file-layouts/2020-2021/cc-est2021-alldata.pdf
data <- fread("https://www2.census.gov/programs-surveys/popest/datasets/2020-2021/counties/asrh/cc-est2021-all.csv")
# Note Connecticut changed to planning regions instead of counties in 2022: https://www.federalregister.gov/documents/2022/06/06/2022-12063/change-to-county-equivalents-in-the-state-of-connecticut

data <- subset(data, YEAR == 3) # 7/1/2021
data <- subset(data, AGEGRP %in% 4:18) # Age 15 to 19 years - Age 85 years or older
data <- subset(data, STNAME %ni% c("Alaska", "Hawaii"))

data$AGEGRP <- car::recode(data$AGEGRP, "4:7 = 1; 8:12 = 2; 13:18 = 3")
data <- data[, c("STATE", "COUNTY", "AGEGRP", 
                "NHWA_MALE", "NHBA_MALE", "NH_MALE", "HWA_MALE", "HBA_MALE", "H_MALE",
                "NHWA_FEMALE", "NHBA_FEMALE", "NH_FEMALE", "HWA_FEMALE", "HBA_FEMALE", "H_FEMALE"), ] %>%
  group_by(STATE, COUNTY, AGEGRP) %>% 
  mutate_if(is.character, as.numeric) %>% 
  summarise_all(list(sum))

data <- data.frame(
  subset(data, AGEGRP == 1)[, c("STATE", "COUNTY")],
  subset(data, AGEGRP == 1)$NHWA_MALE,
  subset(data, AGEGRP == 1)$NHBA_MALE,
  subset(data, AGEGRP == 1)$NH_MALE - (subset(data, AGEGRP == 1)$NHWA_MALE + subset(data, AGEGRP == 1)$NHBA_MALE),
  subset(data, AGEGRP == 1)$HWA_MALE,
  subset(data, AGEGRP == 1)$HBA_MALE,
  subset(data, AGEGRP == 1)$H_MALE - (subset(data, AGEGRP == 1)$HWA_MALE + subset(data, AGEGRP == 1)$HBA_MALE),
  subset(data, AGEGRP == 1)$NHWA_FEMALE,
  subset(data, AGEGRP == 1)$NHBA_FEMALE,
  subset(data, AGEGRP == 1)$NH_FEMALE - (subset(data, AGEGRP == 1)$NHWA_FEMALE + subset(data, AGEGRP == 1)$NHBA_FEMALE),
  subset(data, AGEGRP == 1)$HWA_FEMALE,
  subset(data, AGEGRP == 1)$HBA_FEMALE,
  subset(data, AGEGRP == 1)$H_FEMALE - (subset(data, AGEGRP == 1)$HWA_FEMALE + subset(data, AGEGRP == 1)$HBA_FEMALE),
  subset(data, AGEGRP == 2)$NHWA_MALE,
  subset(data, AGEGRP == 2)$NHBA_MALE,
  subset(data, AGEGRP == 2)$NH_MALE - (subset(data, AGEGRP == 2)$NHWA_MALE + subset(data, AGEGRP == 2)$NHBA_MALE),
  subset(data, AGEGRP == 2)$HWA_MALE,
  subset(data, AGEGRP == 2)$HBA_MALE,
  subset(data, AGEGRP == 2)$H_MALE - (subset(data, AGEGRP == 2)$HWA_MALE + subset(data, AGEGRP == 2)$HBA_MALE),
  subset(data, AGEGRP == 2)$NHWA_FEMALE,
  subset(data, AGEGRP == 2)$NHBA_FEMALE,
  subset(data, AGEGRP == 2)$NH_FEMALE - (subset(data, AGEGRP == 2)$NHWA_FEMALE + subset(data, AGEGRP == 2)$NHBA_FEMALE),
  subset(data, AGEGRP == 2)$HWA_FEMALE,
  subset(data, AGEGRP == 2)$HBA_FEMALE,
  subset(data, AGEGRP == 2)$H_FEMALE - (subset(data, AGEGRP == 2)$HWA_FEMALE + subset(data, AGEGRP == 2)$HBA_FEMALE),
  subset(data, AGEGRP == 3)$NHWA_MALE,
  subset(data, AGEGRP == 3)$NHBA_MALE,
  subset(data, AGEGRP == 3)$NH_MALE - (subset(data, AGEGRP == 3)$NHWA_MALE + subset(data, AGEGRP == 3)$NHBA_MALE),
  subset(data, AGEGRP == 3)$HWA_MALE,
  subset(data, AGEGRP == 3)$HBA_MALE,
  subset(data, AGEGRP == 3)$H_MALE - (subset(data, AGEGRP == 3)$HWA_MALE + subset(data, AGEGRP == 3)$HBA_MALE),
  subset(data, AGEGRP == 3)$NHWA_FEMALE,
  subset(data, AGEGRP == 3)$NHBA_FEMALE,
  subset(data, AGEGRP == 3)$NH_FEMALE - (subset(data, AGEGRP == 3)$NHWA_FEMALE + subset(data, AGEGRP == 3)$NHBA_FEMALE),
  subset(data, AGEGRP == 3)$HWA_FEMALE,
  subset(data, AGEGRP == 3)$HBA_FEMALE,
  subset(data, AGEGRP == 3)$H_FEMALE - (subset(data, AGEGRP == 3)$HWA_FEMALE + subset(data, AGEGRP == 3)$HBA_FEMALE)
  )
names(data) <- c("STATE", "COUNTY", paste0("DEMGRP_",formatC(1:36, width = 2, format = "d", flag = "0")))
data$FIPS <- paste0(formatC(data$STATE, width = 2, format = "d", flag = "0"), 
                    formatC(data$COUNTY, width = 3, format = "d", flag = "0"))
data <- with(data, data.frame(FIPS, data[, 3:38]))

data_long <- gather(data, DEMGRP, DEMGRP_POP, -FIPS)
data_long <- arrange(data_long, FIPS, DEMGRP)
data_long$MALE <- rep(rep(c(rep(1, 6), rep(0, 6)), 3), nrow(data)) # 0 = Male; 1 = Female
data_long$AGE_GROUP <- rep(c(rep(1, 12), rep(2, 12), rep(3, 12)), nrow(data)) # 1 = 18-34; 2 = 35-59; 3 = 60+ 
data_long$HISP <- rep(rep(c(rep(0, 3), rep(1, 3)), 6), nrow(data)) # 0 = Hisp; 1 = Not Hisp
data_long$RACE_GROUP <- rep(rep(1:3, 12), nrow(data)) # 1 = White alone; 2 = Black alone; 3 = Other

tot_data <- aggregate(DEMGRP_POP ~ FIPS, data_long, sum)
names(tot_data) <- c("FIPS", "TOT_POP")
data_long <- merge(data_long, tot_data, by = "FIPS", all.x = TRUE)

org_data <- fread("https://www2.census.gov/programs-surveys/popest/datasets/2020-2022/counties/asrh/cc-est2022-all.csv")
org_data$FIPS <- paste0(formatC(org_data$STATE, width = 2, format = "d", flag = "0"), 
                    formatC(org_data$COUNTY, width = 3, format = "d", flag = "0"))
org_data <- subset(org_data, AGEGRP == 0 & YEAR == 3 & STNAME %ni% c("Alaska", "Hawaii"))
data_long <- merge(data_long, with(org_data, data.frame(FIPS, STATE, COUNTY, STNAME, CTYNAME)), by = "FIPS", all.x = TRUE)
data_long <- data_long[,c("STATE","COUNTY","STNAME","CTYNAME","FIPS","MALE","AGE_GROUP","HISP","RACE_GROUP","DEMGRP_POP","TOT_POP")]
data_long$DEMGRP_PROP <- data_long$DEMGRP_POP / data_long$TOT_POP
nrow(data_long) / 36 # data on 3109 counties

# Join With County Shapefile (c_03mr20) -------------------------
cwa_cnty_shp <- read_sf(paste0(downloads, "c_03mr20"), "c_03mr20") %>% as_tibble() %>% select(CWA, FIPS)
cwa_cnty_shp$CWA <- substr(cwa_cnty_shp$CWA, start = 1, stop = 3) # Only keep first CWA in counties that span multiple CWAs
cwa_cnty_shp$CWA <- ifelse(cwa_cnty_shp$FIPS == "12087", "KEY", cwa_cnty_shp$CWA) # Fix KEY (assign FIPS 12087 to KEY alone, not KEY and MFL)
cwa_cnty_shp <- cwa_cnty_shp %>% distinct(FIPS, .keep_all = TRUE) # Remove duplicate FIPS codes (counties that span multiple CWAs)
cwa_cnty_shp <- cwa_cnty_shp %>% filter(!CWA %in% c("PPG", "SJU", "GUM", "HFO", "AFC", "AFG", "AJK")) # No census data

cnty_data_long <- left_join(data_long, cwa_cnty_shp %>% select(FIPS, CWA), by = "FIPS")
length(table(cnty_data_long$FIPS)) # data on 3108 counties
length(table(cnty_data_long$CWA)) # data on 116 CWAs

cwa_data_long <- cnty_data_long %>% 
  group_by(CWA, MALE, AGE_GROUP, HISP, RACE_GROUP) %>% 
  summarise(DEMGRP_POP = sum(DEMGRP_POP), TOT_POP = sum(TOT_POP)) %>% 
  mutate(DEMGRP_PROP = DEMGRP_POP/TOT_POP)
length(table(cwa_data_long$CWA)) # data on 116 CWAs

# Event Data -------------------------
cwa_storm_data <- read_csv(paste0(outputs, "base_cwa_storm_data.csv"))
cnty_storm_data <- read_csv(paste0(outputs, "base_county_storm_data.csv"))

cwa_storm_data <- cwa_storm_data %>% rename_at(vars(COLD:DROUGHT), ~paste0("CWA_", .))
cnty_storm_data <- cnty_storm_data %>% rename_at(vars(COLD:DROUGHT), ~paste0("FIPS_", .))

cwa_data_long <- left_join(cwa_data_long, cwa_storm_data, by = "CWA")
cnty_data_long <- left_join(cnty_data_long, cnty_storm_data, by = "FIPS")

# SVI Data -------------------------
# https://svi.cdc.gov/Documents/Data/2018_SVI_Data/SVI2018Documentation.pdf # todo: update with 2020 data
# svi_data <- read_csv(paste0(downloads, "SVI2018_US_COUNTY.csv")) %>% 
#   select(FIPS, starts_with("EP_"), starts_with("RPL")) %>% 
#   mutate_all(~ifelse(. == -999, NA, .))

# https://www.atsdr.cdc.gov/placeandhealth/svi/data_documentation_download.html
svi_data <- read_csv(paste0(downloads, "SVI_2020_US_county.csv")) %>% 
  select(FIPS, starts_with("EP_"), starts_with("RPL")) %>% 
  mutate_all(~ifelse(. == -999, NA, .))

# Missing data in RIO ARRIBA, NM (FIPS 35039); REPLACE WITH DATA FROM SAN JUAN, NM (FIPS 35045)
# svi_data$EP_POV <- ifelse(svi_data$FIPS == "35039", svi_data[svi_data$FIPS == "35043", ]$EP_POV, svi_data$EP_POV)
# svi_data$EP_UNEMP <- ifelse(svi_data$FIPS == "35039", svi_data[svi_data$FIPS == "35043", ]$EP_UNEMP, svi_data$EP_UNEMP)
# svi_data$EP_PCI <- ifelse(svi_data$FIPS == "35039", svi_data[svi_data$FIPS == "35043", ]$EP_PCI, svi_data$EP_PCI)
# svi_data$RPL_THEME1 <- ifelse(svi_data$FIPS == "35039", svi_data[svi_data$FIPS == "35043", ]$RPL_THEME1, svi_data$RPL_THEME1)
# svi_data$RPL_THEMES <- ifelse(svi_data$FIPS == "35039", svi_data[svi_data$FIPS == "35043", ]$RPL_THEMES, svi_data$RPL_THEMES)

svi_data <- cnty_data_long %>% 
  select(FIPS, TOT_POP, CWA) %>% 
  distinct(FIPS, .keep_all = TRUE) %>% 
  group_by(CWA) %>% 
  mutate(TOT_POP_PROP_CWA = TOT_POP / sum(TOT_POP)) %>% 
  right_join(., svi_data, by = "FIPS") %>% 
  ungroup()
cnty_data_long <- left_join(cnty_data_long, svi_data %>% select(-c(TOT_POP, CWA)), by = "FIPS")

cwa_svi_data <- svi_data %>% 
  mutate_at(vars(EP_POV150:RPL_THEMES), list(~ . * TOT_POP_PROP_CWA)) %>% 
  group_by(CWA) %>% 
  summarize_at(vars(EP_POV150:RPL_THEMES), list(sum))
cwa_data_long <- left_join(cwa_data_long, cwa_svi_data, by = "CWA")

cnty_data_long <- cnty_data_long %>% rename_at(vars(EP_POV150:RPL_THEMES), ~paste0("FIPS_", .))
cwa_data_long <- cwa_data_long %>% rename_at(vars(EP_POV150:RPL_THEMES), ~paste0("CWA_", .))

# Output Data -------------------------
write_csv(cwa_data_long, paste0(outputs, "base_cwa_census_data.csv"))
write_csv(cnty_data_long, paste0(outputs, "base_county_census_data.csv"))
