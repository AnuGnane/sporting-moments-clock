"""Build build/moments.json from the source CSVs and the override files.

Usage: python3 pipeline/build_data.py [--quiet]

Reads (all overrides optional, partial files are fine):
  data/sporting_moments_v2.csv          source, read only
  data/overrides/venues.csv             zone and place for harvested rows
  data/overrides/duplicates.csv         harvested rows to drop
  data/overrides/time_checks.csv        confirmed, corrected, unconfirmed
  data/overrides/captions.csv           caption replacements
  data/overrides/places_curated.csv     place for curated rows
  data/overrides/images.csv             bundled photos
  data/records_reviewed.csv             reviewed world records
  data/overrides/record_labels.csv      record label and mark per id

Writes build/moments.json, and copies it to app/Resources/moments.json when
app/Resources exists. The format is the contract in SPEC.md.
"""
import csv
import datetime as dt
import glob
import json
import os
import re
import shutil
import sys
from zoneinfo import ZoneInfo, available_timezones

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OVR = os.path.join(DATA, "overrides")
SRC = os.path.join(DATA, "sporting_moments_v2.csv")
OUT = os.path.join(ROOT, "build", "moments.json")
APP_RES = os.path.join(ROOT, "app", "Resources")
IMG_DIR = os.path.join(APP_RES, "images")

BASES = {"documented", "derived", "scheduled", "estimated"}

# Rows where clock_time_local is earlier than scheduled_start_local but the
# date column is already the local date of the moment, so no rollover applies.
# Checked by hand against the captions and the known event dates.
NO_ROLLOVER = {
    "M0134": "haka before kick off: 16:56 is before the 17:00 start, same day",
    "M0150": "date 2012-01-30 is the finish date; the final began 29 January",
    "M0240": "Le Mans: date 2016-06-19 is race day two; the 15:00 start was the day before",
    "M0284": "Doha marathon: started 23:59 on 27 September, date 28 September is the finish date",
    "M0285": "Doha marathon: started 23:59 on 5 October, date 6 October is the finish date",
    "M0298": "UTMB: started 18:00 on 26 August, date 27 August is the finish date",
    "M0299": "UTMB: started 18:00 on 1 September, date 2 September is the finish date",
    "M0325": "London 2012 ceremony began 27 July; date 28 July is the date of the 00:35 lighting",
    "M0326": "Beijing 2008 ceremony began 8 August; date 9 August is the date of the 00:00 lighting",
}


# ---------------------------------------------------------------- reading

