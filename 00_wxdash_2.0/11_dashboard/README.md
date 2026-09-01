# 11_dashboard — the production WxDash site

The deployed dashboard, as the eleventh step of the pipeline. Maintained by
Matthew Henderson on top of Joe Ripberger's estimation pipeline (`01`–`10`);
imported 2026-08-14 from the ShinyRails project where it was developed and
verified (its history lives there, commits `933d668`–`2bdff4e`).

## Two sides, kept separate

**The builder** — `11_build_dashboard.R`. Reads what the pipeline already
produced and assembles the deployable site. It computes **no statistics**:
every percentage, confidence interval and estimate is `10`'s output carried
over verbatim, so the production site cannot disagree with the reference
site. (Before this arrangement an independent reimplementation was verified
against `10`'s output cell by cell — 596,031 cells, zero mismatches,
2026-08-14 — and then retired in favor of consuming `10`'s artifact
directly. If the builder ever grows a calculation, that is the moment to
bring the harness back.)

**The site source** — `site/`. The front end as hand-editable files:
`engine.js`, `engine.css`, `index.html`, vendored libraries under
`site/assets/vendor/`, and the state-outline basemap under
`site/assets/geo/`. Iterating on how the dashboard looks or behaves means
editing here and re-running the builder, which takes seconds.

**The output** — `outputs/11_site/` (outside the repo, like every pipeline
output). Plain static files, fully self-contained: no server code, no
third-party requests, every library vendored. Upload the directory to any
web host. Currently deployed at http://c.itation.net/wxdash.

## Data flow

```
09_wxdash_app/data/*            versioned survey + estimate data (six files)
        │
        ▼
10_build_static_site.R          all statistics (srvyr), ~15 min
        │
        ▼
outputs/10_site/data/           915 question files and the R that rebuilds
                                each of their charts, measures, CWA map values
        │
        ▼                       ┌── site/ (front end source)
11_build_dashboard.R  ◄─────────┘   seconds; no statistics
        │
        ▼
outputs/11_site/                the deployable site
```

Running the builder therefore always reflects the latest committed data and
the latest `10` semantics — there is nothing to hand off and no second copy
of any number.

## Machine setup (once)

`~/.Renviron`, per `00_paths.R`:

```
WXDASH_LOCAL="/path/to/local files"        # outputs/ and downloads/ live here
WXSURVEYS_ROOT="/path/to/wxsurveys/"       # see note
```

Note: `00_paths.R` requires `WXSURVEYS_ROOT` to point at an existing
directory even for scripts (`10`, `11`) that never read survey sources. On a
machine without the wxsurveys repository, an empty placeholder directory
works. Candidate cleanup: gate that check to the scripts that need it.

R packages beyond the repo's usual set: `tidyverse`, `sf`, `jsonlite`,
`here`.

## Building and previewing

```
Rscript 00_wxdash_2.0/10_static_site/10_build_static_site.R   # if data or 10 changed (~15 min)
Rscript 00_wxdash_2.0/11_dashboard/11_build_dashboard.R       # always (seconds)
python3 -m http.server --directory "$WXDASH_LOCAL/outputs/11_site"
```

The builder halts loudly rather than producing a quietly wrong site: menu
entries missing from the map file, mapped measures with no question wording,
quiz questions whose data no longer supports their hand-written prose (see
below), and R sources leaking into the output all stop the build.

## Deploying

`outputs/11_site/` is the rsync unit. Current home:

```
rsync -av --delete "$WXDASH_LOCAL/outputs/11_site/" <host>:<docroot>/wxdash/
```

Because the site is static and self-contained with relative URLs and hash
routing, moving to a different host or domain later needs no changes to the
site itself — DNS, a server block, and a certificate. Every asset URL
carries a `?v=<build>` stamp, so long-lived host caches roll over on each
deploy.

