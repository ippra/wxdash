# wxdash 2.0

Orientation for `00_wxdash_2.0`: what the pipeline does, and the decisions in it
that are easy to undo by accident. Read this before touching anything here.

R in this repository follows the IPPRA house style — two-space indent, native
`|>`, 80 columns, guards before the step they protect, comments that give the
reason rather than the history. The full guide is `~/.claude/ippra-r-style.md`.

## The pipeline

Scripts run in number order; each output is named for the script that wrote it,
so provenance reads off the filename. All of them `source(here::here(
"00_wxdash_2.0", "00_paths.R"))`, which resolves `WXDASH_LOCAL` and
`WXSURVEYS_ROOT` from `~/.Renviron`.

| script | what it produces |
|---|---|
| `01` | county-to-CWA crosswalk |
| `02`, `03` | CWA and county alert counts from NWS archives |
| `04` | poststratification cells and county covariates |
| `05` | `05_survey_responses.csv`, 22 waves, ~400 MB; `05_scale_items.csv` |
| `06` | multilevel models; fixed effects are the five poststrat cells |
| `07` | CWA and county estimates, as CSV and as simplified `sf` for mapping |
| `08` | `variable_reference.csv` — the codebook, read off instruments |
| `11_dashboard/` | the dashboard: every statistic, and the site that shows it |

The numbering skips `09` and `10`, and the gap stays. Closing it would rename
`outputs/11_site/`, which is the rsync target, and renaming a deploy path to
tidy a sequence is how a deploy breaks.

Adding a survey wave is one line of code: the `waves` vector at the top of
`05`. Everything else is data — a new instrument in `08`, a new `_all` alert
year in `downloads/` — then rerun `02` and `03` (only if the alert year is
new), `05`, `06`, `07`, and `11 --data`. Two rough edges on that path: `07`
names `04_county_poststrat_2024.csv` explicitly, so a new poststrat vintage
means editing `07`; and `06` expects a human to read 24 model summaries, which
is deliberate and means the chain is not push-button.

`WXDASH_LOCAL` points inside Dropbox, and **`outputs/` is marked
Dropbox-ignored** — `xattr -w com.dropbox.ignored 1` on that directory. Without
it a sync races a rebuild: Dropbox restores the previous `engine.js` under its
own name and files the new one as a conflicted copy, publishing stale
JavaScript beside fresh data — a site that loads, draws, and is wrong. It
happened three times in one session and produced over a thousand conflicted
copies. The attribute is per machine and does not travel with the repo, so set
it on any machine that runs `10` or `11`; everything under `outputs/` is
regenerable from `01`–`11`, which is the same argument that keeps it out of
git. `10` and `11` both scan the built site for conflicted copies and stop, but
that only catches what a previous run left behind — nothing can catch Dropbox
reverting a build after it finishes.

The five poststratification cells — `AGE_GROUP`, `GENDER_GROUP`, `RACE_GROUP`,
`EDUC_GROUP`, `INCOME_GROUP` — are built in `04` and fit in `06`. Anything
that splits the data should use those, so the app cuts it the way the models
do.

`05` also writes `05_scale_items.csv`: which survey items went into each of the
twelve reception, comprehension and response scales, and which were reverse
coded. The item lists in `05` are the only definition of those scales; `09`
reads this file to show the questions behind a scale rather than keeping a
second copy that would drift.

## Alert categories

`02` and `03` bucket VTEC phenomena into hazard categories. Two splits are
deliberate and easy to undo by accident:

- `FREEZE` is separate from `COLD`. Frost and freeze products are issued for
  agriculture in CA, OR and FL, not for cold places — the two correlate -0.21
  across CWAs, and merging them halved every winter risk correlation.
- `SURG` is separate from `HURR`, so `risk_surge` has an exposure measure of
  its own. `HURR` predicts the item better (.23 against .21) but is dominated
  by tropical wind products; the split was chosen for measurement validity, not
  fit, and dropping `SS` costs the hurricane models nothing. `SS` only exists
  from 2017, so `SURG` spans nine of the sixteen archive years.

