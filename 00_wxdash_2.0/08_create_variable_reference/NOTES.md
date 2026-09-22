# Variable reference — things to double check

Built 2026-08-06 from WX24, WX25, TC23, TC25, WW25, FL25 while producing
`variable_reference.csv`. Extended 2026-08-07 with WX23, TC24, WW23, WW24 and
FL24; 2026-08-10 with WX20, WX21, WX22, TC20, TC21, TC22; and again 2026-08-10
with WX17, WX18, WX19, WW21 and WW22 — now 1,599 rows across **all twenty-two
instruments**, which is every wave the pipeline pools.

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

- [ ] **`resp_more` flips between hazards *and* within WW.** TC: "I usually take
      some type of protective action, but not the most difficult actions"
      (positive). WW22 onward: "I am usually too busy or unable to take
      preparatory or protective actions" (negative). But WW21 reads "I usually
      take some type of preparatory or protective actions, but not the most
      difficult actions" — the positive TC wording. So the flip is not just
      TC-versus-WW; it happens inside WW between 2021 and 2022. Any WW series on
      `resp_more` that spans 2021 crosses a sign change.

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

- [ ] **`income` and `inc_*` reference different tax years** — see sections 8,
      9 and 10; nine different years across the twenty-two instruments, 2016
      through 2024. Every wave asks about the previous calendar year.

- [ ] **FL25's `risk_tie` options don't match its own risk items.** The battery
      says "Extreme heat", "Extreme cold", "Tornadoes"; the tie-breaker says
      "Heat waves", "Cold temperatures", "Tornados". Same underlying hazards,
      different labels shown to the respondent.

- [ ] **`risk_tie` means something different in TC23.** There it is shown only
      to respondents who tied their ratings, as a check box with no fixed option
      list. Everywhere else it is asked of everyone with 14 fixed options.

Filter the sheet on `wording_varies == TRUE` for all 95 rows where the wording
moved between instruments.

## 2. Instrument problems worth fixing before the next fielding

- [x] **`ff_do_conff` (FL25) has no referent — RESOLVED 2026-08-07.** FL24 sets
      it up with a randomized flash flood scenario (`home_ff_do` if at home,
      `car_ff_do` if driving) and asks the confidence question straight after.
      FL25 kept `ff_do_conff` and dropped both scenarios, so FL25 respondents
      were asked how confident they were about actions they were never asked to
      describe. FL25 answers remain uninterpretable; FL24 answers are fine.

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

- [x] **Where do the instruments authoritatively live?** In the repo, beside
      this file; they are committed, so a clone can rebuild the sheet.
      (2026-09-22)

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

- [x] **The sheet covers all 22 instruments — closed 2026-08-10.** WX17, WX18,
      WX19, WW21 and WW22 were the last five and are now in. Every variable in
      every wave the pipeline pools has a row.

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

- [ ] **`srg_foot_ft`, `srg_foot_in`, `srg_car_ft`, `srg_car_in` are tagged
      `comprehension|response`.** They ask the deepest water it is safe to cross
      on foot or in a car, which is knowledge rather than a report of behaviour,
      so `response` is the arguable half. It was kept because the threshold is
      the protective decision — but if `response` is reserved for what people
      say they do, these four should drop it.

- [ ] **The COVID items are `weather`, not `background`.** `covid_risk` compares
      COVID-19 risk *to* weather risk, and `covid_attention` and `covid_respond`
      ask about weather attention and weather protective action. The subject is
      a pandemic, so someone filtering for weather questions may not expect
      them.

- [ ] **`covid_attention` is not marked reverse worded** even though agreeing
      means paying *less* attention. No pre-existing row on a `certainty_5`
      scale is marked reverse worded — the flag is used only on `agree_5` (22
      rows) and `likelihood_notvery_5` (2). Consistent with the sheet, but the
      item does run against the direction of the construct.

## 8. Added by the 2026-08-07 instruments

- [ ] **`risk_bliz` appears in WW23 and FL24 but nowhere else.** Both carry
      Blizzards in the general risk battery. FL24 uses it *instead of*
      `risk_surge`, so the FL risk battery is not constant across waves.

- [ ] **The general risk battery has three distinct label sets.** WX20–WX23,
      TC20–TC23 and the 2023-era instruments use "Extreme high winds", "Extreme
      heat waves", "Extreme cold temperatures", "Droughts"; WW23 and FL24 use
      "Heat waves" and "Cold temperatures"; the 2024–25 instruments use "High
      winds", "Extreme heat", "Extreme cold", "Drought". 66 rows now flag
      `wording_varies`. Anything pooling the risk battery across waves needs a
      decision here. The 2026-08-10 instruments moved the boundary: the long
      labels run unbroken from 2020 to 2023, so the break is between 2023 and
      2024 rather than anywhere earlier.

