library(tidyverse)
library(robustbase)
library(sf)
library(rmapshaper)

downloads <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/downloads/" # define locally!!!
outputs <- "/Users/josephripberger/Dropbox (Univ. of Oklahoma)/Severe Weather and Society Dashboard/local files/outputs/" # define locally!!!

# Make Shapefile ----------------------------------------
state_shp <- read_sf(paste0(downloads, "s_22mr22"), "s_22mr22") # TODO: update with predictions

# Write Shapefile ----------------------------------------
state_shp <- ms_simplify(state_shp, keep = 0.05)
st_write(state_shp, paste0(outputs, "state_estimates"), "state_estimates", driver = "ESRI Shapefile", append = FALSE)