One hosting requirement makes that stamping work: `index.html` itself must
be served with `Cache-Control: no-cache` (cache but revalidate — the server
answers 304 via Last-Modified when unchanged). The HTML is the one file that
cannot version-stamp itself; if the host serves it with a long max-age,
browsers keep the old HTML — and therefore the old `?v=` references — and
new deploys are invisible until a hard refresh. Everything else can and
should be cached as long as the host likes. Learned in production 2026-08-18:
the current host's backend sent max-age=1yr on everything, and its nginx now
overrides just the three HTML entry URLs (`/wxdash`, `/wxdash/`,
`/wxdash/index.html`) to no-cache. Any future host needs the equivalent.

## What the builder adds on top of 10's data

- `config.json` — pages, themes (wxdash light / wxops dark / greyscale
  accessibility), the split roster with caption phrases, popover texts, and
  the caption/popup `{token}` templates the front end fills at render time.
- **Place ranks, percentiles and medians** for the map popups, precomputed
  from `10`'s own values with the same formulas `10`'s app.js derives in the
  browser (rank = 1 + count strictly greater; percentile = share strictly
  below).
- **The alert-history pairing** — which alert layer each measure is offered
  against, in `compare_pairing`, transcribed from `06_fit_models.R`. Drought,
  hail and lightning have no NWS alert product — `06` fits them on FEMA NRI
  frequencies — so their pairing is deliberately absent and the page says so.
  Guards halt the build on a measure with no pairing decided, and on a pairing
  naming an alert layer the menu no longer offers.
- **The scan sheet's prose** (`config.map.scan`) — the caution that makes its
  rows readable: each row is stretched to its own range, so equal positions
  mean equal standing and not equal differences. The three widths it quotes
  (widest warning scale, widest risk item, widest alert count) are measured
  off `10`'s values at build time rather than asserted, and the sentence about
  which years the alert counts cover is written from the menu, so a category
  whose coverage changes moves itself into or out of the exception.
- **Test Your Knowledge quiz**: five two-part questions. Prompts are fixed;
  answer keys and reveal numbers are derived from `10`'s distributions at
  build time, so they always agree with what the explorer shows. Prose
  guards halt the build when the data stops supporting a hand-written claim,
  naming the sentence to re-write. A "which group is highest" answer has to
  clear the runner-up by three points (0.2 on a 1–5 mean) — more than the
  confidence intervals the reveal chart draws on the same numbers, so the
  reader can see the answer rather than being told they lost a coin flip. An
  answer that rests on an ordered split instead claims a direction —
  understanding rises with age — and is guarded for the run still going one
  way end to end, which lets adjacent groups sit close together. A share
  that leaves its answer band, or lands between two bands, halts too.
  On answer the front end also charts the real
  distribution straight from the question's `data/q/` file (part 1 national,
  follow-up split by the question's `explore.params.grouping`); parts whose
  prompt compares several survey variables (the Q2/Q4 openers) instead carry
  builder-emitted `chart` rows, since no single question file matches what
  they ask. Every reveal plus the finale recap deep-links into the survey
  explorer, so a reader can exit the quiz into the data at any point.
- Simplified CWA geometry (the full-resolution polygons and per-measure
  properties in `10`'s geojson aren't needed — values ship separately).

## What the front end does with it

- **A question is a stem and an item.** The stem — the sentence every item of
  a battery shares — is set quiet and small above the item, which carries the
  weight; the same two weights in the chart heading and in each row of the
  question table. `10` supplies `question_intro` and `question_text` beside the
  joined `question`, which is still what search, sort and the PDF title use.
- **Every chart carries the R that rebuilds it.** *Download R code* sits beside
  *Download chart (PDF)* on Explore Survey Questions and saves a script that
  rebuilds that question under that split, from the released wave files and
  nothing else. `10` generates one script per (question, split) and checks a
  sample of them against the numbers it is publishing; this builder carries
  them over the way it carries every other number, and stops if there are
  fewer script files than questions. Download rather than an on-page viewer:
  someone who wants the script wants it in their editor.
- **Explore Communities is one page in four parts**: the toolbar, the map (or
  two), the notes that explain what is mapped, and the scan sheet for whichever
  area was clicked. The notes come before the sheet because one area's standing
  means nothing until the reader knows what is being measured.
