# Paths ------------------------------------------------------------------------
# Every script in this directory sources this file, so the Dropbox roots are
# defined once rather than fourteen times. The machine-specific part lives in
# ~/.Renviron, which is gitignored, so this file is identical on every machine:
#
#   WXDASH_LOCAL="/path/to/Severe Weather and Society Dashboard/local files"
#   WX25_RAW="/path/to/WX25/WX25 Raw Data"
#
# .Renviron is read once when R starts, so restart the session after editing it.
wxdash_local <- Sys.getenv("WXDASH_LOCAL")
wx25_raw <- Sys.getenv("WX25_RAW")

if (wxdash_local == "" || wx25_raw == "") {
  stop("Set WXDASH_LOCAL and WX25_RAW in ~/.Renviron, then restart R.")
}

if (!dir.exists(wxdash_local) || !dir.exists(wx25_raw)) {
  stop("WXDASH_LOCAL or WX25_RAW points somewhere that does not exist.")
}

# Trailing slashes are kept so every paste0(outputs, "file.csv") still works.
downloads <- paste0(wxdash_local, "/downloads/")
outputs <- paste0(wxdash_local, "/outputs/")

# location_files belongs to the WX25 project, not this one. 05 reads the HUD ZIP
# crosswalk from there. Moving or reorganising WX25 breaks 05, and this is the
# only place that dependency is written down.
location_files <- paste0(wx25_raw, "/location_files/")
