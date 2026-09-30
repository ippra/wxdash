# 09_dashboard: the production WxDash site

The deployed dashboard, and the last step of the pipeline. It reads what
`01`–`08` produce, computes every statistic the site shows, and assembles a
static site from those numbers and a hand-edited front end.

## Four parts, kept separate

**The statistics** - `09_statistics.R`, with the script generator in
`09_rcode.R`. Sourced by the builder under `--data`, not run on its own.
Computes every number the dashboard shows and writes `data/`. It reads the
codebook and topic list from `08`, the pooled survey data and scale
definitions from `05`, the model estimates from `07`, the alert spans from
`02`, and the released wave files (to verify the generated R). Roughly
fifteen minutes, almost all of it the 915 questions.

**The builder** - `09_build_dashboard.R`. Assembles the deployable site from
`data/` plus `site/`. It computes **no statistics**: every percentage,
confidence interval and estimate is carried over verbatim, so the site cannot
disagree with what was computed. A calculation added to the builder gives that
property up, and a verification harness would have to replace it.

**The site source** - `site/`. The front end as hand-editable files:
`engine.js`, `engine.css`, `index.html`, vendored Leaflet, Chart.js (with its
datalabels plugin) and jsPDF under `site/assets/vendor/`, and the
state-outline basemap under `site/assets/geo/`. Iterating on how the
dashboard looks or behaves means editing here and re-running the builder,
which takes seconds.

**The data** - `data/`, the only large thing committed in this repo. It is
the boundary between the two halves, and it is versioned so that a clone
builds the site with no pipeline outputs, no survey waves and no `~/.Renviron`.
About 70 MB on disk, about 7 MB packed. It holds:

- `questions.json` - the question index the explorer's search and browser read
- `q/` - one file per question (915): weighted distributions under every
  split, with intervals, counts and the caption summaries
- `rcode/` - one file per question: the R script that rebuilds its chart,
  one per split (and per version, for a split-sample question)
- `measures.json` - the map's measure menu, with each measure's wording
- `cwa.geojson` - the CWA boundaries with every mapped value
- `respondents.json` - respondents in total and per survey, for the landing
  page

**The output** - `outputs/09_site/` under `WXDASH_LOCAL`, or `_site/` here on a
machine without one. Outside the repo either way, like every pipeline output.
Plain static files, fully self-contained: no server code, no third-party
requests, every library vendored. Upload the directory to any web host.
Deployed at http://c.itation.net/wxdash.

## Data flow

```
08 codebook · 05 survey data · 07 estimates · 02 alert spans · wave files
        │
        ▼
09_statistics.R                 all statistics (srvyr), ~15 min
   (09_build_dashboard.R --data)
        │
        ▼
09_dashboard/data/              915 question files and the R that rebuilds
                                each of their charts, measures, CWA map values,
                                respondent counts - committed, so a clone
                                starts here
        │
        ▼                       ┌── site/ (front end source)
09_build_dashboard.R  ◄─────────┘   seconds; no statistics
        │
        ▼
outputs/09_site/ (or _site/)    the deployable site
```

One entry point, two costs. The data directory is the boundary, so iterating
on the front end never pays for the statistics, and there is nothing to hand
off and no second copy of any number.

## Machine setup (once)

**To build and deploy the site, nothing.** Clone, install the packages, run the
builder. `data/` is committed and the site is written beside it, so no
environment variable is read and no file outside the repo is opened. This is
the common case and the reason `data/` is versioned.

**To recompute the statistics** (`--data`, and `01`–`07`), `~/.Renviron`, per
`00_paths.R`:

```
WXDASH_LOCAL="/path/to/local files"        # outputs/ and downloads/ live here
WXSURVEYS_ROOT="/path/to/wxsurveys/"       # the 22 built survey datasets
```

