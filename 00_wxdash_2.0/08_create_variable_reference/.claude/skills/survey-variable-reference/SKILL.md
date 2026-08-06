---
name: survey-variable-reference
description: Build or extend a variable reference sheet (codebook) from Severe Weather and Society survey instruments in Word format, indexed by survey hazard. Use when asked to catalogue survey questions, build or update a codebook or variable reference, index questions by hazard, or add a newly fielded instrument to an existing sheet. Triggers on "variable reference", "codebook", "question sheet", "survey instrument", "index the questions", "variable_data_live".
---

# Survey variable reference

Turns IPPRA severe weather survey instruments (`WX24 Instrument.docx`,
`TC25 Instrument.docx`, …) into one CSV: **one row per survey hazard per
variable**, carrying the question as it was actually asked.

Hazard prefixes: `WX` severe weather, `TC` tropical cyclone, `WW` winter
weather, `FL` flood. Where a hazard has more than one instrument, the newest
supplies the wording and the older ones only record coverage.

## Read the instruments. Do not write a parser.

This was attempted with a regex parser first. It reached ~90% and the last 10%
was silently wrong, which is worse than obviously wrong in a reference table.
Extracting text from the `.docx` is mechanical and scripted below. **Deciding
what the text means is not.** Five things defeat pattern matching, and every
instrument contains all five:

| Looks like a question | Actually is |
|---|---|
| `exf_exp_rand`, `d7`, `d5`, `d3`, `0%`, `15%` | a 9-condition randomization assignment table |
| `svr_hail: Large hail` with no options beneath | one box in a check-all-that-apply battery |
| `st_louis: Imagine that it is a Saturday morning…` | scenario text shown before a question, repeated verbatim on the next page with "Remember" for "Imagine" |
| `p_id: A unique identifier for each respondent.` | a codebook appendix entry, never asked of anyone |
| `home_spec: [VERBATIM]` | the "please specify" box belonging to `home` option 6 |

And the wording that gives an item its meaning is often not on the item's line
at all: `risk_tor: Tornadoes` means nothing without the preamble three
paragraphs above it.

TC23 also writes its page markers with no number (`---End Web pg---`) while
every other instrument numbers them, which is exactly the kind of thing that
makes a parser drop 33 real questions into the appendix.

## Procedure

### 1. Extract the text

```sh
python3 <skill>/scripts/extract_instrument_text.py <instrument_dir> <scratch_dir>
```

One `WX25.txt` per instrument, each line prefixed with its document index. The
script handles the two traps that corrupt naive extraction — `mc:Fallback`
duplicating every text box, and a text-box anchor paragraph slurping its
children onto one line. Do not hand-roll this.

### 2. Read each file end to end

Whole file, in order. Not grep, not head. A stem on line 446 governs items
through line 490; you cannot see that from a search hit. ~1,100–1,550 lines per
instrument.

For a hazard with two instruments, read the newest first, then the older one to
find variables it has that the newer dropped and to spot wording changes.

### 3. Write the rows

Newest instrument's order. Then append variables that only the older
instrument has, in its order.

| column | contents |
|---|---|
| `survey_hazard` | `WX`, `TC`, `WW`, `FL` |
| `variable` | name exactly as written, misspellings preserved — `risk_lignt` and `timine_use_no_info` are in the released data that way |
| `question_type` | `question`, `checkbox_item`, `checkbox_parent`, `verbatim_followup`, `randomization`, `vignette`, `dataset_field` |
| `question_intro` | the preamble the item sits under, brackets stripped. Empty when the item is self-contained |
| `question_text` | the item, verbatim, brackets stripped |
| `response_options` | `1 = Label \| 2 = Label`, separated by ` \| ` |
| `n_options` | count, `0` when none |
| `response_scale` | family name, see below |
| `reverse_worded` | `TRUE` when a negatively worded item sits on a directional scale |
| `asked_if` | the show condition, e.g. `warn_hist = 1`, `home = 6` |
| `notes` | programming directives (`RANDOM ORDER`, `VERBATIM`, `DROP-DOWN 1 - 24 hours`) and anything wrong with the instrument |
| `instruments` | `WX24;WX25` |
| `wording_varies` | `TRUE` when intro or item text differs between instruments |

### 4. Verify

