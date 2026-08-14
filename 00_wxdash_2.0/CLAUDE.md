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
| `09_wxdash_app/` | the Shiny app, with `data/09_create_dashboard_data.R` |
| `10_static_site/` | the dashboard as static files; no R at run time |

Adding a survey wave is one line of code: the `waves` vector at the top of
`05`. Everything else is data — a new instrument in `08`, a new `_all` alert
year in `downloads/` — then rerun `02` and `03` (only if the alert year is
new), `05`, `06`, `07`, `09`, `10`. Two rough edges on that path: `07` names
`04_county_poststrat_2024.csv` explicitly, so a new poststrat vintage means
editing `07`; and `06` expects a human to read 24 model summaries, which is
deliberate and means the chain is not push-button.

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

## The app

`09_wxdash_app/app.R` has two tabs. **Explore Survey Results** is the weighted
response distributions; **Map Survey Estimates** maps 33 measures across the 116
CWAs on MapLibre, with a printable overview sheet per area. The 33 are the 24
measures `06` predicts — twelve reception, comprehension and response scales for
four hazards, plus twelve risk perceptions — and the nine alert-day counts `07`
carries alongside them. It reads six files
from `data/`, all written by `data/09_create_dashboard_data.R`: the questions,
the responses, the CWA geometry, the questions behind each mapped measure, the
measure menu and the year span each alert count covers.
Those paths are **relative** on purpose: a deployed Shiny app is a copy of its
own directory, with no `00_paths.R` and no `WXDASH_LOCAL` on the server. That
is the one place this pipeline departs from "every script writes to
`outputs/`".

`data/` **is versioned**, and its `.gitignore` records why. These six files are
the contract other people build against, and what such a build needs is
provenance — which commit produced these numbers — which git answers natively
and a folder sent out of band cannot. The cost is about 6 MB a refresh, since
`.rds` stores a full new object rather than a delta. Revisit if the refresh
cadence becomes weekly rather than a few times a year.

Nothing in that directory is ignored, deliberately: a seventh output file added
later should be tracked without anyone remembering to allow it, and an explicit
list of six is a list that goes out of date silently. A bare `data/` rule also
never lets git descend far enough to see the build script itself.

A fresh clone therefore has everything the app needs and starts without running
`09` first. Rerun `09` when the survey data changes.

If the app directory is ever renamed again, `09_create_dashboard_data.R` has to
be pointed at the new name. It refuses to write unless `app.R` sits beside the
target, because the failure it is guarding against — writing to the old path
while the app reads the new one — looks like a successful rebuild that changes
nothing.

Percentages are weighted with `srvyr` on `PERSON_WEIGHT`, which comes from
`rake()` against six ACS margins in the `wxsurveys` repo. Two estimators are in
play: `survey_prop(proportion = TRUE)` when confidence intervals are shown, and
`proportion = FALSE` when they are not — identical point estimates, but the
logit fit warns on a cell at 0 or 100%. Measured across 3,109 cells, the two
differ by at most 2.9e-09, so `10` precomputes only the first and uses it for
both.

## The static site

`10_static_site/` holds `10_build_static_site.R` and the site source it copies.
The build writes `outputs/10_site/` — plain HTML, one JavaScript file and a
folder of data — which needs no R, no Shiny and no server. Nothing in the
dashboard is computed from user input, so every view it can draw is precomputed
here instead.

The build script lives in the folder it copies, so the copy filters `.R` files
out and then checks the built site for them. Without that, the script would be
published as readable source at `/10_build_static_site.R`.

A full build takes about fifteen minutes, almost all of it the 915 questions.
`--map-only` reuses the existing question files and rebuilds the map, the
measure list and the HTML in about two seconds; use it for anything that does
not touch survey data. It refuses to run without a previous full build.

**The measure menu is declared once**, in `09_wxdash_app/measures.csv`: one row
per mapped measure, giving its order, its group and its label. `09` validates
that file against what `07` actually produces — in both directions, plus
duplicates — copies it into `data/`, and both front ends read it from there.
Adding a measure is a row in that CSV, and a measure that no longer exists
upstream stops the build rather than vanishing from a menu.

**Splits and palettes are still declared three times** — in `app.R`, in
`10_build_static_site.R` and in `10_static_site/app.js`, across two languages.
Thirteen splits and four palettes, and nothing catches a missed edit. This is
the largest remaining maintenance cost in the repo; the fix is the one that
worked for measures — declare them in a CSV the build script publishes and both
front ends read.

A session can see either dashboard. Chrome is installed and runs headless:

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

Two traps when driving the map tab. Tabs switch on click, with no URL for the
map, so reaching it means injecting a click - and `showTab()` resizes the map
only if it already exists, so wait for `canvas.maplibregl-canvas` to appear
before clicking or the map keeps MapLibre's 400x300 zero-container fallback and
renders nothing. To tell a real blank from a capture artifact, draw the canvas
into a 2D context and count non-white pixels rather than trusting the
screenshot.