`00_paths.R` checks these in `require_roots()`, which the scripts that read a
root call and the assembly half does not. With `WXDASH_LOCAL` set the site goes
to `outputs/09_site/`.

`WXDASH_LOCAL` sits inside Dropbox, so mark `outputs/` Dropbox-ignored on every
machine that runs the builder (`xattr -w com.dropbox.ignored 1` on that
directory). Otherwise a sync can race a rebuild and publish a stale `engine.js`
beside fresh data. The builder compares every copied file with `site/` byte
for byte and stops on a mismatch or on any "conflicted copy" in the output.

R packages: `tidyverse`, `sf`, `jsonlite` and `here` for assembly; `srvyr`
as well for `--data`.

## Building and previewing

```
Rscript 00_wxdash_2.0/09_dashboard/09_build_dashboard.R --data  # if survey data,
                                                                # models or the
                                                                # menu changed
                                                                # (~15 min)
Rscript 00_wxdash_2.0/09_dashboard/09_build_dashboard.R         # always (seconds)
python3 -m http.server --directory 00_wxdash_2.0/09_dashboard/_site
```

Serve over HTTP to preview: the site fetches its data, and `fetch()` is
blocked on `file://`. With `WXDASH_LOCAL` set, serve `$WXDASH_LOCAL/outputs/
09_site` instead.

Without `--data` the builder reads `data/` and refuses to start if it is not
there, rather than assembling a site around an empty question table. In a clone
those files are committed, so their absence means a partial checkout.

The builder halts loudly rather than producing a quietly wrong site. Among the
things that stop it: fewer R scripts than questions, menu measures missing from
the map file or with an area missing a value, mapped measures with no question
wording, a measure with no alert pairing decided or a pairing naming an alert
layer the menu does not offer, quiz questions whose data does not support their
fixed prose (see below), per-survey respondent counts that do not add up to the
total, built files that differ from `site/`, and R sources in the output.

## Deploying

The built site directory is the rsync unit:

```
rsync -av --delete "$WXDASH_LOCAL/outputs/09_site/" <host>:<docroot>/wxdash/
```

The site is static and self-contained with relative URLs and hash routing
(`#home`, `#survey`, `#map`, `#quiz`, `#about`), so moving it to a different
host or domain needs no changes to the site itself: DNS, a server block, and a
certificate. Every asset URL carries a `?v=<build>` stamp, filled into
`index.html` at build time, so long-lived host caches roll over on each deploy.

One hosting requirement makes that stamping work: `index.html` itself must be
served with `Cache-Control: no-cache` (cache but revalidate; the server
answers 304 via Last-Modified when unchanged). The HTML is the one file that
cannot version-stamp itself; if the host serves it with a long max-age,
browsers keep the old HTML, and therefore the old `?v=` references, and new
deploys are invisible until a hard refresh. Everything else can be cached as
long as the host likes. On the current host, nginx sets no-cache on the three
HTML entry URLs (`/wxdash`, `/wxdash/`, `/wxdash/index.html`); any other host
needs the equivalent.

## What the builder adds on top of the computed data

- `config.json` - the five pages (Home, Explore Survey Questions, Explore
  Communities, Test Your Knowledge, About) and all their prose, the default
  theme, the split roster with caption phrases, the measure catalog with its
  alert pairings, the chart caption and map popup `{token}` templates the
  front end fills at render time, the per-measure map notes, the quiz, and
  the footer.
- **Place ranks, percentiles and medians** for the map popups, precomputed
  from the map values themselves (rank = 1 + count strictly greater;
  percentile = share strictly below), in `data/map/cwa_values.json`.
- **The map notes** - for each measure, what respondents were asked (read
  from `measures.json`), how the answers become a score, the observed range the
  colors span, and where the estimates come from. Alert counts get the same
  parts in their own terms. Every number is read off the data.
