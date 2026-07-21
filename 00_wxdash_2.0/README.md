# wxdash 2.0 — Base Dataset Pipeline

Data-preparation pipeline for the **Severe Weather and Society Dashboard (wxdash 2.0)**.
The scripts in this folder build a set of "base" datasets that are joined together into a
single respondent-level survey file (`base_survey_data.csv`) used by the dashboard and
downstream analysis.

This README is the working record of **what each script does** and **where the project
stands**. Update the [Status & Progress](#status--progress) section as work moves forward.

---

## How the pipeline fits together

Each script reads raw inputs from a local `downloads/` folder and writes derived tables to
a local `outputs/` folder (both live in Dropbox — see [Setup](#setup)). Later scripts consume
the outputs of earlier ones. Script `05` is the final join that produces the master file.

```
                       ┌─────────────────────────────┐
 raw shapefiles ─────► │ 01  county → CWA crosswalk   │ ─► county_to_cwa_data.csv ─┐
                       └─────────────────────────────┘                            │
 IEM watch/warn ─────► ┌─────────────────────────────┐                            │
   (CSV)               │ 02  CWA alert counts         │ ─► base_cwa_alert_data.csv ┤
                       └─────────────────────────────┘                            │
 IEM watch/warn ─────► ┌─────────────────────────────┐                            │
   (shapefiles)        │ 03  county alert counts      │ ─► base_county_alert_data.csv
                       └─────────────────────────────┘                            │
 Census + SVI + ─────► ┌─────────────────────────────┐   base_cwa_census_data.csv │
 storm events          │ 04  census / SVI / events    │ ─► base_county_census_data.csv
                       └─────────────────────────────┘                            │
 Survey CSVs + ──────► ┌─────────────────────────────┐                            │
 ZIP crosswalk +       │ 05  base survey dataset      │ ◄──────────────────────────┘
 risk + all above      │     (final join + IRT scores)│ ─► base_survey_data.csv
                       └─────────────────────────────┘
```

---

## Scripts

### `01_create_county_to_cwa_dataset.R`
Builds the **county → NWS County Warning Area (CWA)** crosswalk that ties respondents and
county data to a forecast office.

- **Inputs:** US county shapefile (`cb_2023_us_county_500k`); NWS CWA/county shapefile (`c_18mr25`).
- **Logic:** keeps the first CWA for counties spanning multiple CWAs; hard-codes fixes for
  Florida Keys (`12087` → `KEY`), Connecticut planning regions, and Hawaii's Kalawao County.
- **Output:** `county_to_cwa_data.csv`

### `02_create_base_cwa_storm_alert_dataset.R`
Counts, per **CWA**, the number of **days** with at least one watch/warning issued, by hazard
category.

- **Inputs:** Iowa Environmental Mesonet (IEM) archived watch/warning **CSVs** (files matching `*_all`).
  Source: <https://mesonet.agron.iastate.edu/request/gis/watchwarn.phtml>
- **Logic:** maps VTEC `PHENOM` codes to categories (HEAT, COLD, SNOW, ICE, TORN, WIND, FLOOD,
  HURR, FIRE); dedupes to one row per WFO/category/day; pivots to wide counts. Reads the CSV
  attributes (not the ~1 GB shapefile) for speed.
- **Output:** `base_cwa_alert_data.csv`

### `03_create_base_county_storm_alert_dataset.R`
Same idea as `02` but at the **county (FIPS)** level, using the polygon geometry to intersect
warnings with counties.

- **Inputs:** IEM watch/warning **shapefiles** (`*_all`); US county shapefile (`cb_2023_us_county_20m`).
- **Logic:** spatially intersects each warning polygon with counties (`st_intersects`), maps
  `PHENOM` → category, dedupes to county/category/day, counts, and pivots wide. Processes one
  year-file at a time with `gc()` to manage memory.
- **Output:** `base_county_alert_data.csv`

### `04_create_base_census_dataset.R`
Builds **demographic, storm-event, and social-vulnerability** context at both county and CWA
levels.

- **Inputs:** Census population estimates (`cc-est2021-all.csv`, `cc-est2022-all.csv`, downloaded
  over HTTP); CDC/ATSDR **SVI 2020** (`SVI_2020_US_county.csv`); NWS county shapefile (`c_03mr20`);
  **storm-event tables** (`base_cwa_storm_data.csv`, `base_county_storm_data.csv`).
- **Logic:** collapses population into 36 demographic cells (sex × 3 age groups × Hispanic ×
  3 race groups), computes cell proportions; joins storm events; population-weights county SVI
  up to CWA level. Excludes Alaska & Hawaii from census. Prefixes CWA/county columns.
- **Outputs:** `base_cwa_census_data.csv`, `base_county_census_data.csv`
- ⚠️ **Dependency gap:** reads `base_cwa_storm_data.csv` / `base_county_storm_data.csv`, which
  **no script in this folder produces** (see [Known gaps](#known-gaps--todos)).

### `05_create_base_survey_dataset.R`
The **master join**: assembles all survey waves and enriches each respondent with geography,
alerts, risk, census, and IRT-based latent measures.

- **Inputs:** weighted survey CSVs by hazard/year:
  - **WX** (severe weather / tornado) 2017–2025
  - **TC** (tropical cyclone) 2020–2025
  - **WW** (winter weather) 2021–2025
  - **FL** (flood) 2024–2025
  - HUD ZIP→county crosswalk (`ZIP_COUNTY_032025.xlsx`); outputs of `01`–`04`; FEMA risk tables
    (`base_cwa_risk_data.csv`, `base_county_risk_data.csv`).
- **Logic:** stacks all waves (`rbindlist(fill = TRUE)`, with per-wave type/scale fixes);
  geocodes ZIP → FIPS (highest residential ratio) → CWA; recodes demographics; left-joins alert,
  FEMA risk, and census/SVI tables; fits IRT models (`ltm`/`grm`) for reception, subjective &
  objective comprehension, response, trust, readiness, and efficacy, joining factor scores by `p_id`.
- **Output:** `base_survey_data.csv`
- ⚠️ **Dependency gap:** reads `base_cwa_risk_data.csv` / `base_county_risk_data.csv`, which
  **no script in this folder produces** (see [Known gaps](#known-gaps--todos)).

---

## Setup

Each script defines two local paths at the top — set these to your machine:

```r
downloads <- ".../Severe Weather and Society Dashboard/local files/downloads/"
outputs   <- ".../Severe Weather and Society Dashboard/local files/outputs/"
```

**Note:** scripts `01`–`04` currently point at `/Users/josephripberger/Dropbox (Univ. of Oklahoma)/...`
while `05` points at `/Users/jtr/Library/CloudStorage/Dropbox-Univ.ofOklahoma/...`. These should be
reconciled (ideally to a single config sourced by all scripts).

**Packages:** `tidyverse`, `data.table`, `sf`, `lubridate`, `readxl`, `car`, `ltm`, `tigris`.

**Run order:** `01` → `02` → `03` → `04` → `05` (plus the missing storm/risk scripts before `04`/`05`).

---

## Data dependency map

| Script | Reads (key derived inputs) | Writes |
|--------|----------------------------|--------|
| 01 | shapefiles only | `county_to_cwa_data.csv` |
| 02 | IEM watch/warn CSVs | `base_cwa_alert_data.csv` |
| 03 | IEM watch/warn shapefiles, county shp | `base_county_alert_data.csv` |
| 04 | Census/SVI, `base_*_storm_data.csv` ⚠️ | `base_cwa_census_data.csv`, `base_county_census_data.csv` |
| 05 | survey CSVs, `county_to_cwa_data.csv`, `base_*_alert_data.csv`, `base_*_census_data.csv`, `base_*_risk_data.csv` ⚠️ | `base_survey_data.csv` |

---

## Known gaps / TODOs

- [ ] **Missing storm-event script** — `04` consumes `base_cwa_storm_data.csv` /
      `base_county_storm_data.csv`; the script that builds these is not in this folder.
- [ ] **Missing FEMA risk script** — `05` consumes `base_cwa_risk_data.csv` /
      `base_county_risk_data.csv`; the script that builds these is not in this folder.
- [ ] **Reconcile `downloads`/`outputs` paths** across `01`–`05` (currently two different users/roots).
- [ ] **`05` line 1:** `library(ltm)` is commented out, but `grm()` / `ltm()` are called bare —
      confirm `ltm` is attached or uncomment.
- [ ] **`05` lines 55 & 62:** likely copy-paste bug — `rand_eve = as.character(rand_aft)` sets
      `rand_eve` from `rand_aft` (should be `rand_eve`).
- [ ] **`04` SVI:** consider updating hard-coded fixes / revisit RIO ARRIBA (35039) imputation
      (currently commented out).

---

## Status & Progress

Update this as the project moves. Suggested convention: ✅ done · 🚧 in progress · ⬜ not started.

| Component | Status | Notes |
|-----------|--------|-------|
| 01 county → CWA crosswalk | ✅ | Stable. |
| 02 CWA alert counts | ✅ | Stable. |
| 03 county alert counts | ✅ | Stable. |
| 04 census / SVI / events | 🚧 | Depends on missing storm script; SVI still on 2020 data. |
| 05 base survey dataset | 🚧 | Added 2025 waves (WX/TC/WW/FL); depends on missing risk script. |
| Storm-event script | ⬜ | Not in repo. |
| FEMA risk script | ⬜ | Not in repo. |

### Changelog
- **2026-07-20** — Added 2025 survey waves (WX25, TC25, WW25, FL25) to script `05`. Created this README.
