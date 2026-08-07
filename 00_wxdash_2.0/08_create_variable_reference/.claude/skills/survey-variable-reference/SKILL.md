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
| `experimental` | `TRUE` when the answer depends on a stimulus that varied between respondents — see below |
| `question_focus` | `weather` or `background` |
| `keywords` | one or more content tags, ` \| `-separated, from the fixed list below |
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

### 4. Classify each row — by reading it, never by rule

`experimental`, `question_focus` and `keywords` are decided **by reading the
question**, one row at a time. Do not write a script that assigns them from
name prefixes or regexes over the wording. The whole point of these columns is
the judgment; a rule that gets 90% of them right is the failure mode this skill
exists to avoid. Scripting the *paste-in* of decisions already made is fine —
and safer than retyping, because it cannot alter the verbatim question text.

**`experimental`** — `TRUE` when the answer depends on a stimulus that varied
between respondents, so the item is not a clean population measure:

- randomized wording appears in what the respondent read (`[rand_morn]`,
  `[rand_dev]`, `[exf_exp_rand_d7]`, `[home_ins_rand_perc]`)
- the respondent was shown a graphic, map or image and asked about it
- an upstream randomization changed what they saw first, even where the
  question's own wording is fixed — `tor_em_seek_shelt` reads identically for
  everyone, but half the sample had just read a definition of a tornado
  EMERGENCY and half had not

A **piped answer is not a randomization**. `[exf_adv_look]`, `[ice_thrsh]`,
`[snow_thrsh]`, `[Kennedy]` insert the respondent's own earlier answer; those
stay `FALSE`.

A stimulus everyone saw is a judgment call: flag it `TRUE` if the answer is
unintelligible without the graphic (`ar_balance_cat1`, `snmapbest`), `FALSE` if
the question stands alone (`ar_fam`, `timing_aware`, `exf_aware`).

Filtering `experimental == FALSE` is how the sheet is reduced to comparable
substantive questions. Nothing is deleted — the row stays so the record is
complete.

