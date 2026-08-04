library(tidyverse)
library(data.table)
library(lubridate)

source(here::here("00_wxdash_2.0", "00_paths.R"))

# Locate Watch/Warning Data ----------------------------------------------------
wwa_paths <- list.files(downloads, full.names = TRUE, pattern = "_all") # source: https://mesonet.agron.iastate.edu/request/gis/watchwarn.phtml

# Function to Process Watch/Warning CSVs ---------------------------------------
process_wwa_summary <- function(dir_path) {
  file_year <- str_extract(basename(dir_path), "\\d{4}")
  cat("Processing file for year:", file_year, "\n")

  # Read attributes from the CSV (no geometry) instead of the ~1 GB shapefile
  csv_path <- list.files(dir_path, pattern = "\\.csv$", full.names = TRUE)

  wwa_summary <- fread(csv_path, select = c("WFO", "ISSUED", "PHENOM")) |>
    as_tibble() |>
    mutate(
      issue_date = as_date(ymd_hm(ISSUED)),
      year = year(issue_date),
      CATEGORY = case_when(
        PHENOM %in% c("EH", "HT", "XH") ~ "HEAT", # https://github.com/akrherz/pyIEM/blob/main/src/pyiem/nws/vtec.py
        PHENOM %in% c("CW", "EC", "WC", "FR", "FZ", "HZ", "UP") ~ "COLD",
        PHENOM %in%
          c(
            "BS",
            "HS",
            "LB",
            "LE",
            "SB",
            "SN",
            "SQ",
            "WS",
            "WW",
            "BZ"
          ) ~ "SNOW",
        PHENOM %in% c("IS", "IP", "ZR") ~ "ICE",
        PHENOM %in% c("TO") ~ "TORN",
        PHENOM %in% c("SV", "HW", "WI") ~ "WIND",
        PHENOM %in% c("CF", "FA", "FF", "FL", "LS", "DF", "HY", "LO") ~ "FLOOD",
        PHENOM %in% c("EW", "HF", "HU", "SS", "TR", "TY", "HI", "TI") ~ "HURR",
        PHENOM %in% c("FW") ~ "FIRE",
        TRUE ~ NA_character_
      )
    ) |>
    filter(!is.na(issue_date)) |>
    distinct(WFO, CATEGORY, year, issue_date) |>
    count(WFO, CATEGORY, year, name = "day_count")

  return(wwa_summary)
}

# Initialize results list
summary_list <- list()

# Loop through each file sequentially and store results
for (path in wwa_paths) {
  summary_list[[length(summary_list) + 1]] <- process_wwa_summary(path)
  gc()
}

# Combine all results into a single dataframe
combined_summary <- bind_rows(summary_list)

# Aggregate final results
result_summary <- combined_summary |>
  filter(!is.na(CATEGORY)) |>
  group_by(WFO, CATEGORY) |>
  summarise(day_count = sum(day_count), .groups = "drop") |>
  pivot_wider(names_from = CATEGORY, values_from = day_count, values_fill = 0)

# Save results
write_csv(result_summary, paste0(outputs, "02_cwa_alert_counts.csv"))
