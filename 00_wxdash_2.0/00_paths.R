# Paths ------------------------------------------------------------------------
# Every script in this directory sources this file, so the roots are defined
# once rather than fourteen times. The machine-specific part lives in
# ~/.Renviron, which is gitignored, so this file is identical on every machine:
#
#   WXDASH_LOCAL="/path/to/Severe Weather and Society Dashboard/local files"
#   WXSURVEYS_ROOT="/path/to/wxsurveys/"
#
# .Renviron is read once when R starts, so restart the session after editing it.
wxdash_local <- Sys.getenv("WXDASH_LOCAL")
wxsurveys_root <- Sys.getenv("WXSURVEYS_ROOT")

if (wxdash_local == "" || wxsurveys_root == "") {
  stop("Set WXDASH_LOCAL and WXSURVEYS_ROOT in ~/.Renviron, then restart R.")
}

if (!dir.exists(wxdash_local) || !dir.exists(wxsurveys_root)) {
  stop("WXDASH_LOCAL or WXSURVEYS_ROOT points somewhere that does not exist.")
}

# Trailing slashes are kept so every paste0(outputs, "file.csv") still works.
downloads <- paste0(wxdash_local, "/downloads/")
outputs <- paste0(wxdash_local, "/outputs/")

# The 22 built survey datasets, from the wxsurveys repository. 05 reads them.
# They are committed there, so a clone has them without rebuilding anything.
survey_files <- paste0(wxsurveys_root, "english_surveys/data/")