**`question_focus`** — `weather` when the question is about weather, hazards,
forecasts, warnings or what the respondent does about them. `background` when
it is primarily a demographic or personal characteristic: age, gender, race,
income, education, household size, tenure, where they live, insurance holdings,
numeracy, attention checks, and the codebook appendix fields. Judge the question
itself, not the section it sits in — `home_ins` ("do you have homeowners
insurance") is `background` even though the section is about weather-driven
premiums, while `ins_crisis_aware` is `weather` because it asks about a
weather-driven problem.

**`keywords`** — pick every tag that genuinely applies, usually one or two:

`reception` · `comprehension` · `response` · `risk_perception` · `trust` ·
`sources` · `channels` · `graphics` · `forecast_products` · `preparedness` ·
`mitigation` · `experience` · `relocation` · `insurance` · `recovery` · `ai` ·
`numeracy` · `engagement` · `open_feedback` · `attention_check` ·
`demographics` · `household` · `location` · `admin`

`sources` versus `channels` follows the instruments' own distinction: WW25 and
FL25 split "sources" (organizations and people — NWS, local TV, emergency
managers, family) from "channels" ("tools or avenues of information" — radio,
television, internet, social media, word-of-mouth, phone). Apply that split
everywhere, including where an instrument's own stem calls a list of media
"sources".

`comprehension` covers both self-rated understanding (`*_und`) and objective
knowledge tests (`torwatch`, `warn_size`, `otlks_cat_recall_spc`).
`experience` is for past events the respondent lived through; where they also
report what they did, add `response`.

### 5. Write NOTES.md

Alongside the sheet, write `NOTES.md` — the human-facing list of what needs a
second pair of eyes. **This is required, not optional.** The `notes` column is
a per-row record; `NOTES.md` is the part someone will actually act on.

Every item is a `- [ ]` checkbox so it can be worked through and ticked off.
Group by what to do about it, not by where it was found:

1. **Check before pooling or modelling** — anything that silently changes a
   result. Items that reverse direction between hazards, batteries whose
   wording moved between waves, names that mean different things in different
   instruments, reference years that shifted.
2. **Instrument problems worth fixing before the next fielding** — orphaned
   questions, swapped names, wrong interpolations, answer formats that
   contradict the question.
3. **Misspelled variable names — do NOT fix** — with the reason: they are in
   the released data, so correcting them breaks the join.
4. **Fielding metadata** — impossible dates, unfilled header placeholders,
   labels that disagree with the fielding date.
5. **Cosmetic issues** — typos and spacing that do not affect the data but do
   make the documents harder to read mechanically.
6. **Open questions** — anything the documents could not settle. Say plainly
   that it is unresolved rather than guessing.

Rules: state what the document says and what it should probably say, and never
resolve it silently in the sheet. Carry unticked items forward when a new
instrument is added — a fixed item gets ticked and dated, not deleted, so the
file also records what stopped being a problem.

Start it with the build date and the instruments it covers.

### 6. Verify

```sh
python3 <skill>/scripts/check_coverage.py <sheet.csv> <scratch_dir> WX
```

`missing` must be zero. `extra` is expected and must be only randomization
variables (they appear inside brackets, never as `name:` lines), names the
instrument writes with no space after the colon, names it writes mid-line
(`long_years`, `long_months` in TC23 and WW25), and mixed-case names the
pattern deliberately skips (`Kennedy`, `Adams` in TC23).

Then check that no row has both `question_intro` and `question_text` empty —
**except `randomization` rows**, which legitimately have neither. Their arms
live in `response_options` and their purpose in `notes`.

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

**Record instrument errors in `notes`, never fix them,** and raise the ones that
matter in `NOTES.md`. Found so far: six variable-name misspellings that are in
the released data and so must be preserved; `ffd_und` and `ffd_watchwarn_und`
whose names are swapped relative to their content; `exf_ex_monitor`
interpolating a location where a time period belongs; `ff_do_conff` whose
scenario is missing from the document entirely; and `flood_prob_30yr` asking for
a percent but collecting bands.

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

A family groups scales with the same structure and endpoints. Exact wording is
never lost — it lives verbatim in `response_options` — so a one-word difference
in a middle label is recorded in `notes` rather than spawning a new family.
Reuse these 56 names; add one only when the shape is genuinely new, and name it
for what it measures plus its length.

`agree_5` · `ar_category_6` · `awareness_5` · `benefit_hazard_4` ·
`categorical` · `certainty_5` · `chance_5` · `checkbox` · `checkbox_parent` ·
`concern_5` · `concern_slightly_5` · `confidence_5` · `confidence_slightly_5` ·
`dropdown` · `effectiveness_5` · `endpoint_5` · `evacuation_5` · `extent_5` ·
`familiarity_5` · `frequency_5` · `frequency_6` · `frequency_always_5` ·
`gender` · `helpfulness_5` · `importance_5` · `lead_time_5` · `likelihood_5` ·
`likelihood_neutral_5` · `likelihood_notsure_5` · `likelihood_notvery_5` ·
`likelihood_slightly_5` · `likelihood_slightly_6_nr` · `none` · `open_text` ·
`probability_band_6` · `quality_5` · `randomization` · `ranking` ·
`reliance_5` · `risk_5` · `satisfaction_5` · `severity_5` · `significance_5` ·
`support_5` · `support_tax_5` · `surprise_5` · `true_false_5` · `trust_5` ·
`trust_change_5` · `understanding_5` · `use_likelihood_5` · `worry_5` ·
`yes_no` · `yes_no_maybe` · `yes_no_recall` · `yes_no_unsure`

The five `likelihood_*` families are genuinely different scales and must not be
merged — the instruments use "Very unlikely / Somewhat unlikely / About as
likely as not / ...", "... / Unlikely / **Neutral** / ...", "... / Unlikely /
**Not sure** / ...", "Not at all / **Not very** / Somewhat / ...", and
"Not at all / **Slightly** / Moderately / ...". Same for `confidence_5` versus
`confidence_slightly_5`. `endpoint_5` is for items where only positions 1 and 5
carry labels.

## Adding a newly fielded instrument

Drop the `.docx` in with the others and re-run from step 1 for that hazard
only. For each variable already in the sheet, compare wording: identical means
append the instrument to `instruments`; different means take the new wording,
keep the old in `notes`, and set `wording_varies` to `TRUE`. Anything new gets
a row. Anything dropped keeps its row with its old `instruments` list — that is
the record of when it stopped being asked.

Then update `NOTES.md`: carry unticked items forward, tick and date anything
the new instrument fixed, and add whatever the new instrument introduced.

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
contain, and `NOTES.md` the record of what still needs checking. Both are small
enough to belong in git.

## Current state

All four hazards are built and coverage-verified against the six instruments in
hand — 916 rows, every one classified by reading.

| hazard | rows | experimental | instruments |
|---|---|---|---|
| WX | 294 | 83 | WX24, WX25 |
| TC | 244 | 33 | TC23, TC25 |
| WW | 153 | 18 | WW25 |
| FL | 225 | 55 | FL25 |

189 rows are experimental, 152 are `background`. The substantive comparable set
— `experimental == FALSE & question_focus == "weather"` — is 578 rows.

The next run will be an update, not a build: follow **Adding a newly fielded
instrument** above.