- **The alert-history pairing** - which alert layer each measure is offered
  against, in `compare_pairing`, transcribed from `06_fit_models.R`. Drought,
  hail and lightning have no NWS alert product (`06` fits them on FEMA NRI
  frequencies), so their pairing is deliberately absent and the page says so.
- **The overview sheet's prose** (`config.map.scan`) - the caution that makes
  its rows readable: each row is stretched to its own range, so compare a
  community's position within a row, not across rows. The count of other
  offices is read off the data, and the sentence on which years the alert
  counts cover is written from the menu, so a category whose coverage differs
  moves itself into or out of the exception.
- **The landing page's figures** - responses, years, hazards and surveys,
  counted from `respondents.json`, and the dot field: one column per year,
  each holding every respondent to date at one dot per 50, colored by hazard.
- **The About page** - the project, the survey, how to interpret survey
  results, community estimates, alert history, how to use the site, data and
  reproducibility, the two methods papers, publications using the survey
  (grouped by year, each linked by DOI, and checked to be newest first),
  support, and contact. The alert years and the count of areas are read from
  the data.
- **Test Your Knowledge**: thirteen questions in six sections that follow a
  warning along its path: Receiving, Understanding, Trust, Warning Decisions,
  Risk, Responding. Most have a follow-up; the regional risk question asks the
  same thing of each census region in turn; and one asks the reader to pick a
  forecast office and guess its highest-rated hazard, scored against the
  modeled estimates the map shows. Prompts are fixed; answer keys and reveal
  numbers are derived from the distributions at build time, so they always
  agree with what the explorer shows. Guards halt the build when the data
  stops supporting a fixed claim, naming the sentence to rewrite. A "which
  group is highest" answer has to clear the runner-up by three points (0.2 on
  a 1–5 mean), more than the confidence intervals on the same numbers, so the
  reader can see the answer rather than being told they lost a coin flip. An
  answer that rests on an ordered split instead claims a direction
  (understanding rises with age) and is guarded for the run still going one
  way end to end, which lets adjacent groups sit close together. A share that
  leaves its answer band, or lands between two bands, halts too. Shares are
  carried unrounded into the guards, since rounding first can walk an answer
  past a margin it does not clear. A split-sample question is refused
  outright: an answer drawn from one version is a claim about the people who
  saw that version.

  Each part carries the chart its reveal draws and a `highlight` naming the
  bars its answer is made of, so the reveal lights exactly those and fades
  the rest. A part about one question charts that question's file; a part
  comparing several survey questions carries builder-written `chart` rows,
  since no single question file matches what it asks; a follow-up draws one
  bar per group, the share or mean its answer compares, with the survey
  page's two-line note. Every reveal and the final score page link into the
  survey explorer.
- Simplified CWA geometry (the full-resolution polygons and per-measure
  properties in the computed geojson are not needed, because values ship
  separately).

## What the front end does with it

- **Five pages on one skeleton.** The two explore pages and the quiz share a
  layout: the page's title and introduction; a small label over a large
  heading naming what is shown; the controls on the page, not in a card, with
  one options toggle ("Chart options", "Map options"); the figure as the one
  card, with its downloads at its foot; then the page's notes and its browser
  or overview sheet. Above every page sits the black IPPRA bar, static markup
  in `index.html` that becomes a back link when the reader arrived from
  ippra.net.
- **Themes.** "Adjust colors" in the navbar switches between WxDash (light),
  Ops (dark) and Greyscale (high contrast); `?theme=` deep-links one. Themes
  restyle the chrome. Chart and map colors are a separate setting under the
  options toggle: Blue (the default), Viridis, or Grey (print safe), shared
  through `?scheme=`.
- **Explore Survey Questions** opens with a search over the full wording of
  every question, stem and item together: every word typed must appear, and
  matches in the item itself rank first. Below the chart, the question browser
  filters by survey, topic and question type, searches within what they leave,
  and lists ten questions a page. A pick from either loads the question the
  same way. "Compare responses by" chooses one of thirteen splits; "Chart
  options" holds the color scheme and 95% confidence intervals. `?q=`,
  `?grouping=`, `?ci=1` and `?scheme=` deep-link a view.
