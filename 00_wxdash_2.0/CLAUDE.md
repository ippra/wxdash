# wxdash 2.0

Orientation for `00_wxdash_2.0`: what the pipeline does, and the decisions in it
that are easy to undo by accident. Read this before touching anything here.

R in this repository follows the IPPRA house style: two-space indent, native
`|>`, 80 columns, guards before the step they protect, comments that give the
reason rather than the history. The full guide is `~/.claude/ippra-r-style.md`.

## The pipeline

Scripts run in number order; each output is named for the script that wrote it,
so provenance reads off the filename. All of them `source(here::here(
"00_wxdash_2.0", "00_paths.R"))`, which resolves `WXDASH_LOCAL` and
`WXSURVEYS_ROOT` from `~/.Renviron`. Every script that reads those paths calls
`require_roots()` first. The check is a function rather than a check at source
time because `09`'s assembly half needs neither root: it reads data committed
in the repo and writes beside it.

| script | what it produces |
|---|---|
| `01` | county-to-CWA crosswalk |
| `02`, `03` | CWA and county alert counts from NWS archives |
| `04` | poststratification cells and county covariates |
| `05` | `05_survey_responses.csv`, 22 waves, ~400 MB; `05_scale_items.csv` |
| `06` | multilevel models; fixed effects are the five poststrat cells |
| `07` | CWA and county estimates, as CSV and as simplified `sf` for mapping |
| `08` | `variable_reference.csv`, the codebook, read off instruments |
| `09_dashboard/` | the dashboard: every statistic, and the site that shows it |

Adding a survey wave is one line of code: the `waves` vector at the top of
`05`. Everything else is data (a new instrument in `08`, a new `_all` alert
year in `downloads/`), then rerun `02` and `03` (only if the alert year is
new), `05`, `06`, `07`, and `09 --data`. Two rough edges on that path: `07`
names `04_county_poststrat_2024.csv` explicitly, so a new poststrat vintage
means editing `07`; and `06` expects a human to read 24 model summaries, which
is deliberate and means the chain is not push-button.

`WXDASH_LOCAL` points inside Dropbox, and **`outputs/` is marked
Dropbox-ignored** (`xattr -w com.dropbox.ignored 1` on that directory).
Without it a sync races a rebuild: Dropbox restores the previous `engine.js`
under its own name and files the new one as a conflicted copy, publishing
stale JavaScript beside fresh data, a site that loads, draws, and is wrong.
The attribute is per machine and does not travel with the repo, so set it on
any machine that runs `09`. Everything under `outputs/` is regenerable from
`01`-`09`, which is also why it stays out of git; the one exception is
`09_dashboard/data/`, which is committed (see The production site). The
builder compares every copied site file byte for byte with `site/` and stops
on any conflicted copy in the built site, but nothing can catch Dropbox
reverting a build after it finishes.

The five poststratification cells, `AGE_GROUP`, `GENDER_GROUP`, `RACE_GROUP`,
`EDUC_GROUP`, `INCOME_GROUP`, are built in `04` and fit in `06`. Anything that
splits the data should use those, so the app cuts it the way the models do.

`05` also writes `05_scale_items.csv`: which survey items go into each of the
twelve reception, comprehension and response scales, and which are reverse
coded. The item lists in `05` are the only definition of those scales; `09`
reads this file to show the questions behind a scale rather than keeping a
second copy that would drift.

## Alert categories

`02` and `03` bucket VTEC phenomena into hazard categories. Two splits are
deliberate and easy to undo by accident:

- `FREEZE` is separate from `COLD`. Frost and freeze products are issued for
  agriculture in CA, OR and FL, not for cold places: the two correlate -0.21
  across CWAs, and merging them halves every winter risk correlation.
- `SURG` is separate from `HURR`, so `risk_surge` has an exposure measure of
  its own. `HURR` predicts the item slightly better (.23 against .21) but is
  dominated by tropical wind products; the split is for measurement validity,
  not fit, and leaving `SS` out of `HURR` costs the hurricane models nothing.
  `SS` exists from 2017, so `SURG` spans 2017-2025, nine of the sixteen
  archive years; every other category spans 2010-2025.

`07` carries the nine alert counts the models fit onto the CWA map file under an
`ALERT_` prefix, so exposure can be read beside the estimate it helps explain.
They are total days over each category's years, the numbers the models are
scaled against. The map shows them as days per year instead: `09_statistics.R`
divides each by its category's years from `02_alert_years.csv` (16 for most,
9 for storm surge, which was first issued in 2017) as it writes the map file,
which puts surge on the same footing as the rest and leaves every model and
estimate as it was, since `06` standardizes each count. Every archive year is
complete, 1 January to 31 December. They are days, not a 1-5 scale, and the
front end branches on that.

## The variable reference

`08_create_variable_reference/variable_reference.csv` is one row per survey
hazard per variable, carrying each question as it was actually asked. It covers
all 22 instruments. Two companions matter as much as the sheet:

- `NOTES.md`: what still needs a second pair of eyes, grouped by what to do
  about it. Instrument errors are recorded there and in the `notes` column,
  never corrected in the sheet: the sheet records what the documents say.
- `.claude/skills/survey-variable-reference/`: the procedure. Adding an
  instrument means following it, not improvising. Read the instruments end to
  end; do not write a parser for what the text *means*. Extraction is scripted,
  judgment is not.

