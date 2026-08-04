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

  # Read attributes from the CSV (no geometry) instead of the ~1 GB shapefile.
  # read_csv rather than fread: the FCSTER column holds unquoted forecaster
  # initials such as "MGF, JD", so those rows parse as 27 fields against a
  # 26-field header. fread stops at the first one and returns everything before
  # it -- that silently cost 2025 89% of its rows. No fread option recovers
  # them; fill and quote = "" both stop in the same place.
  csv_path <- list.files(dir_path, pattern = "\\.csv$", full.names = TRUE)

  # ISSUED is read as character because read_csv would otherwise type it POSIXct,
  # and ymd_hm() returns NA on a POSIXct, which empties the table.
  wwa_summary <- read_csv(
    csv_path,
    col_select = c(WFO, ISSUED, PHENOM),
    col_types = cols(ISSUED = col_character(), .default = col_guess()),
    progress = FALSE
  ) |>
    mutate(
      issue_date = as_date(ymd_hm(ISSUED)),
      year = year(issue_date),
      CATEGORY = case_when(
        PHENOM %in% c("EH", "HT", "XH") ~ "HEAT", # https://github.com/akrherz/pyIEM/blob/main/src/pyiem/nws/vtec.py
        # COLD is cold air only. FR/FZ/HZ (frost, freeze, hard freeze) are split
        # out as FREEZE because they are issued for agricultural areas in CA, OR
        # and FL, not for cold places -- the two correlate -0.21 across CWAs, and
        # merging them halved every winter risk correlation.
        PHENOM %in% c("CW", "EC", "WC", "UP") ~ "COLD",
        PHENOM %in% c("FR", "FZ", "HZ") ~ "FREEZE",
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