- **A question is a stem and an item.** The stem, the sentence every item of
  a battery shares, is set quiet and small above the item, which carries the
  weight; the same two weights in the chart heading, in each row of the
  question browser and in the search suggestions. The data half supplies
  `question_intro` and `question_text` beside the joined `question`, which is
  what the downloads and the R script title use.
- **Split-sample questions carry a version menu.** Where the wording varied by
  a randomization variable, the chart shows one version at a time and the menu
  sits under the question heading; `?arm=` deep-links one. There is no pooled
  option: pooling averages across the difference being tested.
  `question_arms.csv` pairs a question with its randomizer and `arms.csv`
  labels the values; both live beside the builder, and each pairing is
  checked against the survey data before it is used. `questionSlice()` in
  `engine.js` is the one place that knows about the nesting.
- **Wording never shows a variable name.** `readableWording()` in
  `engine.js` puts the version shown into the question, in bold, and turns
  every other placeholder into words: a listed set reads "[15, 30, or 60]", a
  range "[5 to 100]", a named one what `placeholders` in the builder's config
  says ("[the respondent's state]"). The names go in the note under the chart
  instead: "Randomization:" for the menu's own variable, "Wording varies
  with:" for the rest.
- **Questions can be hidden by listing them.** `hidden_questions.csv` is the
  record of what is off Explore Survey Questions and why. `hide` takes a
  question off the list; `needs-context` only records it. Assembly filters the list, so every
  question keeps its data files and a change needs no `--data` run. Fill it
  from the browser: `?flag=1` adds a flag beside the question heading and a
  panel that exports the file. The flag is gated on that parameter because it
  is scaffolding, and a reader never sees it. Flags are kept in
  `localStorage`, so they are per browser and per origin; export before
  switching.
- **Readers can save questions.** "Save question" beside Download R code adds it
  to a "Saved questions" panel at the foot of the page, which appears only
  once something is saved and downloads the list as CSV. Kept in
  `localStorage` under its own key, apart from the flags, so a reader's list
  never feeds the hide list.
- **Every chart carries the R that rebuilds it.** *Download R code* sits beside
  *Download chart (PNG)* and *Download chart (PDF)* at the foot of the chart on
  Explore Survey Questions, and saves a script that rebuilds that question
  under that split, from the released wave files and nothing else. The data
  half generates one script per (question, split) and runs a sample covering
  every hazard by every split against the numbers it is publishing; assembly
  carries them over the way it carries every other number, and stops if there
  are fewer script files than questions. A download rather than an on-page
  viewer: someone who wants the script wants it in their editor.
- **Explore Communities is one page in four parts**: the controls, the map (or
  two), the notes that explain what is mapped, and the overview sheet for
  whichever area was clicked. The notes come before the sheet because one
  area's standing means nothing until the reader knows what is being measured.
  The controls are "What do you want to explore?" (the measure),
  "Compare with alert history", and "Forecast office", a list that selects an
  area exactly as a click on the map does, so everything the map does is
  reachable from the keyboard. `?measure=`, `?compare=` and `?place=`
  deep-link a view.
- **Comparison is two maps.** Choosing an alert layer draws it beside the
  measure at the same size in a contrasting ramp; hovering either map outlines
  the area on both, either tooltip carries both numbers, and the notes below
  split into two columns to match, one explanation per map. Both quantities
  stay on screen together, so the reader compares two pictures rather than
  holding one of them in memory. Changing the measure moves a live comparison
  to that measure's paired layer.
