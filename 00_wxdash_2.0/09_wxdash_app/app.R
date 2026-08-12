library(shiny)
library(tidyverse)
library(DT)
library(srvyr)
library(ggtext) # wraps title and caption to the image width on a download
library(sf)
library(mapgl)

# All four files come from 09_create_dashboard_data.R, which writes them into
# data/ beside this file. Paths are relative on purpose: Shiny sets the working
# directory to the app directory both locally and on the server, and nothing
# here may reach outside that directory - 00_paths.R and WXDASH_LOCAL exist on
# a workstation, not on a deployment.
data_dir <- "data"
needed <- file.path(data_dir, c("09_dashboard_questions.csv",
                                "09_dashboard_responses.rds",
                                "09_dashboard_cwa.rds",
                                "09_dashboard_measure_questions.csv"))

# Failing here with the reason beats failing later with "object not found".
if (!all(file.exists(needed))) {
  stop("Missing app data: ",
       paste(basename(needed[!file.exists(needed)]), collapse = ", "),
       ". Run 09_create_dashboard_data.R before launching or deploying.")
}

questions <- read_csv(needed[1], show_col_types = FALSE)
responses <- read_rds(needed[2])
cwa_estimates <- read_rds(needed[3])

# One row per question per mapped measure, written by 09 from 05's scale
# composition and the variable reference. The app quotes these rather than
# describing them, so what it says was asked is what the instrument says.
measure_questions <- read_csv(needed[4], show_col_types = FALSE)

# The map is MapLibre on CARTO basemap tiles, which need no access token.
# Mapbox was the other option and was dropped: at national zoom, under polygons
# drawn at 75% opacity, none of what it does better is visible, and it would
# have cost a token that has to be set on every deployment separately
# (.Renviron is not part of the app bundle) plus a map-load quota that this tab
# spends on every change of measure.

# Named once because the caption is written as plain prose and then linked by
# substitution, so the page text and the downloaded image cannot drift apart.
institute <- paste("The University of Oklahoma's Institute for Public Policy",
                   "Research and Analysis")
institute_url <- "https://www.ou.edu/ippra"
archive <- "dataverse.harvard.edu/dataverse/wxsurvey"
archive_url <- "https://dataverse.harvard.edu/dataverse/wxsurvey"

# The five demographics are the poststratification cells 04 builds and 06 fits
# on, so a split here cuts the data the same way the estimates do. Census region
# is a county attribute rather than a cell dimension and no model fits it, so it
# describes who answered rather than showing the geographic signal - that lives
# in the CWA and county random effects and comes out in 07. The five between it
# and survey year are built in 09 from background questions and are likewise not
# model terms - they describe who answered. Survey year is last because a
# question asked in more than one wave is pooled across them everywhere else in
# the app.
groups <- c(
  "Everyone" = "All",
  "Age" = "AGE_GROUP",
  "Gender" = "GENDER_GROUP",
  "Race and ethnicity" = "RACE_GROUP",
  "Education" = "EDUC_GROUP",
  "Income" = "INCOME_GROUP",
  "Census region" = "CENSUS_REGION",
  "Urban, suburban, rural" = "RURAL_GROUP",
  "Housing tenure" = "TENURE_GROUP",
  "Residence type" = "HOME_GROUP",
  "Children in household" = "CHILDREN_GROUP",
  "Weather salience" = "SALIENCE_GROUP",
  "Survey year" = "survey_year"
)

# Plain-language forms of the hazard and the split, for a caption meant to be
# read by someone looking at a screenshot with no other context.
hazard_phrases <- c(
  "Severe Weather (WX)" = "severe weather",
  "Tropical Cyclone (TC)" = "tropical cyclones",
  "Winter Weather (WW)" = "winter weather",
  "Flooding (FL)" = "flooding"
)

group_phrases <- c(
  AGE_GROUP = "age group",
  GENDER_GROUP = "gender",
  RACE_GROUP = "race and ethnicity group",
  EDUC_GROUP = "education group",
  INCOME_GROUP = "income group",
  CENSUS_REGION = "census region",
  RURAL_GROUP = "community type",
  TENURE_GROUP = "housing tenure",
  HOME_GROUP = "residence type",
  CHILDREN_GROUP = "children-in-household group",
  SALIENCE_GROUP = "weather salience group",
  survey_year = "survey year's respondents"
)

# Colour schemes ---------------------------------------------------------------
# Every value below was checked with the data-viz validator against a white
# panel, not chosen by eye. Two things it caught are worth recording.
#
# The previous default, viridis(end = 0.9), put its top group at #BBDF27 - 1.53:1
# against white, which is barely a mark at all. Pulling the end in to 0.75 lifts
# that to 2.12:1 and clears the 2:1 floor for an ordered ramp.
#
# The distinct-hue set is Okabe-Ito with its yellow and black dropped (both sit
# outside the lightness band) and the rest re-ordered. Re-ordering alone took the
# worst adjacent pair under simulated deuteranopia from 7.6 to 18.0, against a
# target of 8 - the same six colours, just never placing purple next to green.
#
# The two single-hue ramps are stepped evenly in OKLCH, so lightness carries the
# order even in greyscale or for any type of colour blindness. They are stored as
# literal hex at eight steps because that is the form that was validated; taking
# evenly spaced elements for a smaller split keeps the first and last, so the
# steps stay monotone and the gaps only widen.
ramp_blue <- c("#032A4C", "#043C69", "#054E88", "#1061A5",
               "#2B76BB", "#428BD2", "#57A1E9", "#70B6FD")
