# Severe Weather and Society Dashboard — Estimation Pipeline

This directory builds small-area estimates of how the American public receives
severe weather information. It combines the Severe Weather and Society Survey
with Census microdata, National Weather Service warning records, and county
social and hazard indicators, then uses multilevel regression and
poststratification (MRP) to produce an estimate for every county in the
contiguous United States and every NWS County Warning Area (CWA).

The pipeline is nine numbered steps, run in order. Each output file is named
for the script that wrote it, so `03_county_alert_counts.csv` came from `03`.
Steps `01`-`07` build the estimates; `08` documents the survey instruments; and
`09` computes every statistic the dashboard shows and assembles the site that
shows them.

---

## What it produces

Two long-format files, one row per area per measure:

| file | rows | contents |
|---|---|---|
| `07_county_estimates.csv` | 74,616 | 3,109 counties × 24 measures |
| `07_cwa_estimates.csv` | 2,784 | 116 CWAs × 24 measures |

and the same estimates joined to simplified boundaries for mapping, wide rather
than long:

| file | contents |
|---|---|
| `07_county_estimates_sf.rds` | 3,109 counties × 24 measures + geometry |
| `07_cwa_estimates_sf.rds` | 116 CWAs × 24 measures + 9 alert counts |

The CWA file also carries the nine alert counts the models are fitted on, under
an `ALERT_` prefix, so exposure can be read beside the estimate it helps
explain. They are counts of days, not a 1–5 scale.

Twenty-four measures in four families. Twelve are composite scales, each the
mean of several 1–5 survey items; twelve are single 1–5 risk perception items.

**Reception** — how well warning information reaches the respondent:

| code | hazard | survey years |
|---|---|---|
| `TO_RECEP` | tornado | 2018–2025 |
| `HU_RECEP` | tropical cyclone | 2020–2025 |
| `WW_RECEP` | winter weather | 2021–2025 |
| `FL_RECEP` | flood | 2024–2025 |

**Comprehension** — whether they understand what warning products mean:
`TO_SUBJ_COMP`, `HU_SUBJ_COMP`, `WW_SUBJ_COMP`, `FL_SUBJ_COMP`, over the same
years as their reception counterparts.

**Response** — what they do when a warning arrives: `TO_RESP`, `HU_RESP`,
`WW_RESP`, `FL_RESP`.

**Risk perception** — how risky they rate a hazard where they live, one item
each: `RISK_TOR`, `RISK_HUR`, `RISK_SURGE`, `RISK_SNOW`, `RISK_ICE`,
`RISK_COLD`, `RISK_HEAT`, `RISK_FLOOD`, `RISK_FIRE`, `RISK_DROUGHT`,
`RISK_HAIL`, `RISK_LIGNT`.

The two geographies are consistent by construction: both come from the same set
of cell-level predictions, and `07` verifies that population-weighting a CWA's
county estimates reproduces its CWA estimate.

---

## Data sources

All inputs are downloaded manually into a single `downloads/` directory, except
the ACS county tables, which are pulled through the Census API at run time. No
data is stored in this repository.

### Survey data

