# wxdash

Severe Weather and Society Dashboard. `00_wxdash_2.0/` holds the current
pipeline; the numbered scripts at the repo root are the previous generation.

Large inputs and outputs live outside the repo, under Dropbox paths defined at
the top of each script as `downloads` and `outputs`.

## R style

These rules are applied to all new and edited R code. The four scripts in
`00_wxdash_2.0/` (`01`–`04`) are the reference implementation — match them.

Do **not** bulk-reformat the legacy scripts at the repo root; bring a file up to
this standard when you are already editing it for another reason.

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

### Guards over silence

Data-quality checks print a one-line summary every run and stop on failure,
rather than filtering problems away quietly. Follow the pattern in `04`:

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
script. `01` writes `county_to_cwa_data.csv`; `04` reads it. Two copies drift —
they had different NWS shapefile vintages and only one carried the Connecticut
planning-region fix.

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