ramp_grey <- c("#25292F", "#363B40", "#474D53", "#5A6066",
               "#6E737A", "#82888E", "#969CA3", "#ACB2B9")

# Fixed order, taken from the front for smaller splits and never cycled.
hues_distinct <- c("#009E73", "#0072B2", "#D55E00",
                   "#56B4E9", "#E69F00", "#CC79A7")

palettes <- c(
  "Blue (one hue)" = "blue",
  "Grey (print safe)" = "grey",
  "Viridis" = "viridis",
  "Distinct hues" = "distinct"
)

# The map offers only the three ordered schemes. Distinct hues is a categorical
# set, and a choropleth of an ordered quantity drawn in unordered colours cannot
# be read - the reader has to consult the legend for every polygon.
map_palettes <- palettes[palettes != "distinct"]

# No basemap. CARTO positron was under this and its grey water and land read as
# a second set of shapes competing with the estimates - the 116 areas already
# tile the country, so its coastline is drawn by the data itself.
#
# A style with no sources rather than a hidden layer, so nothing is fetched at
# all. sources must serialize as {} and not [], which is why it is built with
# setNames() rather than list().
#
# This is also what the PDF download draws, so what is on screen and what leaves
# the app now match.
blank_basemap <- list(
  version = 8,
  sources = setNames(list(), character(0)),
  layers = list(list(
    id = "background",
    type = "background",
    paint = list("background-color" = "#FFFFFF")
  ))
)

# Grouped by hazard, with the risk battery kept together at the end. The map is
# read by people who did not fit the models, so the label is what it is called
# here and RISK_SURGE is what it is called in the data.
#
# Every label names its hazard even though the group heading already does. A
# closed select shows the option and not the group it came from, so a label of
# "Reception" alone would leave the control reading as nothing once chosen.
#
# Reception, comprehension and response are the three constructs the models in
# 06 fit, named here as they are named there. The hazard word follows the
# instrument: ice is "ice and freezing rain" because that is what was asked.
map_measures <- list(
  "Tornadoes" = c(
    "Tornado warning reception" = "TO_RECEP",
    "Tornado warning comprehension" = "TO_SUBJ_COMP",
    "Tornado warning response" = "TO_RESP"
  ),
  "Hurricanes" = c(
    "Hurricane warning reception" = "HU_RECEP",
    "Hurricane warning comprehension" = "HU_SUBJ_COMP",
    "Hurricane warning response" = "HU_RESP"
  ),
  "Winter storms" = c(
    "Winter storm warning reception" = "WW_RECEP",
    "Winter storm warning comprehension" = "WW_SUBJ_COMP",
    "Winter storm warning response" = "WW_RESP"
  ),
  "Floods" = c(
    "Flood warning reception" = "FL_RECEP",
    "Flood warning comprehension" = "FL_SUBJ_COMP",
    "Flood warning response" = "FL_RESP"
  ),
  "Risk perceptions" = c(
    "Tornado risk perceptions" = "RISK_TOR",
    "Hurricane risk perceptions" = "RISK_HUR",
    "Storm surge risk perceptions" = "RISK_SURGE",
    "Flood risk perceptions" = "RISK_FLOOD",
    "Snow risk perceptions" = "RISK_SNOW",
    "Ice and freezing rain risk perceptions" = "RISK_ICE",
    "Extreme cold risk perceptions" = "RISK_COLD",
    "Extreme heat risk perceptions" = "RISK_HEAT",
    "Wildfire risk perceptions" = "RISK_FIRE",
    "Drought risk perceptions" = "RISK_DROUGHT",
    "Hail risk perceptions" = "RISK_HAIL",
    "Lightning risk perceptions" = "RISK_LIGNT"
  )
)

# The ends of the response scale, read off the options the instrument offered
# rather than described from memory. "3.4" means nothing without knowing what 5
# was called.
scale_anchors <- function(options) {
  o <- option_labels(options)
  if (nrow(o) == 0) return(NA_character_)
  paste0(o$value[1], " (", str_to_lower(o$label[1]), ") to ",
         o$value[nrow(o)], " (", str_to_lower(o$label[nrow(o)]), ")")
}

# Small counts read as words in a sentence. Anything larger than this falls back
# to the numeral rather than inventing more names.
count_word <- function(n) {
  words <- c("one", "two", "three", "four", "five", "six", "seven", "eight",
             "nine")
  if (n >= 1 && n <= length(words)) words[n] else as.character(n)
}

