# wxdash

Severe Weather and Society Dashboard. `00_wxdash_2.0/` holds the current
pipeline, `01`–`07`, from shapefiles through to county and CWA estimates.
`00_wxdash_1.0/` is the retired previous generation, kept for reference; it is
self-contained, including its own `outputs/` that the deployed dashboard reads.

Large inputs and outputs live outside the repo, under Dropbox paths defined at
the top of each script as `downloads`, `outputs` and `location_files`. Note that
`location_files` points into the WX25 project, not this one.

## R style

These rules are applied to all new and edited R code. The scripts in
`00_wxdash_2.0/` (`01`–`07`) are the reference implementation — match them.

Do **not** bulk-reformat anything in `00_wxdash_1.0/`.

### Layout

- Two-space indentation. No tabs anywhere.
- `<-` for assignment, never `=` at statement level.
- Double quotes for strings.
- No trailing whitespace. Every file ends with a newline.
- **One line per call if it fits in 80 columns.** Break onto multiple lines only
  when it does not, and then put one argument per line. `arrange(STATE, CELL)`
  stays on one line; a seven-branch `case_when()` does not.
- In multi-line `case_when()`, align the `~` into a column.

### Pipes

- Native `|>` only. Do not use `%>%`.
- Do not mix the two within a file, which earlier versions of `02` and `03` did.

### Comments

- Section headings are Title Case, `# Heading ` followed by dashes padded to
  **exactly 80 characters**:

  ```r
  # County Totals ----------------------------------------------------------------
  ```

- Comments on their own line start with a capital letter.
- Trailing comments after code start lowercase: `filter(AGE >= 18) # adults only`
- Continuation lines of a multi-line comment stay lowercase.
- Comments beginning with an identifier, function name, acronym or URL keep
  their natural case (`# expand_grid() returns ...`, `# B19001 counts ...`).

### Console output

Do not wrap inspection output in `print()`, `message()` or `cat()`. Write the
bare expression and let R auto-print it, as `05` does:

```r
cor(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
psych::alpha(to_recep_data |> select(-p_id, -to_recep_scale), use = "pairwise.complete.obs")
```

Three exceptions, all present in the current scripts:

- `message()` plus `stop()` for guards that must halt a build — see below.
- `cat()` for progress inside a long loop, as in `02` and `03`.
- `|> print(n = Inf)` at the end of a pipe when a tibble would otherwise be
  truncated, as in `01`.

### Guards over silence

This is the exception to the rule above. Data-quality checks report a one-line
summary and stop on failure, rather than filtering problems away quietly. Use
them in build scripts that write files, not in exploratory sections. Follow the
pattern in `04`:

```r
message("CWA: ", nrow(cwa_check), " CWAs; max proportion error ", ...)

if (nrow(cwa_unmatched) > 0) {
  print(cwa_unmatched)
  stop("Counties above have no CWA - they would be dropped ...")
}
```

Check *before* the step the check protects, not after. Connecticut silently
vanished from the CWA output for exactly this reason.

### Shared data

Build a crosswalk once and read it downstream; do not rebuild it in a second
script. `01` writes `01_county_cwa_crosswalk.csv`; `04` reads it. Two copies
drift — they had different NWS shapefile vintages and only one carried the
Connecticut planning-region fix.

Outputs are named for the script that writes them, so provenance is readable
off the filename: `03_county_alert_counts.csv` came from `03`.

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

Note that BSD `sed` treats `[ \t]` as space, backslash or the letter `t`, so it
silently truncates trailing `t` characters. Use R for whitespace normalisation.