`07` carries the nine alert counts the models fit onto the CWA map file under an
`ALERT_` prefix, so exposure can be read beside the estimate it helps explain.
They are counts of days, not a 1-5 scale, and both dashboards branch on that.

## The variable reference

`08_create_variable_reference/variable_reference.csv` is one row per survey
hazard per variable, carrying each question as it was actually asked. It covers
all 22 instruments. Two companions matter as much as the sheet:

- `NOTES.md` — what still needs a second pair of eyes, grouped by what to do
  about it. Instrument errors are recorded there and in the `notes` column,
  never corrected in the sheet: the sheet records what the documents say.
- `.claude/skills/survey-variable-reference/` — the procedure. Adding an
  instrument means following it, not improvising. Read the instruments end to
  end; do not write a parser for what the text *means*. Extraction is scripted,
  judgment is not.

Its judgment columns are independent and easy to confuse:

- `experimental` — what the respondent read varied. Order-only randomization
  (`RANDOM ORDER`) is **not** experimental; that would sweep in the core trend
  batteries.
- `graphic_shown` — a graphic was displayed and the answer rests on it. Not
  the same as the `graphics` keyword, which is a topic tag and includes
  questions *about* maps where nothing was shown.
- `question_focus` — `weather` or `background`; `09` drops background items.

Watch two traps. `"graphics" in keywords` also matches `demographics`, so match
keyword tokens exactly. And the option separator is `" | "`, so a pipe inside an
option label makes `response_options` unsplittable.

The `.docx` instruments are gitignored, so a fresh clone has the sheet and the
skill but not the sources.

## The statistics

`11_dashboard/11_statistics.R` computes every number the dashboard shows, and
nothing else does. It is sourced by `11_build_dashboard.R` under `--data`, not
run on its own, and it writes `outputs/11_data/`: the 915 question files, the R
that rebuilds each of their charts, the measure menu and the map.

**The two halves of `11` are split on cost, not on subject.** This one reads a
400 MB file and makes about 24,000 `srvyr` calls, and takes roughly fifteen
minutes; assembly reads what it wrote and takes two seconds. Front-end work is
the common case, so `outputs/11_data/` is the boundary between them and the
default run does not touch it. Run `--data` when the survey data, the models or
the measure menu change; without it for anything else. Assembly refuses to
start if that directory is not there.

Percentages are weighted with `srvyr` on `PERSON_WEIGHT`, which comes from
`rake()` against six ACS margins in the `wxsurveys` repo. Two estimators are in
play: `survey_prop(proportion = TRUE)` when confidence intervals are shown, and
`proportion = FALSE` when they are not — identical point estimates, but the
logit fit warns on a cell at 0 or 100%. Measured across 3,109 cells, the two
differ by at most 2.9e-09, so only the first is computed and it is used for
both. The second call was most of the build: with both, a full run took over an
hour.

**Every chart carries the R that rebuilds it.** `11_rcode.R` holds the
generator, and the question loop runs it: one concrete script per (question,
split), written into `11_data/rcode/<id>.json` and fetched by the front end on
the first click. The code that computed the numbers writes the code that
reproduces them, so the two cannot drift.

The scripts read the released wave files — `WX18_data_wtd.csv` and the rest of
the 22 — rather than `05`'s pooled output, which is 400 MB and which nothing
releases. Three rules the generated code follows, and they are the point of it:
no helper functions, column names written where they are used rather than
through `.data[[ ]]`, and only the columns that chart needs. That is why there
is a script per split instead of one template: splitting by age should not make
a reader read a roster of twelve grouping columns, and the five derived splits
each write their own `case_when` out where a reader can see it.

**It then runs them and compares.** `verify_r_code()` evaluates a script
against the same wave files a reader would download and checks its estimates
against the rows being written to the question file — matching on *labels*, so
a levels/labels pairing that had drifted would not slip through. Coverage is
every hazard by every split, so each derived `case_when` is exercised in all
four, plus one Everyone script per response scale. Running all ~11,900 would
add hours for no more coverage than that.