def read_csv(path, required=False):
    if not os.path.exists(path):
        if required:
            raise SystemExit(f"missing {path}")
        return None
    with open(path, encoding="utf-8-sig", newline="") as fh:
        return [{(k or "").strip(): (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh)]


def by_id(rows, key="id"):
    out = {}
    for r in rows or []:
        if r.get(key):
            out[r[key]] = r
    return out


def hhmm(s):
    m = re.fullmatch(r"(\d{1,2}):(\d\d)", s or "")
    if not m:
        return None
    h, mi = int(m[1]), int(m[2])
    if h > 23 or mi > 59:
        return None
    return h, mi


def to_int(s):
    try:
        return int(float(s))
    except (TypeError, ValueError):
        return None


# ---------------------------------------------------------------- time

def local_instant(date_s, start_s, clock_s, tz_name, rid, log):
    """Return (aware local datetime, utc datetime) or None.

    Midnight rollover: a clock time earlier than the scheduled start belongs to
    the next local day, unless the row is in NO_ROLLOVER.
    """
    clock = hhmm(clock_s)
    if not clock or not tz_name or not date_s:
        return None
    try:
        d = dt.date.fromisoformat(date_s)
    except ValueError:
        log.append(f"{rid}: bad date {date_s!r}")
        return None
    start = hhmm(start_s)
    if start and clock < start and rid not in NO_ROLLOVER:
        d = d + dt.timedelta(days=1)
    tz = ZoneInfo(tz_name)
    naive = dt.datetime(d.year, d.month, d.day, clock[0], clock[1])
    a0 = naive.replace(tzinfo=tz, fold=0)
    a1 = naive.replace(tzinfo=tz, fold=1)
    if a0.utcoffset() != a1.utcoffset():
        # either ambiguous (fall back) or nonexistent (spring forward)
        back = a0.astimezone(dt.timezone.utc).astimezone(tz)
        if back.replace(tzinfo=None) == naive:
            log.append(f"{rid}: {naive} is ambiguous in {tz_name}, first occurrence used")
        else:
            log.append(f"{rid}: {naive} does not exist in {tz_name} (clocks went forward), read with the earlier offset")
    utc = a0.astimezone(dt.timezone.utc)
    local = utc.astimezone(tz)
    return local, utc


# ---------------------------------------------------------------- fields

def minute_label(gclock, mm):
    m = re.match(r"\s*(\d{1,3})(?:\s*\+\s*(\d{1,2}))?\s*(?:min|')", gclock or "")
    if m:
        lab = m[1] + (f"+{m[2]}" if m[2] else "")
        total = int(m[1]) + int(m[2] or 0)
        if mm is None or total == mm:
            return lab
    return str(mm) if mm is not None else None


MARK_RE = re.compile(r"\d[\d:.,]*(?:\s?m)?")


def clear_mark(gclock):
    s = (gclock or "").strip()
    return s if MARK_RE.fullmatch(s) else None


def harvested_fame_sub(caption, source_url):
    c = caption.lower()
    if c.startswith("gold for "):
        return 0  # Olympic final
    tail = c.rsplit(", ", 1)[-1]
    if re.search(r"semi ?final", tail): return 1
    if "third place" in tail: return 2
    if re.search(r"quarter ?final", tail): return 3
    if "round of 16" in tail: return 4
    if tail.endswith("final"): return 0
    return 5


def credit_for(img):
    if img.get("credit_line"):
        return img["credit_line"]
    if img.get("author") and img.get("licence"):
        return f"Photo: {img['author']} · {img['licence']} · Wikimedia Commons"
    return None


# ---------------------------------------------------------------- build

def build(quiet=False, write=True, ovr_dir=None, records_path=None):
    """Build the moments. ovr_dir and records_path exist so tests can point at
    empty or partial override sets; write=False keeps everything in memory."""
    log = []
    ovr = ovr_dir or OVR
    src = read_csv(SRC, required=True)
    venues = by_id(read_csv(os.path.join(ovr, "venues.csv")))
    dups = read_csv(os.path.join(ovr, "duplicates.csv")) or []
    checks = by_id(read_csv(os.path.join(ovr, "time_checks.csv")))
    captions = by_id(read_csv(os.path.join(ovr, "captions.csv")))
    places = by_id(read_csv(os.path.join(ovr, "places_curated.csv")))
    images = by_id(read_csv(os.path.join(ovr, "images.csv")))
    records = read_csv(records_path or os.path.join(DATA, "records_reviewed.csv"))
    labels = by_id(read_csv(os.path.join(ovr, "record_labels.csv")))
    zones = available_timezones()

    src_ids = {r["id"] for r in src}
    drop = {}
    for d in dups:
        # A blank keep_id drops a row outright (unreliable data, reason given in the file).
        if d.get("drop_id") in src_ids and (not d.get("keep_id") or d.get("keep_id") in src_ids) and d["drop_id"] != d.get("keep_id"):
            drop[d["drop_id"]] = d.get("keep_id")
        elif d.get("drop_id"):
            log.append(f"duplicates.csv: ignored row {d}")

    stats = {"source_rows": len(src), "dropped_duplicate": 0, "dropped_unknown": [], "timed": 0, "rolled_over": [],
             "no_start_timed": [], "images": 0, "image_rejected": [], "missing_zone": [], "checks_applied": 0}
    moments = []
    for r in src:
        rid = r["id"]
        if rid in drop:
            stats["dropped_duplicate"] += 1
            continue
        harvested = r["set"] == "harvested"
        start, clock, basis, unc, source = r["scheduled_start_local"], r["clock_time_local"], r["time_basis"], r["uncertainty_minutes"], r["time_source"]
        checked = r["checked_against_source"] == "yes"

        tc = checks.get(rid)
        if tc:
            st = tc.get("status", "")
            if st == "corrected":
                start = tc["scheduled_start_local"] or start
                clock = tc["clock_time_local"] or clock
                basis = tc["time_basis"] or basis
                unc = tc["uncertainty_minutes"] or unc
                source = tc["source_url"] or source
                checked = True
                stats["checks_applied"] += 1
            elif st == "confirmed":
                source = tc["source_url"] or source
                checked = True
                stats["checks_applied"] += 1
            elif st == "unconfirmed":
                checked = False
                stats["checks_applied"] += 1
            else:
                log.append(f"time_checks.csv: {rid} has unknown status {st!r}")

        if harvested:
            v = venues.get(rid, {})
            tz = v.get("venue_tz", "")
            place = v.get("place", "")
        else:
            tz = r["venue_time_zone"]
            place = places.get(rid, {}).get("place", "")
        if tz and tz not in zones:
            log.append(f"{rid}: unknown zone {tz!r}, treated as missing")
            tz = ""

        mm = to_int(r["match_minute_number"])
        digits = r["digits_time"] if hhmm(r["digits_time"]) else None
        mark = clear_mark(r["match_minute_or_game_clock"]) if digits else None

        timed = bool(hhmm(clock)) and basis in BASES
        if hhmm(clock) and not tz:
            stats["missing_zone"].append(rid)
            timed = False
        if not timed and not digits and mm is None:
            stats["dropped_unknown"].append(rid)
            continue

        rec = {
            "id": rid,
            "sport": r["sport"],
            "caption": captions.get(rid, {}).get("caption") or r["moment"],
            "date": r["date"],
            "instantUTC": None, "venueTZ": None, "venueLocal": None,
            "place": place or None,
            "basis": None, "plusMinusMin": None,
            "checked": checked,
            "recordDigits": digits, "recordMark": mark, "recordEvent": None, "recordLabel": None,
            "matchMinute": mm,
            "matchMinuteLabel": minute_label(r["match_minute_or_game_clock"], mm) if mm is not None else None,
            "fame": 3 if harvested else 1,
            "fameSub": harvested_fame_sub(r["moment"], r["time_source"]) if harvested else 0,
            "sourceURL": source or None,
            "image": None,
        }
        if timed:
            got = local_instant(r["date"], start, clock, tz, rid, log)
            if got:
                local, utc = got
                rec.update(instantUTC=utc.strftime("%Y-%m-%dT%H:%M:%SZ"), venueTZ=tz, venueLocal=local.strftime("%Y-%m-%dT%H:%M"),
                           basis=basis, plusMinusMin=to_int(unc), date=local.date().isoformat())
                stats["timed"] += 1
                if local.date().isoformat() != r["date"]:
                    stats["rolled_over"].append(rid)
                if not hhmm(start):
                    stats["no_start_timed"].append(rid)
        if not rec["instantUTC"]:
            rec["checked"] = False

        img = images.get(rid)
        if img and img.get("local_file"):
            why = None
            if img.get("tier") not in ("moment", "event"): why = f"tier {img.get('tier')!r}"
            elif not os.path.isfile(os.path.join(IMG_DIR, img["local_file"])): why = "file not in app/Resources/images"
            elif (to_int(img.get("width_px")) or 0) < 1600: why = f"width {img.get('width_px')!r} under 1600"
            elif not (img.get("author") and img.get("licence")): why = "author or licence blank"
            elif not credit_for(img): why = "no credit"
            if why:
                stats["image_rejected"].append((rid, why))
            else:
                rec["image"] = {"file": img["local_file"], "credit": credit_for(img)}
                stats["images"] += 1
                if img.get("tier") == "event":
                    rec["_donor"] = True
        # Same match = same sport, match date, kickoff and city. Used to share a match photo below.
        city = (place or "").split(",")[-1].strip()
        if r["sport"] == "Football" and hhmm(start) and city:
            rec["_match"] = (r["date"], start, city)
        moments.append(rec)

    # ------------------------------------------------------------ shared match photos
    # A photo of the match on the day (tier "event") also sits behind the other moments of
    # that match. A photo of one specific moment (tier "moment") is never shared. The credit
    # says it is from the same match, so the card does not claim to show this goal.
    donors = {}
    for m in moments:
        if m.get("_donor") and m.get("_match"):
            donors.setdefault(m["_match"], m["image"])
    stats["images_shared"] = 0
    for m in moments:
        key = m.pop("_match", None)
        m.pop("_donor", None)
        if key in donors and m["image"] is None:
            d = donors[key]
            credit = d["credit"]
            if credit.startswith("Photo: "):
                credit = "Photo from the same match: " + credit[len("Photo: "):]
            m["image"] = {"file": d["file"], "credit": credit}
            stats["images_shared"] += 1

    # ------------------------------------------------------------ records
    by_mid = {m["id"]: m for m in moments}
    n_rec = n_merge = 0
    if records is not None:
        for rr in records:
            rid = rr.get("record_id", "")
            digits = rr.get("digits_time", "")
            if not re.fullmatch(r"R\d{3,}", rid) or not hhmm(digits):
                log.append(f"records_reviewed.csv: skipped {rid or rr}")
                continue
            mid = rr.get("moment_id", "")
            if mid:
                m = by_mid.get(mid)
                if not m:
                    log.append(f"records_reviewed.csv: {rid} merges into {mid}, which is not in the build")
                    continue
                m["recordDigits"] = digits
                m["recordMark"] = rr.get("mark") or m["recordMark"]
                m["recordEvent"] = rr.get("event") or m["recordEvent"]
                n_merge += 1
                continue
            try:
                rdate = dt.date.fromisoformat(rr.get("date", "")).isoformat()
            except ValueError:
                log.append(f"records_reviewed.csv: skipped {rid}, date {rr.get('date')!r} is not YYYY-MM-DD")
                continue
            fame = to_int(rr.get("fame"))
            if fame not in (2, 4):
                log.append(f"records_reviewed.csv: {rid} fame {rr.get('fame')!r} is not 2 or 4, used 4")
                fame = 4
            caption = captions.get(rid, {}).get("caption") or rr.get("caption") or " ".join(
                x for x in (rr.get("athlete"), rr.get("mark"), rr.get("event")) if x)
            img = images.get(rid)
            image = None
            if img and img.get("local_file") and img.get("tier") in ("moment", "event") and os.path.isfile(os.path.join(IMG_DIR, img["local_file"])) \
                    and (to_int(img.get("width_px")) or 0) >= 1600 and img.get("author") and img.get("licence"):
                image = {"file": img["local_file"], "credit": credit_for(img)}
            moments.append({
                "id": rid, "sport": "Athletics", "caption": caption, "date": rdate,
                "instantUTC": None, "venueTZ": None, "venueLocal": None,
                "place": rr.get("place") or None, "basis": None, "plusMinusMin": None, "checked": False,
                "recordDigits": digits, "recordMark": rr.get("mark") or None, "recordEvent": rr.get("event") or None,
                "recordLabel": None, "matchMinute": None, "matchMinuteLabel": None,
                "fame": fame, "fameSub": 0, "sourceURL": rr.get("source_url") or None, "image": image,
            })
            n_rec += 1

    # ------------------------------------------------------------ extra moments
    # data/moments_extra_*.csv: hand researched moments for thin hours. The date is the
    # local date of the moment itself, so there is no midnight rollover here.
    stats["extra_moments"] = 0
    seen = {m["id"] for m in moments}
    for path in sorted(glob.glob(os.path.join(DATA, "moments_extra_*.csv"))):
        name = os.path.basename(path)
        for er in read_csv(path) or []:
            eid = (er.get("id") or "").strip()
            tz = (er.get("venue_time_zone") or "").strip()
            caption = (er.get("moment") or "").strip()
            basis = (er.get("time_basis") or "").strip()
            if not re.fullmatch(r"[A-Z]\d{3,}", eid) or eid[0] in "MRX" or eid in seen:
                log.append(f"{name}: skipped {eid or er}, bad or duplicate id"); continue
            if tz not in zones or not caption or basis not in ("documented", "derived", "scheduled", "estimated") or not er.get("time_source"):
                log.append(f"{name}: skipped {eid}, missing zone, caption, basis or source"); continue
            got = local_instant(er.get("date", ""), "", er.get("clock_time_local", ""), tz, eid, log)
            if not got:
                log.append(f"{name}: skipped {eid}, no usable date and time"); continue
            local, utc = got
            seen.add(eid)
            moments.append({
                "id": eid, "sport": (er.get("sport") or "").strip() or "Other", "caption": caption, "date": local.date().isoformat(),
                "instantUTC": utc.strftime("%Y-%m-%dT%H:%M:%SZ"), "venueTZ": tz, "venueLocal": local.strftime("%Y-%m-%dT%H:%M"),
                "place": (er.get("place") or "").strip() or None, "basis": basis, "plusMinusMin": to_int(er.get("uncertainty_minutes")),
                "checked": True, "recordDigits": None, "recordMark": None, "recordEvent": None, "recordLabel": None,
                "matchMinute": None, "matchMinuteLabel": None, "fame": 1, "fameSub": 1,
                "sourceURL": er["time_source"].split()[0], "image": None,
            })
            img = images.get(eid)
            if img and img.get("local_file") and img.get("tier") in ("moment", "event") and (to_int(img.get("width_px")) or 0) >= 1600 \
                    and img.get("author") and img.get("licence") and os.path.isfile(os.path.join(IMG_DIR, img["local_file"])):
                moments[-1]["image"] = {"file": img["local_file"], "credit": credit_for(img)}
                stats["images"] += 1
            stats["extra_moments"] += 1

    # ------------------------------------------------------------ extra records
    # data/records_extra.csv: records and famous numbers from other sports (ids X001 onward).
    # Each row carries its own label and sport, and may have no date.
    stats["extra_records"] = 0
    extra_labels = {}
    for xr in read_csv(os.path.join(DATA, "records_extra.csv")) or []:
        xid = (xr.get("record_id") or "").strip()
        digits = (xr.get("digits_time") or "").strip()
        if not re.fullmatch(r"X\d{3,}", xid) or xid in seen or not hhmm(digits) or not xr.get("mark") or not xr.get("caption") or not xr.get("record_label"):
            log.append(f"records_extra.csv: skipped {xid or xr}"); continue
        xdate = None
        if xr.get("date"):
            try:
                xdate = dt.date.fromisoformat(xr["date"].strip()).isoformat()
            except ValueError:
                log.append(f"records_extra.csv: {xid} date {xr['date']!r} is not YYYY-MM-DD, left blank")
        fame = to_int(xr.get("fame"))
        seen.add(xid)
        extra_labels[xid] = xr["record_label"].strip()
        moments.append({
            "id": xid, "sport": (xr.get("sport") or "").strip() or "Other", "caption": xr["caption"].strip(), "date": xdate,
            "instantUTC": None, "venueTZ": None, "venueLocal": None,
            "place": (xr.get("place") or "").strip() or None, "basis": None, "plusMinusMin": None, "checked": False,
            "recordDigits": digits, "recordMark": xr["mark"].strip(), "recordEvent": (xr.get("event") or "").strip() or None,
            "recordLabel": None, "matchMinute": None, "matchMinuteLabel": None,
            "fame": fame if fame in (2, 4) else 4, "fameSub": 1, "sourceURL": (xr.get("source_url") or "").strip() or None, "image": None,
        })
        stats["extra_records"] += 1

    # ------------------------------------------------------------ record labels
    # Default "World record"; record_labels.csv replaces the label and, when
    # non-blank, the mark (for curated digits that are not world records).
    by_any = {m["id"]: m for m in moments}
    for lid, lr in labels.items():
        m = by_any.get(lid)
        if not m or not m["recordDigits"]:
            log.append(f"record_labels.csv: {lid} has no record digits in the build, ignored")
    for m in moments:
        if not m["recordDigits"]:
            continue
        lr = labels.get(m["id"], {})
        m["recordLabel"] = lr.get("record_label") or extra_labels.get(m["id"]) or "World record"
        if lr.get("record_mark"):
            m["recordMark"] = lr["record_mark"]
    stats["record_mark_missing"] = [m["id"] for m in moments if m["recordDigits"] and not m["recordMark"]]

    moments.sort(key=lambda m: (m["id"][0] != "M", m["id"]))
    out = {"version": 1, "generated": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "moments": moments}
    copied = False
    if write:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
    if write and os.path.isdir(APP_RES):
        shutil.copyfile(OUT, os.path.join(APP_RES, "moments.json"))
        copied = True

    stats.update(records_file=records is not None, record_entries=n_rec, record_merges=n_merge, written=len(moments), copied_to_app=copied)
    if not quiet:
        report(stats, log, moments)
    return out, stats, log


def coverage(moments):
    real = {m["venueLocal"][11:16] for m in moments if m["venueLocal"]}
    recs = {m["recordDigits"] for m in moments if m["recordDigits"]}
    return len(real), len(real | recs)


def report(stats, log, moments):
    p = print
    p(f"moments.json: {stats['written']} entries ({stats['timed']} with a UTC instant)")
    p(f"  source rows {stats['source_rows']}, dropped as duplicates {stats['dropped_duplicate']}, "
      f"dropped with no time, no record digits and no match minute {len(stats['dropped_unknown'])}")
    p(f"  midnight rollovers applied {len(stats['rolled_over'])}: {' '.join(stats['rolled_over'])}")
    p(f"  timed rows with no scheduled start (date taken as the local date) {len(stats['no_start_timed'])}")
    p(f"  time checks applied {stats['checks_applied']}, images bundled {stats['images']}, shared with same match {stats['images_shared']}, rejected {len(stats['image_rejected'])}")
    p(f"  records file present {stats['records_file']}, record entries {stats['record_entries']}, merged into moments {stats['record_merges']}")
    p(f"  extra moments {stats['extra_moments']}, extra records {stats['extra_records']}")
    if stats["missing_zone"]:
        p(f"  timed rows with no venue zone (left untimed) {len(stats['missing_zone'])}: {' '.join(stats['missing_zone'][:40])}")
    if stats.get("record_mark_missing"):
        p(f"  record digits with no mark yet {len(stats['record_mark_missing'])}: {' '.join(stats['record_mark_missing'])}")
    for rid, why in stats["image_rejected"]:
        p(f"  image rejected {rid}: {why}")
    real, both = coverage(moments)
    p(f"  coverage, venue time: real time {real}/1440 ({100 * real / 1440:.1f}%), real time plus records {both}/1440 ({100 * both / 1440:.1f}%)")
    p(f"  copied to app/Resources/moments.json: {stats['copied_to_app']}")
    for line in log:
        p("  note: " + line)


if __name__ == "__main__":
    build(quiet="--quiet" in sys.argv)
