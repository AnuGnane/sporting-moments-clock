# Research findings

Summary of the feasibility research, done 19 to 20 November 2026.

## Verdict

Feasible, with two changes to the original idea.

1. Real clock time alone cannot fill the day. Sport happens between noon and midnight, and almost nothing happens anywhere between 05:00 and 08:00. A second layer is needed.
2. The screen has to lead with the caption, not the photo. About 3 in 10 moments have a usable free photo and about 1 in 5 have one good enough for full screen.

## Coverage of the 1,440 minutes (venue time)

* First pass, 267 moments: 195 minutes (14%). Longest dead spell 4h 33m.
* Curated only, 340 moments: 249 minutes (17%). Longest dead spell 1h 52m.
* Curated plus harvested, 1,784 moments: 626 minutes (43%). Longest dead spell 1h 52m, from 06:30 to 08:22. Three spells over 30 minutes.
* Plus the athletics records layer: 807 minutes (56%). Longest dead spell 1h 03m, from 05:27 to 06:30.
* Plus every parsed record including swimming (noisy, not shipped): 914 minutes (64%).
* Plus match minute fill at :MM of every hour: 1,440 minutes (100%). All 60 minute slots have at least one moment.

Minutes covered in each hour, 00 to 23, for curated plus harvested:

`10, 4, 8, 3, 6, 0, 1, 0, 3, 7, 12, 11, 25, 39, 28, 38, 52, 55, 55, 53, 58, 59, 58, 41`

With the records layer added:

`10, 20, 40, 25, 45, 7, 1, 19, 28, 13, 16, 11, 31, 39, 28, 39, 52, 55, 55, 55, 59, 59, 58, 42`

For comparison, one count of the literature clock's data found 907 of 1,440 minutes covered by 1,451 quotes.

## Other approaches tested

* **Match minute as elapsed time or as digits** (93rd minute at 09:33 and 21:33): about 150 minutes, because only 75 or so distinct match minutes exist. Not worth building.
* **Date match:** does not pick a minute. 221 of 366 calendar days have at least one moment. Over half fall in May to July. Best used as a tie breaker.
* **London time conversion:** tested in the first pass and rejected because it is not universal. It did fill the night well, which is the case for a viewer time zone mode.

## How reliable the times are

Of 1,784 moments:

* **Derived from kickoff plus match minute: 1,479.** All football. Good to about 2 minutes in the first half, 4 in the second, 6 to 7 in extra time and 8 for shootouts.
* **Scheduled start plus duration: 163.** Athletics finals, marathons, triathlons, horse races. Good to 3 to 6 minutes.
* **Estimated: 65.** US sports, cricket, golf, boxing. 6 to 20 minutes either way.
* **Documented to the minute: 51.** Baseball walk offs, late night tennis finishes, the 1985 snooker final.
* **No time found: 26.**

1,639 of the 1,758 timed rows had their time, or the start time it is worked out from, confirmed against a source. 119 did not.

Even documented times can disagree. Hank Aaron's 715th home run is 9:07pm in one account and 9:10pm in another.

### The football timing model

Clock time is kickoff plus an offset in minutes:

* First half: the match minute.
* Second half: match minute plus first half stoppage (2, or 3 from 2018) plus half time (15, or 10 before 1980).
* First period of extra time: as above plus second half stoppage (4, or 6 from 2018) plus a 5 minute break.
* Second period of extra time: as above plus 3 more.
* End of a shootout: kickoff plus 160 (before 1980), 165, or 174 (from 2018).

This assumes kickoff was on time. One kickoff looks odd and should be rechecked: the 1997 Roberto Carlos free kick is listed at 21:40 on Wikipedia.

## Images

Checked for the first 267 moments only, using the free images embedded in each moment's Wikipedia article.

* The moment itself or its immediate aftermath: 22 (8%).
* The event on the day: 55 (21%).
* Only generic images: 91 (34%).
* Nothing found: 99 (37%).
* 50 of the 77 real photos are 1,600 pixels wide or more.

A direct Commons search for 9 of the "nothing found" moments turned up real event photos for 2, so these numbers are a floor.

The worst era is 1990 to 2004 (7 of 60 moments have a real photo). Older moments have public domain archive photos and newer ones have fan photos. Most licences are CC BY or CC BY SA, which need attribution. Some older photos are public domain only in their country of origin, so check before distributing widely.

## Ideas noted but not built

* **Matches replayed in real time.** The harvest has every goal of about 470 matches, so a match can play through beat by beat (Brazil v Germany 2014 at 17:11, 17:23, 17:24, 17:26, 17:29).
* **Start times as moments.** "15:00, the 1966 final kicks off" is the one kind of time that is exact and well documented.
* **Show a moment anywhere inside its error margin.** Derived times are not exact, so this is honest and widens coverage.

## What was not done

* The Olympic harvest parsed about 100 of 271 event pages. More is available.
* Swimming records were parsed but left out of the records file because relay rows were unreliable.
* No search for prior art beyond one web search, which found no existing sports version of the clock.
* The selection of curated moments is one person's judgement and leans British.