# Reversed for blue and grey so the darkest step carries the highest value,
# which is the direction a choropleth is read in. Viridis is left in its own
# order: it already runs dark to bright, and reversing it puts the bright end
# on the low values, which reads as the opposite of what it means.
map_colours <- function(palette, n = 7) {
  values <- switch(
    palette,
    blue = rev(ramp_colours(ramp_blue, n)),
    grey = rev(ramp_colours(ramp_grey, n)),
    viridis = viridisLite::viridis(n, end = 0.75)
  )
  # Trimmed to six digits. viridisLite returns #RRGGBBAA and the two hand-built
  # ramps are #RRGGBB, so the palettes would reach the map in two different
  # forms. The alpha is FF in every case and opacity is set on the layer, so
  # nothing is lost - and a colour the style parser rejects does not warn, it
  # just leaves the areas unpainted.
  substr(values, 1, 7)
}

# Every measure is stretched over its own range rather than a shared 1-5. The
# risk items span 1.3 to 4.9 across CWAs while the warning scales span 2.6 to
# 3.8, so a fixed 1-5 ramp would draw all twelve warning maps in one flat mid
# tone and hide the variation the map exists to show. The legend prints the
# range, so the stretch is stated rather than implied.
map_breaks <- function(values, n = 7) {
  seq(min(values), max(values), length.out = n)
}

# Flattened once. unlist() on the nested list would name each element
# "group.label", so the lookup is built explicitly instead of parsed back apart.
# Labels repeat across groups - three of them are "Tornado warnings" - but the
# column names do not, so the match is on the column.
measure_lookup <- map_measures |>
  imap(\(x, group) tibble(group = group, label = names(x),
                          measure = unname(x))) |>
  list_rbind()

measure_label <- function(measure) {
  measure_lookup$label[match(measure, measure_lookup$measure)]
}

# Eight steps is the ceiling for an ordered ramp on a white panel: the light end
# has to stay above 2:1 contrast and each step has to sit 0.06 OKLCH lightness
# from its neighbour, and nine steps cannot do both. Splitting by survey year
# asks for nine on 43 of the questions, so those fall back to viridis, which at
# least stays perceptually even where a hand-stepped ramp would not.
ramp_colours <- function(ramp, n) {
  if (n > length(ramp)) return(viridisLite::viridis(n, end = 0.75))
  ramp[round(seq(1, length(ramp), length.out = n))]
}

fill_scale <- function(palette, n) {
  values <- switch(
    palette,
    blue     = ramp_colours(ramp_blue, n),
    grey     = ramp_colours(ramp_grey, n),
    viridis  = viridisLite::viridis(n, end = 0.75),
    distinct = if (n <= length(hues_distinct)) {
      hues_distinct[seq_len(n)]
    } else {
      # Never invent a hue for an extra series - fall back to the ordered ramp.
      viridisLite::viridis(n, end = 0.75)
    }
  )
  # Reversed to match fct_rev on the fill, so the first group reads darkest and
  # sits at the top of each response.
  scale_fill_manual(values = rev(values),
                    guide = guide_legend(reverse = TRUE, nrow = 1))
}

# The single-series case takes the ramp's dark end, so switching scheme changes
# the ungrouped chart too rather than leaving one colour stranded.
solo_colour <- function(palette) {
  switch(palette,
         blue = ramp_blue[1], grey = ramp_grey[1],
         viridis = viridisLite::viridis(1, end = 0.15),
         distinct = hues_distinct[1])
}

# Years are collapsed into runs so a caption reads "2018-2021, 2024" rather
# than listing nine of them. The gaps are the informative part: a question can
# be asked, dropped for a wave and asked again.
year_runs <- function(years) {
  y <- sort(unique(as.integer(years)))
  ends <- c(which(diff(y) != 1), length(y))
  starts <- c(1, head(ends, -1) + 1)
  runs <- if_else(
    y[starts] == y[ends],
    as.character(y[starts]),
    paste0(y[starts], "-", y[ends])
  )
  paste(runs, collapse = ", ")
}

# Response options arrive as "1 = White | 2 = Black or African American". The
# value is matched back to the data as text, because a question fielded in one
# wave and not another can come out of the CSV as either numeric or character.
option_labels <- function(x) {
  empty <- tibble(value = character(), label = character())
  if (is.na(x) || x == "") return(empty)
  parts <- str_split(x, fixed(" | "))[[1]]
  matches <- str_match(parts, "^\\s*(.+?)\\s*=\\s*(.*)$")
  tibble(value = matches[, 2], label = matches[, 3]) |>
    drop_na()
}