- [ ] **`income` now spans six tax years** — 2019 (WX20, TC20), 2020 (WX21,
      TC21), 2021 (WX22, TC22), 2022 (WX23, WX24, TC23, WW23), 2023 (TC24,
      WW24, FL24) and 2024 (WX25, TC25, WW25, FL25).

- [ ] **`wea_rand_img` means two different experiments.** In WX23 its arms are
      hazard/impact/action combinations for a severe thunderstorm; in FL24 they
      are warning/emergency/base/consequence/category versions of a flash flood
      alert. Same variable name, different manipulation, different hazard.

- [ ] **`threedays_source` and `oneday_source` also collide.** WX23 asks them
      against a storm timeline, TC24 against a hurricane timeline.

- [ ] **`slogan_eff` (WW23) skips option 4.** The awareness battery offers five
      slogans, but the effectiveness question lists only four and keeps the code
      5 for the last one — `slogan_4` ("When a snow squall is near, the roads
      should be clear") is never offered as a choice.

- [ ] **`color_diff` (WW24) has an inverted show condition.** It is displayed
      `IF und > 4`, which selects respondents who found the graphic *easy*, then
      tells them "You indicated that understanding this graphic was somewhat
      difficult."

- [ ] **`torn_svr_imp` (WX23) is not monotonic.** Its options run Not at all /
      Slightly / Neutral / Moderately / Extremely important, so "Slightly"
      sits below "Neutral" and "Moderately" above it.

- [ ] **WW24 carries `timing_1` through `timing_65`** as page-level timers.
      They have no colon in the instrument so they are not questions and are not
      in the sheet, but they will be columns in the released data.

- [ ] **WX23 offers a seventh race option** ("Some other race", with
      `race_spec`) that no other instrument does. Race is not a constant
      category set across waves. Superseded by section 9: WX20–WX22 and
      TC20–TC22 offer it too, so the seventh option is the 2020–2023 norm and
      its removal in 2024 is the change.

- [ ] **Two more misspelled variable names, both in the released data.**
      `ian_rand_leadeaders` was already listed; add `color_lignt` (TC24, carries
      the same `lignt` error as `risk_lignt`) and `ff_do_conff` (FL24 and FL25,
      doubled f).

- [ ] **WX23 and WW23 headers are unfilled** — "Date: XXXXX; Respondents = XXXX"
      and "Date: April XX-XX, XXXX". TC24's reads "Date:XXXXX" with no space.
      Four of the eleven instruments now have placeholder fielding metadata.

## 9a. New column: `graphic_shown` (added 2026-08-10)

`TRUE` on 262 of 1,599 rows — the questions whose answer rests on a graphic,
map, chart, forecast image or photograph the respondent was shown. WX 106, TC 72, WW 46, FL 38. It sits beside `experimental` and is deliberately independent of
it: 232 rows are both, 14 are a graphic shown to everyone with nothing
randomized, and the randomized *text* forecasts are the mirror image.

- [ ] **It is not the `graphics` keyword.** The keyword is a topic tag and
      includes questions *about* graphics where none was displayed:
      `hur_map_und`, `tor_map_und`, `tor_radar_und`, `flood_map_und`,
      `flood_map_pref`, `gr_rec` and `wep_rec` are all keyword `graphics` and
      `graphic_shown = FALSE`. Filtering on the keyword to find graphic-based
      questions would pull in seven items that ask about maps in the abstract.

- [ ] **The 14 TC `color_*` items are the only rows that are `graphic_shown`
      without being `experimental`.** Everyone saw the same
      `iowa_cloud_cover_graphic` and the same swatches, so nothing varied — but
      the answers cannot be read without knowing what was on screen. If a
      colour-association analysis ever compares across waves, that graphic is
      part of the instrument.

- [ ] **The meteorologist block is a judgment call.** `met_accurate_*`,
      `met_relevant_*`, `met_follow_*` and `met_choice` are `TRUE` because
      respondents were shown a photograph whose race and gender were
      randomized. It is a portrait, not a weather graphic, so anyone filtering
      `graphic_shown` to find *forecast product* questions will need to exclude
      these four names. Flagging rather than deciding it away.

- [ ] **Text stimuli that read like graphics are `FALSE`**, and worth knowing
      about: WX's `cond_risk_*`, `clim_risk_*`, `rand_cond_format`,
      `rand_clim_format` and `spc_rand`, and WW's `fcst_conf_*`. Each sits under
      a preamble mentioning graphics, or beside a graphic block, but what varied
      was wording.

## 9. Added by the 2026-08-10 instruments (WX20–WX22, TC20–TC22)

These six are older than everything already in the sheet, so they change no
wording: the newest instrument still supplies each item's text. What they add is
123 rows for questions that had been retired before WX23, and a longer run of
coverage for 328 rows that were already here.

**Check before pooling or modelling.**

- [ ] **`rip_und` means two different things in TC20 and TC21.** The name is
      used once for "How would you rate your understanding of rip currents?" on
      a Poor-to-Excellent scale, and again, in the same instrument, for the
      true/false item "In addition to pulling you away from shore, rip currents
      can pull you under the water." TC22 renamed the second one `rip_pull`.
      Whatever the released 2020 and 2021 data hold under `rip_und`, it is not
      the same quantity as `rip_und` from 2022 onward. Check which of the two
      questions the released column actually carries before using it.

- [ ] **`wx_info7` changes referent in TC.** TC20 and TC21 read "Automated text
      or phone notifications"; TC22 onward read "Cell phone applications or
      notifications". Applications and automated notifications are different
      channels, so the reliance series breaks at 2022.

- [ ] **`srg_watch_time` changes its gloss of storm surge.** TC20 and TC21 say
      "a rise in seawater level caused by the storm"; TC22 onward say
      "inundation from rising water moving inland", which is what
      `srg_warn_time` said all along. Respondents in 2020 and 2021 were told a
      different definition inside the question they were answering.

- [ ] **The COVID-19 block is period-bound.** `covid_risk`, `covid_attention`,
      `covid_respond` and (TC only) `covid_hurplans` appear in 2020, 2021 and
      2022 and nowhere after. They are not missing from later waves; they were
      retired. `covid_risk` also asks a comparison — COVID risk *relative to*
      weather risk — so it is not a weather risk measure on its own.

- [ ] **WX22 uses three names twice each.** `rand_clim_format`,
      `cond_risk_conc` and `cond_risk_perc` each appear under two different
      experiments in the same instrument: a ten-arm climatological-framing block
      early on, and a five-arm conditional-damage block later. WX21 carries only
      the six-arm version of `rand_clim_format`. Anyone reading the WX22 columns
      needs to know which experiment a given column belongs to, and the document
      does not say.

**Instrument problems worth fixing before the next fielding.**

- [ ] **`met_follow_2` (TC22) contains two questions.** "Would you follow/watch
      rand_fname_2 if they were a meteorologist in your area? Would you rely on
      Alex during a dangerous weather event in your area?" The second sentence
      is left over from an earlier draft and hard-codes Alex, so half the sample
      — the ones shown Cameron — were asked about a person they had not been
      introduced to. `met_follow_1` has only the first sentence.

- [ ] **`spc_risk_perc` (WX20) is named for the wrong quantity.** It asks "how
      concerned would you be", on a 0-100 concern scale, while its sibling
      `spc_resp_perc` asks about changing plans. The `_risk_perc` suffix
      elsewhere in WX means a likelihood judgment.

- [ ] **`qp_test` option 3 is garbled in all three waves** — "There is a 90%
      chance of that Location A will get approximately get 4 inches of rain."
      The same option is clean in `ss_test` and `ws_test`.

**Cosmetic issues in the documents.**

- [ ] `VERBATIM` misspelled `VERBATIN` throughout the storm surge depth items
      (`srg_foot_ft`, `srg_foot_in`, `srg_car_ft`, `srg_car_in`) in TC20, TC21
      and TC22; `VERATIM` also appears in all six, as it does in TC23 and TC25
- [ ] `ALIGN BOXES HORIZANTALLY` — TC20, TC21, TC22
- [ ] `RANDOMIZE ALERT EXAMPLEE` — TC22 `surge_flood_risk`
- [ ] `one_day` reads "1 days before the storm" — TC20, TC21, TC22
- [ ] `info_nhc` (TC20) reads "How often you get information", missing "do"
- [ ] `rand_surge_2` (TC20, TC21) reads "storm surge Charleston, SC", missing
      "in"
- [ ] `watch_leadtime` (WX21, WX22) reads "Many people want much time as
      possible", missing "as"
- [ ] `spc_rand` (WX20) arms read "AN LEVEL 3 of 5 RISK" and "AN 15% CHANCE" —
      respondents saw the grammatical slip inside the forecast being tested
- [ ] `resp_small_group` and `resp_large_group` read "a small group friends or
      family" in WX20, WX21 and WX22, missing "of"; `rec_phone` and `resp_phone`
      read "If phone is not on" rather than "If your phone is not on"
- [ ] `wx_info4` runs its first response option onto the item line in all six,
      the same defect already recorded for WX23 and TC23
- [ ] `rand_ws` (TC22) is written `rand_ws: rand_ss: 0 = LINK…`, carrying the
      previous block's prefix

**Fielding metadata.**

- [ ] **WX22's header is unfilled** — "Date: April XX-XX, XXXX; Respondents =
      X,XXX". Five of the seventeen instruments now carry placeholder metadata.
      The other five new ones are filled: WX20 Jun 10-19 2020 (3,000), WX21 Jun
      9-17 2021 (1,550), TC20 Jun 29 - Jul 2 2020 (3,000), TC21 Jun 22 - Jul 1
      2021 (1,550), TC22 Jun 30 - Jul 8 2022 (2,082).

**Open questions.**

- [ ] **Do the released 2020–2022 files carry one column or two for WX22's
      duplicated names?** If Qualtrics wrote `cond_risk_conc` once, one of the
      two experiments overwrote the other and the earlier block's answers are
      gone. The instrument cannot answer this; the data can.

- [ ] **Was `ign_instruct` dropped or just unrecorded in WX22?** It appears in
      WX20, WX21, TC20, TC21 and TC22 but not WX22, which is the only wave in
      the group without an attention check.

**Found reviewing the sheet itself, not the instruments.**

- [x] **`ian_rand_program` (TC23) said three arms and listed two — corrected
      2026-08-10 to two.** The instrument reads
      `[ian_rand_program: permanent home | new job]`. Its two siblings,
      `ian_rand_leadeaders` and `ian_rand_population`, do have three arms each,
      and the count had been copied across.

- [x] **Two rows put the option separator inside an option label — corrected
      2026-08-10.** `rand_cond_format` (WX) carried `[rand_cond_perc: 5 | 30]`
      and `amount_format` (TC) carried `[amount_format_rand1: 4 | 12]`, so
      splitting `response_options` on " | " produced ten fields where
      `n_options` said five, and four where it said two. Both now write the
      alternatives with "or" inside the bracket. These were the only two rows in
      the sheet with a pipe inside `response_options`; pipes inside
      `question_intro` and `question_text` are harmless, since those fields are
      never split, and 25 rows have them.

- [ ] **Three WW25 rows carry a count with no labels.** `snmapbest`, `snmaphi`
      and `snmaplow` record `n_options = 31` with `response_options` empty. The
      instrument does list all 31 dropdown entries (0 inches through 30 inches).
      Either the labels belong in the sheet or the count belongs at 0, as it is
      for other dropdowns such as `age`.

- [x] **Seventeen rows added this run used the wrong certainty family —
      corrected 2026-08-10.** They carry the five-point "Definitely no …
      Definitely yes" set but were labelled `yes_no_unsure`, which in this sheet
      means the three-point No / Yes / Not sure set: all 54 pre-existing
      `yes_no_unsure` rows use the three-point version and all 23 pre-existing
      five-point rows use `certainty_5`. Now `certainty_5`: `covid_attention`
      and `covid_respond` in both hazards, the five WX credibility items, the
      six TC meteorologist items and `ai_1_acc` / `ai_2_acc`. Worth knowing that
      the two names do not distinguish scale *length* by their names alone.

- [x] **`met_follow_1` and `met_follow_2` were tagged `channels` — corrected
      2026-08-10 to `trust|sources`.** A meteorologist is a person, which this
      sheet counts as a source; "follow/watch" does not make them a channel.
      Every other person-or-organization row, including their own siblings
      `met_accurate_*` and `met_relevant_*`, is `trust|sources`.

- [ ] **Two rows describe their arms in prose rather than listing them** —
      `spc_scale_level_disp` (`n_options = 0`, "Derived from spc_scale_rand and
      spc_level_rand") and `rand_clim_format` (`n_options = 10`, a sentence
      describing the ten conditions). Both are defensible for a derived or
      crossed randomization, but they are the only two rows where
      `response_options` is not a `value = label` list, so anything parsing that
      column has to tolerate them.

## 10. Added by the second 2026-08-10 batch (WX17, WX18, WX19, WW21, WW22)

The last five instruments, and the oldest. 275 new rows, 327 existing rows
extended. With these the sheet covers every wave `05` pools.

**Check before pooling or modelling.**

- [ ] **WX17 asks the whole reception and response battery on a seven-point
      scale.** `rec_all`, `rec_soon`, `rec_miss`, `rec_area`, `rec_time`,
      `resp_ignore`, `resp_prot`, `resp_busy` and `resp_unsure` run Strongly
      disagree / Disagree / Somewhat disagree / Neither agree nor disagree /
      Somewhat agree / Agree / Strongly agree. From WX18 on they are five-point.
      `05` already drops the WX17 columns rather than pooling them, and this is
      the documentary record of why. WX17 also has no `rec_most`.

- [ ] **`alert_und` is a randomized question in WX17.** Half the sample read
      "the difference between watches, warnings, and advisories" and half "the
      difference between watches and warnings", piped through `alert_type`. From
      WX18 on it is a single fixed question. The WX17 column pools two wordings.

- [ ] **`resp_ignore`, `resp_always` and `resp_more` were all reworded in WW
      between 2021 and 2022** — see section 1 for `resp_more`, which changes
      sign. `resp_always` moves from "I almost always take the preparatory or
      protective actions that officials suggest, even if the actions are
      difficult" to the much weaker "I usually take the preparatory or
      protective actions". `resp_usually` exists only in WW21.

- [ ] **`exp2_chal` and `exp2_use` name different experiments in WW21 and
      WW22.** In WW22 they belong to a single-forecast uncertainty-statement
      experiment; in WW21 they are the Tuesday forecast of a two-day revision
      experiment. The sheet carries WW22's wording and flags `wording_varies`.
      WW21's siblings are `exp2_conf` and `exp2_confme`, which drop the `_1_`
      that their `exp1_1_*` counterparts carry, so `exp2_conf` and `exp1_1_conf`
      are the same question at the same point in the design.

- [ ] **`ice_thrsh` and `snow_thrsh` changed stems.** WW21 asks "What is the
      smallest amount of X that can disrupt your daily activities?"; WW22 onward
      prefix it with "If you were to get X,". Both feed the piped `ice_prob` and
      `snow_prob`, so a threshold series crosses the change.

**Instrument problems worth fixing before the next fielding.**

- [ ] **`watch_time_hours` is shown on the wrong condition in WX17, WX18 and
      WX19.** It is displayed `IF watch_time = 1` — the "less than 1 hour"
      answer — but asks "You indicated that there is 1 to 24 hours...".
      Corrected to `watch_time = 2` from WX20 on. Three waves of this variable
      were collected from the wrong respondents, and `warn_time_hours` beside it
      is correct throughout, so the two are not comparable.

- [ ] **WW21's social-media follow-up has an inverted show condition.** The
      `soc_*` battery is displayed `IF rely_soc < 2` — respondents who said they
      rely on social media *least* — and then tells them "You indicated that you
      rely on social media." The same defect as `color_diff` in WW24.

**Misspelled variable names - do NOT fix.** Add to section 3:

- [ ] `wach_prob_house` - WX17, should be `watch_`; WX18 spells it correctly, so
      the two waves carry the same question under different names
- [ ] `ffd_descrive` - WX19, should be `describe`
- [ ] `aff_ecx` - WX17, should be `exc` for excited

**Mixed-case names.** `oft_FB` (WX17, WX18, WX19) is the only lower-and-upper
name outside TC23's `Kennedy` and `Adams`. Worth confirming what the released
data calls it.

**Cosmetic issues in the documents.**

- [ ] `warn_size` and `watch_size` (WX17) read "the area included an average
      tornado WARNING", missing "in"
- [ ] `rel_4` (WX18) reads "God leaves it up to me make good decisions", missing
      "to"
- [ ] `next_act_night` (WX17) labels option 0 "continue my daily activities" on
      the middle-of-the-night version of the question
- [ ] `probintens` (WX17) option 3 reads "equality important"
- [ ] The `rank_evnt_imp_*` stem (WW21) reads "cause relatively slight
      inconveniences whereas cause significant damage", dropping a word
- [ ] `cost_download` offers a price drawn from 0.99:49.99 but its follow-up
      `cost_download_conf` writes the range as 0.99:99.99

**Open questions.**

- [ ] **Does WX17's `consent` reach the released data?** It is the only wave
      that records consent as a variable, and anyone who answered 0 was routed
      out, so the column should be constant.

- [ ] **`tor_time` and `tor_ssn` (WX17) are slider answers.** The instrument
      says periods appear as the slider moves but does not say what is stored -
      a period label or a number.
