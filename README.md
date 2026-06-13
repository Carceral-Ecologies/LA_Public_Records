# Exploring LAPD Public-Records Requests

Descriptive analysis of public-records (CPRA) requests filed through the City of
Los Angeles request portal, with a focus on the Los Angeles Police Department:
how long requests take, how they're closed, and how the **public visibility** of
LAPD requests has changed over time.

The repo is a single, self-contained R script (`lapd_charts.R`) that reads one CSV
export and reproduces four figures.

---

## Background

The City of Los Angeles runs a public records portal on NextRequest
(now at <https://recordsrequest.lacity.org/>, formerly `lacity.nextrequest.com`).
Anyone can browse and export the publicly-posted requests by clicking the 'Run Report' button on the top right of the portal. This project works from
a full **"All Open + Closed"** export — **63,961 requests** spanning 2017–2026 —
and asks some basic questions:

- How long do requests take from creation to closure, and how are they closed?
- How does LAPD compare to other departments?
- Has the transparency of LAPD requests changed over time?

The answer to the last question turned out to be the interesting part (see below).

---

## Key findings

> All figures are produced by running the script. The numbers below come from the
> 2026-06-11 export and will shift slightly with a newer export.

**1. LAPD is the single largest source of requests** — roughly **23,000 requests
(~36% of the entire portal)**, more than the Fire Department and City Clerk
combined. It is also slower than average (median ~9 days vs ~7 elsewhere, with a
much heavier tail).

**2. The "Closed – Other" black hole.** Among the LAPD requests that *are* posted
publicly, the share closed with the contentless code **"PD: Closed – Other"** —
which records no disposition at all — grew from **~12% (2018) to ~93% (2024)**.
Over the same period, closures that tell you something collapsed: explicit
**"records released"** fell from ~23% to ~0.2%, and even explicit
**denials/exemptions** fell from ~38% to ~2.5%.


<img width="1260" height="910" alt="lapd_2_outcome_mix_by_year" src="https://github.com/user-attachments/assets/1ebedca9-8916-43ee-905d-dc81a6d08f82" />


**3. Public posting of LAPD requests largely stopped in April 2025.** Monthly
LAPD requests visible in the portal drop from ~250–460/month to single digits
beginning April 2025, while every other department continues normally. LAPD
remains a *participating department* on the portal — so this reflects requests no
longer being **published publicly**, not the department leaving. Requests appear
to still flow into the portal behind its embargo/visibility setting; they're just
no longer visible to the public. Measured against the portal's shared, sequential
request-ID counter, the share of each year's requests that appears publicly falls
from a historical **~70% to ~40% (2025) and ~32% (2026)**, with the drop timed to
April and specific to LAPD.

<img width="1330" height="840" alt="lapd_4_public_vs_withheld" src="https://github.com/user-attachments/assets/988297c2-ab8e-448f-ad57-612b567110ab" />


The overall arc: the requests LAPD *did* publish became progressively
uninformative, and then public posting itself largely stopped — two reductions in
visibility a few years apart.

---

## The data

This repo does **not** redistribute the dataset. To reproduce the charts, export
the data yourself:

1. Go to <https://recordsrequest.lacity.org/>.
2. Export the full request list (the analysis used the **All Open + Closed**
   export--you can check those boxes on the left).
3. Save the CSV. By default the script expects it at:

   ```
   ~/Downloads/requests-2026-06-11_All_Open_Closed.csv
   ```

   To use a different path or filename, edit the `CSV <- ...` line near the top of
   `lapd_charts.R`.

**Schema** (columns used): `Id`, `Created At`, `Request Text`,
`Point of Contact`, `Embargo Ends On Date`, `Closed Date`, `Closure Reasons`,
`URL`. There is **no department field** — department is derived (see *How it
works*).

---

## Requirements

- R (≥ 4.0 recommended)
- R packages: `readr`, `dplyr`, `tidyr`, `stringr`, `lubridate`, `ggplot2`, `scales`

```r
install.packages(c("readr","dplyr","tidyr","stringr","lubridate","ggplot2","scales"))
```

---

## Usage

```bash
# from the repo directory, with the CSV saved in ~/Downloads
Rscript lapd_charts.R
```

…or run it interactively in RStudio. The script prints each plot and writes four
PNGs to the current working directory.

> **Date-parsing note:** the portal timestamps are 12-hour with AM/PM, which needs
> an English/C time locale. The script sets `Sys.setlocale("LC_TIME", "C")`. If
> you're on Windows and dates come back as `NA`, change `"C"` to `"English"`.

---

## Outputs

| File | Figure |
|------|--------|
| `lapd_1_monthly_lapd_vs_other.png` | Monthly posted requests, 2024–2026 — LAPD vs. all other departments (shows the April-2025 collapse, LAPD-specific) |
| `lapd_2_outcome_mix_by_year.png`   | Where LAPD requests end up — outcome mix by year (the "Closed – Other" black hole) |
| `lapd_3_monthly_volume.png`        | LAPD requests visible in the public portal, per month (volume over time) |
| `lapd_4_public_vs_withheld.png`    | Public vs. withheld — share of each year's requests that actually appears publicly |

The two monthly charts include a neutral dashed reference line at April 2025;
delete the `geom_vline(... CUT ...)` lines (or the `CUT` definition) to remove it.

---

## How it works

All derivations happen once, right after the CSV is loaded:

- **Department.** The export has no department column, so each request's department
  is taken from the prefix of its **Closure Reason** (e.g. `PD:`, `LAFD`, `Clerk`,
  `CUPA`, `LASAN`). Requests are consolidated into a single **`LAPD`** category when
  they carry a `PD`, `LAPD`, or `1421` (SB 1421) closure prefix, **or** are handled by
  an `LAPD …` analyst *and* closed under a code that confirms a police disposition.
  (An analyst assignment alone isn't counted — that excludes requests merely routed to
  an LAPD analyst but closed under a generic code, and keeps the count aligned with the
  portal's own LAPD filter. It also correctly retains `LAFD – PD 911 …` codes, which are
  police 911 records despite the `LAFD`-prefixed token.)

- **Closure outcome (LAPD).** Closure reasons are bucketed with a priority-ordered
  keyword classifier into *Records released, No records, Denied/Exempt, Withdrawn,
  Duplicate, Closed-Other,* and *Other/uncoded*.

- **Public vs. withheld.** Portal request IDs are a single sequential counter shared
  across all departments (`YY-NNNNN`). For each filing year, the script compares the
  number of requests actually present in the public export against the highest ID
  reached that year. The gap is the portion of the ID sequence that never appears
  publicly.

  ---
  
  ## Validation

The `LAPD` category is a derived field, so it was checked against ground truth: the
portal's own LAPD department filter returns **23,104** requests, and the rule used here
yields **23,040** — a match to within ~0.3%. (The small residual is still-open requests,
which have no closure code to confirm a disposition.)

Two things are worth knowing if you try to reproduce that check:

- **The CSV export ignores the on-screen department filter.** Filtering the portal to
  "Police Department (LAPD)" and clicking *export* still downloads the **entire**
  all-department list — the filtered and unfiltered exports come out byte-for-byte
  identical. The only per-department ground-truth signal the portal gives you is the
  **result count** shown in the browser, not a filtered file.
- **The public LAPD count is effectively frozen.** Because LAPD stopped publishing new
  requests to the portal around April 2025 (see finding 3), the LAPD-filtered count no
  longer grows day to day — a count read today reflects the same set as an export pulled
  a few days earlier.

---

## Caveats & limitations

This is an exploratory analysis of a public export, not an audit. Please read these
before drawing conclusions:

- **Department is inferred, not given.** The closure-prefix mapping is a heuristic, though it matches the portal's own LAPD count to within ~0.3% (see *Validation*).
- **The export only contains publicly-visible requests.** The "withheld" figures are
  therefore an **inference**, not a direct measurement — by definition, the requests
  being inferred are the ones not in the file.
- **The ID sequence always has gaps.** Historically ~30% of IDs never appear publicly
  (drafts, withdrawn requests, spam). The *finding* is that this gap roughly doubled
  in 2025–26, that the jump is timed to April, and that it is specific to LAPD — not
  that every missing ID is an LAPD request.
- **"Closed – Other" measures labeling, not outcomes.** A rising "Closed – Other"
  share means the public record stopped *describing* what happened; it cannot, on its
  own, distinguish "records stopped being released" from "records were delivered by
  other means and the portal entry was left uncoded."
- **Outcome buckets are keyword-derived** and approximate.
- **Recent-year cohorts are partial** (marked as such in the charts).

---

## Disclaimer

Not affiliated with, endorsed by, or produced by the City of Los Angeles or the
Los Angeles Police Department. Provided for transparency and research purposes.
All data originates from the City's public records portal.

---

## License
Licensed under GPL-3.0 — see LICENSE
