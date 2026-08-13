# IPPRA R Style Guide

Conventions for R code at the Institute for Public Policy Research and Analysis.
These apply to all new and edited R, in any project.

Each rule below exists because breaking it cost us something real. Where a rule
looks fussy, the note explains what it prevents.

Do **not** bulk-reformat existing code to match this guide. Bring a file up to
standard when you are already editing it for another reason.

---

## Layout

- Two-space indentation. No tabs anywhere.
- `<-` for assignment, never `=` at statement level.
- Double quotes for strings.
- No trailing whitespace. Every file ends with a newline.
- **One line per call if it fits in 80 columns.** Break onto multiple lines only
  when it does not, and then put one argument per line. `arrange(STATE, CELL)`
  stays on one line; a seven-branch `case_when()` does not.
- In multi-line `case_when()`, align the `~` into a column.
- Prefer a named vector or small object over an aligned continuation, which is
  hard to keep inside 80 columns and produces odd indentation:

  ```r
  # instead of aligning a long vector under an open paren
  drop_columns <- c(
    "OID_", "NRI_ID", "STATE", "STATEABBRV", "STATEFIPS", "COUNTY"
  )
  data |> select(-any_of(drop_columns))
  ```

## Pipes

- Native `|>` only. Do not use `%>%`.
- Do not mix the two within a file.

## Comments

- Section headings are Title Case, `# Heading ` followed by dashes padded to
  **exactly 80 characters**:

  ```r
  # County Totals ----------------------------------------------------------------
  ```

- Comments on their own line start with a capital letter.
- Trailing comments after code start lowercase: `filter(AGE >= 18) # adults`
- Continuation lines of a multi-line comment stay lowercase.
- Comments beginning with an identifier, function name, acronym or URL keep
  their natural case (`# expand_grid() returns ...`, `# B19001 counts ...`).
- Comment the **why**, not the what. A comment that records a decision, a
  rejected alternative, or a number you measured is worth keeping; one that
  restates the code is not.

## Console output

Do not wrap inspection output in `print()`, `message()` or `cat()`. Write the
bare expression and let R auto-print it:

```r
cor(scale_data |> select(-id), use = "pairwise.complete.obs")
psych::alpha(scale_data |> select(-id), use = "pairwise.complete.obs")
```

Three exceptions:

- `message()` plus `stop()` for guards that must halt a build — see below.
- `cat()` for progress inside a long loop.
- `|> print(n = Inf)` at the end of a pipe when a tibble would otherwise be
  truncated.

## Guards over silence

This is the exception to the rule above. Data-quality checks report a one-line
summary and stop on failure, rather than filtering problems away quietly. Use
them in build scripts that write files, not in exploratory sections:

```r
message("IPF: ", sum(!check$OK), " of ", nrow(check), " failed to converge")

if (nrow(unmatched) > 0) {
  print(unmatched)
  stop("Rows above have no match - they would be dropped silently.")
}
```

Check **before** the step the check protects, not after. A whole state once
vanished from a crosswalk output because the check ran downstream of the join
that dropped it.

Guard anything that would produce a quietly wrong file rather than an error:
unmatched join keys, missing predictors before a `predict()` call, proportions
that should sum to one, row counts that should be preserved.

---

## Reading data

R's readers fail quietly in several ways. These have each cost us real data.

**Type guessing on sparse columns.** `readr` guesses column types from the first
1,000 rows. A column that is empty for longer than that is typed `logical`, and
every real value after it silently becomes `NA`. Pass `guess_max = Inf` when a
file may have sparse columns:

```r
read_csv(path, col_types = cols(ID = col_character(), .default = col_guess()),
         guess_max = Inf)
```

This applies to files *we* write too — a sparse column written to CSV re-creates
the trap on every read.

**Malformed rows.** `data.table::fread()` stops at the first row whose field
count does not match the header and returns everything before it, with no error.
One free-text column containing an unquoted comma cost us 89% of a year's data.
`readr::read_csv()` reads such files completely. Prefer it, and if you must use
`fread` for speed, check `nrow()` against the file's line count.

**Type changes when swapping readers.** `fread` and `read_csv` type the same
column differently — a timestamp string comes back as `character` from one and
`POSIXct` from the other. Downstream parsing then returns `NA` for every row and
a filter empties the table. Re-check types after changing a reader.

**Sentinel values.** Public microdata encodes missingness as extreme numbers,
not `NA` — `9999999` for income in IPUMS, `-999` and `999` elsewhere. Handle
them explicitly before any comparison, or they become the largest value in your
data.

**Identifiers as numbers.** FIPS codes, ZIP codes and similar lose leading zeros
the moment they are read as numeric. Read them as `col_character()` and pad if
already damaged.

## Selecting and renaming columns

Name columns explicitly. Do not select or rename by position or range:

```r
# fragile: the range depends on column order, which differs between files
rename_at(vars(COLD:TORN), ~paste0("FIPS_", .))

# robust
hazards <- c("COLD", "FIRE", "FLOOD", "HEAT", "HURR", "ICE", "SNOW", "TORN")
select(GEOID, all_of(hazards)) |>
  rename_with(~paste0("FIPS_", .x), .cols = -GEOID)
```