# One plot definition, drawn on the page and written to a download. Bars run
# horizontally because response options are sentences as often as they are
# words - "I would trust forecasts generated by machine learning much less than
# forecasts generated by humans" does not fit under a tick.
distribution_plot <- function(d, show_ci, grouping, palette) {
  dodge <- position_dodge(width = 0.8)
  plot <- ggplot(d, aes(x = p, y = fct_rev(label), fill = fct_rev(group))) +
    geom_col(position = dodge, width = 0.75)

  # Worth switching on before reading a gap between two groups or two years
  # as real, particularly where one of the cells is small.
  if (show_ci) {
    plot <- plot +
      geom_errorbar(aes(xmin = p_low, xmax = p_upp), position = dodge,
                    width = 0.25, linewidth = 0.4)
  }

  plot <- plot +
    # Not decoration: two of the distinct hues sit just under 3:1 against white,
    # which the colour checks allow only where a visible label carries the value.
    geom_text(aes(x = p_upp, label = paste0(round(p), "%")), position = dodge,
              hjust = -0.25, size = 4) +
    labs(x = "Respondents (%)", y = NULL, fill = NULL) +
    theme_classic(base_size = 16) +
    theme(legend.position = "top") +
    scale_x_continuous(expand = expansion(mult = c(0, 0.15)))

  # fill is reversed so the first group sits at the top of each response,
  # matching the order it is listed in; the legend is reversed back inside
  # fill_scale.
  if (grouping == "All") {
    plot + scale_fill_manual(values = solo_colour(palette)) + guides(fill = "none")
  } else {
    plot + fill_scale(palette, n_distinct(d$group))
  }
}

# The downloaded map is drawn with ggplot rather than captured from the page.
# MapLibre paints to a WebGL canvas the server cannot reach, and a screenshot of
# it would be a raster of whatever the viewer happened to be zoomed to. This
# redraws the same polygons and the same ramp as vector art at a fixed extent.
#
# There is no basemap under it. The CARTO tiles are not the institute's to
# redistribute in a PDF, and at this extent they carried little anyway.
#
# Albers rather than the stored 4326: an equal-area projection is what a
# national choropleth should be read in, and plate carree stretches the
# northern CWAs enough to change which look large.
map_plot <- function(d, colours, title, caption) {
  ggplot(d) +
    geom_sf(aes(fill = value), colour = "white", linewidth = 0.15) +
    scale_fill_gradientn(colours = colours, name = NULL) +
    coord_sf(crs = 5070) +
    labs(title = title, caption = caption) +
    theme_void(base_size = 12) +
    theme(
      legend.position = "bottom",
      legend.key.width = unit(2.4, "cm"),
      legend.key.height = unit(0.4, "cm"),
      plot.margin = margin(14, 14, 10, 14),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      plot.title = element_textbox_simple(
        size = 15, face = "bold", margin = margin(b = 14)
      ),
      plot.caption = element_textbox_simple(
        size = 9, colour = "grey30", margin = margin(t = 16)
      )
    )
}

# ggtext wraps, so the drawn line count is not known ahead of the draw. The map
# caption carries explicit <br> breaks, so counting characters alone would
# under-count it badly - each segment is measured separately and every break
# costs a line of its own.
textbox_lines <- function(text, per_line) {
  segments <- str_split(text, fixed("<br>"))[[1]]
  sum(pmax(1, ceiling(nchar(segments) / per_line)))
}

# Fixed height crushes the labels of the few questions with a dozen options
# into each other, so the panel grows with the bars instead.
plot_height <- function(d) {
  max(320, 55 * n_distinct(d$label), 22 * nrow(d) + 90)
}

ui <- navbarPage(
  "Extreme Weather and Society Survey",
  tabPanel(
  "Explore Survey Questions and Results",
  helpText(
    "Click a survey question in the table below to see the weighted",
    "distribution of responses. Each question is listed once per survey hazard,",
    "because the wording differs between hazards. Where the wording also",
    "changed between waves, the most recent version is shown."
  ),
  # One row above the chart. The split stays left because it scopes what the
  # chart shows; the three that only change how it is drawn sit right, so the
  # row reads as scope first, appearance second rather than four equal knobs.
  # Bootstrap puts a bottom margin on every form group, which would leave the
  # select, the checkbox and the button sitting at three different heights, so
  # the margin is zeroed inside this row only - loosening it globally would move
  # the search boxes in the question table too.
  tags$style(HTML(paste(
    ".chart-controls .form-group { margin-bottom: 0; }",
    ".chart-controls .checkbox { margin: 0; }"
  ))),
  div(
    class = "chart-controls",
    style = paste("display: flex; align-items: flex-end; gap: 16px;",
                  "flex-wrap: wrap; margin: 12px 0 20px;"),
    selectInput("group", "Split responses by", choices = groups,
                width = "260px"),
    div(
      style = "display: flex; align-items: flex-end; gap: 16px; margin-left: auto;",
      selectInput("palette", "Change color scheme", choices = palettes,
                  width = "200px"),
      # Nudged off the bottom edge so the checkbox text and the button label
      # sit on the same line as the select, which carries a label above it.
      div(style = "padding-bottom: 6px;",
          checkboxInput("ci", "Show 95% confidence intervals", value = FALSE)),
      div(style = "padding-bottom: 6px;",
          downloadButton("download", "Download chart (PDF)"))
    )
  ),
  # The question sits above the plot rather than in its title: some questions
  # carry a paragraph of scenario text, which as a title left the bars an inch
  # of vertical space.
  uiOutput("question"),
  plotOutput("distribution", height = "auto"),
  uiOutput("caption"),
  hr(),
  DTOutput("questions")
  ),

  # Map Tab --------------------------------------------------------------------
  # Estimates rather than responses. The help text leads with that difference,
  # because the two tabs look alike and mean different things: the first is what
  # respondents said, this is what the models predict for a whole population,
  # including the areas where few people were surveyed.
  tabPanel(
    "Map Survey Estimates",
    helpText(
      "These are model estimates, not raw survey responses. Each County",
      "Warning Area gets a value built from the demographic makeup of its",
      "counties and",
      "how people like them answered, so every area has an estimate, including",
      "those where few people were surveyed. Hover an area to read its value."
    ),
    div(
      class = "chart-controls",
      style = paste("display: flex; align-items: flex-end; gap: 16px;",
                    "flex-wrap: wrap; margin: 12px 0 20px;"),
      selectInput("measure", "Map estimates for", choices = map_measures,
                  width = "320px"),
      div(
        style = paste("display: flex; align-items: flex-end; gap: 16px;",
                      "margin-left: auto;"),
        selectInput("map_palette", "Change color scheme",
                    choices = map_palettes, width = "200px"),
        # Nudged off the bottom edge so the button label sits on the same line
        # as the select, which carries a label above it.
        div(style = "padding-bottom: 6px;",
            downloadButton("map_download", "Download map (PDF)"))
      )
    ),
    # Fixed height rather than auto: a map has no natural content height, and
    # left to itself the container collapses to nothing and the tab looks empty.
    maplibreOutput("cwa_map", height = "620px"),
    uiOutput("map_notes")
  )
)