```sh
python3 <skill>/scripts/check_coverage.py <sheet.csv> <scratch_dir> WX
```

`missing` must be zero. `extra` is expected and must be only randomization
variables (they appear inside brackets, never as `name:` lines) plus names the
instrument writes with no space after the colon.

Then confirm it parses:

```sh
Rscript -e 'readr::read_csv("<sheet.csv>", guess_max = Inf) |> dplyr::count(question_type)'
```

## Rules that matter

**Verbatim means verbatim.** Do not tidy grammar, expand contractions, or
change punctuation. Commas inside option labels stay commas — that is why the
option separator is ` | ` and not `; `. Genuine semicolons do occur
(`Nothing; continued my daily activities`, `Some College; NO degree`) and must
survive.

**Checkbox items get `0 = Not selected | 1 = Selected`.** The instrument shows
no options for them; that is the coding, and leaving it blank loses it.

**Record instrument errors in `notes`, never fix them.** Found so far: two
variable-name misspellings; `ffd_und` and `ffd_watchwarn_und` whose names are
swapped relative to their content; `exf_ex_monitor` interpolating a location
where a time period belongs; an option reading "Somewhat likely as not".

**`reverse_worded` is about wording, not about any scale's coding.** Cues, from
how these instruments actually write reversals: "Sometimes I miss…", "Sometimes
I am not sure…", "Sometimes I ignore…", "too busy to…", "I don't understand…".

Watch `rec_time`: negative in WX ("Sometimes I am not sure what time tornado
warnings begin and end") and positive in TC/WW/FL ("I receive new information
about my location as soon as it is available"). Same name, opposite direction.
Anything that treats reverse-coding as a property of the variable name rather
than of the hazard's wording is wrong.

**Appendix entries are `dataset_field`.** They describe released columns
(`p_id`, `PERSON_WEIGHT`, `FIPS`), sit after the last page marker, and in WX24
live inside a Word text box. Only WX24 has one so far.

## Response scale families

Reuse these names so the sheet stays consistent across runs. Add a new one only
when no existing family has the same labels; name it for what it measures, with
its length.

`agree_5` · `risk_5` · `quality_5` · `certainty_5` · `confidence_5` ·
`confidence_slightly_5` · `trust_5` · `trust_change_5` · `reliance_5` ·
`concern_5` · `concern_slightly_5` · `likelihood_5` · `likelihood_slightly_5` ·
`use_likelihood_5` · `understanding_5` · `helpfulness_5` · `satisfaction_5` ·
`significance_5` · `surprise_5` · `frequency_5` · `frequency_6` · `gender` ·
`yes_no` · `yes_no_unsure` · `yes_no_maybe` · `yes_no_recall` · `checkbox` ·
`categorical` · `dropdown` · `open_text` · `randomization` · `none`

The `_slightly_` variants exist because both
"Not at all / **Not very** / Somewhat / Very / Extremely" and
"Not at all / **Slightly** / Moderately / Very / Extremely" are in use. They
are different scales; do not merge them.

## Adding a newly fielded instrument

Drop the `.docx` in with the others and re-run from step 1 for that hazard
only. For each variable already in the sheet, compare wording: identical means
append the instrument to `instruments`; different means take the new wording,
keep the old in `notes`, and set `wording_varies` to `TRUE`. Anything new gets
a row. Anything dropped keeps its row with its old `instruments` list — that is
the record of when it stopped being asked.

## Where the instruments come from

`00_wxdash_2.0/08_create_variable_reference/` in the wxdash repo holds the
`.docx` instruments, one per hazard per fielding, named `WX25 Instrument.docx`.

They are **gitignored** — roughly 10 MB of Word binaries, and a binary
committed once cannot be removed from history without a rewrite. A fresh clone
therefore has this skill and `variable_reference.csv` but no instruments, and
they have to be copied in before step 1 will run.

> Canonical source not yet recorded. Fill this in with wherever the instruments
> are authoritatively kept, so they can be re-obtained rather than passed hand
> to hand.

`variable_reference.csv` is the versioned record of what the instruments
contain, and is small enough to belong in git.

## Current state

Done: **WX** (294 rows, from WX24 + WX25, coverage verified).
Not yet done: **TC** (TC23 + TC25), **WW** (WW25), **FL** (FL25) — roughly 600
more rows.
