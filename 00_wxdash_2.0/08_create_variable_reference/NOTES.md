# Variable reference — things to double check

Built 2026-08-06 from WX24, WX25, TC23, TC25, WW25, FL25 while producing
`variable_reference.csv` (916 rows).

Everything here was found by reading the instruments. Nothing was corrected in
the sheet — the sheet records what the documents say. This file is the list of
things worth a second pair of eyes.

---

## 1. Check these before pooling waves or fitting anything

These change results silently if missed.

- [ ] **`rec_time` reverses direction by hazard.** WX: "Sometimes I am not sure
      what time tornado warnings begin and end for my area" (negative). TC, WW,
      FL: "I receive new information about my location as soon as it is
      available" (positive). `05` already handles this; anything new that
      touches `rec_time` must too.

- [ ] **`resp_more` also flips.** TC: "I usually take some type of protective
      action, but not the most difficult actions" (positive). WW: "I am usually
      too busy or unable to take preparatory or protective actions" (negative).
      Same name, opposite construct — arguably these should never have shared a
      name.

- [ ] **FL uses different names for the reception items.** `rec_most_fl` /
      `rec_miss_fl`, worded "information that **I need**", against TC and WW's
      `rec_most` / `rec_miss`, worded "information that **is available**".
      Different name, different wording, same intended construct. Confirm the
      FL reception scale is meant to be comparable to the others.

- [ ] **TC23's `risk_snow` includes ice.** It reads "Extreme snow (or ice)
      storms". TC25 splits them into `risk_snow` and `risk_ice`. Pooling TC23
      with TC25 on `risk_snow` mixes two different quantities.

- [ ] **Five more TC risk items were relabelled between TC23 and TC25**:
      `risk_wind` ("Extreme high winds" → "High winds"), `risk_rain` ("Extreme
      rain storms" → "Excessive rain"), `risk_heat` ("Extreme heat waves" →
      "Extreme heat"), `risk_drought` ("Droughts" → "Drought"), `risk_cold`
      ("Extreme cold temperatures" → "Extreme cold"). Decide whether these are
      the same item across waves.

- [ ] **`income` and `inc_*` reference different tax years** — 2022 in WX24 and
      TC23, 2024 in WX25, TC25, WW25, FL25.

- [ ] **FL25's `risk_tie` options don't match its own risk items.** The battery
      says "Extreme heat", "Extreme cold", "Tornadoes"; the tie-breaker says
      "Heat waves", "Cold temperatures", "Tornados". Same underlying hazards,
      different labels shown to the respondent.

- [ ] **`risk_tie` means something different in TC23.** There it is shown only
      to respondents who tied their ratings, as a check box with no fixed option
      list. Everywhere else it is asked of everyone with 14 fixed options.

Filter the sheet on `wording_varies == TRUE` for all 33 rows where the wording
moved between instruments.

## 2. Instrument problems worth fixing before the next fielding

- [ ] **`ff_do_conff` (FL25) has no referent.** "How confident are you that your
      actions would protect you from the flash flood?" sits alone on page 38
      with no flash flood scenario anywhere before it. Either a page was cut or
      the question is orphaned. Its answers may be uninterpretable.

- [ ] **`ffd_und` and `ffd_watchwarn_und` (WX24) are swapped.** `ffd_und` asks
      about flash flood watches and warnings; `ffd_watchwarn_und` asks about the
      difference between floods and flash floods. The names describe each
      other's content.

- [ ] **`exf_ex_monitor` (WX24) interpolates the wrong variable.** "How likely
      would you be to continue monitoring the weather forecast over the next
      **[exf_ex_loc]**" — a location where a time period belongs. Respondents
      saw "over the next Location A".

- [ ] **`flood_prob_30yr` (FL25) mismatches its answer format.** The question
      says "Please indicate the probability as a percent between 0 and 100" but
      the answer is collected as one of six bands.

- [ ] **Placeholders written as bare text** so respondents likely saw the
      variable name: `resp_ef_infr_2` (FL25) "keeps people safe from rand_haz";
      `student_evac` (TC25) "If you were at location rand_loc". Both have a
      sibling item that brackets it correctly.

- [ ] **`co_verbal_prob` (WX25) option 3** reads "Somewhat likely as not to
      experience severe weather" — looks like a merge of "somewhat likely" and
      "as likely as not".

- [ ] **`exf_reliable` and `exf_detail` (WX24)** use "Unsure" as the middle
      option where every other certainty item uses "Not sure".

- [ ] **`ar_conf` (FL25)** uses "Not confident" where every other confidence
      item uses "Not very confident".

- [ ] **`ai_*_sup` (WW25)** use "Neither oppose nor support"; TC25's
      `ins_crisis_*` use "Neither support nor oppose".

## 3. Misspelled variable names — do NOT fix

These are in the released data as-is. Correcting them in the instrument would
break the join to existing waves; correcting them in the sheet would make the
sheet wrong.

- [ ] `risk_lignt` — all four hazards
- [ ] `ar_haz_lignt` — FL25, same misspelling
- [ ] `timine_use_no_info` — WX24, should be `timing_`
- [ ] `ff_do_conff` — FL25, doubled f
- [ ] `risk_reduc_dain` — TC25, should be `drain`
- [ ] `ian_rand_leadeaders` — TC23, should be `leaders`

Worth deciding once, and recording the decision, whether new waves keep
perpetuating these or break cleanly with a rename plus a crosswalk.

## 4. Fielding metadata in the document headers

- [ ] **WX25 says it was fielded "October 28-31, 2026"** — a date that has not
      happened yet as of this build. Probably 2025.
- [ ] **WW25 was fielded January 5-8, 2026** despite the WW25 label. If the
      naming convention is the fielding year, this file is misnamed; if it is
      the season, fine.