Its judgment columns are independent and easy to confuse:

- `experimental`: what the respondent read varied. Order-only randomization
  (`RANDOM ORDER`) is **not** experimental; that would sweep in the core trend
  batteries.
- `graphic_shown`: a graphic was displayed and the answer rests on it. Not
  the same as a question *about* graphics: rating your understanding of maps
  shows nothing.
- `question_focus`: `weather` or `background`; `09` drops background items.
- `topics`: what the question is about, from the fixed list of ten in
  `topics.csv` beside the sheet, whose deciding rules settle the boundaries.
  Usually one; a second after `" | "` only where a question plainly spans
  two. Read off the wording like the others, never inferred by rule, and read
  four times: a first reading and three independent checkers, with every row
  they do not all agree on decided by Joe (the skill's procedure). `09` checks
  two constraints and stops on either: `Background` goes with
  `question_focus = background` and nowhere else; and an item in a mapped
  measure is filed under the topic `topics.csv` names as that measure's
  `measure_construct` (reception under Getting weather information,
  comprehension under Understanding weather and warnings, response under
  Protective actions, `risk_*` under Risk perceptions), even where its wording
  alone would read otherwise (`rec_area`).

Watch one trap: the option separator is `" | "`, so a pipe inside an option
label makes `response_options` unsplittable.

The `.docx` instruments are committed beside the sheet, so a clone has the
sources as well as the record read off them. They are binaries that stay in
history once added; replace one only when its content changes.

## The statistics

`09_dashboard/09_statistics.R` computes every number the dashboard shows, and
nothing else does. It is sourced by `09_build_dashboard.R` under `--data`, not
run on its own, and it writes `09_dashboard/data/`: `questions.json` and the
915 question files under `q/`, the R that rebuilds each of their charts under
`rcode/`, `measures.json`, `cwa.geojson` and `respondents.json`.

**The two halves of `09` are split on cost, not on subject.** This one reads a
400 MB file and makes about 24,000 `srvyr` calls, and takes roughly fifteen
minutes; assembly reads what it wrote and takes seconds. Front-end work is the
common case, so `09_dashboard/data/` is the boundary between them and the
default run does not touch it. Run `--data` when the survey data, the models or
the measure menu change; without it for anything else. Assembly refuses to
start if the data files are not there.

Percentages are weighted with `srvyr` on `PERSON_WEIGHT`, which comes from
`rake()` against six ACS margins in the `wxsurveys` repo. Only
`survey_prop(proportion = TRUE)` is computed, and it serves both the chart with
confidence intervals and the one without. `proportion = FALSE` gives the same
point estimates (at most 2.9e-09 apart across 3,109 cells) and only avoids the
logit warning on a cell at 0 or 100%, and computing both would roughly
quadruple the build.

The design is weights only (`ids = 1`, no strata or clusters), so the 95%
intervals are logit intervals for a weighted proportion treating respondents
as independent draws; the caption says so while they are drawn, and that they
leave out the other errors of a nonprobability sample, and the screen-reader
table then carries each bound. Each wave's weights average exactly one, so a
pooled estimate counts every year in proportion to its respondents (the
2018-2020 severe weather waves, near 3,000 each, count about twice the later
ones); a caption over several years says the years are pooled and describe
that span together, not the latest year, the quiz's included.

Each question file's `summaries` carry, per split, the respondent count `n`,
the `years` as runs ("2018-2021, 2024"), the `smallest` group with its
`smallest_n`, and `group_n`, every group's own count. A figure drawn from one
group, such as a single survey year, states that group's count rather than the
pooled one. A count over one survey year is labelled U.S. adults and a count
over several is labelled responses, since each year is its own sample and a
total across them is not a count of distinct people; `counted_as()` in the
builder and `countedAs()` on the page make that choice the same way.

**Every chart carries the R that rebuilds it.** `09_rcode.R` holds the
generator, and the question loop runs it: one concrete script per (question,
split), written into `data/rcode/<id>.json` and fetched by the front end on
the first click. The code that computed the numbers writes the code that
reproduces them, so the two cannot drift.

The scripts read the released wave files (`WX18_data_wtd.csv` and the rest of
the 22) rather than `05`'s pooled output, which is 400 MB and which nothing
releases. Three rules the generated code follows, and they are the point of it:
no helper functions, column names written where they are used rather than
through `.data[[ ]]`, and only the columns that chart needs. That is why there
is a script per split instead of one template: splitting by age should not make
a reader read a roster of twelve grouping columns, and the five derived splits
each write their own `case_when` out where a reader can see it.

**It then runs them and compares.** `verify_r_code()` evaluates a script
against the same wave files a reader would download and checks its estimates
against the rows being written to the question file, matching on *labels*, so
a levels/labels pairing that has drifted cannot slip through. Coverage is every
hazard by every split, so each derived `case_when` is exercised in all four
hazards, plus one Everyone script per response scale, plus every version of
every split-sample question. Running all of them would add hours for no more
coverage than that.

Two things the generated code makes visible that the pipeline only describes:
the WX17 reception and response batteries are dropped because WX17 asked them
on a 1-7 scale, and weather salience needs both items rather than one.

**A question is a stem and an item, and they are set differently.** `08`
records `question_intro` and `question_text` apart, and both are carried
through beside the joined `question`. The front end sets the stem quiet, small
and unbolded above the item, which carries the weight: over the chart, in each
row of the question browser and in the search suggestions. The stem is the
same sentence on every item of a battery and the item is what changes, so
without it a row of the risk battery reads "Tornadoes", which is not a
question. Where a question has no item of its own (148 of the 915), the stem
*is* the question, so it moves into `question_text` and nothing is left above
it.

`question` stays the one string anything needing a whole question uses: the
download title, the browser's search, and the title of the R script that
rebuilds the chart.

**A split-sample question is estimated one version at a time.** Some questions
were asked of everyone but not in the same words: the wording varied by a
randomization variable the instrument records beside the answer. Those carry a
version menu under the heading, and the chart always shows one version. There
is no pooled option, because pooling averages across the difference the
experiment was testing and reports a number nobody was asked. `?arm=`
deep-links one.

Two declarations in `09_dashboard/`, because they answer different questions
and grow at different rates. `question_arms.csv` says which randomizer governs
a question; the variable reference marks the randomizers themselves
(`question_type == "randomization"`, 73 variables) but records nowhere which
question each governs, so this is read off the instruments and grows a row at a
time. `arms.csv` is the roster: one prompt per randomizer and a label and order
per value, because the raw values are codes as often as words
(`spc_high_ero_slight`, `1`). The build stops if a randomizer carries two
prompts, is paired but not rostered, is not a column in the data, or takes a
value the roster does not list.

The shape follows: an armed question nests `splits` and `summaries` one level
deeper, under the version, and carries `arms` and `arm_prompt`. **Presence of
`arms` is the signal**, so it has to be absent everywhere else: `list(arms =
NULL)` serialises as `"arms":{}`, which would put an empty key on every
question and read as armed to anything checking truthiness. `questionSlice()`
in `engine.js` is the one place that knows about the nesting; every component
that charts a question goes through it. The quiz reads an armed question only
at a version it names: an answer drawn from one arm is a claim about the
people who saw that version, so the prompt has to quote that version's
wording. Q6 does this with the amount-format items, quoting and scoring the
12-inch version and linking the explorer to it with `arm`.

**The pairing is verified, not asserted.** `08`'s `experimental_review.csv`
carries a `depends_on` column naming what varied; that supplies the candidates,
and each is then checked against the survey data: the randomizer and the
question co-occur in a wave, and at least two versions were answered; a
question whose respondents saw one version is charted as an ordinary question.
165 questions across 36 randomizers are armed. Where a randomizer's values are
bare codes, the labels come from reading the instrument with the skill's
extraction script, not from the code: `rand_wind` 1-4 are how the chance was
worded, and `rand_ai_2` reverses `rand_ai_1`'s ordering, which copying the one
to the other would get backwards.

**Randomization columns are read as text, never guessed.** `rand_aft` holds
`10:00` in the wave file; `05` reads that with type guessing, parses it as a
time, and writes it back as `10:00:00`; guessing again turns it into an `hms`
whose distinct values are seconds since midnight, and a version menu built on
that is labelled `36000`. Forcing those columns to `col_character()` in the
read prevents it, at no cost for the columns that are already text.

The two files therefore spell the same version differently (`10:00:00` pooled
against `10:00` in the wave), which matters because the split reads one and
the generated script reads the other. `arms.csv` carries a `script_value` for
exactly that case, empty everywhere the two agree. Nothing checks it directly:
the generated script is run against the wave file and compared with the chart
it claims to rebuild, so a wrong spelling shows up as a script matching no rows
rather than as a quiet mislabel.

**Wording never shows a variable name.** The instruments write what varied as
a placeholder (`[lead_time: 15 | 30 | 60]`, `[fcst_conf]`), and
`readableWording()` in `engine.js` replaces each one wherever a question's
wording is shown, and in its response labels, which `fetchQuestion()` puts
into words as it loads a question file (the format experiments carry the
randomized amount in the options: "[4 or 12] inches"). The menu's own variable becomes the version on screen, in
bold, from the first of: the roster's `wording` column; the survey value,
where it is the text respondents read (`flooding event`); the label.
`wording` exists for randomizers whose value is a code (`fcst_conf` is `high`
and the respondent read a sentence) or whose label would not fit the sentence
("15 minutes" in "the next [lead_time] minutes"). Once any row of a
randomizer has it, every row is read from it and an empty one means the
version added nothing, so fill the whole randomizer or none of it. Where no version is
chosen (the question browser, search, saved questions) the menu's own slot
names its versions instead, from `arm_versions` in `config.json`: a run of
times or numbers as its two ends ("[1:00 AM to 9:00 AM]"), a few short values
as a list, longer ones as a count, so the morning, afternoon and evening
variants of one item read differently in a list. Every other
placeholder is put into words: a listed set as "[15, 30, or 60]", a range as
"[5 to 100]", a named one from `placeholders` in the builder's config
("[the respondent's state]"). The names move to the note under the chart,
"Randomization:" for the menu's variable and "Wording varies with:" for the
rest, so a reader who wants the column has it. The same rule in R is
`readable_wording()` in `09_dashboard/09_wording.R`, which both halves source:
the builder sends its `placeholder_words` to the page, and the statistics use
it for the comment and plot title of each generated script, so a script names
the version it rebuilds in the words the page shows.

Where a version changed what came *before* the question rather than the
question itself (`tor_em_rare` decided whether a definition of a tornado
emergency came first), the roster's `shown_before` column carries that text,
and the page sets it above the stem under "Shown on the screen before this
question:" while that version is selected. Without it the menu would change
the chart and nothing a reader can see.

`exp2_chal` and `exp2_use` in the winter survey are two experiments under one
name: WW21 asked them after Tuesday's forecast in its revision scenario, WW22
after its uncertainty scenario. They share one menu on `exp2_cond_rand`, whose
WW21 values are codes 1-6 and WW22 values sentences, and the WW21 versions are
labelled and worded as 2021 so the WW22 stem above them is not read as theirs.

Not every experiment fits this. Where the randomizer decided *which column* a
respondent answered (`rand_evnt_cncrn_ice` against `_snow`,
`exf_exp_d3/d5/d7`), the arms are separate variables, and they stay separate
questions in the browser. A menu cannot split what was never one column.

**Questions are hidden from a list, not from the code.**
`09_dashboard/hidden_questions.csv` carries one row per flagged question
(`id`, `disposition`, `note`, `question`), and it is the record of what was
taken off Explore Survey Questions and why. There are two dispositions:
`hide` takes a question off the list, and `needs-context` only records it.
Assembly does the filtering, not the data half: every question keeps its data
and script files in `09_dashboard/data/`, so a change to the list takes effect
in a normal build with no `--data` run, and a question can come back without
one. Each build reports how many questions are hidden. A stale id, an unknown
disposition or a duplicate row stops the build: an entry that matches no
question looks like the question is hidden while the question is on the
page. So does a hidden question that a quiz part links to: the
explorer opens only listed questions and falls back to the first one, so the
link would open the wrong chart (`WW_range10_nozero` stays listed for this
reason).

The list is filled in the browser. `?flag=1` puts a flag beside the question
heading and a panel at the foot of the explorer that exports exactly those four
columns, so the judgement is made where the problem is visible rather than
against a roster of variable names. It is gated on the parameter because it is
scaffolding, not a reader feature, and it keeps its list in `localStorage`
because the site is plain files with nothing to POST to. That makes the list
per-browser and per-origin, so flags made against a local preview do not follow
you to the deployed site. Export before switching.

**The measure menu is declared once**, in `09_dashboard/measures.csv`: one row
per mapped measure (33: twelve warning scales, twelve risk perceptions, nine
alert counts), giving its order, its group and its label. It is validated
against what `07` produces in both directions, plus duplicates, so adding a
measure is a row in that CSV, and a measure that no longer exists upstream
stops the build rather than vanishing from a menu.

**Splits are declared twice**, both in R: the `groups` and `group_phrases`
vectors in `09_statistics.R`, which computes them, and the same two in
`09_build_dashboard.R`, which writes them into `config.json` as `groupings`
for the front end to read. Thirteen splits (Everyone plus twelve) with a
caption phrase each, and nothing catches a missed edit, though the five
derived ones (`RURAL_GROUP`, `TENURE_GROUP`, `HOME_GROUP`, `CHILDREN_GROUP`,
`SALIENCE_GROUP`) are also written out as generated R where `verify_r_code()`
would fail on a drift. `CENSUS_REGION` is offered as description of who
answered; no model in `06` fits it.

## The production site

`09_dashboard/` is the deployed dashboard, built on top of `01`-`08`. It has its
own `README.md`, which is the fuller account; what matters from here is the
property the arrangement buys. **Assembly computes no statistics**: every
percentage, interval and estimate is read from `09_dashboard/data/` verbatim, so
the site cannot disagree with what was computed. What assembly adds is
presentation: `config.json`, place ranks, percentiles and medians derived from
the map values, simplified geometry, and the quiz's answer keys read off the
distributions. A calculation moved into the assembly half gives the property up,
and a verification harness would have to replace it.

**`09_dashboard/data/` is committed**, and is the only large thing in the repo
(about 70 MB on disk). It is versioned so that a clone builds and deploys the
site with no pipeline outputs, no survey waves and no `~/.Renviron`: the whole
front-end and hosting side of the work needs nothing but the repo. The cost is
real: the write loop rewrites all 915 question files and all 915 script files
on every `--data` run, so each run adds its own copy to history, and it cannot
be taken back out without a rewrite. Weigh that before adding anything else
large. The built site stays out of git.

`site/` is the hand-edited front end: `engine.js`, `engine.css`, `index.html`,
Leaflet, Chart.js (with its datalabels plugin) and jsPDF vendored under
`assets/vendor/`, and the state outlines under `assets/geo/`. The builder
rebuilds its output from scratch, copies `site/`, fills the `__BUILD__`
cache-busting stamp in `index.html`, drops anything hidden (`.DS_Store`), and
refuses to publish a built site containing `.R` files, missing a required file,
or with fewer R-code files than questions (a Download R code link that 404s
looks to the page exactly like a network failure). It writes
`outputs/09_site/` under `WXDASH_LOCAL`, or `09_dashboard/_site/` on a machine
without one; either is the rsync unit. A run takes seconds. It is deployed twice:
GitHub Actions (`.github/workflows/deploy-beta.yml`) builds it on every push
to master with `WXDASH_CHANNEL=beta` and publishes it to GitHub Pages as the
beta, which carries a Beta label, a `noindex` tag and a disallow-all
`robots.txt`; production at ippra.net/wxdash is a build of a release tag,
with the variable unset, copied to our own server. The workflow runs only the
assembly half, so a `--data` run reaches the beta by being committed.

### Look and chrome

The site shares its front end with the fusion dashboard (`fusion_dash`), so a
change to the shared chrome is worth carrying to the other. Four pieces are
common to both: the black IPPRA bar above the masthead, static markup in
`index.html` that becomes a back link when the reader arrived from ippra.net; a
title over every page but home, from `pageHead()` and each page's `title`; a
landing page that says what the project is and why it matters rather than
showing a result; and an About page in eyebrow-headed sections. The masthead
carries `nav_subtitle`, which names the project. Pages route on the hash:
`#home`, `#survey`, `#map`, `#quiz`, `#about`.

The default theme is `wxdash`, purple chrome with `--accent: #443A83`. An
"Adjust colors" menu offers two more, Ops (dark) and Greyscale (high
contrast); `?theme=` deep-links one and the pick is kept in
`sessionStorage`. Themes restyle chrome; chart colors are a separate choice,
the color scheme under Chart options: Blue (one hue) by default, Viridis, and
Grey (print safe), shared across pages through `?scheme=` so the quiz charts
in whatever scheme the reader picked on the survey page.

### Home and About

The landing page runs title, introduction, the data gap as a two-line
statement, what the project is, four figures, two paired sections on why it
matters, then three cards into the data. All of its words are in the builder's
`hero`, `sections` and `explore`, and none uses an em dash. The four figures
(responses, years, hazards, surveys) and the dot field beside the statement
are counted, never typed, all from `respondents.json`, which `09_statistics.R`
writes with each survey's respondent count (a survey being one hazard in one
year). The field draws one column per year, each holding every respondent to
date at one dot per 50, stacked oldest year at the bottom and colored by hazard
in the order the hazards joined; the column's own year is full strength, the
years beneath it faded. The build stops if the per-survey counts do not add up
to the total.

