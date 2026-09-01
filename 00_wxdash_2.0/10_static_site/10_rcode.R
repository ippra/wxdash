# Reproduction Scripts ---------------------------------------------------------
# Every chart on the explore page carries the R that rebuilds it. This file
# holds the generator and the check that a generated script actually produces
# the numbers being published beside it. Sourced by 10_build_static_site.R,
# which is the script that computes those numbers - the code that reproduces an
# estimate is written by the code that made it, so the two cannot drift.
#
# One script per (question, split), not one template with placeholders. A
# script for a specific chart should name that chart's columns and no others:
# splitting by age should not make a reader read a roster of twelve grouping
# columns, and it should say `AGE_GROUP`, not `.data[[SPLIT]]`. Three rules the
# generated code follows, and they are the point of it:
#
#   - no helper functions. Every step is a call the reader can run on its own.
#   - column names written where they are used, never through .data[[ ]].
#   - only the columns this chart needs - no grouping column at all under
#     Everyone.
#
# The scripts read the released wave files, <WAVE>_data_wtd.csv, which is what
# 05 reads. They do not read 05's pooled output: that file is 400 MB and
# nothing releases it, while a wave file is one to three MB and a question
# rarely spans more than nine of them.

# Literals ---------------------------------------------------------------------
r_quote <- function(x) paste0('"', gsub('([\\\\"])', '\\\\\\1', x), '"')

# Non-syntactic column names need backticks. Survey variables mostly do not,
# but the reference carries what the instruments carry rather than what R
# parses, so this is checked rather than assumed.
r_name <- function(x) if (make.names(x) == x) x else paste0("`", x, "`")

# c("a", "b", ...) wrapped to fit. Breaks between elements only: strwrap()
# breaks at any whitespace, which would put a newline inside a response label
# and quietly change the string.
r_vec <- function(x, indent) {
  pad <- strrep(" ", indent)
  parts <- paste0(r_quote(x), c(rep(",", length(x) - 1), ""))
  lines <- character(0)
  cur <- ""
  for (piece in parts) {
    if (!nzchar(cur)) {
      cur <- piece
    } else if (indent + nchar(cur) + 1 + nchar(piece) > 78) {
      lines <- c(lines, cur)
      cur <- piece
    } else {
      cur <- paste(cur, piece)
    }
  }
  paste0("c(", paste(c(lines, cur), collapse = paste0("\n", pad)), ")")
}

# A question stem runs past 500 characters in these instruments. One string
# literal that long is a line nobody can read, so it is broken into fragments.
r_title <- function(title) {
  if (nchar(title) <= 60) return(r_quote(title))
  parts <- strwrap(title, 60)
  paste0("paste(\n      ",
         paste(r_quote(parts), collapse = ",\n      "), "\n    )")
}

# Splits -----------------------------------------------------------------------
# The five derived groupings, written out where they are used. A reader holding
# the script and the wave files has everything; a reader sent to look up
# 09_create_dashboard_data.R does not. The labels and the cuts are that
# script's - the prefixes it uses to order the groups are dropped here, and the
# order comes back as factor levels below.
r_derive <- list(
  RURAL_GROUP = list(
    pre = NULL,
    expr = paste0(
      "      RURAL_GROUP = case_when(\n",
      "        rural == \"1\" ~ \"Urban\",\n",
      "        rural == \"2\" ~ \"Suburban\",\n",
      "        rural == \"3\" ~ \"Rural\"\n",
      "      )")
  ),
  TENURE_GROUP = list(
    pre = NULL,
    expr = paste0(
      "      TENURE_GROUP = case_when(\n",
      "        rent == \"1\" ~ \"Live with family\",\n",
      "        rent == \"2\" ~ \"Rent\",\n",
      "        rent == \"3\" ~ \"Own\"\n",
      "      )")
  ),
  # Six residence types collapse to five: boat, boathouse, ship or dock is a
  # bar drawn off a handful of people in any single hazard, so it joins Other.
  HOME_GROUP = list(
    pre = NULL,
    expr = paste0(
      "      HOME_GROUP = case_when(\n",
      "        home == \"1\" ~ \"House\",\n",
      "        home == \"2\" ~ \"Attached home\",\n",
      "        home == \"3\" ~ \"Apartment\",\n",
      "        home == \"4\" ~ \"Mobile home\",\n",
      "        home %in% c(\"5\", \"6\") ~ \"Other\"\n",
      "      )")
  ),
  # children arrives as text, so it is parsed rather than compared: comparing
  # it as text reads \"00\" as greater than \"0\". Values above 20 are sentinels
  # or typing errors - the drop-down stops at \"More than 20\".
  CHILDREN_GROUP = list(
    pre = paste0(
      "    mutate(\n",
      "      kids = suppressWarnings(as.numeric(children)),\n",
      "      kids = if_else(kids >= 0 & kids <= 20, kids, NA_real_)\n",
      "    ) |>\n"),
    expr = paste0(
      "      CHILDREN_GROUP = case_when(\n",
      "        kids == 0 ~ \"No children\",\n",
      "        kids >= 1 ~ \"Has children\"\n",
      "      )")
  ),
  # Weather salience is the mean of two items, and it requires both: a
  # one-item scale is a different quantity from the two-item mean, not a
  # noisier version of it. The sum divided by two propagates NA, which is what
  # requiring both means here.
  SALIENCE_GROUP = list(
    pre = paste0(
      "    mutate(\n",
      "      salience = (as.numeric(follow) + as.numeric(plan_around)) / 2\n",
      "    ) |>\n"),
    expr = paste0(
      "      SALIENCE_GROUP = case_when(\n",
      "        salience <  3 ~ \"Low\",\n",
      "        salience <  4 ~ \"Moderate\",\n",
      "        salience >= 4 ~ \"High\"\n",
      "      )")
  )
)

