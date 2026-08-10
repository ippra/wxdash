library(shiny)
library(tidyverse)
library(DT)
library(srvyr)
library(ggtext) # wraps title and caption to the image width on a download

# Both files come from 09_create_dashboard_data.R, which writes them into data/
# beside this file. Paths are relative on purpose: Shiny sets the working
# directory to the app directory both locally and on the server, and nothing
# here may reach outside that directory - 00_paths.R and WXDASH_LOCAL exist on
# a workstation, not on a deployment.
data_dir <- "data"
needed <- file.path(data_dir, c("09_dashboard_questions.csv",
                                "09_dashboard_responses.rds"))

# Failing here with the reason beats failing later with "object not found".
if (!all(file.exists(needed))) {
  stop("Missing app data: ",
       paste(basename(needed[!file.exists(needed)]), collapse = ", "),
       ". Run 09_create_dashboard_data.R before launching or deploying.")
}

questions <- read_csv(needed[1], show_col_types = FALSE)
responses <- read_rds(needed[2])

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

# Fixed height crushes the labels of the few questions with a dozen options
# into each other, so the panel grows with the bars instead.
plot_height <- function(d) {
  max(320, 55 * n_distinct(d$label), 22 * nrow(d) + 90)
}

ui <- fluidPage(
  titlePanel("Explore Survey Questions and Results"),
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
