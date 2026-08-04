library(tidyverse)
library(sf)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Import Shapefiles -----------------
cnty_shp <- st_read("~/Univ. of Oklahoma Dropbox/Joe Ripberger/nws_product_climatology/wwa_data/wwa_shiny_app/data/cb_2023_us_county_500k") |> st_transform(crs = 5070)
cwa_cnty_shp <- st_read("~/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/c_18mr25") |> st_transform(crs = 5070)

cwa_cnty_data <- cwa_cnty_shp |> 
  st_drop_geometry() |> 
  mutate(CWA = substr(CWA, start = 1, stop = 3)) |>  # only keep first CWA in counties that span multiple CWAs
  mutate(CWA = ifelse(FIPS == "12087", "KEY", CWA)) |> # assign KEY to MFL (Miami) for counties that span multiple CWAs
  distinct(FIPS, CWA, .keep_all = TRUE) # remove duplicate FIPS codes (counties that span multiple CWAs)

cwa_cnty_data |> filter(!FIPS %in% cnty_shp$GEOID) |> tibble() |> print(n = Inf) # n = 45 (CT, PW, MH, FM)
cnty_shp |> filter(!GEOID %in% cwa_cnty_data$FIPS) |> print(n = Inf) # n = 10 (CT Planning Regions, HI Kalawao County) # fix below

cnty_shp <- cnty_shp |> 
  left_join(cwa_cnty_data |> select(FIPS, CWA), by = c("GEOID" = "FIPS")) |> 
  mutate(CWA = case_when(
    NAMELSAD %in% c("Northwest Hills Planning Region") ~ "ALY",
    NAMELSAD %in% c("Capitol Planning Region", 
                    "Northeastern Connecticut Planning Region") ~ "BOX",
    NAMELSAD %in% c("Lower Connecticut River Valley Planning Region", 
                    "Southeastern Connecticut Planning Region",
                    "Western Connecticut Planning Region", 
                    "South Central Connecticut Planning Region", 
                    "Naugatuck Valley Planning Region", 
                    "Greater Bridgeport Planning Region") ~ "OKX",
    NAMELSAD %in% c("Kalawao County") ~ "HFO",
    TRUE ~ CWA
  ))

# Write Data -----------------------------
write_csv(cnty_shp |> st_drop_geometry(), paste0(outputs, "county_to_cwa_data.csv"))


