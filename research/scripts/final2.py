import json, os, re, sys, csv, urllib.parse
from collections import Counter
BASE = sys.argv[1]; C2 = os.path.join(BASE, "cache2"); idx = json.load(open(os.path.join(C2, "index.json")))
W = lambda t: "https://en.wikipedia.org/wiki/" + urllib.parse.quote(t.replace(" ", "_"), safe="_(),:'")
old = list(csv.DictReader(open(os.path.join(BASE, "sporting_moments.csv"), encoding="utf-8-sig")))
rows = []
for r in old:
    rows.append(dict(set="curated", sport=r["sport"], moment=r["moment"], date=r["date"], gclock=r["match_minute_or_game_clock"], mm=r["match_minute_number"], start=r["scheduled_start_local"], local=r["clock_time_local"],
        tz=r["time_zone"], basis=r["time_basis"], unc=r["uncertainty_minutes"], checked=r["checked_this_session"], src=r["time_source"], digits=r["digits_time"], img=r["image_tier"], ifile=r["image_file"], ipage=r["image_page"],
        ilic=r["image_licence"], iw=r["image_width_px"], ifs=r["image_full_screen_ok"]))
BL = {"D": "documented", "R": "documented", "S": "scheduled", "E": "estimated", "U": "unknown"}
nchk = 0
for line in open(os.path.join(BASE, "other2.txt"), encoding="utf-8"):
    if line.startswith("#") or not line.strip(): continue
    f = line.rstrip("\n").split("|") + [""] * 3
    sport, title, date, tz, start, gclock, clock, basis, unc, wiki, cq, num = f[:12]
    v = idx.get(wiki); txt = open(os.path.join(C2, v[0]), encoding="utf-8").read().replace("&nbsp;", " ").replace("{{nbsp}}", " ") if v else ""
    def has(t):
        if not t: return False
        h, mi = t.split(":"); h = int(h)
        return any(re.search(r"(?<!\d)" + re.escape(c) + r"(?!\d)", txt) for c in {f"{h}:{mi}", f"{h:02d}:{mi}", f"{(h - 1) % 12 + 1}:{mi}", f"{(h - 1) % 12 + 1}.{mi}"})
    ok = has(clock) if basis in "DR" else (has(start) or has(clock))
    nchk += ok
    rows.append(dict(set="curated", sport=sport, moment=title, date=date, gclock=gclock, mm="", start=start, local=clock, tz=tz, basis=BL[basis], unc=unc, checked="yes" if ok else "no", src=W(v[1]) if v else "", digits=num,
        img="not checked yet", ifile="", ipage="", ilic="", iw="", ifs=""))
print("hand rows", sum(1 for r in rows) - len(old), "confirmed in article text", nchk)
cur = [(r["date"], r["local"], r["mm"]) for r in rows]
def tmin(s): return int(s[:2]) * 60 + int(s[3:])
bydate = {}
for d, l, m in cur:
    if l: bydate.setdefault(d, []).append((tmin(l), m))
dup = 0
for fn in ("h_football.json", "h_olympic.json"):
    for o in json.load(open(os.path.join(C2, fn))):
        if re.search(r"[#{}|\[\]<>]", o["moment"]) or len(o["moment"]) > 150: continue
        near = bydate.get(o["date"], [])
        if any((str(o.get("mm") or "") == str(m) and m != "") or abs(tmin(o["local"]) - t) <= (1 if o["sport"] == "Football" else 4) for t, m in near): dup += 1; continue
        rows.append(dict(set="harvested", sport=o["sport"], moment=o["moment"].replace("–", " to ").replace("-", " "), date=o["date"], gclock=o["gclock"], mm=o.get("mm") or "", start=o["start"], local=o["local"], tz="",
            basis="derived" if o["basis"] == "K" else "scheduled", unc=o["unc"], checked="yes", src=W(o["art"]), digits="", img="not checked yet", ifile="", ipage="", ilic="", iw="", ifs=""))
