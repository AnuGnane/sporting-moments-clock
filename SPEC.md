# Sporting Moments Clock: build contract

Read `docs/` first. This file is the design contract the build was written against.

## Approved decisions

* Native macOS: a shared SwiftUI core, a screensaver bundle, and a small Mac app with desk clock mode, demo bar and settings. No web view.
* Venue time is the default mode. Viewer time is a setting.
* Default layers: real time plus records. Match minute fill is a setting, off by default.
* Football at 83% is accepted.
* Names on screen keep their real hyphens (Knox-Johnston, Robson-Kanu, Fraser-Pryce). No other dashes in captions. Use a middle dot or comma as a separator.
* Wikimedia Commons images only. Never invent a time, source, author or licence. If unknown, leave blank and say so.
* No tragedies.

## Layout and ownership

Each workstream writes only its own files. Nobody edits the source CSVs in `data/`. Do not run git commands that change state (the orchestrator commits).

```
data/*.csv                         source, read only
data/overrides/venues.csv          pipeline agent
data/overrides/duplicates.csv      pipeline agent
data/overrides/time_checks.csv     time check agent
data/overrides/captions.csv        captions agent
data/overrides/places_curated.csv  captions agent
data/overrides/images.csv          images agent
data/records_reviewed.csv          records agent
pipeline/                          pipeline agent (Python 3.11, standard library only)
build/moments.json                 pipeline output
app/                               Swift agent
app/Resources/images/              images agent writes JPEG files here
research/cache, research/cache2    unpacked Wikipedia cache, read only
```

## Override file formats (UTF 8 CSV, header row, no BOM)

* `venues.csv`: `id,venue_tz,place`. One row per harvested moment. `place` is "Stadium, City".
* `places_curated.csv`: `id,place`. Curated rows (M0001 to M0340). Blank place if not certain.
* `duplicates.csv`: `drop_id,keep_id,reason`. Harvested rows that duplicate a curated row.
* `time_checks.csv`: `id,status,scheduled_start_local,clock_time_local,time_basis,uncertainty_minutes,source_url,note`. `status` is `confirmed`, `corrected` or `unconfirmed`. Blank fields mean no change. `corrected` rows carry the new values.
* `captions.csv`: `id,caption`. Only rows whose caption changes.
* `images.csv`: `id,tier,commons_file,commons_page,author,licence,licence_url,credit_line,width_px,local_file,note`. `local_file` is the file name inside `app/Resources/images/`, blank if not downloaded. Only tier `moment` or `event` rows with a verified author and licence may have a `local_file`.
* `records_reviewed.csv`: `record_id,moment_id,digits_time,mark,athlete,event,date,place,fame,caption,source_url,note`. `record_id` is R001 onward. `moment_id` is the curated moment id when the record is already a curated moment (then the two are merged), else blank. `fame` is 2 for famous records, 4 for lesser ones.

The pipeline must tolerate any override file being absent or partial.

## build/moments.json

```json
{
  "version": 1,
  "generated": "2026-11-20T00:00:00Z",
  "moments": [
    {
      "id": "M0054",
      "sport": "Football",
      "caption": "\"And Solskjaer has won it\"",
      "instantUTC": "1999-05-26T20:35:00Z",
      "venueTZ": "Europe/Madrid",
      "venueLocal": "1999-05-26T22:35",
      "place": "Camp Nou, Barcelona",
      "basis": "derived",
      "plusMinusMin": 4,
      "checked": false,
      "recordDigits": null,
      "recordMark": null,
      "recordEvent": null,
      "matchMinute": 93,
      "matchMinuteLabel": "90+3",
      "fame": 1,
      "fameSub": 0,
      "sourceURL": "https://en.wikipedia.org/wiki/1999_UEFA_Champions_League_final",
      "image": { "file": "M0054.jpg", "credit": "Photo: Author Name · CC BY-SA 2.0 · Wikimedia Commons" }
    }
  ]
}
```

* `instantUTC`, `venueTZ`, `venueLocal`, `basis`, `plusMinusMin` are null for moments with no known clock time (they can still appear through `recordDigits` or `matchMinute`).
* `venueLocal` is the venue wall clock date and time of the instant, after the midnight rollover fix. It is the real local date, so the Istanbul shootout is `2005-05-26T00:30`.
* `basis`: `documented`, `derived`, `scheduled` or `estimated`.
* `fame`: 1 curated moment, 3 harvested goal. Record only entries (ids R001 onward, `sport` "Athletics", no instant unless known) carry 2 or 4. A curated moment that is also a record keeps fame 1 and carries `recordDigits`.
* `fameSub`: tie break inside a fame tier, lower is better. For harvested goals: final 0, semi final 1, third place 2, quarter final 3, round of 16 4, group and other 5.
* `image` is null unless a verified full screen photo (width 1,600 or more, tier moment or event) is bundled.

## Picker rules (Swift core)

Input: the current date, the viewer time zone, the mode (venue or viewer), and layer switches.

1. `HH:mm` is the viewer's wall clock minute.
2. Real time candidates. Venue mode: `venueLocal` time equals `HH:mm`. Viewer mode: `instantUTC` shown in the viewer's zone, using the offset in force at that instant, equals `HH:mm`.
3. Record candidates (if the records layer is on): `recordDigits` equals `HH:mm`.
4. Rank. Real time candidates use their `fame`. A record candidate uses fame 2, or 4 if its own fame is 4. Lower fame wins. Then a moment whose venue month and day equal today's wins. Then lower `fameSub`. Then a daily rotation: sort the remaining ties by id and pick index `dayOfYear mod count`.
5. If there are no candidates and match minute fill is on: moments where `matchMinute mod 60` equals the minute of the hour, ranked the same way.
6. If still nothing, keep the previous card. On launch with no previous card, walk back minute by minute (up to 1,440) and show the first hit.

Card labels:

* Real time: "Exactly" when `basis` is documented, otherwise "Around". In viewer mode add "your time" and show the venue time beside the big time.
* Record: "World record · the mark reads 9.58". Second line shows the event, date and place.
* Fill: "Minute 90+3 · match clock, not time of day".
* A small live clock is always visible in the top right corner.

Visual reference: the approved mockup. Night ground `#0c131f`, text `#f3eee2`, secondary `#8f9bb0`, one accent `#f4b740`. Time in Barlow Condensed Semibold, caption in Newsreader, small text in the system font. Lower left lockup: accent label, huge time, caption, then date and place. Photo full bleed under a dark gradient from the bottom. Credit line bottom right.