The About page (`about_html`, rendered by `components.static_page`) opens with
a lede and a paragraph on why the project exists, then sections under `<h3>`
eyebrows: The survey; Interpreting survey results; Community estimates;
Alert history; Using this site (a link card for each of the three working
pages); Data and reproducibility; Methods; Publications using the Extreme
Weather and Society Survey; Support; Contact. Figures in it (the alert spans,
the number of areas) are read from the data. Publications are declared with
`pub(year, title, authors, journal, detail, doi)`, listed newest first and
grouped by year, each title linked to `https://doi.org/<doi>` and followed by
"Authors (Year). *Journal*, detail."; the build stops if the list is out of
order. Methods cites two of them in the same format, picked by DOI:
`10.1175/WCAS-D-19-0015.1` (2019) and `10.1175/BAMS-D-19-0064.1` (2020). The
three page descriptions shared by the landing cards, the About links and the
menu are written once, in `blurbs`.

### Explore Survey Questions (`components.explore`)

The page opens with a search over the full wording of every question, stem and
item together (`questionSearch()`): every word typed must appear, matches in
the item itself rank first, and a pick loads the question exactly as a click in
the browser does and pages the browser to it.

The browser at the foot of the page (`questionBrowser()`) filters by survey,
topic and question type, searches within what they leave, and lists ten
questions a page as rows, not a spreadsheet. Each question carries `topic`, the
one its row is labelled with, and `topics`, every topic it was given, which the
Topic menu matches; both come from the sheet's `topics` column by way of
`09_statistics.R`. The menu is disabled when the question data carries no
topics, rather than guessing them from the wording. Question type is `kind`:
Standard, Experiment, Graphic, or Experiment, graphic.