- **The overview sheet** - every measure for one County Warning Area, drawn as
  a row stretched to its own range across the 116 areas: a tick per area, the
  median, this area's dot, the range ends, the value and the percentile.
  Selecting a row maps that measure. Values are the ones the popup reads, so
  the two cannot disagree. Clicking an area fills it; `Clear` in its header or
  `Clear selection` on the map card empties it, and clearing re-frames the
  maps (a popup auto-pans to stay in view, which shifts an otherwise fixed
  frame). The sheet and its prose share one width (`--scan-width`), and the
  strips are drawn at the width their column actually got, measured after
  layout.
- **The map surface carries no color of its own** - the choropleth sits
  directly on the card. Polygon borders are therefore a theme token
  (`--map-hairline`): white borders against a white card would lose the shape
  of the palest areas along with their fill. The hover and selection outline is
  chosen against the fill's luma for the same reason, since any single color
  fails at one end of a ramp: grey is invisible on the dark end of the greys
  the comparison map uses.
- **Downloads are one picture in two formats.** The chart, the map and the
  overview sheet each download as PNG and PDF, drawn once by `figureImage()`
  so every figure has the same frame: a small label, a stem, the title, the
  figure, the page's own caption lines read off the rendered page, and a
  source line (`FIGURE_SOURCE`), on the theme's own background. It is laid out
  at 1200px and drawn at four times the density, 4800px across, which holds up
  full-width on a slide; the PDF is that image on a page 11 inches wide cut to
  its height. The chart is redrawn off screen by Chart.js with slide-sized
  type. Leaflet paints at screen resolution, so `vectorMap()` redraws every
  map path from the positions and styles Leaflet has already worked out, which
  keeps outlines sharp and shows the same frame, colors and selection as the
  screen. The overview sheet redraws its key, column heads and rows with the
  page's own marks.
- **Text alternatives.** A chart drawn on a canvas says nothing to a screen
  reader, so every bar chart carries a spoken label and, beside it, a table of
  the same numbers hidden on screen (`chartAlt()`), marking the highlighted
  bars in the quiz. The map does the same: a labelled region and a hidden
  table of every forecast office's value for the measure shown (and the
  comparison layer, when one is drawn). Nothing in either table is computed;
  they repeat the values already drawn.
- **Test Your Knowledge** shows progress as one row per section, with a
  segment per prompt marked right or wrong by glyph as well as color, and
  lets the reader step back to any answered prompt. The score counts first
  answers only, and the score page recaps every question under its section.

## Working in this directory

- **GitHub is the master.** Start every session with `git pull`; push when a
  change lands. Several people and sessions iterate here, so expect the
  directory to have moved since you last saw it: read the diff, not your
  memory of it.
- **Statistics belong in the data half.** A change to what is computed goes in
  `01`–`08` or `09_statistics.R`; a change to what is shown goes in `site/`
  and the builder. If the shape of `data/` changes, the builder's guards fail
  loudly: update the reader code and this README in the same commit.
- R code here follows the repo's style guide (`00_wxdash_2.0/CLAUDE.md`).
- The split roster and caption phrases in the builder (`groups` and
  `group_phrases`) mirror the one in `09_statistics.R`; if a split is added
  there, add it here too. `engine.js` has no roster of its own: it reads the
  splits from `config.json`. Nothing checks the two R copies against each
  other, so nothing catches a missed edit.

## Maintainer notes

- Split groups render in their coded `"(1) "` order, stripped for display: the
  prefixes order the levels upstream and are noise in a legend. Sorting the
  stripped labels alphabetically instead would scramble ordinal splits like
  income and education.
- The chart lookup separator in `engine.js` is the escape `"\x1F"` rather than
  a literal control byte, so the file stays text to git and grep.
- The engine renders only precomputed values; the one derivation it performs
  is presentation arithmetic (assembling popup sentences from shipped rank,
  percentile and median). Keep it that way: it is what makes the "cannot
  disagree with what was computed" property inspectable.
- `index.html` is covered by a `.gitignore` negation: the repo ignores
  rendered `*.html`, and this one is source.