# The columns each derived grouping is built from. Checked against the wave
# files before anything is generated: a script naming a column its wave file
# does not have is an error the reader meets, not one we do.
derive_sources <- list(
  RURAL_GROUP = "rural",
  TENURE_GROUP = "rent",
  HOME_GROUP = "home",
  CHILDREN_GROUP = "children",
  SALIENCE_GROUP = c("follow", "plan_around")
)

# The wave a hazard and a year name together: "Severe Weather (WX)" and 2018
# are WX18_data_wtd.csv, which is what 05 reads and what a reader downloads.
wave_of <- function(hazard, year) {
  paste0(str_extract(hazard, "(?<=\\()..(?=\\))"), substr(year, 3, 4))
}

# The Generator ----------------------------------------------------------------
# `waves` is the wave codes this chart rests on, in the order they should be
# stacked; `years` runs parallel to it and is only used by the survey-year
# split, which has no column in the data and names the year per file instead.
r_script <- function(question, variable, hazard, waves, years, split,
                     split_label, level_values, level_labels,
                     group_order = NULL, wx17_note = FALSE) {
  obj <- str_to_lower(waves)
  grp <- if (split == "All") NULL else split
  derived <- !is.null(grp) && !is.null(r_derive[[grp]])

  # What each wave contributes: the weight, the grouping if there is one, and
  # the answer. Nothing else - a chart split by age has no business reading
  # eleven other grouping columns out of a 217-column file.
  stack <- map2_chr(obj, years, function(o, year) {
    pre <- if (derived) r_derive[[grp]]$pre else NULL
    lines <- "      PERSON_WEIGHT = as.numeric(PERSON_WEIGHT)"
    if (!is.null(grp)) {
      lines <- c(lines, if (grp == "survey_year") {
        paste0("      survey_year = ", r_quote(as.character(year)))
      } else if (derived) {
        r_derive[[grp]]$expr
      } else {
        # The "(1) " prefixes order the groups in the data rather than label
        # them, and the chart shows the labels without them.
        paste0("      ", grp, " = str_remove(", grp,
               ", \"^\\\\(\\\\d+\\\\) \")")
      })
    }
    lines <- c(lines, paste0("      resp = ", r_name(variable)))
    paste0("  ", o, " |>\n", if (is.null(pre)) "" else pre,
           "    transmute(\n", paste(lines, collapse = ",\n"), "\n    )")
  })

  # Dropped before the design is built, not after: a respondent with no weight
  # has no place in a weighted percentage, and one with no grouping is not in
  # any of the bars being drawn.
  drops <- c("!is.na(resp)",
             if (!is.null(grp) && grp != "survey_year")
               paste0("!is.na(", grp, ")"),
             "!is.na(PERSON_WEIGHT)")

  est <- paste0(
    "est <- d |>\n",
    "  as_survey_design(ids = 1, weights = PERSON_WEIGHT) |>\n",
    "  group_by(", paste(c(grp, "resp"), collapse = ", "), ") |>\n",
    "  summarise(p = survey_prop(proportion = TRUE, vartype = \"ci\"),\n",
    "            .groups = \"drop\")\n")

  # Response codes are character, so sorting them as strings puts 10 between 1
  # and 2. The instrument's own order is used instead, and a code the
  # instrument does not document is shown as itself rather than dropped.
  order_block <- paste0(
    "est <- est |>\n",
    "  mutate(\n",
    "    p = 100 * p, p_low = 100 * p_low, p_upp = 100 * p_upp,\n",
    "    resp = factor(\n",
    "      resp,\n",
    "      levels = ", r_vec(level_values, 17), ",\n",
    "      labels = ", r_vec(level_labels, 17), "\n",
    "    )",
    if (!is.null(group_order)) {
      paste0(",\n    ", grp, " = factor(\n      ", grp, ",\n      levels = ",
             r_vec(group_order, 17), "\n    )")
    } else "",
    "\n  )\n")

  fill <- if (is.null(grp)) "" else paste0(", fill = ", grp)
  dodge <- if (is.null(grp)) "" else
    "\n                position = position_dodge2(reverse = TRUE),"
  plot <- paste0(
    "ggplot(est, aes(x = p, y = fct_rev(resp)", fill, ")) +\n",
    "  geom_col(", if (is.null(grp)) "" else
      "position = position_dodge2(reverse = TRUE), ", "width = 0.8) +\n",
    "  geom_errorbar(aes(xmin = p_low, xmax = p_upp),", dodge, "\n",
    "                width = 0.2, linewidth = 0.3) +\n",
    "  labs(\n",
    "    title = str_wrap(", r_title(question), ", 70),\n",
    "    x = \"Share of respondents (%)\",\n",
    "    y = NULL",
    if (is.null(grp)) "" else paste0(",\n    fill = ", r_quote(split_label)),
    "\n  ) +\n",
    "  theme_minimal()\n")

  paste0(
    paste(strwrap(question, 76, prefix = "# "), collapse = "\n"), "\n",
    "#\n",
    "# WxDash, the IPPRA Extreme Weather and Society Project. Rebuilds this\n",
    "# chart from the released wave files and nothing else.\n",
    "# ", hazard, ", ", paste(waves, collapse = ", "), ".\n",
    if (split == "All") "" else
      paste0("# Split by ", str_to_lower(split_label), " (the `", split,
             "` column).\n"),
    if (wx17_note)
      paste0("# WX17 asked this on a 1-7 scale rather than 1-5, so it is not\n",
             "# pooled with the waves below.\n") else "",
    "\n",
    "library(tidyverse)\n",
    "library(srvyr)\n\n",
    "# Read as character: a question asked in one wave is empty in the\n",
    "# others, and a column empty for its first thousand rows is guessed\n",
    "# logical, which turns every real value after it into NA.\n",
    paste0(obj, " <- read_csv(", r_quote(paste0(waves, "_data_wtd.csv")),
           ",\n", strrep(" ", nchar(obj) + 13),
           "col_types = cols(.default = col_character()))",
           collapse = "\n"), "\n\n",
    "d <- bind_rows(\n", paste(stack, collapse = ",\n"), "\n) |>\n",
    "  filter(", paste(drops, collapse = ", "), ")\n\n",
    est, "\n", order_block, "\n", plot)
}