Readers can keep a list of questions, and the page does not push it. "Save
question" is a link beside Download R code at the foot of the chart, and
"Saved questions (n)" under the search box jumps to the list once it has
anything in it; the "Saved questions"
panel at the foot of the page appears only once something is saved, opens a
question on a click, and downloads the list as CSV (survey, years, question,
variable), which is how a list is kept: it lives in `localStorage` under
`wxdash-saved`, per browser, and the panel says so. A saved question that is
later hidden stays in the list, greyed, and no longer opens. It is separate
from the `?flag=1` triage list, so saving a question to read later never
feeds `hidden_questions.csv`.

The comparison ("Compare responses by") stands alone as the control that
matters; the color scheme and the 95% confidence intervals sit behind "Chart
options", open from the start only when a link has already set one of them.
`?grouping=` and `?ci=1` deep-link those.

Chart.js keys a bar by its category label, so two responses whose labels read
the same once cut to three lines would share one bar, and one of them would
vanish without an error. The format experiments are built that way (options
that differ only in their last sentence, or in a number past the cut), so
`tickLabeller()` wraps any label that would collide in full rather than
cutting it, and category ticks never auto-skip.

### Downloads

**Charts and maps download as one picture in two formats**, PNG and PDF, drawn
once by `figureImage()` so both pages export in the same frame: a small label,
a stem, the title, the figure, the page's own caption lines read off the DOM,
and a source line, on the theme's own background. It is laid out at 1200px and
drawn at four times the density, 4800px across, which holds up full-width on a
slide; the PDF is that image on a page 11 inches (792pt) wide cut to its
height. The chart is redrawn off screen by Chart.js with slide-sized type. The
map cannot be: Leaflet paints at screen resolution, so `vectorMap()` redraws
every path from the positions and styles Leaflet has already worked out, which
keeps the outlines sharp at any size and shows the same frame, colors and
selection as the screen. The overview sheet is the third figure: its key,
column heads and rows are redrawn in the same frame with the page's own marks.
Every figure puts its links at its foot, and all three share the first source
sentence (`FIGURE_SOURCE`) and a bold facts line of the same form, count first.

