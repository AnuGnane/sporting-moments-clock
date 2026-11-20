"""Tests for the moments build. Run: python3 -m unittest discover pipeline/tests"""
import csv
import datetime as dt
import os
import re
import sys
import tempfile
import unittest
from zoneinfo import ZoneInfo, available_timezones

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.dirname(PIPE)
sys.path.insert(0, PIPE)
import build_data as bd  # noqa: E402

KEYS = {"id", "sport", "caption", "instantUTC", "venueTZ", "venueLocal", "place", "basis", "plusMinusMin", "checked",
        "recordDigits", "recordMark", "recordEvent", "recordLabel", "date", "matchMinute", "matchMinuteLabel", "fame", "fameSub", "sourceURL", "image"}
TIME_KEYS = ("instantUTC", "venueTZ", "venueLocal", "basis")
ZONES = available_timezones()


def parse_utc(s):
    return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


class BuildTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out, cls.stats, cls.log = bd.build(quiet=True, write=False)
        cls.moments = cls.out["moments"]
        cls.by_id = {m["id"]: m for m in cls.moments}
        cls.src = {r["id"]: r for r in bd.read_csv(bd.SRC, required=True)}

    # ------------------------------------------------------------ schema
    def test_top_level(self):
        self.assertEqual(self.out["version"], 1)
        self.assertRegex(self.out["generated"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertGreater(len(self.moments), 1500)

    def test_schema_every_record(self):
        for m in self.moments:
            with self.subTest(id=m["id"]):
                self.assertEqual(set(m), KEYS)
                self.assertRegex(m["id"], r"^(M\d{4}|[A-Z]\d{3,})$")
                self.assertIsInstance(m["sport"], str); self.assertTrue(m["sport"])
                self.assertIsInstance(m["caption"], str); self.assertTrue(m["caption"].strip())
                self.assertIsInstance(m["checked"], bool)
                if m["id"][0] == "X" and m["date"] is None:
                    pass  # famous numbers (career or season totals) may have no single date
                else:
                    self.assertRegex(m["date"] or "", r"^\d{4}-\d\d-\d\d$")
                    dt.date.fromisoformat(m["date"])
                if m["venueLocal"]:
                    self.assertEqual(m["date"], m["venueLocal"][:10])
                self.assertEqual(m["recordLabel"] is not None, m["recordDigits"] is not None, "recordLabel must be set exactly when recordDigits is")
                if m["recordLabel"] is not None:
                    self.assertIsInstance(m["recordLabel"], str); self.assertTrue(m["recordLabel"].strip())
                timed = m["instantUTC"] is not None
                for k in TIME_KEYS:
                    self.assertEqual(m[k] is not None, timed, f"{k} null state differs from instantUTC")
                if timed:
                    self.assertRegex(m["instantUTC"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
                    self.assertRegex(m["venueLocal"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d$")
                    self.assertIn(m["basis"], {"documented", "derived", "scheduled", "estimated"})
                    local = parse_utc(m["instantUTC"]).astimezone(ZoneInfo(m["venueTZ"])).strftime("%Y-%m-%dT%H:%M")
                    self.assertEqual(local, m["venueLocal"], "venueLocal is not the instant in venueTZ")
                else:
                    self.assertIsNone(m["plusMinusMin"])
                    self.assertTrue(m["recordDigits"] or m["matchMinute"] is not None, "untimed entry with nothing to show")
                if m["plusMinusMin"] is not None:
                    self.assertIsInstance(m["plusMinusMin"], int)
                if m["recordDigits"] is not None:
                    self.assertRegex(m["recordDigits"], r"^([01]\d|2[0-3]):[0-5]\d$")
                for k in ("recordMark", "recordEvent", "place", "sourceURL", "matchMinuteLabel"):
                    self.assertTrue(m[k] is None or (isinstance(m[k], str) and m[k].strip()), k)
                if m["matchMinute"] is not None:
                    self.assertIsInstance(m["matchMinute"], int)
                    self.assertTrue(0 <= m["matchMinute"] <= 130)
                    self.assertIsNotNone(m["matchMinuteLabel"])
                    lab = m["matchMinuteLabel"]
                    self.assertEqual(sum(int(x) for x in lab.split("+")), m["matchMinute"], lab)
                else:
                    self.assertIsNone(m["matchMinuteLabel"])
                if m["id"].startswith("M"):
                    expect = 1 if self.src[m["id"]]["set"] == "curated" else 3
                    self.assertEqual(m["fame"], expect)
                elif m["id"][0] in "RX":
                    # R: reviewed athletics records. X: records and famous numbers from other sports.
                    self.assertIn(m["fame"], (2, 4))
                    if m["id"][0] == "R":
                        self.assertEqual(m["sport"], "Athletics")
                    self.assertIsNotNone(m["recordDigits"])
                    self.assertIsNotNone(m["recordMark"])
                else:
                    # Extra researched moments: real time only, ranked just below the original curated set.
                    self.assertEqual(m["fame"], 1)
                    self.assertEqual(m["fameSub"], 1)
                    self.assertIsNotNone(m["instantUTC"])
                    self.assertTrue(m["sourceURL"])
                self.assertIn(m["fameSub"], range(6))
                if m["fame"] == 1 and m["id"].startswith("M"):
                    self.assertEqual(m["fameSub"], 0)
                if m["image"] is not None:
                    self.assertEqual(set(m["image"]), {"file", "credit"})
                    self.assertTrue(os.path.isfile(os.path.join(bd.IMG_DIR, m["image"]["file"])))
                    self.assertTrue(m["image"]["credit"])
                if m["sourceURL"]:
                    self.assertRegex(m["sourceURL"], r"^https?://")

    def test_no_duplicate_ids(self):
        ids = [m["id"] for m in self.moments]
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_venue_tz_is_valid(self):
        for m in self.moments:
            if m["venueTZ"] is not None:
                self.assertIn(m["venueTZ"], ZONES, m["id"])

    def test_harvested_fame_sub(self):
        self.assertEqual(self.by_id["M0378"]["fameSub"], 0)  # 1974 World Cup final
        for m in self.moments:
            if m["id"].startswith("M") and self.src[m["id"]]["set"] == "harvested":
                cap = self.src[m["id"]]["moment"]
                if cap.endswith("semi final") or cap.endswith("semifinal"):
                    self.assertEqual(m["fameSub"], 1, m["id"])
                elif cap.endswith("round of 16"):
                    self.assertEqual(m["fameSub"], 4, m["id"])

    # ------------------------------------------------------------ midnight
    def test_istanbul_shootout_rolls_over(self):
        m = self.by_id["M0069"]
        self.assertEqual(m["venueLocal"], "2005-05-26T00:30")
        self.assertEqual(m["venueTZ"], "Europe/Istanbul")
        self.assertEqual(m["instantUTC"], "2005-05-25T21:30:00Z")

    def test_other_rollovers(self):
        self.assertEqual(self.by_id["M0074"]["venueLocal"], "2008-05-22T01:30")  # Moscow 2008 shootout
        self.assertEqual(self.by_id["M1692"]["venueLocal"], "2022-12-10T00:54")  # harvested, Lusail
        self.assertEqual(self.by_id["M1692"]["venueTZ"], "Asia/Qatar")

    def test_no_rollover_when_date_is_already_local(self):
        self.assertEqual(self.by_id["M0150"]["venueLocal"], "2012-01-30T01:37")  # Djokovic Nadal, date is finish date
        self.assertEqual(self.by_id["M0134"]["venueLocal"], "2019-10-26T16:56")  # haka before kick off
        self.assertEqual(self.by_id["M0205"]["venueLocal"], "1975-10-22T00:34")  # no start: date is the local date

    def test_rollover_rule_unit(self):
        log = []
        local, utc = bd.local_instant("2005-05-25", "21:45", "00:30", "Europe/Istanbul", "X", log)
        self.assertEqual(local.strftime("%Y-%m-%dT%H:%M"), "2005-05-26T00:30")
        local, utc = bd.local_instant("2005-05-25", "21:45", "23:59", "Europe/Istanbul", "X", log)
        self.assertEqual(local.strftime("%Y-%m-%d"), "2005-05-25")
        local, utc = bd.local_instant("2005-05-25", "", "00:30", "Europe/Istanbul", "X", log)
        self.assertEqual(local.strftime("%Y-%m-%d"), "2005-05-25")

    def test_gap_and_fold_are_reported(self):
        log = []
        bd.local_instant("2021-03-28", "", "01:30", "Europe/London", "GAP", log)
        bd.local_instant("2021-10-31", "", "01:30", "Europe/London", "FOLD", log)
        self.assertTrue(any("GAP" in l and "does not exist" in l for l in log))
        self.assertTrue(any("FOLD" in l and "ambiguous" in l for l in log))
        self.assertFalse([l for l in self.log if "does not exist" in l or "ambiguous" in l], "a moment sits in a DST gap or fold")

    # ------------------------------------------------------------ v1 regression
    def test_v1_london_regression(self):
        """The source data, converted without overrides, must reproduce v1 clock_time_london.
        The built output may differ only where time_checks.csv corrected the row."""
        v1 = bd.read_csv(os.path.join(bd.DATA, "archive", "sporting_moments_v1.csv"), required=True)
        self.assertEqual(len(v1), 267)
        checks = bd.by_id(bd.read_csv(os.path.join(bd.OVR, "time_checks.csv")))
        corrected = {k for k, v in checks.items() if v.get("status") == "corrected"}
        raw_bad, built_bad = [], []
        london = ZoneInfo("Europe/London")
        for r in v1:
            mid = "M0" + r["id"][1:]
            s = self.src[mid]
            if not r["clock_time_london"]:
                self.assertFalse(s["clock_time_local"], mid)
                continue
            got = bd.local_instant(s["date"], s["scheduled_start_local"], s["clock_time_local"], s["venue_time_zone"], mid, [])
            self.assertIsNotNone(got, mid)
            if got[1].astimezone(london).strftime("%H:%M") != r["clock_time_london"]:
                raw_bad.append(mid)
            m = self.by_id.get(mid)
            if m is None or m["instantUTC"] is None:
                built_bad.append((mid, "missing"))
            elif parse_utc(m["instantUTC"]).astimezone(london).strftime("%H:%M") != r["clock_time_london"] and mid not in corrected:
                built_bad.append((mid, m["instantUTC"]))
        self.assertEqual(raw_bad, [])
        self.assertEqual(built_bad, [])

    # ------------------------------------------------------------ overrides
    def test_venues_cover_every_harvested_row(self):
        rows = bd.read_csv(os.path.join(bd.OVR, "venues.csv"), required=True)
        ids = [r["id"] for r in rows]
        harvested = {k for k, v in self.src.items() if v["set"] == "harvested"}
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), harvested)
        for r in rows:
            self.assertIn(r["venue_tz"], ZONES, r["id"])
            if r["place"]:
                self.assertNotRegex(r["place"], r"[\[\]{}|<>]", r["id"])

    def test_duplicates_file(self):
        rows = bd.read_csv(os.path.join(bd.OVR, "duplicates.csv")) or []
        for r in rows:
            self.assertEqual(self.src[r["drop_id"]]["set"], "harvested")
            self.assertNotIn(r["drop_id"], self.by_id)
            if not r["keep_id"]:
                # Outright drop of unreliable data: a reason is required.
                self.assertTrue(r["reason"], r["drop_id"])
                continue
            self.assertEqual(self.src[r["keep_id"]]["set"], "curated")
            self.assertIn(r["keep_id"], self.by_id)

    def test_tolerates_missing_overrides(self):
        with tempfile.TemporaryDirectory() as empty:
            out, stats, log = bd.build(quiet=True, write=False, ovr_dir=empty, records_path=os.path.join(empty, "none.csv"))
        ms = out["moments"]
        self.assertGreater(len(ms), 1000)
        # harvested rows have no zone without venues.csv, so they are untimed but still kept by match minute
        self.assertTrue(all(m["venueTZ"] is None for m in ms if m["fame"] == 3))
        self.assertIn("M0069", {m["id"] for m in ms})

    def test_tolerates_partial_overrides(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "time_checks.csv"), "w", encoding="utf-8") as fh:
                fh.write("id,status,scheduled_start_local,clock_time_local,time_basis,uncertainty_minutes,source_url,note\n"
                         "M0069,corrected,,00:31,,,,test\nM0001,unconfirmed,,,,,,\n")
            with open(os.path.join(d, "records.csv"), "w", encoding="utf-8") as fh:
                fh.write("record_id,moment_id,digits_time,mark,athlete,event,date,place,fame,caption,source_url,note\n"
                         "R001,M0172,09:58,9.58,Usain Bolt,Men's 100 metres,2009-08-16,Berlin,2,,,\n"
                         "R002,,03:43,3:43.13,Hicham El Guerrouj,Men's 1500 metres,1998-07-14,Rome,2,El Guerrouj runs 3:43.13,,\n")
            with open(os.path.join(d, "record_labels.csv"), "w", encoding="utf-8") as fh:
                fh.write("id,record_label,record_mark\nM0145,Test record,400 not out\nM0172,,\n")
            out, stats, log = bd.build(quiet=True, write=False, ovr_dir=d, records_path=os.path.join(d, "records.csv"))
        ms = {m["id"]: m for m in out["moments"]}
        self.assertEqual(ms["M0069"]["venueLocal"], "2005-05-26T00:31")
        self.assertTrue(ms["M0069"]["checked"])
        self.assertFalse(ms["M0001"]["checked"])
        self.assertEqual(ms["M0172"]["recordEvent"], "Men's 100 metres")
        self.assertEqual(ms["M0172"]["fame"], 1)
        self.assertEqual(ms["R002"]["fame"], 2)
        self.assertEqual(ms["R002"]["date"], "1998-07-14")
        self.assertEqual(ms["R002"]["recordLabel"], "World record")
        self.assertEqual(ms["M0069"]["date"], "2005-05-26")
        self.assertEqual(ms["M0145"]["recordLabel"], "Test record")
        self.assertEqual(ms["M0145"]["recordMark"], "400 not out")
        self.assertEqual(ms["R002"]["recordDigits"], "03:43")
        self.assertIsNone(ms["R002"]["instantUTC"])

    def test_date_rules(self):
        self.assertEqual(self.by_id["M0069"]["date"], "2005-05-26")  # rolled over
        self.assertEqual(self.by_id["M0193"]["date"], "1976-07-18")  # untimed: source date
        self.assertEqual(self.by_id["M0172"]["recordLabel"] is not None, True)

    def test_report_record_marks_still_missing(self):
        """Reports, does not fail: entries with record digits but no mark after overrides."""
        missing = [m["id"] for m in self.moments if m["recordDigits"] and not m["recordMark"]]
        print(f"\nrecord digits with no recordMark yet: {len(missing)}" + (f": {' '.join(missing)}" if missing else ""))

    # ------------------------------------------------------------ coverage
    def test_coverage_report(self):
        real = {m["venueLocal"][11:16] for m in self.moments if m["venueLocal"]}
        recs = {m["recordDigits"] for m in self.moments if m["recordDigits"]}
        both = real | recs
        print(f"\ncoverage (venue time): real time {len(real)}/1440 ({100 * len(real) / 1440:.1f}%), "
              f"real time plus records {len(both)}/1440 ({100 * len(both) / 1440:.1f}%)")
        print("per hour, real time:     ", [sum(1 for t in real if int(t[:2]) == h) for h in range(24)])
        print("per hour, plus records:  ", [sum(1 for t in both if int(t[:2]) == h) for h in range(24)])
        self.assertGreaterEqual(len(real), 600)
        self.assertGreaterEqual(len(both), len(real))


if __name__ == "__main__":
    unittest.main()