Two things the generated code makes visible that the pipeline only describes:
the WX17 reception and response batteries dropped for being on a 1-7 scale, and
that weather salience needs both items rather than one.

**A question is a stem and an item, and they are set differently.** `08`
records `question_intro` and `question_text` apart, and both are carried
through beside the joined `question`. The front end sets the stem quiet, small
and unbolded above the item, which carries the weight — in the chart heading
and in each row of the question table. The stem is the same sentence on every
item of a battery and the item is what changes, so without it a row of the risk
battery reads "Tornadoes", which is not a question. Where a question has no
item of its own — 148 of the 915 — the stem *is* the question, so it moves into
`question_text` and nothing is left above it.

`question` stays the one string anything needing a whole question uses: the
PDF title, the table's search and sort, and the title of the R script that
rebuilds the chart.

**The measure menu is declared once**, in `11_dashboard/measures.csv`: one row
per mapped measure, giving its order, its group and its label. It is validated
against what `07` actually produces — in both directions, plus duplicates — so
adding a measure is a row in that CSV, and a measure that no longer exists
upstream stops the build rather than vanishing from a menu.

**Splits are declared twice** — in `11_statistics.R` and in
`11_dashboard/site/engine.js`, across two languages. Thirteen splits with a
caption phrase each, and nothing catches a missed edit, though the five derived
ones are also written out as generated R where `verify_r_code()` would fail on
a drift. This was five declarations before `09` and `10` were retired, and
palettes were worse still; what is left is one duplication across the language
boundary, which is the smallest it goes without a CSV both sides read.

## The production site

`11_dashboard/` is the deployed dashboard, maintained by Matthew Henderson on
top of `01`–`08`. It has its own `README.md`, which is the fuller account; what
matters from here is the property the arrangement buys. **Assembly computes no
statistics**: every percentage, interval and estimate is read from
`outputs/11_data/` verbatim, so the site cannot disagree with what was
computed. A calculation moved into the assembly half gives that up, and a
verification harness would have to come back to replace it.

The map and chart PDFs are documents rather than screenshots: title, subtitle,
plot, legends, then the page's own notes set in columns, with a footer. Their
notes are lifted from the rendered DOM — `notesCard.innerHTML` for the map, the
caption element for the chart — so an export cannot say something the page it
came from does not. Three things make that layout hold: the note height is
measured before the plot is placed, so the plot takes what is left rather than
pushing prose onto a second page; the snapshot is cropped to what was actually
drawn, since the map container is a fixed frame the CONUS floats inside; and
legends are positioned from the image rather than the page margin, or the
second one lands under the gap between two maps instead of under its own. The
scan sheet's PDF is a different animal — rows, not a plot — and is built by
`scanPDF` with its own geometry.

**Download R code** sits beside **Download chart (PDF)** on Explore Survey
Questions, in a `.wx-toolbar-actions` group because `.wx-pdf-btn` takes
`margin-left: auto` and two of them loose in the row end up at opposite ends of
it. The scripts come from the data half, carried over like the numbers they
rebuild, and assembly refuses to publish a site with fewer scripts than
questions — a
button that 404s looks to the page exactly like a network failure. It is a
download and not a panel: someone who wants the script wants it in their
editor, not in a scrolling box.

`site/` is the hand-edited front end — `engine.js`, `engine.css`, `index.html`,
vendored Leaflet, Chart.js and jsPDF. The builder copies it, fills the
`__BUILD__` cache-busting stamp, drops anything hidden, and refuses to publish
a built site containing `.R` files. It writes `outputs/11_site/`, which is the
rsync unit; a run takes seconds, so iterating on the front end is cheap.

The quiz is the one place the builder authors claims about the data. Prompts
are fixed, answers and reveal numbers are read off the distributions, and
guards halt the build when the data stops supporting the sentence: an answer
naming a winner has to clear the runner-up by three points, more than the
intervals the reveal chart draws beside it, while an answer resting on an
ordered split claims a direction instead and is guarded for the run still going
one way. Shares are carried unrounded for exactly this reason — rounding first
moves a group up to a point, which is enough to walk an answer past a margin it
does not clear.