**Download R code** sits beside the two chart downloads on Explore Survey
Questions, as quiet links at the foot of the chart under its caption: the
caption says who answered and where the data come from, and the script is part
of that account. They are downloads, not view settings, so they stay out of
Chart options, and a download rather than a panel, because someone who wants
the script wants it in their editor, not in a scrolling box. The link is hidden
until a question is chosen.

### Explore Communities (`components.wx_map_explorer`)

The comparison pairings in the builder's `compare_pairing` are transcribed from
`06_fit_models.R`; the build stops on a mapped measure with no pairing or a
pairing to an alert layer the menu does not offer. Choosing an alert history
draws it as a second map beside the measure its model was fitted on, so both
quantities are on screen at once and the reader compares two pictures rather
than holding one in memory. Both maps are the same size, the second takes a
contrasting ramp, hovering either outlines the area on both, either tooltip
carries both numbers, and each measure keeps its own note in the card below.
Drought, hail and lightning are fitted on FEMA NRI frequencies rather than an
NWS product, so they have no pairing and the page says so. `?measure=`,
`?compare=` and `?place=` deep-link the page.

The estimates are point estimates with no uncertainty: `07` predicts from the
`06` fits for an average year (the year effect dropped) and keeps no standard
errors. The page says so rather than suggesting separation it cannot show.
The popup calls the value a modeled estimate and its rank and percentile a
ranking of estimates, where close ones may not differ; the estimate note says
the same, that each estimate pools every year that asked the question, and
that every area has an estimate for every hazard, which where the hazard is
rare describes how adults answer, not local experience. The legend names the
scale and that its colors span the observed range, and an alert legend its
counting period ("Alert days per year, 2010-2025"). The alert note says a partial
alert counts, so not every resident was under it, and that because the models
use these counts as predictors, an estimate map that resembles the alert map
partly reflects the model.

