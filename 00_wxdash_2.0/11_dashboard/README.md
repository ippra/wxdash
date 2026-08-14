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
outputs/10_site/data/           915 question files, measures, CWA map values
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

## What the builder adds on top of 10's data

- `config.json` — pages, themes (wxdash light / wxops dark / greyscale
  accessibility), the split roster with caption phrases, popover texts, and
  the caption/popup `{token}` templates the front end fills at render time.
- **Place ranks, percentiles and medians** for the map popups, precomputed
  from `10`'s own values with the same formulas `10`'s app.js derives in the
  browser (rank = 1 + count strictly greater; percentile = share strictly
  below).
- **Alert-history comparison**: the map crossfades a measure against the
  alert-day layer its model is fitted on (`compare_pairing` in the builder,
  transcribed from `06_fit_models.R`). Drought, hail and lightning have no
  NWS alert product — `06` fits them on FEMA NRI frequencies — so their
  pairing is deliberately absent and the page says so.
- **Test Your Knowledge quiz**: five two-part questions. Prompts are fixed;
  answer keys and reveal numbers are derived from `10`'s distributions at
  build time, so they always agree with what the explorer shows. Prose
  guards halt the build when the data stops supporting a hand-written claim
  (a share that left its answer band, a trend like "reliance falls with
  age" that flipped, a tie for a "which is highest" question) and name the
  sentence to re-write.
- Simplified CWA geometry (the full-resolution polygons and per-measure
  properties in `10`'s geojson aren't needed — values ship separately).

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
