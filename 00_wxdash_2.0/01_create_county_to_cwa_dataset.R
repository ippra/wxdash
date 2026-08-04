library(tidyverse)
library(sf)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Import Shapefiles ------------------------------------------------------------
cnty_shp <- st_read(paste0(downloads, "cb_2025_us_county_20m")) |> st_transform(crs = 5070)
cwa_cnty_shp <- st_read(paste0(downloads, "c_16ap26")) |> st_transform(crs = 5070)

cwa_cnty_data <- cwa_cnty_shp |>
  st_drop_geometry() |>
  mutate(CWA = substr(CWA, start = 1, stop = 3)) |>  # only keep first CWA in counties that span multiple CWAs
  mutate(CWA = ifelse(FIPS == "12087", "KEY", CWA)) |> # assign Mainland Monroe to KEY (Key West)
  distinct(FIPS, CWA, .keep_all = TRUE) # remove duplicate FIPS codes (counties that span multiple CWAs)

cwa_cnty_data |> filter(!FIPS %in% cnty_shp$GEOID) |> tibble() |> print(n = Inf) # n = 58 (AS, VI, CT, PW, MP, GU, FM)
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
  )
)

# Write Data -------------------------------------------------------------------
write_csv(cnty_shp |> st_drop_geometry(), paste0(outputs, "county_to_cwa_data.csv"))
