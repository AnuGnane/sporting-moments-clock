# Data dictionary

All files are UTF 8 CSV with a byte order mark, so they open cleanly in Excel.

## data/sporting_moments_v2.csv

1,784 rows. This is the main dataset.

* `id`: M0001 to M1784. Rows M0001 to M0267 are the first pass and match the v1 file in order.
* `set`: `curated` (340 rows, picked by hand) or `harvested` (1,444 rows, parsed from Wikipedia). Prefer curated when both fit a minute.
* `sport`: 26 values. Football is 1,479 rows.
* `moment`: the one line caption.
* `date`: ISO date of the event at the venue. For matches that run past midnight this is still the match date.
* `match_minute_or_game_clock`: free text. "90+3 min", "Penalty shootout", "Round 8, 2:58", or a winning time.
* `match_minute_number`: the match minute as a number, stoppage included (90+3 is 93). Football and some rugby only. Used for the match minute fill.
* `scheduled_start_local`: kickoff or scheduled start, venue time, HH:MM.
* `clock_time_local`: the clock time of the moment at the venue, HH:MM. Blank for 26 rows.
* `venue_time_zone`: IANA name, for example `Europe/London`. Present for curated rows only. Harvested rows are blank and need filling.
* `time_basis`: `documented`, `derived`, `scheduled`, `estimated` or `unknown`. See the findings doc for what each means.
* `uncertainty_minutes`: plus or minus, in minutes.
* `checked_against_source`: `yes` if the time, or the start time it is worked out from, was confirmed against the source. `no` means it came from memory.
* `time_source`: URL.
* `digits_time`: for a few curated rows, a record mark that reads as a clock time.
* `image_tier`: `moment`, `event`, `related only`, `none found`, or `not checked yet` (1,517 rows).
* `image_file`: Wikimedia Commons file name, without the `File:` prefix.
* `image_page`: URL of the Commons file page. Fetch author and licence details from here for the credit line.
* `image_licence`: short licence name.
* `image_width_px`: width of the original.
* `image_full_screen_ok`: `yes` when the tier is moment or event and the width is 1,600 pixels or more.

## data/record_digits_prototype.csv

411 rows. Athletics world records whose mark reads as a clock time. Machine parsed, not reviewed.

* `digits_time`: the clock time the mark reads as, HH:MM. A time of 3:43.13 becomes 03:43, a marathon of 2:01:39 becomes 02:01, a height of 6.25 m becomes 06:25.
* `mark`: the record as written.
* `athlete`: parsed name. Sometimes wrong.
* `event`: event name, with men's or women's where it could be worked out. Sometimes wrong.
* `date`: ISO date. Sometimes wrong.
* `source`: URL of the Wikipedia progression page.
* `status`: always "machine harvested, not reviewed".

## data/archive/sporting_moments_v1.csv

The first 267 moments. Superseded by v2, kept for three columns v2 dropped:

* `time_zone_abbr`: the zone abbreviation on the day, for example BST.
* `clock_time_london`: the same instant in London time.
* `time_note`: one line on how the time was arrived at.

## research/

* `football.txt`, `other.txt`, `other2.txt`: the hand written lists behind the curated rows, pipe separated, with a header comment. `extra_titles.txt` lists extra Wikipedia pages to fetch.
* `scripts/`: the Python used to fetch, check, harvest and build. Written quickly for research and not tidy. `build.py` and `final.py` made v1. `harvest_fb.py`, `harvest_oly.py`, `harvest_rec.py` and `final2.py` made v2 and the records file.
* `wikipedia_cache.tar.gz`: the Wikipedia page text and image metadata the scripts used. Unpack it inside `research/` to get `cache/` and `cache2/`. Each script takes the `research/` folder as its one argument. `final2.py` also expects the v1 CSV there, named `sporting_moments.csv`.