- [ ] **TC23's header is unfilled**: "Date: XXX; Respondents = XXX; Median Time
      = XX min".

## 5. Cosmetic issues in the documents

Harmless to the data, but they make automated reading harder and they are the
kind of thing that becomes a real problem later.

- [ ] `VERBATIM` misspelled `VERATIM` — TC23 and TC25 (`zip`, `rec_dif_sit`,
      `resp_dif_sit`)
- [ ] `exf_access_no_fnd` (WX24) written with no space after the colon
- [ ] Stray `[%]` after the "No" option of `hisp` (WW25)
- [ ] "learn more about **about** weather hazards" — `ai_weather_haz` (WW25)
- [ ] `snmapund`, `snmapclear`, `snmapconf` (WW25) write the first option as
      "1- Strongly disagree" with no space
- [ ] "co- workers" broken across a space — `rely_wom` and `rely_tie` (WW25)
- [ ] `flood_damage_yrs` (FL25) option spacing: "0 - 5 years ago",
      "6 -10 years ago", "11-15 years ago"
- [ ] TC23 `wx_info4` runs its first response option onto the end of the item
- [ ] TC23 writes page markers with no number, unlike every other instrument
- [ ] `ar_act_*` (FL25) options mix "AR1" and "AR 3" spacing
- [ ] FL25 `last_zip` shows on the condition written `=/ Other`

## 6. Open questions I could not answer from the documents

- [ ] **Where do the instruments authoritatively live?** They are gitignored, so
      a fresh clone cannot rebuild this sheet. Recorded as unresolved in the
      skill.

- [ ] **Are the WX24-only blocks retired or just not repeated?** `tor_eff1`–`8`,
      `rand_svr*`, `rand_otlk*`, the `timing_*` block, `exf_access`/`exf_use`/
      `exf_trust`, and `rq_1`–`rq_10` all appear in WX24 and not WX25. TC25
      still carries `rq_1`–`rq_10`, so the preparedness battery moved rather
      than being dropped.

- [ ] **What are `Kennedy` and `Adams` called in the released TC23 data?** They
      are the two school allocation amounts, capitalised in the instrument,
      which is not the convention anywhere else.

- [ ] **Is `ar_haz_earthquake` (FL25) a deliberate distractor?** An earthquake
      is not a weather hazard, so it reads as an attention or knowledge check,
      but nothing in the instrument says so.

- [ ] **`ign_instruct` (TC23) is an attention check** — respondents are told to
      ignore the question and click a blue dot. Confirm how a pass versus a fail
      is coded in the released data.

- [ ] **The sheet covers 6 instruments; the pipeline uses 22 waves.** WX17–WX23,
      TC20–TC22, TC24, WW21–WW24, and FL24 have no instrument here, so any
      variable unique to those waves is absent from this reference.

## 7. Classification calls worth a second opinion

Every row was classified by reading it. These are the ones where the call could
reasonably go the other way — worth checking before anyone filters on them.

- [ ] **`tor_em_seek_shelt`, `tor_em_shelt_type`, `tor_em_shelt_desc` are marked
      experimental** even though their wording is identical for everyone.
      `tor_em_rare` decided whether the respondent read the definition of a
      tornado EMERGENCY first, so the two halves are not answering the same
      question. Same logic applied nowhere else — if you disagree, these three
      are the rows to change.

- [ ] **The whole AR block after the graphic is marked experimental**
      (`ar_seen`, `ar_conf`, `ar_balance_cat1`–`5`, `ar_act_*`) but the block
      before it is not (`ar_fam`, `ar_haz_*`, `ar_scale_know_*`). The dividing
      line is whether the answer needs the graphic. `ar_act_*` is the closest
      call — the question is about AR categories generally, but those categories
      only exist for the respondent because the graphic introduced them.

- [ ] **`aware_*` is not experimental but `aware_prog`, `eftv_*`, `adopt_*` and
      `resp_ef_infr_*` are.** "Have you heard of green roofs" reads the same for
      everyone; the others interpolate `[rand_dev]`, `[rand_haz]` or
      `[rand_prog]`. Worth confirming the `aware_*` items really were shown with
      identical wording, since their *definitions* did vary with `rand_haz`.

- [ ] **The `home_ins_*` block is `background`, the `ins_crisis_*` block is
      `weather`.** Holding insurance is a household characteristic; views on a
      weather-driven insurance crisis are not. Reasonable people could put the
      whole section either way.

- [ ] **`ww_live`, `ww_trav`, `ww_fam`, `snow_exp_live`, `coast_live` are
      `background`.** They describe where someone lives rather than what they
      think about weather, which puts them with `rural`. But they are winter- and
      coast-specific exposure, so they may belong with the weather items.

- [ ] **`rq_1`–`rq_10` are `weather` with keyword `preparedness`.** They ask
      about general emergency preparedness — disaster kits, meeting places, CPR
      — with no weather mention. Kept as `weather` because preparedness is a
      substantive outcome rather than a background trait.

- [ ] **Numeracy items are `background`.** `cointoss`, `bigbucks`, `acme_pub`,
      `choir`, `fiveside`, `sixside`, `mushroom`, `your_ability`,
      `public_ability` measure a personal capability. But the forecast
      probability items (`incremental_prob`, `cumulative_prob`, `percentile_*`,
      `exceedance_*`, `cond_prob`) are `weather` and tagged
      `comprehension|numeracy`, because they interpret an actual forecast.

- [ ] **`wthr_info_*` is tagged `channels`, not `sources`,** even though its own
      stem says "sources". The items are media types, and WW25/FL25 define
      channels as "tools or avenues of information". Flagging because it means
      the keyword disagrees with the instrument's own wording.