The comparison pairings in `11` are transcribed from `06_fit_models.R`. Choosing
an alert history draws it as a second map beside the measure its model was
fitted on, so both quantities are on screen at once and the reader compares two
pictures rather than holding one in memory. Both maps are the same size, the
second takes a contrasting ramp, hovering either outlines the area on both,
either tooltip carries both numbers, and each measure keeps its own note in the
card below. Drought, hail and lightning are fitted on FEMA NRI frequencies
rather than an NWS product, so they have no pairing and the page says so.

The map surface carries no color of its own: the choropleth sits directly on
the card. Two things follow from that and are easy to undo by accident. Polygon
borders are a theme token (`--map-hairline`), because white borders against a
white card lose the shape of the palest areas along with their fill. And the
hover and selection outline is chosen against the fill's luma, because any
single color fails at one end of a ramp — a grey outline is invisible on the
dark end of the greys the comparison map draws in.

Explore Communities carries `09`'s CWA overview sheet as the last panel on the
page, below the map and the notes that explain it: click an area and every
measure is drawn as a row stretched to its own range across the areas, with a
one-page vector PDF beside it. The numbers are the ones already in
`cwa_values.json`, so the sheet cannot disagree with the popup above it. What
the builder authors is the caution that makes the rows readable, and the three
widths it quotes are measured off the data rather than asserted. The sheet and
its prose share one width (`--scan-width`), and the strips are drawn at the
width the column actually got, measured after layout.

Picking an area is undone from either end — `Clear` in the sheet's header or
`Clear selection` in the toolbar — and clearing re-frames both maps. A popup
auto-pans to stay in view, which shifts a frame that is otherwise fixed, and
nothing else puts it back.

A session can see any of the three dashboards. Chrome is installed and runs
headless:

```sh
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless=new --enable-unsafe-swiftshader --window-size=1400,1100 \
  --virtual-time-budget=40000 --screenshot=out.png http://127.0.0.1:8899/
```

Serve the built site over HTTP first - `fetch()` is blocked on `file://`, so
every data file returns nothing. `--enable-unsafe-swiftshader` supplies software
WebGL, which MapLibre needs; `--disable-gpu` removes WebGL entirely and the map
comes back blank. `preserveDrawingBuffer: true` is already set in `app.js`, so
the canvas survives being read back.

Two traps when driving `09` or `10`'s map tab. Tabs switch on click, with no
URL for the map, so reaching it means injecting a click - and `showTab()`
resizes the map only if it already exists, so wait for
`canvas.maplibregl-canvas` to appear before clicking or the map keeps
MapLibre's 400x300 zero-container fallback and renders nothing. To tell a real
blank from a capture artifact, draw the canvas into a 2D context and count
non-white pixels rather than trusting the screenshot.

Neither trap applies to `11`, which routes on the hash - `#survey`, `#map`,
`#quiz` go straight to a page - and draws with Leaflet on a 2D canvas, so it
needs no WebGL and no swiftshader flag.

Checking `11`'s PDFs headlessly needs the DevTools protocol rather than a
screenshot, and three things get in the way. jsPDF copies its API onto each
instance at construction, so patching `jsPDF.prototype.save` captures nothing —
replace `window.jspdf.jsPDF` with a wrapper that overrides `save` on the
instance it returns and read `doc.output("datauristring")` there. Chrome caches
`index.html`, so after a rebuild the previous `engine.js?v=<build>` keeps
loading and the old code is what runs — pass a cache-busting query parameter or
`Network.setCacheDisabled`. And a Leaflet popup fades rather than closing at
once, so a DOM check in the same tick as the click that closed it still finds
the element; wait before asserting it is gone. There is no `node` and no
`pdftoppm` on this machine: `qlmanage -t -s 1400 -o <dir> <file.pdf>` renders
the first page to PNG.