print("harvest duplicates of curated rows dropped", dup)
for i, r in enumerate(rows, 1): r["id"] = f"M{i:04d}"
with open(os.path.join(BASE, "sporting_moments_v2.csv"), "w", newline="", encoding="utf-8-sig") as fh:
    w = csv.writer(fh)
    w.writerow(["id", "set", "sport", "moment", "date", "match_minute_or_game_clock", "match_minute_number", "scheduled_start_local", "clock_time_local", "venue_time_zone", "time_basis", "uncertainty_minutes", "checked_against_source",
                "time_source", "digits_time", "image_tier", "image_file", "image_page", "image_licence", "image_width_px", "image_full_screen_ok"])
    for r in rows: w.writerow([r[k] for k in ("id", "set", "sport", "moment", "date", "gclock", "mm", "start", "local", "tz", "basis", "unc", "checked", "src", "digits", "img", "ifile", "ipage", "ilic", "iw", "ifs")])
recs = json.load(open(os.path.join(C2, "h_records.json")))
PLACES = {"Oslo", "Toronto", "London", "Berlin", "Paris", "Rome", "Tokyo", "Stockholm", "Zürich", "Zurich", "Moscow", "Helsinki", "Los Angeles", "Budapest", "Sydney", "Melbourne", "Monaco", "Eugene", "Brussels", "Rieti", "Cologne"}
ath = [o for o in recs if not re.search(r"freestyle|medley|backstroke|breaststroke|butterfly", o["event"]) and o["athlete"] not in PLACES and not re.search(r"\d", o["athlete"])]
with open(os.path.join(BASE, "record_digits_prototype.csv"), "w", newline="", encoding="utf-8-sig") as fh:
    w = csv.writer(fh); w.writerow(["digits_time", "mark", "athlete", "event", "date", "source", "status"])
    for o in sorted(ath, key=lambda o: (o["digits"], o["date"])): w.writerow([o["digits"], o["mark"], o["athlete"], o["event"], o["date"], W(o["art"]), "machine harvested, not reviewed"])
# ---------- stats ----------
fmt = lambda m: f"{m // 60:02d}:{m % 60:02d}"
def gs(S):
    s = sorted(S); g = sorted((((s[(i + 1) % len(s)] - s[i]) % 1440 or 1440), s[i]) for i in range(len(s)))[::-1]
    return {"covered": len(s), "pct": round(100 * len(s) / 1440, 1), "top_gaps": [f"{fmt(a)} to {fmt((a + x) % 1440)} ({x} min)" for x, a in g[:4]], "gaps_over_60": sum(x > 60 for x, _ in g), "gaps_over_30": sum(x > 30 for x, _ in g),
            "avg_card_age": round(sum(x * x for x, _ in g) / 2 / 1440, 1)}
T = [r for r in rows if r["local"]]
cur_ = {tmin(r["local"]) for r in T if r["set"] == "curated"}; old_ = {tmin(r["clock_time_local"]) for r in old if r["clock_time_local"]}; allv = {tmin(r["local"]) for r in T}
D_ath = {tmin(o["digits"]) for o in ath}; D_all = {tmin(o["digits"]) for o in recs}
mmres = {int(r["mm"]) % 60 for r in rows if str(r["mm"]).isdigit()}
st = {"rows": len(rows), "by_set": Counter(r["set"] for r in rows), "timed": len(T), "by_sport_top": Counter(r["sport"] for r in rows).most_common(8),
      "basis": Counter(r["basis"] for r in rows), "checked": Counter(r["checked"] for r in T),
      "A_round1_venue": gs(old_), "B_curated_venue": gs(cur_), "C_all_venue": gs(allv),
      "records_athletics": len(ath), "records_all": len(recs), "D_records_ath_alone": gs(D_ath), "E_all_venue_plus_records_ath": gs(allv | D_ath), "F_all_venue_plus_records_all": gs(allv | D_all),
      "G_plus_minute_fill": len(allv | D_ath | {m for m in range(1440) if m % 60 in mmres}), "residues": len(mmres),
      "per_hour_venue": [len({m for m in allv if m // 60 == h}) for h in range(24)], "per_hour_with_records": [len({m for m in (allv | D_ath) if m // 60 == h}) for h in range(24)],
      "per_hour_round1": [len({m for m in old_ if m // 60 == h}) for h in range(24)],
      "dates": len({r["date"][5:] for r in rows}), "unc<=5": sum(1 for r in T if str(r["unc"]).isdigit() and int(r["unc"]) <= 5)}
json.dump(st, open(os.path.join(C2, "stats2.json"), "w"), indent=1, default=str)
for k, v in st.items(): print(k, "=", v)
import random; random.seed(11)
for o in random.sample(ath, 8): print("   rec:", o["digits"], o["mark"], o["athlete"], "|", o["event"], o["date"])