- **Comparison is two maps.** Choosing an alert layer draws it beside the
  measure at the same size in a contrasting ramp; hovering either map outlines
  the area on both, either tooltip carries both numbers, and the notes below
  split into two columns to match, one explanation per map. Both quantities
  stay on screen together, so the reader compares two pictures rather than
  holding one of them in memory.
- **The scan sheet** — every measure for one County Warning Area, drawn as a
  row stretched to its own range across the 116 areas: a tick per area, the
  median, this area's dot, the range ends, the value and the percentile.
  Selecting a row maps that measure. Values are the ones the popup reads, so
  the two cannot disagree. Clicking an area fills it; `Clear` in its header or
  `Clear selection` in the toolbar empties it, and clearing re-frames the maps
  (a popup auto-pans to stay in view, which shifts an otherwise fixed frame).
  `?place=OUN` deep-links an area. The sheet and its prose share one width, and
  the strips are drawn at the width their column actually got, measured after
  layout.
- **The map surface carries no color of its own** — the choropleth sits
  directly on the card. Polygon borders are therefore a theme token
  (`--map-hairline`): white borders against a white card would lose the shape
  of the palest areas along with their fill. The hover and selection outline is
  chosen against the fill's luma for the same reason, since any single color
  fails at one end of a ramp — grey is invisible on the dark end of the greys
  the comparison map uses.
- **PDF downloads as standalone documents.** The map export and the chart
  export are not screenshots: each is a titled document carrying a subtitle
  (measure and area count, or survey, variable, split and whether intervals are
  shown), the plot, its legends, and the page's own notes underneath — what was
  asked, how it was scored, how the colors are stretched, who ran the survey,
  where the data lives. The notes are read off the rendered page rather than
  re-authored, so a download cannot say something the screen does not. Three
  details keep the layout honest: the notes are measured before the plot is
  placed, so the plot takes what is left rather than pushing prose onto a
  second page; the snapshot is cropped to what was drawn, since the map
  container is a fixed frame the CONUS floats inside; and each legend is
  positioned from the image, so with two maps the second sits under its own map
  rather than under the gap. Short notes run one full-width column, long ones
  two. The scan sheet's own PDF is built separately (`scanPDF`), since it is
  rows rather than a plot: drawn with jsPDF primitives so the type stays
  selectable, and sized so the whole catalog and its footnote land on one page
  (it paginates rather than shrinking if the catalog outgrows that).

## Working in this directory (Matthew, Joe, and our Claudes)

- **GitHub is the master.** Start every session with `git pull`; push when a
  change lands. Both of us (and both Claude sessions) iterate here, so
  expect the directory to have moved since you last saw it — read the diff,
  not your memory of it.
- **Statistics belong upstream.** A change to what is computed goes in
  `01`–`10` (Joe's side); a change to what is shown goes here (`site/` and
  the builder). If `10`'s output schema changes, the builder's guards fail
  loudly — update the reader code and this README in the same commit.
- R code here follows the repo's style guide (`00_wxdash_2.0/CLAUDE.md`).
- The split roster and caption phrases in the builder intentionally mirror
  `10_build_static_site.R`; if a split is added there, add it here too.

## Maintainer notes

- Split groups render in their coded `"(1) "` order, stripped for display —
  matching `app.R`'s design ("the prefixes order the levels upstream; they
  are noise in a legend"). `10`'s app.js sorts the stripped labels
  alphabetically instead, which scrambles ordinal splits like income and
  education; worth aligning someday.
- `engine.js` was forked 2026-08-14 from the ShinyRails shared engine (which
  continues to serve the S3OK dashboard there). This copy is maintained here
  and has diverged deliberately: S3OK-only components are removed, and the
  chart lookup separator is the escape `"\x1F"` rather than a literal NUL
  byte so the file stays text to git and grep.
- The engine renders only precomputed values; the one derivation it performs
  is presentation arithmetic (assembling popup sentences from shipped rank/
  percentile/median). Keep it that way — it is what makes the "cannot
  disagree with 10" property inspectable.
- `index.html` is covered by a `.gitignore` negation (the repo ignores
  rendered `*.html`; this one is source, same exception as
  `10_static_site/`).