The map surface carries no color of its own: the choropleth sits directly on
the card. Two things follow from that and are easy to undo by accident. Polygon
borders are a theme token (`--map-hairline`), because white borders against a
white card lose the shape of the palest areas along with their fill. And the
hover and selection outline is chosen against the fill's luma (`inkOn()`),
because any single color fails at one end of a ramp: a grey outline is
invisible on the dark end of the greys the comparison map draws in.

The CWA overview sheet is the last panel on the page, below the map and the
notes that explain it: pick an area and every measure is drawn as a row
stretched to its own range across the areas, with PNG and PDF downloads at its
foot. The numbers are the ones already in `cwa_values.json`, so the sheet
cannot disagree with the popup above it. What the builder authors is the
caution that makes the rows readable (compare a community's position within a
row, not across rows), with the count of other offices read off the data. The
sheet and its prose share one width (`--scan-width`), and the strips are drawn
at the width the column actually got, measured after layout.

Picking an area is undone from either end: `Clear` in the sheet's header or
`Clear selection` in the map card's corner, shown only while an area is
selected. Clearing re-frames both maps, because a popup auto-pans to stay in
view, which shifts a frame that is otherwise fixed, and nothing else puts it
back.

### Shared skeleton

The explore pages and the quiz share one skeleton, so moving between them
feels like one site: the page's title and introduction; a small label over a
large heading naming what is shown (the survey and question, or "Community
estimates" and the measure; the quiz sets its prompt as that heading); the
controls on the page, not in a card, with at most one "options" toggle (Chart
options, Map options); the figure as the one card, with its downloads, or the
quiz's way into the explorer, at its foot; then the page's notes and its
browser or overview sheet. The downloads carry the same label and title the
page shows. Change one page's skeleton and the others should follow.

### Page state

What a reader has chosen lives in the query string, so a reload or a copied
address shows the same view: the question, its version (`arm`), the
comparison (`grouping`, absent for Everyone), the color scheme and the map's
measure, comparison and area. Changing the question clears `arm`. A reader's
own choice is a step in the browser's history (`setParams(..., true)`), so
Back undoes it; a Back or Forward that changes only the query redraws the page
from the address it then shows, so the selection, the chart and the URL
agree. A link from
one page to another is built by `pageLink()`, which carries the theme and
scheme and nothing else and puts the full address in the `href`, so it works
opened in a new tab or copied as well as clicked. Changing the theme does not
rebuild the page: a page that can repaint itself sets `pageRestyle` (the
explorer redraws its chart, the quiz its current prompt, the map its layers),
which keeps browse filters, search text, a quiz in progress and a chosen area.
Jump targets carry `scroll-margin-top` to clear the sticky menu bar.

### Accessibility

The site is held to Section 508 and WCAG 2.0 AA, and four things are easy to
undo. Every bar chart is a canvas, so `groupedBarChart()` gives it a spoken
label naming what it answers (`altTitle`) and `chartAlt()` puts a table of the
same numbers beside it, hidden on screen with class `wx-sr-only`; the map
carries the same, a table of every office's value, rebuilt with each measure.
Everything the map does by clicking can be done from the "Forecast office"
select beside it, which follows the map both ways. Small print uses the muted
text color (`--text-muted`), never `opacity`, which takes it below AA contrast.
And lists are list markup: the question browser's rows are `<li>` items with a
button inside, not buttons standing in for list items. Run axe-core (WCAG 2
A/AA and Section 508 rules) on every page after front-end changes.

## The quiz

Test Your Knowledge (`components.wx_quiz`) is the one place the builder
authors claims about the data. Prompts are fixed; answers, reveal numbers and
chart values are read off the question files at build time; and guards halt
the build when the data stops supporting a sentence, naming the sentence to
re-word. It is all in the builder's `# Quiz` section, which produces the
`questions` of the quiz page in `config.json`.

### Running order

Thirteen questions, 26 prompts, every one scored. They run in the order a
warning travels, declared once in `running_order`, which places each question
by the survey item its explorer link names (or its `id`, for the community
question) and stops the build if a question is missing or named twice. The
section, written into each question as `theme`, is:

| theme | questions (by item) |
|---|---|
| Receiving | `WX_wx_info7` (sources), `WX_rec_all` (reception) |
| Understanding | `WX_alert_und`, `WX_warn_time`, `FL_flood_warn`, |
| | `WW_amount_format`, `TC_wep_rec` |
| Trust | `WX_nws_trust` |
| Warning Decisions | `WX_mi_fa_should` |
| Risk | `WX_risk_heat` (top risk by region), `community_risk` |
| Responding | `TC_resp_always`, `WX_last_act` |

### Reading the data, and the guards

- `share_of()` and `mean_of()` read a question's rows at full precision.
  Shares are never rounded before a guard, because rounding first moves a
  group up to a point, which is enough to walk an answer past a margin it does
  not clear. `shown_pct()` and `shown_mean()` round only for prose and chart
  labels, to what the explorer shows.
- `split_rows()` reads a split-sample question only at the version passed as
  `arm` (as does `share_of()`), and stops without one.
- `pct_band()` picks the offered band ("About 60%") nearest a share, and stops
  unless the share is within half the narrowest gap between bands.
- `decisive()` is for a single winner among unordered choices: it has to clear
  the runner-up by 3 points, more than the intervals the explorer draws on the
  same numbers (about 1.6 points on a share); `margin = 0.2` on a 1-5 mean.
- `gradient()` is for an ordered split, where the answer claims a direction
  (understanding rises with age) rather than a winner: the run has to go one
  way end to end with no tie at the top, and adjacent groups may sit close.
- `lean_answer()` decides "most lean one way / the other / evenly divided": a
  side is "most" when it is 5 or more points past half, and a share within 1.5
  points of that line stops the build. The lead-time follow-up offers only the
  two sides and needs a side at least 2 points past half.
- Region series: hazards within `close_margin` (5 points) of a region's top
  all count as right; the build stops if a hazard sits within a point of that
  cut, or if a hazard the options leave out comes within 5 points of the top.
- `check_prose()` guards every fixed sentence that states a fact (a miss
  heading's "about half", codes still meaning what the prompt assumes, the
  range formats still carrying 80/50/30%, every format example still at 55%
  or more for a range, and so on). `asked_of()` stops if compared questions no
  longer share one stem; `compare_caption()` if they no longer share one
  survey and span of years.
- The latest survey year is read from the data (`group_n` of the
  `survey_year` summary), so year-specific questions move with each new wave,
  and a figure from one year states that year's count.
- A question about change over time is built only from items every respondent
  was asked every year. The reliance battery qualifies; its "rely on most" item
  (`wx_info_tie`) does not, because some waves put it only to respondents who
  tied their ratings.

### Question and part fields

A question is `part1`, an optional `part2` (a follow-up), and any further parts
in `more`; plus `explore` (`href`, `label`, `params` with `q` and `grouping`),
the explorer link the reveal and the score page use; `id`, only where there is
no explore item to name it; and `theme`, added by the running order.

A part carries:

- `prompt`, `options`, `answer` (0-based), and optionally `accept`, a list of
  every option that counts as right where the data cannot rank them.
- `setup`: a quiet line above the prompt. `quote`: text respondents read, set
  as a blockquote, read from the question file. `quotes`: several of those,
  each `{label, text}`, shown as "A:", "B:".
- `reveal`: the sentence of numbers after answering. `result` and `miss`:
  the verdict on a wrong answer is `miss` if given, else "The survey result is
  `result`"; a right answer reads "You got it."
- `highlight`: `resp` (the response codes the answer adds up), `group`, or
  `category` (the winning bar on a comparison chart), from the same values the
  guards check, so the reveal chart lights exactly the bars the answer is made
  of and fades the rest.
- `chart_note`: the part's own words for what the highlight marks, appended to
  the caption in place of the generated "Highlighted:" line.
- `chart` (`rows`, `y_label`) with `asked` (`stem`, `items`, or a `table` of
  `lead`, `head`, `rows`) and `caption` (`meta`, `bars`): builder-made bars,
  used where a prompt compares several survey variables, and for every
  follow-up by group (`split_chart()`), which draws one bar per group, the very
  share or mean the answer compares, rather than the full distribution.
  `cmp_chart()` orders bars highest first except on an ordered split.
- `grouping`: the split a builder-made chart's explorer link opens at.
- `explore`: a part-level link, for a part that charts a different item from
  its question (the winter follow-up, the flash flood half); the reveal then
  charts and links to that item.
- `tag` and `lead`, on series parts: `tag` names the part in the progress bar
  ("Midwest"), `lead` labels the button that reaches it ("Next Region →"). The
  top-risk question is a series: the same six hazards for each census region.

Without `chart`, the reveal fetches the item's question file and charts it at
`All` for the first part and at the question's `grouping` for a follow-up,
with the explorer's own caption templates, and the quiz prompt's wording as the
chart's spoken label.

### The community question

`kind: "community"` asks about the reader's own area: they choose a forecast
office (`choose` is the menu's first line), then guess which of `measures`
(the `RISK_*` estimates, labelled as hazards) people there rate highest. It is
scored against `cwa_values.json`, the file Explore Communities maps, which the
page only puts in order, so the quiz cannot disagree with the map. Hazards
within `tie` (0.1 on the 1-5 scale) of the top all count as right, since 48 of
the 116 areas have their top two that close. `reveal_one`, `reveal_tied`,
`miss_one`, `miss_tied`, `meta` and `map_link` are templates whose
`{place}`, `{top}`, `{value}`, `{second}`, `{second_value}`, `{tied}` and
`{either}` are filled on the page; `bars` is the caption. Because the right
answer depends on the office, the choice is stored as `{code, guess, right}`
with its verdict. The chart's foot links to the map at that office and its top
measure. Once answered, "See another office (not scored)" draws any other
office's ranking below it, `alongside` the first chart rather than replacing
it, and leaves the stored answer as it was.

### Layout and scoring

Each prompt is set in layers: the setup quiet above, any quotation, then the
prompt as the large heading, with its options on the page. Answering locks the
options, marks the right ones ✓ and a wrong pick ✗, and shows the verdict and
reveal as a callout (`role="status"`), then the chart as the one card: the
survey question as respondents read it, the bars, the caption, and "Open in
the survey explorer →" at its foot. The next button reads the next part's
`lead`, or "Try a Follow-Up →", "Next Question →", "See Your Score →".

Progress is kept for the browser session in `sessionStorage` under
`wxdash-quiz` (where the reader is and every answer), so following a link
into the explorer and coming back, or reloading, resumes where they left off;
a new visit starts afresh. The saved state carries a signature of the quiz's
questions and parts, and one that no longer matches is ignored, so a deploy
that changes the quiz cannot resume into the wrong place. "Start over" clears
it.

The score counts first answers only. "← Previous Question" steps back one
prompt and shows it as it was answered, locked, so going back is for
rereading, not a second try.

The progress bar sits at the top of the card, one row per section read top to
bottom: the section's name as a button, then a segment for every prompt in it,
grouped by question, so a follow-up reads as part of its question. A segment
opens its question or part, answered or not; a section name opens the
section's first question; the current section's name is set in the accent and
the current segment is outlined; ✓ and ✗ glyphs carry the state, never color
alone. Rows are short, so it fits a phone. There is no "Question N of M" label:
the rows say where the reader is.

The score page reads "You got X of Y right" and recaps every question under its
section, with a count per section, a labelled mark for each prompt ("✓
Question ✗ Follow-up", or a series' own tags), and an explorer link, then
"Explore the survey questions" and "Start over".

## Seeing the site headless

Chrome is installed and runs headless:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --window-size=1400,1100 \
  --virtual-time-budget=40000 --screenshot=out.png http://127.0.0.1:8899/
```

Serve the built site over HTTP first (`python3 -m http.server --directory
00_wxdash_2.0/09_dashboard/_site 8899`, or the `outputs/09_site/` copy):
`fetch()` is blocked on `file://`, so every data file returns nothing. The site
routes on the hash, so `#survey`, `#map` and `#quiz` go straight to a page, and
it draws with Leaflet and Chart.js on 2D canvases, so it needs no WebGL flags.

Checking the PDFs headlessly needs the DevTools protocol rather than a
screenshot, and three things get in the way. jsPDF copies its API onto each
instance at construction, so patching `jsPDF.prototype.save` captures nothing:
replace `window.jspdf.jsPDF` with a wrapper that overrides `save` on the
instance it returns and read `doc.output("datauristring")` there. Chrome caches
`index.html`, so after a rebuild the previous `engine.js?v=<build>` keeps
loading and the old code is what runs: pass a cache-busting query parameter or
`Network.setCacheDisabled`. And a Leaflet popup fades rather than closing at
once, so a DOM check in the same tick as the click that closed it still finds
the element; wait before asserting it is gone. There is no `node` and no
`pdftoppm` on this machine: `qlmanage -t -s 1400 -o <dir> <file.pdf>` renders
the first page to PNG.