server <- function(input, output, session) {

  selected <- reactive({
    row <- input$questions_rows_selected
    questions[if (is.null(row)) 1 else row, ]
  })

  # The respondents a question actually rests on, shared by the plot and the
  # caption so both describe the same rows.
  respondents <- reactive({
    question <- selected()
    grouping <- input$group

    responses |>
      filter(survey_hazard == question$hazard) |>
      transmute(
        resp = .data[[question$variable]],
        group = if (grouping == "All") {
          "All"
        } else {
          as.character(.data[[grouping]])
        },
        survey_year,
        PERSON_WEIGHT
      ) |>
      drop_na(resp, group, PERSON_WEIGHT)
  })

  distribution <- reactive({
    options <- option_labels(selected()$response_options)

    # Percentages are within group, so each group's bars sum to 100 and the
    # groups are comparable even where one is a tenth the size of another.
    design <- respondents() |>
      as_survey_design(ids = 1, weights = PERSON_WEIGHT) |>
      group_by(group, resp)

    # Two estimators, same percentages - checked equal to 7e-10 across every
    # group of a five-option question. proportion = TRUE fits a logit, which
    # earns its cost in interval coverage but fails to converge and warns on a
    # cell at 0 or 100% (pick gend, split by gender). With no interval to draw
    # there is nothing to buy, so the plain ratio estimator runs instead.
    # Passing proportion explicitly also settles srvyr's default-change notice.
    d <- if (input$ci) {
      design |> summarize(p = survey_prop(proportion = TRUE, vartype = "ci"))
    } else {
      design |>
        summarize(p = survey_prop(proportion = FALSE, vartype = NULL)) |>
        mutate(p_low = p, p_upp = p) # one plot rule then serves both
    }

    d <- d |>
      mutate(across(c(p, p_low, p_upp), ~.x * 100)) |>
      mutate(value = as.character(resp))

    # An unlabelled value is shown as itself rather than dropped - it means the
    # data carries a code the instrument does not document, which is worth
    # seeing on the plot.
    d |>
      left_join(options, by = "value") |>
      mutate(label = str_wrap(coalesce(label, value), 40)) |>
      arrange(resp) |>
      mutate(label = fct_inorder(label)) |>
      # The "(1) " prefixes order the levels upstream; they are noise in a
      # legend, so they are stripped after factor() has used them to sort.
      mutate(group = fct_relabel(factor(group),
                                 ~str_remove(.x, "^\\(\\d+\\) ")))
  })

  # Just the question. The variable name is in the caption instead, where it
  # sits next to the archive link - the two are used together, since the name
  # is how you find this question in the downloaded data.
  output$question <- renderUI({
    h4(selected()$question)
  })

  # Written as prose, and rendered as page text under the plot rather than
  # inside it, so it sits with the question above the plot instead of in two
  # different typefaces at two different widths. The question is already page
  # text, so a screen grab wide enough to carry the question carries this too.
  # Someone reading only that grab should learn whose data it is, what was
  # asked about, when, of how many people, and what the bars are a percentage
  # of. The smallest group is named because it is the one most easily
  # over-read.
  caption_text <- reactive({
    d <- respondents()

    years <- year_runs(d$survey_year)
    waves <- if (str_detect(years, "[-,]")) {
      paste0("across the ", years, " waves")
    } else {
      paste0("in the ", years, " wave")
    }

    counts <- table(d$group)
    split_text <- ""
    smallest_text <- ""
    if (input$group != "All") {
      split_text <- paste0(" of each ", group_phrases[[input$group]])
      smallest_text <- paste0(
        " The smallest group, ",
        str_remove(names(counts)[which.min(counts)], "^\\(\\d+\\) "),
        ", has ", format(min(counts), big.mark = ","), " respondents."
      )
    }

    # Plain prose, which is what the downloaded image needs. The page turns
    # the two names below into links by substitution, so the wording can only
    # be written once. The archive link sits last rather than in a parenthesis
    # after the survey name, where it reads as an aside interrupting the first
    # sentence.
    paste0(
      "Public survey data from the Extreme Weather and Society Survey, run by ",
      institute, ". ", format(nrow(d), big.mark = ","), " US adults answered ",
      "this question about ", hazard_phrases[[selected()$hazard]], " ", waves,
      ". Bars show the weighted percentage", split_text,
      " giving each answer; every wave is raked to American Community Survey ",
      "benchmarks for age, gender, race, education, income and region.",
      smallest_text, " This question is stored as ", selected()$variable,
      " in the survey data, which is available at ", archive, "."
    )
  })

  # Built by substitution rather than assembled from tags: a tagList renders
  # each child on its own line, and the browser collapses that newline into a
  # space, which shows up as "Analysis . 17,785" and "wxsurvey ." The variable
  # name is matched with the words around it, since a name like "age" also
  # occurs inside "age group".
  output$caption <- renderUI({
    linked <- htmltools::htmlEscape(caption_text()) |>
      str_replace(
        fixed(institute),
        paste0("<a href=\"", institute_url, "\" target=\"_blank\">",
               institute, "</a>")
      ) |>
      str_replace(
        fixed(paste0("stored as ", selected()$variable, " in")),
        paste0("stored as <code>", selected()$variable, "</code> in")
      ) |>
      str_replace(
        fixed(archive),
        paste0("<a href=\"", archive_url, "\" target=\"_blank\">",
               archive, "</a>")
      )

    div(class = "help-block", HTML(linked))
  })

  output$distribution <- renderPlot({
    distribution_plot(distribution(), input$ci, input$group, input$palette)
  }, height = function() plot_height(distribution()))

  # The download is the chart plus the question and the caption, because a
  # chart that leaves the app without them cannot be read. On the page those
  # two are HTML around the plot; here they have to be drawn into it, wrapped
  # by ggtext to the width of the image.
  output$download <- downloadHandler(
    filename = function() {
      suffix <- if (input$group == "All") "" else paste0("_by_", input$group)
      paste0(selected()$variable, "_",
             str_extract(selected()$hazard, "(?<=\\()..(?=\\))"), suffix,
             ".pdf")
    },
    contentType = "application/pdf",
    content = function(file) {
      d <- distribution()
      plot <- distribution_plot(d, input$ci, input$group, input$palette) +
        labs(title = selected()$question, caption = caption_text()) +
        theme(
          # Without the plot margin the first line of a wrapped title is
          # clipped by the top edge of the image. Both blocks are positioned
          # against the image rather than the panel, so they start at the left
          # edge instead of indenting past the response labels.
          plot.margin = margin(14, 14, 10, 14),
          plot.title.position = "plot",
          plot.caption.position = "plot",
          plot.title = element_textbox_simple(
            size = 15, face = "bold", margin = margin(b = 14)
          ),
          plot.caption = element_textbox_simple(
            size = 10, colour = "grey30", margin = margin(t = 16)
          )
        )

      # ggtext wraps, so the line count is not known ahead of the draw. These
      # divisors are characters per line at 11 inches, measured off the two
      # longest questions in the sheet; the +80 is slack so a wrap that runs
      # one line longer than estimated is not clipped.
      title_height <- 26 * ceiling(nchar(selected()$question) / 90)
      caption_height <- 18 * ceiling(nchar(caption_text()) / 135)
      height <- plot_height(d) + title_height + caption_height + 80

      # encoding = "WinAnsi" is not optional. ggtext renders the title and
      # caption as markdown, and that turns every straight apostrophe into
      # U+2019, which the pdf device cannot write in its default encoding - it
      # substitutes a plain quote and warns once per line of text. WinAnsi
      # covers the typographic quotes and dashes markdown produces.
      # cairo_pdf would also handle it, but capabilities("cairo") reports TRUE
      # on machines where the device then fails to load, this one included, so
      # it is not something to depend on. Height is in pixels above, so /96
      # puts it in inches.
      ggsave(file, plot, width = 11, height = height / 96,
             device = "pdf", encoding = "WinAnsi", limitsize = FALSE)
    }
  )

  # Map -----------------------------------------------------------------------
  # The chosen measure copied into one column, because the fill and the tooltip
  # both reference it by name and mapgl reads the name out of the source.
  cwa_selected <- reactive({
    measure <- input$measure
    cwa_estimates |>
      mutate(
        value = .data[[measure]],
        # Built here rather than in the layer: mapgl takes a column name for the
        # tooltip, so anything shown on hover has to exist as a column first.
        tooltip = paste0("<strong>", CWA_NAME, " (", CWA, ")</strong><br>",
                         measure_label(measure), ": ", round(value, 2))
      )
  })

  # The ramp and the legend end labels, which the initial draw and the update
  # below both need and would otherwise write out twice.
  map_style <- reactive({
    d <- cwa_selected()
    colours <- map_colours(input$map_palette)
    list(
      data = d,
      colours = colours,
      fill = interpolate(column = "value",
                         values = map_breaks(d$value, length(colours)),
                         stops = colours),
      title = measure_label(input$measure),
      ends = c(sprintf("%.1f", min(d$value)), sprintf("%.1f", max(d$value)))
    )
  })

  # Drawn once. Everything reactive is read through isolate(), so changing the
  # measure or the palette does not rebuild the map - the observer below edits
  # the one that is already there. A rebuild would reset the camera, throwing
  # away a zoom into the Gulf coast on every change of measure.
  output$cwa_map <- renderMaplibre({
    style <- isolate(map_style())
    d <- style$data

    # bounds fits the view to the areas actually drawn, so the map opens on the
    # lower 48 rather than on the whole globe with the data in one corner.
    maplibre(style = blank_basemap, bounds = d) |>
      add_fill_layer(
        id = "cwa",
        source = d,
        fill_color = style$fill,
        # Fully opaque now there is nothing underneath to show through. At 0.75
        # every area was mixed with the white behind it, so the fills sat a
        # shade lighter than the same colours in the legend beside them.
        fill_opacity = 1,
        # A boundary line, or 116 areas of similar colour read as one blob.
        fill_outline_color = "#FFFFFF",
        tooltip = "tooltip",
        # Hover has to move opacity the other way now: raising it from 0.75 was
        # the old highlight and there is no headroom above 1.
        hover_options = list(fill_opacity = 0.7)
      ) |>
      add_continuous_legend(
        legend_title = style$title,
        values = style$ends,
        colors = style$colours,
        position = "bottom-left"
      )
  })

  # The update path. set_source carries the new value and tooltip columns, so
  # hovering reports the measure now on screen rather than the one drawn first;
  # set_paint_property restretches the ramp over the new measure's range. The
  # legend is cleared and redrawn rather than edited, because both its title and
  # its end labels change with the measure.
  #
  # ignoreInit because the map does not exist yet on the first flush - the
  # initial colours come from the render above, and this only ever edits.
  observeEvent(list(input$measure, input$map_palette), {
    style <- map_style()

    maplibre_proxy("cwa_map") |>
      set_source(layer_id = "cwa", source = style$data) |>
      set_paint_property(layer_id = "cwa", name = "fill-color",
                         value = style$fill) |>
      clear_legend() |>
      add_continuous_legend(
        legend_title = style$title,
        values = style$ends,
        colors = style$colours,
        position = "bottom-left"
      )
  }, ignoreInit = TRUE)

  # One block rather than two, because the order below is the point: what the
  # map is, then the questions behind it, then how to read the colours, then
  # where it all came from. Split across two outputs the ordering would live in
  # two places and drift.
  #
  # Prose for the same reason the chart caption is prose: someone looking at a
  # screen grab should learn what was asked, what the number is on, and that it
  # is modelled rather than measured.
  # Built once as parts, because both the page and the downloaded PDF need the
  # same words. Composed separately in two places they would drift, and the
  # download is exactly where nobody would notice.
  map_notes_parts <- reactive({
    d <- cwa_selected()
    items <- measure_questions |> filter(measure == input$measure)

    # One intro shared by every item is shown once as a stem. The four
    # comprehension scales draw their items from different question blocks, so
    # there is no one stem and each item carries its own.
    shared <- n_distinct(items$question_intro) == 1 &&
      !is.na(items$question_intro[1]) && nzchar(items$question_intro[1])

    question_text <- if (shared) {
      items$question_text
    } else {
      str_squish(paste(coalesce(items$question_intro, ""), items$question_text))
    }

    # The survey name rides here rather than in the title, which would otherwise
    # carry both a hazard and a survey name and read as a repetition.
    anchors <- scale_anchors(items$response_options[1])
    scored <- if (nrow(items) > 1) {
      paste0(
        "The ", count_word(nrow(items)), " answers, all from the ",
        str_remove(items$hazard[1], " \\(..\\)$"), " survey, are averaged ",
        "into one score", if (is.na(anchors)) "" else paste0(" from ", anchors),
        "."
      )
    } else {
      paste0("Answers run",
             if (is.na(anchors)) "" else paste0(" from ", anchors), ".")
    }

    # n_intros counts distinct wordings, not surveys - storm surge was asked in
    # four surveys with three intros between them - so the sentence says
    # wordings. Saying "three surveys" would be wrong.
    varies <- if (!is.na(items$n_intros[1]) && items$n_intros[1] > 1) {
      paste0(
        " The introduction was worded ", count_word(items$n_intros[1]),
        " slightly different ways across the surveys that asked it; the most",
        " widely used version is shown."
      )
    } else {
      ""
    }

    list(
      title = paste0(
        measure_label(input$measure), " across the ", nrow(d),
        " National Weather Service County Warning Areas of the contiguous ",
        "United States."
      ),
      stem = if (shared) items$question_intro[1] else NA_character_,
      question_text = question_text,
      reverse_coded = items$reverse_coded,
      reading = paste0(
        scored, varies, " Colors are stretched over ",
        sprintf("%.1f to %.1f", min(d$value), max(d$value)),
        " rather than the full 1 to 5, so areas are compared against each ",
        "other rather than against the ends of the scale."
      ),
      source = paste0(
        "From the Extreme Weather and Society Survey, run by ", institute,
        ". Estimates come from multilevel models fitted to survey responses ",
        "and reweighted to the adult population of each county, then combined ",
        "to the County Warning Area, so they describe the whole population ",
        "rather than only the people surveyed. The survey data behind them is ",
        "available at ", archive, "."
      )
    )
  })

  # Prose for the same reason the chart caption is prose: someone looking at a
  # screen grab should learn what was asked, what the number is on, and that it
  # is modelled rather than measured.
  output$map_notes <- renderUI({
    p <- map_notes_parts()

    linked <- htmltools::htmlEscape(p$source) |>
      str_replace(
        fixed(institute),
        paste0("<a href=\"", institute_url, "\" target=\"_blank\">",
               institute, "</a>")
      ) |>
      str_replace(
        fixed(archive),
        paste0("<a href=\"", archive_url, "\" target=\"_blank\">",
               archive, "</a>")
      )

    div(
      class = "help-block",
      tags$p(p$title),
      if (is.na(p$stem)) {
        # The heading still appears, or the block runs from the title straight
        # into a bare list with nothing introducing it.
        tags$p(tags$strong("Respondents were asked:"))
      } else {
        tags$p(tags$strong("Respondents were asked: "), tags$q(p$stem))
      },
      tags$ul(
        lapply(seq_along(p$question_text), function(i) {
          tags$li(
            p$question_text[i],
            if (isTRUE(p$reverse_coded[i])) tags$em(" (reverse coded)")
          )
        })
      ),
      tags$p(p$reading),
      tags$p(HTML(linked))
    )
  })

  # The map plus the words under it, because a map that leaves the app without
  # them cannot be read. On the page those are HTML around the widget; here they
  # are drawn into the image, wrapped by ggtext to its width.
  output$map_download <- downloadHandler(
    filename = function() paste0(str_to_lower(input$measure), "_cwa_map.pdf"),
    contentType = "application/pdf",
    content = function(file) {
      p <- map_notes_parts()
      style <- map_style()

      bullets <- paste0(
        "&bull; ", p$question_text,
        if_else(p$reverse_coded, " (reverse coded)", ""),
        collapse = "<br>"
      )

      stem <- if (is.na(p$stem)) {
        "Respondents were asked:"
      } else {
        paste0("Respondents were asked: &ldquo;", p$stem, "&rdquo;")
      }

      caption <- paste(stem, bullets, p$reading, p$source, sep = "<br>")

      plot <- map_plot(style$data, style$colours, p$title, caption)

      # Characters per line at 11 inches, matching the divisors the chart
      # download uses; the +80 is slack so a wrap running one line longer than
      # estimated is not clipped.
      title_height <- 26 * ceiling(nchar(p$title) / 90)
      caption_height <- 17 * textbox_lines(caption, 150)
      height <- 640 + title_height + caption_height + 80

      # encoding = "WinAnsi" as in the chart download: ggtext turns straight
      # quotes into typographic ones, which the pdf device cannot write in its
      # default encoding. Height is in pixels above, so /96 puts it in inches.
      ggsave(file, plot, width = 11, height = height / 96,
             device = "pdf", encoding = "WinAnsi", limitsize = FALSE)
    }
  )

  # Only survey and question are shown. The scale, the variable name, the
  # response options and the content keywords ride along hidden: DataTables
  # searches a column whether or not it is visible, so the search box finds a
  # question by its variable name, by an answer it offers, by its scale, or by
  # what it is about - "reception", "trust", "graphics" - without any of the
  # four taking up a column. The keywords are what make the last of those work:
  # nothing in the wording of "I receive all tornado warnings that are issued
  # for my area" contains the word reception. Hiding them by target index means
  # they must stay last in the select() below.
  # One column rather than two, to keep the table as narrow as it was. As a
  # factor the four combinations filter from a drop-down, which is the useful
  # move: "Standard" alone is the set that estimates the population.
  output$questions <- renderDT({
    datatable(
      questions |>
        mutate(kind = factor(case_when(
          experimental & graphic_shown ~ "Experiment, graphic",
          experimental                 ~ "Experiment",
          graphic_shown                ~ "Graphic",
          TRUE                         ~ "Standard"
        ), levels = c("Standard", "Graphic", "Experiment",
                      "Experiment, graphic"))) |>
        select(hazard, question, kind, response_scale, variable,
               response_options, keywords),
      filter = "top",
      selection = "single",
      rownames = FALSE,
      colnames = c("Survey" = "hazard", "Question Text" = "question",
                   "Type" = "kind"),
      options = list(
        pageLength = 10,
        columnDefs = list(list(visible = FALSE, targets = c(3, 4, 5, 6)))
      )
    )
  })
}

shinyApp(ui, server)
