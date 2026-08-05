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