Two files with the same columns in different orders will silently produce
different results from the same range. Whatever falls outside the range arrives
unprefixed and collides with something else.

Use `all_of()` when the columns must exist and `any_of()` when they may not —
both fail loudly rather than returning fewer columns than intended.

---

## Project structure

**Paths in one file.** Define data locations once, in a `00_paths.R` that every
script sources. Machine-specific roots belong in `~/.Renviron`, which is
gitignored, so the paths file is identical on every machine:

```r
project_root <- Sys.getenv("PROJECT_ROOT")

if (project_root == "") {
  stop("Set PROJECT_ROOT in ~/.Renviron, then restart R.")
}

downloads <- paste0(project_root, "/downloads/")
outputs <- paste0(project_root, "/outputs/")
```

Source it with `here::here()` so it resolves regardless of working directory:

```r
source(here::here("00_paths.R"))
```

`.Renviron` is read once at R startup — restart the session after editing it.

**Never put credentials in a script.** API keys go in `~/.Renviron` and are read
with `Sys.getenv()`. A key committed once stays in git history forever; removing
it from the working tree does not remove it from clones, so a leaked key must be
rotated at the provider.

**Number scripts in run order**, and name each output for the script that wrote
it, so provenance is readable off the filename: `03_county_alert_counts.csv`
came from `03`. The outputs directory then sorts into pipeline order.

**Build shared data once and read it downstream.** Do not rebuild a crosswalk in
a second script. Two copies drift — ours had different source vintages, and only
one carried a needed fix.

**Keep large data out of the repo.** Raw inputs and derived outputs live outside
git. Only code and small reference tables are versioned. A large file committed
once cannot be removed from history without a rewrite.

**Every input needs a recorded source.** A URL in a comment or a README table.
An input nothing can regenerate is a liability: we found files feeding live
models that no script produced and no one could rebuild.

**Watch vintage alignment.** Geographies, crosswalks and reference data must
describe the same universe. Connecticut's 2022 shift from counties to planning
regions breaks joins built against either vintage. FEMA's National Risk Index
changed methodology between releases — the same field correlates 0.61 across
them, so "newer" was not a refresh but a different measurement.

---

## Statistical work

- Build composite scales with an explicit minimum-item rule, and count the same
  items you average. A one-item "scale" is not a noisy version of the full
  scale; it is a different quantity, because item means differ.
- Compute reliability **after** reverse-coding, and check that all inter-item
  correlations are positive. A negative one means an item is mis-keyed or does
  not belong.
- Check `alpha` if-dropped before trusting a scale. An item that raises alpha
  when removed is measuring something else.
- Check collinearity before adding a second measure of the same construct. Two
  predictors correlating above about 0.85 give unstable coefficients and no new
  information.
- Report what you measured, not what you assume. Correlations, variance shares
  and sample costs are cheap to compute and settle arguments that intuition
  does not.

## Verifying a restyle

Whitespace-only changes can be proved rather than asserted — compare deparsed
parse trees before and after:

```r
tree <- function(path) {
  p <- parse(path, keep.source = FALSE)
  unlist(lapply(p, function(e) paste(deparse(e), collapse = " ")))
}
identical(tree(before), tree(after))
```

Note that a pipe conversion is **not** whitespace-only: `|>` resolves at parse
time to `f(x)` while `%>%` remains a call, so the trees differ legitimately.

Two shell traps when editing R in bulk:

- BSD `sed` treats `[ \t]` as space, backslash or the letter `t`, so it silently
  truncates trailing `t` characters. Use R for whitespace normalisation.
- Escapes like `\d`, `\.` and `\(` do not survive `Rscript -e` through a shell.
  Write the script to a file and run it.

---

# This repository: wxdash 2.0

Everything above is general IPPRA style. This section is specific to
`00_wxdash_2.0` and is the orientation a new session needs before touching
anything.

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
response distributions; **Map Survey Estimates** maps the 24 CWA estimates from
`07` on MapLibre, with a printable overview sheet per area. It reads four files
from `data/`, all written by `data/09_create_dashboard_data.R`: the questions,
the responses, the CWA geometry and the questions behind each mapped measure.
Those paths are **relative** on purpose: a deployed Shiny app is a copy of its
own directory, with no `00_paths.R` and no `WXDASH_LOCAL` on the server. That
is the one place this pipeline departs from "every script writes to
`outputs/`".

`data/` is gitignored — derived, and the `.rds` would otherwise land in git
history on every rebuild. The one exception is
`data/09_create_dashboard_data.R`, negated in the app's `.gitignore` because it
is source, not output. That negation needs `data/*` rather than `data/`: with a
trailing slash git will not descend into the directory, so a negation inside it
never matches. A fresh clone must still run `09` before the app starts, which is
what the guard at the top of `app.R` says.

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

**The measure list, splits, palettes and phrasing are declared three times** —
in `app.R`, in `10_build_static_site.R` and in `10_static_site/app.js`, across
two languages. Adding a measure means three edits and nothing catches a missed
one. This is the largest maintenance cost in the repo; the fix is for the build
script to write that list to JSON and both front ends to read it.

Neither dashboard was ever verified in a browser from a session — there is no
headless browser on the workstation. Checks are `testServer`, serving the site
locally and reading the payloads. Ask before claiming anything about how it
looks.