# Verification -----------------------------------------------------------------
# Does the generated script actually rebuild the chart? Checked, not asserted.
# A script is run against the same wave files a reader would download and its
# estimates compared with the rows being written to the question file.
# Publishing code that does not reproduce the chart printed beside it would be
# worse than publishing none, and a generator is exactly the kind of thing that
# goes subtly wrong.
#
# read_csv is shimmed to a cache in the evaluation environment, so a run does
# not read the same 22 files a hundred times. Same arguments, same result.
r_code_cache <- new.env(parent = emptyenv())

cached_read_csv <- function(file, ...) {
  key <- paste0(survey_files, file)
  if (is.null(r_code_cache[[key]])) {
    r_code_cache[[key]] <- readr::read_csv(key, ...)
  }
  r_code_cache[[key]]
}

new_rcode_tally <- function() {
  e <- new.env(parent = emptyenv())
  e$checks <- 0L
  e$scripts <- 0L
  e
}

# `expect` is the rows being written to the question file: group, resp (the
# response *code*), p. `options` maps value -> label.
verify_r_code <- function(script, expect, options, label, tally) {
  e <- new.env(parent = globalenv())
  assign("read_csv", cached_read_csv, envir = e)
  ok <- try(suppressWarnings(suppressMessages(
    eval(parse(text = script), envir = e))), silent = TRUE)

  if (inherits(ok, "try-error")) {
    cat(script)
    stop("The generated R for ", label, " does not run: ",
         conditionMessage(attr(ok, "condition")))
  }

  # The script labels its responses, so the published codes are labelled to
  # match rather than the other way round. Comparing on the codes would not
  # notice a levels/labels pairing that had drifted.
  got <- get("est", envir = e) |> as_tibble()
  gcol <- setdiff(names(got), c("resp", "p", "p_low", "p_upp", "p_se"))
  got <- got |>
    transmute(
      group = if (length(gcol) == 1) as.character(.data[[gcol]]) else "All",
      resp = as.character(resp), gen = round(p, 2))
  want <- expect |>
    left_join(options, by = c("resp" = "value")) |>
    transmute(group = as.character(group), resp = label, pub = round(p, 2))

  cmp <- full_join(want, got, by = c("group", "resp"))

  if (any(is.na(cmp$pub)) || any(is.na(cmp$gen)) ||
      max(abs(cmp$pub - cmp$gen)) > 0.011) {
    print(cmp |> filter(is.na(pub) | is.na(gen) | abs(pub - gen) > 0.011))
    stop("The generated R for ", label, " does not reproduce its chart.")
  }

  tally$checks <- tally$checks + 1L
}
