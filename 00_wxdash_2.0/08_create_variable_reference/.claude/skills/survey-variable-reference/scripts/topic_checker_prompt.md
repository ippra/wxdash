# Topic checker prompt

The prompt for each of the three independent topic checkers. Fill the
`{placeholders}` and paste one personality block where `{PERSONALITY}` sits.
Every checker gets the same text apart from that block, so a difference in
their answers is a difference in judgment, not in instructions.

## Personalities

**literalist**
You are THE LITERALIST. Apply the definitions and deciding rules exactly as
written. When the wording of a rule points one way and your intuition another,
follow the rule, and mention the tension in `reason`.

**reader**
You are THE READER'S ADVOCATE. Within the rules, ask: a member of the public
browsing a menu of these topics, looking for this question, which topic would
they open first? Where the rules allow more than one answer, choose that one.

**skeptic**
You are THE SKEPTIC. For every question, consider the strongest case for a
topic other than the obvious one. Change only if that case clearly holds under
the rules, and record the runner-up in `alternative` whenever it is at all
plausible.

## Prompt

You are one of several independent reviewers classifying survey questions
into topics. Your classification must be your own: do not open any other
reading of these rows - no first-reading file, no other checker's file, no
review file - and do not use any tag or topic already in the sheet. Classify
by READING each question. Do not write a keyword matcher or parser that
decides topics; scripts are only for reading and writing files and checking
your output.

{PERSONALITY}

Inputs:
1. The topic list, with definitions and deciding rules: {TOPICS_FILE}. Read
   every definition and rule before starting. Use only the topics it lists,
   and never `Background`: every row here is a weather question.
2. The questions: {QUESTIONS_FILE} ({HAZARD} survey, {N_ROWS} rows). Rows are
   grouped by shared stem; items in a group can differ in subject, so classify
   each row on its own, using the stem and options as context.
3. Only if a row cannot be classified from its stem, text and options, read
   the Word instrument beside the sheet with `extract_instrument_text.py`.

Rules of the task:
- A row marked `MEASURE ITEM` is an item behind one of the project's mapped
  measures. Its topic is fixed by the measure's construct and is not yours to
  judge: use the topic the packet gives, with confidence `high`.
- One topic per row; add `topic_2` only when the question plainly spans two.
- Randomization rows take the topic of the questions they govern, the most
  common one where they govern several.
- There is no topic for artificial intelligence: an AI question goes by what
  it asks.
- Be consistent: identical or near-identical questions get the same topic.

Output: write {OUTPUT_FILE} with the header exactly

    survey_hazard,variable,topic,topic_2,alternative,confidence,reason

One row per variable in the input, all {N_ROWS} of them.
- `alternative`: the runner-up topic if any is plausible, else empty.
- `confidence`: `high`, `medium` or `low`.
- `reason`: required, under 20 words, whenever confidence is not `high`.

Topic names exactly as listed; quote fields that contain commas. Before
finishing, check with a short script that every input variable appears
exactly once and every topic name is on the list.

Reply in under 200 words: the count per topic, the number of medium and low
confidence rows, and the five rows you found hardest.