| files | source |
|---|---|
| `WX17`–`WX25`, `TC20`–`TC25`, `WW21`–`WW25`, `FL24`–`FL25`, each `_data_wtd.csv` (22 files) | [Severe Weather and Society Survey, Harvard Dataverse](https://dataverse.harvard.edu/dataverse/wxsurvey) |

Prefixes denote the survey instrument: `WX` general severe weather, `TC`
tropical cyclone, `WW` winter weather, `FL` flood. The `_wtd` suffix indicates
the released file carries survey weights. 35,457 respondents across 22 waves
survive processing.

### Geography

| file | source |
|---|---|
| `c_16ap26/` — NWS county-to-CWA assignment | [weather.gov/gis/Counties](https://www.weather.gov/gis/Counties) |
| `w_16ap26/` — NWS CWA boundaries | [weather.gov/gis/CWA](https://www.weather.gov/gis/CWABounds) |
| `cb_2025_us_county_20m/` — Census county boundaries, 20m generalization | [Census cartographic boundary files](https://www.census.gov/geographies/mapping-files/time-series/geo/cartographic-boundary.html) |

`c_16ap26` supplies the county-to-CWA assignment in `01`; its geometry is not
used, because it predates Connecticut's planning regions. County geometry comes
from `cb_2025_us_county_20m` throughout, and CWA geometry from `w_16ap26` in
`07`.

Respondent location is not resolved here. The wave files arrive from the
`wxsurveys` repository already carrying `ZIP_FIPS`, `ZIP_CWA` and `ZIP_STATE`,
so no ZIP crosswalk is read by this pipeline.

### Warning records

| files | source |
|---|---|
| `2010_all/` … `2025_all/` — archived watch, warning and advisory polygons, one directory per year | [Iowa Environmental Mesonet, Iowa State University](https://mesonet.agron.iastate.edu/request/gis/watchwarn.phtml) |

By far the largest inputs, roughly 1.4 GB per year. VTEC phenomenon codes are
grouped into eleven hazard categories following
[pyIEM's VTEC reference](https://github.com/akrherz/pyIEM/blob/main/src/pyiem/nws/vtec.py).

### Population and area characteristics

| file | source |
|---|---|
| `usa_00035.xml` + `usa_00035.dat.gz` — ACS microdata | [IPUMS USA](https://usa.ipums.org), collection `usa`, sample `us2024c` (2020–2024 ACS 5-year) |
| ACS county tables B01001, B03002, B15001, B19001 | Census API via `tidycensus`, `acs5`, year 2024 |
| `SVI_2022_US_county.csv` — Social Vulnerability Index | [CDC/ATSDR SVI](https://www.atsdr.cdc.gov/place-health/php/svi/) |
| `NRI_Table_Counties/NRI_Table_Counties.csv` — National Risk Index | [FEMA NRI](https://hazards.fema.gov/nri/data-resources), December 2025 release |

The IPUMS extract definition is reproduced as a comment in `04`, so the exact
extract can be rebuilt. IPUMS assigns a new number to each extract, so the
filename in the script must be updated to match when it is.

---

## The scripts

### `00_paths.R`

Defines `downloads`, `outputs` and `survey_files`. Every other script sources
it, so directory locations exist in exactly one place, and it stops if either
root in `~/.Renviron` is unset or points somewhere that does not exist. Not a
pipeline step.

### `01_create_county_cwa_crosswalk.R`

Assigns each county to one NWS County Warning Area.

Counties spanning multiple CWAs are assigned to the first listed. Two
corrections are applied by hand: mainland Monroe County, Florida is assigned to
Key West, and Connecticut's nine planning regions are assigned individually,
because the NWS county file uses Connecticut's pre-2022 county geography and
would otherwise leave the entire state unmatched.

**Writes** `01_county_cwa_crosswalk.csv` — 3,222 counties and their CWA.

### `02_create_cwa_alert_dataset.R`

Counts warning days per CWA per hazard, 2010–2025.

Reads the attribute CSV inside each yearly archive rather than the shapefile,
since the CWA is already an attribute and no geometry is needed. Counts are
distinct **days**, not events, so a hazard producing twenty warnings in one day
counts once.

`FREEZE` is kept separate from `COLD`, and `SURG` separate from `HURR`. Both
splits are deliberate: frost and freeze products are issued for agriculture in
California, Oregon and Florida rather than for cold places, and storm surge
warnings did not exist before 2017. Merging either would blur an exposure
measure the models rely on.

**Writes** `02_cwa_alert_counts.csv` — 124 CWAs × 11 hazard categories — and
`02_alert_years.csv`, the first and last year each category appears in. The
totals sum the years away, and anything reporting "alert days between X and Y"
needs the span for that hazard rather than the archive's.

### `03_create_county_alert_dataset.R`

The same counts at county level.

This one needs geometry: warning polygons are intersected against county
boundaries in EPSG:5070 (Albers equal area), so a county is credited when any
part of it was covered. This is the slowest script in the pipeline by a wide
margin.

**Writes** `03_county_alert_counts.csv` — 3,222 counties × 11 hazard
categories.

### `04_create_poststrat_dataset.R`

Builds the poststratification table: how many adults of each demographic type
live in each county.

Demographics are crossed into 192 cells — 4 age groups × 2 genders × 4 race and
ethnicity groups × 3 education levels × 2 income levels. County totals for age,
gender, race and education come from ACS tables, but the ACS does not publish
the full 192-way cross. Iterative proportional fitting reconciles a state-level
seed built from IPUMS microdata against the county margins, producing cell
counts that agree with every published marginal.

The donor microdata is filtered to adults in households, excluding group
quarters. Alaska, Hawaii and Puerto Rico are excluded throughout.

The script also assembles the county covariate lookup from SVI and NRI. This is
kept separate from the poststratification table rather than joined into it: the
table has 192 rows per county, so joining 607 columns would store every county
value 192 times and turn a 106 MB file into roughly 3.5 GB.

Convergence is checked across all 3,109 counties, and the script halts if any
county fails to converge or has no CWA.

**Writes** `04_county_poststrat_2024.csv` (596,928 rows) and
`04_county_covariates.csv` (3,232 counties × 608 columns).

### `05_create_survey_dataset.R`

Combines the 22 survey waves into one respondent-level file.

The wave files arrive from the `wxsurveys` repository already carrying
`SURVEY_YEAR`, `SURVEY_HAZARD` and `SURVEY_LANGUAGE`, the poststratification
groups, `PERSON_WEIGHT`, and the respondent's location as `ZIP_FIPS`, `ZIP_CWA`
and `ZIP_STATE`. Location is resolved upstream, and the `ZIP_` prefix records
that all three are derived from the respondent's zip rather than from anything
self-reported. This script renames them to `FIPS`, `CWA` and `STATE_NAME`, which
is what `06` and `07` model on.

`WX17` is handled separately: it asked the reception and response batteries on a
1–7 scale where 2018 onward use 1–5, so those columns are dropped rather than
pooled across incompatible scales.

Alert counts and county covariates are joined on, and the twelve composite
scales are built — four reception, four comprehension, four response. Each is
the mean of its items and requires at least two non-missing responses, because a
one-item "scale" is a different quantity from the multi-item mean rather than a
noisier version of it. Reverse coding is decided per scale: `rec_time` is
negatively worded in the severe weather instrument and positively worded in the
other three, so a uniform rule would mis-key it in one or the other.

This script is the single definition of those scales — which items go into each,
and which are reverse coded. It writes that definition out alongside the
responses, so the dashboards can show the questions behind a scale from one
source rather than a second copy.

**Writes** `05_survey_responses.csv` — 35,457 respondents — and
`05_scale_items.csv`, 50 items across 12 scales.


### `06_fit_models.R`

Fits one multilevel model per measure, twenty-four in all.

Each takes the same form: the five poststratification demographics as fixed
effects, a measure of hazard exposure, county social vulnerability, and random
intercepts for CWA, county and survey year.

Hazard exposure is the county and CWA warning-day counts for the relevant
hazard, except for drought, hail and lightning. NWS issues no warning for those
— hail and lightning fold into severe thunderstorm — so those three carry a
FEMA NRI annualized frequency instead, which is county-level only.

NRI frequencies are not added to the models that already have alert counts.
Against their own counts they correlate 0.92 for cold and 0.93 for hurricane,
which is duplication rather than a second measurement.

Social vulnerability enters as the overall SVI percentile rather than its four
themes. Splitting them raises AIC in 21 of 24 models, and Theme 3 (racial and
ethnic minority status) is the only one that reaches significance in more than
a handful — four terms for one signal.

Because county FIPS codes are globally unique, `(1 | CWA) + (1 | FIPS)` is
already a nested hierarchy — the county effect is a deviation from its CWA, not
a competing effect. A county with two respondents shrinks toward its CWA rather
than toward the national mean.

Between 42% and 75% of counties have no respondents, depending on the measure.
Their county effect shrinks to zero, so their estimate is demographic
composition plus the CWA effect plus county covariates. That is real
information, but it is not measurement.

**Writes** `06_models/` — twenty-four `.rds` fit objects.

### `07_predict_estimates.R`

Predicts every cell and aggregates to both geographies.

The area covariates the models need are joined onto the poststratification table
here rather than stored in it. A missing predictor would silently produce `NA`
and drop that county, so the script checks for gaps before predicting.

The survey-year random effect is excluded from prediction, so estimates describe
an average year rather than whichever years a hazard happened to be fielded in.
Counties and CWAs absent from the fit are allowed as new levels.

County estimates are the population-weighted mean over the 192 cells; CWA
estimates are the population-weighted mean over every cell in the CWA. Both come
from the same prediction set, and the script verifies that rebuilding the CWA
figures from county estimates reproduces them to within 1e-8.

The estimates are also joined to boundaries for mapping. County geometry comes
from `cb_2025_us_county_20m`, the same file `03` counts against, so `FIPS` keys
to `GEOID` directly — the NWS county file predates Connecticut's planning
regions and would leave nine holes in the state. CWA geometry is `w_16ap26`.
Both are simplified with `rmapshaper`, which simplifies shared borders once
rather than once per polygon, so adjacent areas meet exactly instead of
leaving slivers between them.

**Writes** `07_county_estimates.csv`, `07_cwa_estimates.csv`, and the two
`_sf.rds` files described under **What it produces**.

### `08_create_variable_reference/`

The codebook: one row per survey hazard per variable, carrying each question as
it was actually asked across all 22 instruments.

Read off the `.docx` instruments by hand rather than parsed. Extraction is
scripted; judgment is not. Instrument errors are recorded in `NOTES.md` and in
the `notes` column, never corrected in the sheet — the sheet records what the
documents say.

**Writes** `variable_reference.csv`. The `.docx` instruments are gitignored, so
a fresh clone has the sheet but not the sources.

### `09_dashboard/`

The dashboard, in two halves behind one entry point.

`09_build_dashboard.R --data` sources `09_statistics.R`, which computes every
number the dashboard shows — weighted response distributions for 915 questions
across thirteen splits, the map values, and one R script per (question, split)
that rebuilds its chart from the released wave files. About fifteen minutes.
Percentages are weighted with `srvyr` on `PERSON_WEIGHT`, which comes from
raking against six ACS margins in the `wxsurveys` repository. **Writes**
`outputs/09_data/`.

Without the flag it assembles the site from that directory and computes no
statistics: every percentage, interval and estimate is carried over verbatim,
so the site cannot disagree with what was computed. Two seconds, which is why
front-end work does not pay for the statistics.

What the front end adds: themes, a landing page, and a knowledge quiz whose
answer keys are derived from the distributions. Every chart carries a
**Download R code** button beside its PDF download. On the map, choosing an
alert history draws it as a second map beside the measure its model was fitted
on, and clicking an area opens an overview sheet — every measure for that area,
each row stretched to its own range — as a panel on the page. Map and chart
downloads are standalone PDF documents, carrying the plot, its legends and the
page's own notes, so a download says what was asked, how it was scored and
where it came from; the sheet has a one-page printable form of its own.

Preview with
`python3 -m http.server --directory "$WXDASH_LOCAL/outputs/09_site"`.

**Writes** `outputs/09_site/`.

---

## Configuration

Data lives outside the repository. Two roots are set once per machine in
`~/.Renviron`:

```
WXDASH_LOCAL="/path/to/local files"
WXSURVEYS_ROOT="/path/to/wxsurveys/"
```

`00_paths.R` derives three directories from these, and stops if either root is
unset or missing:

- `downloads/` — everything listed under **Data sources**
- `outputs/` — everything the pipeline writes
- `survey_files/` — the 22 built wave datasets, read from the `wxsurveys`
  repository rather than downloaded

`.Renviron` is read once at R startup, so restart the session after editing it.
A Census API key is required as `CENSUS_API_KEY`, and an IPUMS key as
`IPUMS_API_KEY` if you rebuild the microdata extract.

**Packages.** Estimation: `tidyverse`, `data.table`, `sf`, `lubridate`,
`readxl`, `here`, `ipumsr`, `tidycensus`, `mipfp`, `lme4`, `psych`,
`rmapshaper`. Dashboards: `shiny`, `DT`, `srvyr`, `ggtext`, `mapgl`,
`viridisLite`, `htmltools`, `jsonlite`.

---

## Running it

```r
source("01_create_county_cwa_crosswalk.R")
source("02_create_cwa_alert_dataset.R")
source("03_create_county_alert_dataset.R")   # slowest by far
source("04_create_poststrat_dataset.R")
source("05_create_survey_dataset.R")
source("06_fit_models.R")
source("07_predict_estimates.R")
```

then, from a shell rather than from R, because it takes a flag:

```sh
Rscript 00_wxdash_2.0/09_dashboard/09_build_dashboard.R --data
```

`01` through `03` depend only on downloaded data and can run in any order. `04`
needs `01`. `05` needs `01` through `04`. `06` needs `05`. `07` needs `02`,
`03`, `04` and `06`. `09 --data` needs `05`, `07` and `08`.

Re-running only the tail is common and safe: if the survey data has not changed,
`06` and `07` can be run on their own.

`06` is not push-button. It prints a summary for each of the 24 models and
expects someone to read them before `07` publishes anything from the fits.

### Adding a survey wave

One line of code: the `waves` vector at the top of `05`. Everything else is
data — the new instrument added to `08` following the procedure there, and a
new `_all` alert year in `downloads/` if the archive has moved.

Then rerun `02` and `03` (only if the alert year is new), `05`, `06`, `07`, and
`09 --data`. Two rough edges: `07` names `04_county_poststrat_2024.csv`
explicitly, so a new poststratification vintage means editing `07`; and the
alert archive spans differ by hazard, which `02` records rather than anything
assuming.

---

## Interpreting the estimates

**The families differ enormously in how much they vary across counties.** County
and CWA random effects account for this share of total variance:

| family | geographic variance | county estimate spread |
|---|---|---|
| risk perception | 2.6 – 29.3% | 1.5 – 3.5 points |
| comprehension | 2.8 – 7.2% | 0.8 – 1.1 points |
| response | 0.9 – 3.1% | 0.3 – 0.6 points |
| reception | 0.1 – 3.0% | 0.3 – 0.6 points |

Risk perception is where places genuinely differ — whether you face snow or
wildfire is largely determined by where you live. Reception and response are
mostly individual, and their county estimates span a third to two thirds of a
point on a 1–5 scale.

**Choose a colour scale deliberately.** Scaling every map to its own range
makes a 0.3-point reception spread look as differentiated as a 3.5-point risk
spread, and the two are not comparable. A shared 1–5 scale keeps measures
comparable to each other. Stretching each measure to its own range instead shows
where places differ on that measure, at the cost of comparability — necessary
for the warning measures, which on a shared scale render as a single flat tone.
The dashboards stretch, and name the range beneath every map so the span is
stated rather than assumed.

**Estimates carry no uncertainty.** Given that most counties contribute no
respondents, the interval around a county estimate is substantially wider than
the spread between counties. Treat the estimates as central tendencies, not as
precise county-level measurements. This matters most for the reception and
response measures, where the spread is smallest.

**Four models report singular fits** — a variance component pinned at zero.
`hu_recep` has no county variance, `ww_resp` no CWA variance, and `fl_subj_comp`
and `risk_surge` no year variance, the last because flood was fielded in only
two years. Fixed effects and predictions remain usable; the boundary variance
components should not be interpreted.

**`ww_resp` is the one to treat cautiously.** Its CWA variance is zero while its
year variance is the largest in the set, so it varies over time rather than
across places — the opposite of what a map is for.

---

## Data quality notes

Several checks are built in and will halt a run rather than produce a quietly
wrong file: IPF convergence across all counties, counties with no CWA, missing
predictors before prediction, and agreement between the county and CWA
estimates.

Two recurring hazards are worth knowing when extending this code.

**Sparse columns and type guessing.** Several NRI hazard columns are empty for
thousands of rows before their first value. R's default 1,000-row type guess
reads them as logical and silently converts every real value to `NA`. Reads of
those files pass `guess_max = Inf`.

**Vintage alignment.** The county boundaries, the CWA crosswalk, the alert
counts and the ACS release must all describe the same set of counties.
Connecticut's 2022 shift from counties to planning regions is the case that
breaks most often.
