import json, os, re, sys, csv, urllib.parse, random, statistics
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo
BASE = sys.argv[1]; CACHE = os.path.join(BASE, "cache")
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
LON = ZoneInfo("Europe/London")
def wurl(t):
    t = resolved.get(t, t).replace("SEARCH:", "")
    return "https://en.wikipedia.org/wiki/" + urllib.parse.quote(t.replace(" ", "_"), safe="_(),:'")
# kickoffs that could not be confirmed against a match box this session (recalled from memory)
KO_UNVERIFIED = ["Ricky Villa", "Cantona's kung fu", "Tony Yeboah", "Higuita", "Beckham scores from the halfway", "Cantona's chip", "Goalkeeper Jimmy Glass",
    "Rooney's overhead", "Messi holds his shirt", "Ibrahimović", "Sheringham equalises", "\"And Solskjaer"]
KO_CONFIRMED_2 = []
def fb_rows():
    out = []
    for line in open(os.path.join(BASE, "football.txt"), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        f = line.rstrip("\n").split("|")
        title, date, tz, ko, minute, wiki, cq = f[:7]; munc = int(f[7]) if len(f) > 7 and f[7] else 0
        y = int(date[:4]); modern = y >= 2018; ht = 15 if y >= 1980 else 10; s1 = 3 if modern else 2; s2 = 6 if modern else 4
        if minute == "pens":
            off = 174 if modern else (165 if y >= 1980 else 160); unc = 8; mm = None; label = "Penalty shootout"
        else:
            b, _, e = minute.partition("+"); b = int(b); e = int(e or 0); m = b + e; mm = m
            label = (f"{b}+{e}" if e else f"{b}") + " min"
            if b <= 45: off, unc = m, 2
            elif b <= 90: off, unc = m + s1 + ht, 4
            elif b <= 105: off, unc = m + s1 + ht + s2 + 5, 6
            else: off, unc = m + s1 + ht + s2 + 5 + 3, 7
            if y < 1980: unc += 2
        unc += munc
        out.append(dict(sport="Football", moment=title, date=date, tz=tz, start=ko, gclock=label, mm=mm, off=off, basis="K", unc=unc, wiki=wiki, cq=cq, num=""))
    return out
def other_rows():
    out = []
    for line in open(os.path.join(BASE, "other.txt"), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        f = line.rstrip("\n").split("|") + [""] * 3
        sport, title, date, tz, start, gclock, clock, basis, unc, wiki, cq, num = f[:12]
        mm = None
        if sport == "Rugby union":
            m = re.search(r"(\d+)(?:st|nd|rd|th) minute", gclock)
            if m: mm = int(m.group(1))
        out.append(dict(sport=sport, moment=title, date=date, tz=tz, start=start, gclock=gclock, mm=mm, clock=clock, basis=basis, unc=int(unc) if unc else None, wiki=wiki, cq=cq, num=num))
    return out
rows = fb_rows() + other_rows()
BASIS = {"D": "documented", "R": "documented (recalled, not rechecked)", "K": "derived from kickoff and match minute", "S": "scheduled start plus elapsed", "E": "estimated", "U": "unknown"}
for i, r in enumerate(rows, 1):
    r["id"] = f"M{i:03d}"
    z = ZoneInfo(r["tz"]); y, mo, d = map(int, r["date"].split("-"))
    if r["basis"] == "K":
        h, mi = map(int, r["start"].split(":"))
        dt = datetime(y, mo, d, h, mi, tzinfo=z) + timedelta(minutes=r["off"])
        dt = dt.astimezone(z)
    elif r.get("clock"):
        h, mi = map(int, r["clock"].split(":")); dt = datetime(y, mo, d, h, mi, tzinfo=z)
    else: dt = None
    r["dt"] = dt
    if dt:
        r["local"] = dt.strftime("%H:%M"); r["abbr"] = dt.tzname(); lon = dt.astimezone(LON); r["london"] = lon.strftime("%H:%M")
        r["lmin"] = dt.hour * 60 + dt.minute; r["umin"] = lon.hour * 60 + lon.minute
    else:
        r["local"] = r["abbr"] = r["london"] = ""; r["lmin"] = r["umin"] = None
json.dump([{k: (v.isoformat() if k == "dt" and v else v) for k, v in r.items()} for r in rows], open(os.path.join(CACHE, "rows.json"), "w"), ensure_ascii=False, indent=0)
if __name__ == "__main__":
    timed = [r for r in rows if r["lmin"] is not None]
    print("moments", len(rows), "football", sum(r["sport"] == "Football" for r in rows), "timed", len(timed))
    from collections import Counter
    print(Counter(r["basis"] for r in rows))
    print(Counter(r["sport"] for r in rows).most_common())
    for r in rows:
        if r["sport"] == "Football" and r["moment"].startswith(("\"Agüer", "\"And Sol", "Maradona's Hand", "\"They think", "Ghiggia", "Istanbul: Dudek", "Donnarumma", "Montiel", "Iniesta wins")):
            print(r["moment"][:40], r["start"], r["gclock"], "->", r["local"], r["abbr"], "| London", r["london"], "±", r["unc"])
