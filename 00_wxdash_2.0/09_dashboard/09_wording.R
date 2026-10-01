# Question Wording -------------------------------------------------------------
# The instruments write what varied between respondents as a placeholder in the
# question: `[lead_time: 15 | 30 | 60]`, `[fcst_conf]`, a bare `rand_dev`. The
# page puts those into words in engine.js (readableWording()); this is the
# same rule in R, for the text R writes where a reader sees it - the comment
# and plot title of each generated script. Both halves of 09 source this
# file: the builder sends `placeholder_words` to the page, and the statistics
# use readable_wording() for the scripts, so the two cannot name a
# placeholder differently.

# Placeholders that are not a version menu's own variable, in words a reader
# can follow. Anything not listed reads "[varied between respondents]".
placeholder_words <- c(
  state = "the respondent’s state",
  ice_thrsh = "the amount the respondent gave earlier",
  snow_thrsh = "the amount the respondent gave earlier",
  cold_thrsh = "the temperature the respondent gave earlier",
  range_max = "an upper amount that varied",
  .default = "varied between respondents"
)

# A listed set reads "[15, 30, or 60]" and a range "[5 to 100]". A value keyed
# to another placeholder ("2 and 6 if amount_format_rand1 = 4, or 10 and 14
# if ...") keeps its alternatives and drops the conditions, unless the version
# it is keyed to is the one shown, in which case it is that version's value.
placeholder_text <- function(name, spec, arm_variable, arm_value) {
  if (!is.na(spec) && str_detect(spec, "\\sif\\s")) {
    alts <- str_match_all(
      spec,
      "(?:^|,)\\s*(?:or\\s+)?(.+?)\\s+if\\s+([a-z][a-z0-9_]*)\\s*=\\s*([^,]+)"
    )[[1]]
    hit <- alts[alts[, 3] %in% arm_variable &
                  str_trim(alts[, 4]) %in% arm_value, , drop = FALSE]
    if (nrow(hit) > 0) return(str_trim(hit[1, 2]))
    return(paste0("[", str_trim(str_remove_all(
      spec, "\\s+if\\s+[a-z][a-z0-9_]*\\s*=\\s*[^,\\]]+"
    )), "]"))
  }
  if (!is.na(spec) && str_detect(spec, "^\\s*\\d+\\s*:\\s*\\d+\\s*$")) {
    ends <- str_trim(str_split_1(spec, ":"))
    return(paste0("[", ends[1], " to ", ends[2], "]"))
  }
  if (!is.na(spec) && str_trim(spec) != "") {
    items <- str_trim(str_split_1(spec, if (str_detect(spec, "\\|")) "\\|"
                                  else ","))
    items <- items[items != ""]
    if (length(items) > 1) {
      return(paste0("[", paste(items[-length(items)], collapse = ", "),
                    if (length(items) > 2) "," else "", " or ",
                    items[length(items)], "]"))
    }
    return(paste0("[", items, "]"))
  }
  word <- placeholder_words[name]
  paste0("[", if (is.na(word)) placeholder_words[[".default"]] else word, "]")
}

# The question as a reader reads it. `arm_variable` and `arm_slot` are the
# version menu's variable and the words the shown version puts in its slot
# (empty where that version added nothing); without them every placeholder is
# put into words.
readable_wording <- function(text, arm_variable = NULL, arm_slot = NULL,
                             arm_value = NULL) {
  pattern <- "\\[([a-z][a-z0-9_]*)(?::\\s*([^\\]]*))?\\]|\\b(rand_[a-z0-9_]+)\\b"
  hits <- str_match_all(text, pattern)[[1]]
  if (nrow(hits) == 0) return(text)
  spans <- str_locate_all(text, pattern)[[1]]
  out <- ""
  last <- 1
  for (i in seq_len(nrow(hits))) {
    name <- if (!is.na(hits[i, 2])) hits[i, 2] else hits[i, 4]
    words <- if (!is.null(arm_variable) && name == arm_variable &&
                 !is.null(arm_slot)) {
      arm_slot
    } else {
      placeholder_text(name, hits[i, 3], arm_variable, arm_value)
    }
    out <- paste0(out, str_sub(text, last, spans[i, 1] - 1), words)
    last <- spans[i, 2] + 1
  }
  str_squish(paste0(out, str_sub(text, last)))
}
