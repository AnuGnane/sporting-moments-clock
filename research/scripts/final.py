import json, os, sys, csv, random, importlib.util, statistics, urllib.parse
from collections import Counter
BASE = sys.argv[1]; S = os.path.join(BASE, "scripts"); sys.path.insert(0, S)
sys.argv = [sys.argv[0], BASE]
def load(name):
    sp = importlib.util.spec_from_file_location(name, os.path.join(S, name + ".py")); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
build = load("build"); rows = build.rows
im = load("images"); import tiers
img = tiers.assign(im.rows, im.classify, im.af, im.fi, im.resolved)
W = "https://en.wikipedia.org/wiki/"
SRC = {"Wilkinson": None, "The Brighton Miracle": None, "England face the haka": None, "Dhoni": None, "Brathwaite": None, "Super over": None, "Nadal beats Federer": None,
 "Isner beats": None, "Djokovic outlasts": None,
 "Hewitt beats": "https://www.eurosport.com/tennis/atp-acapulco/2022/alexander-zverev-beats-jenson-brooksby-in-latest-ever-tennis-finish-at-4.55am-on-remarkable-day-in-a_sto8812400/story.shtml",
 "Zverev beats": "https://www.eurosport.com/tennis/atp-acapulco/2022/alexander-zverev-beats-jenson-brooksby-in-latest-ever-tennis-finish-at-4.55am-on-remarkable-day-in-a_sto8812400/story.shtml",
 "Murray beats Kokkinakis": "https://www.10sballs.com/2023/01/19/miracle-in-melbourne-as-murray-comes-back-from-the-dead-to-win-after-five-hours/",
 "Jesse Owens sets": None, "Bannister": W + "Roger_Bannister", "Abebe Bikila": None, "Bob Beamon": None, "Michael Johnson": None, "Kelly Holmes": None,
 "Bolt runs 9.69": None, "Bolt runs 19.30": None, "Bolt runs 9.58": None, "Bolt runs 19.19": None,
 "Super Saturday": "https://athleticsweekly.com/news/reports/from-the-aw-archive-london-2012-super-saturday-1039929034/",
 "Bolt retains": None, "Rudisha": None, "Van Niekerk": None, "Bolt wins a third": None, "Kipchoge runs a marathon": None, "Noah Lyles": None, "Duplantis": None,
 "Phelps wins the 100": None, "Redgrave": None, "Miracle on Ice": None, "Crosby": None,
 "Bobby Thomson": "https://sabr.org/gamesproj/game/october-3-1951-giants-win-pennant", "Mazeroski": W + "Bill_Mazeroski",
 "Hank Aaron": "https://sabr.org/gamesproj/game/april-8-1974-hank-aaron-hammers-historic-715th-home-run-break-babe-ruths-record", "Fisk": W + "Carlton_Fisk",
 "Kirk Gibson": None, "The Cubs": "https://www.wptv.com/sports/chicago-cubs-win-first-world-series-since-1908-beating-cleveland-8-7-in-10th-inning-of-game-7-",
 "Freeman's": W + "Kirk_Gibson%27s_1988_World_Series_home_run", "The Immaculate Reception": None, "Wide Right": None, "Malcolm Butler": None, "The Patriots complete": None,
 "The Minneapolis Miracle": None, "Rumble in the Jungle": None, "Thrilla in Manila": None, "Toyota stops": None, "Ford finish": None, "Hamilton passes": None, "Button wins": None,
 "Verstappen passes": None, "Secretariat": None, "Rachael Blackmore": None, "Tiger wins the Masters again": None, "Dennis Taylor": None, "Captain Webb": None, "Hillary and Tenzing": None}
BL = {"D": "documented", "R": "documented", "K": "derived", "S": "scheduled", "E": "estimated", "U": "unknown"}
for r in rows:
    if r["sport"] == "Football":
        r["checked"] = "no" if any(r["moment"].startswith(p) for p in build.KO_UNVERIFIED) else "yes"; r["src"] = build.wurl(r["wiki"])
    else:
        k = next((p for p in SRC if r["moment"].startswith(p)), None)
        r["checked"] = "yes" if k and r["basis"] != "U" else "no"
        r["src"] = (SRC[k] or build.wurl(r["wiki"])) if k else (build.wurl(r["wiki"]) if r["basis"] != "U" else "")
    if r["basis"] == "U": r["unc"] = None
    t, f, x = img[r["id"]]; r["tier"] = t; r["ifile"] = f; r["ix"] = x
TIER = {1: "moment", 2: "event", 3: "related only", 4: "none found"}
NOTE = {"K": "Kickoff plus match minute, allowing for half time and typical stoppage", "S": "Scheduled start plus the known duration", "E": "Rough estimate from start time and typical running length",
        "D": "Clock time stated in the source", "R": "Clock time as widely reported; recalled, not rechecked this session", "U": "No clock time found"}
out = os.path.join(BASE, "sporting_moments.csv")
with open(out, "w", newline="", encoding="utf-8-sig") as fh:
    w = csv.writer(fh)
    w.writerow(["id", "sport", "moment", "date", "match_minute_or_game_clock", "match_minute_number", "scheduled_start_local", "clock_time_local", "time_zone", "time_zone_abbr", "clock_time_london",
                "time_basis", "uncertainty_minutes", "checked_this_session", "time_source", "time_note", "digits_time", "image_tier", "image_file", "image_page", "image_licence", "image_width_px", "image_full_screen_ok"])
    for r in rows:
        x = r["ix"]
        w.writerow([r["id"], r["sport"], r["moment"], r["date"], r["gclock"], r["mm"] or "", r["start"], r["local"], r["tz"], r["abbr"], r["london"], BL[r["basis"]], r["unc"] if r["unc"] is not None else "",
                    r["checked"], r["src"], NOTE[r["basis"]], r["num"], TIER[r["tier"]], (r["ifile"] or "")[5:], (x or {}).get("page", "") if r["ifile"] else "", (x or {}).get("lic", "") if r["ifile"] else "",
                    (x or {}).get("w", "") if r["ifile"] else "", ("yes" if x and x["w"] >= 1600 else "no") if r["ifile"] and r["tier"] <= 2 else ""])
# ---------- stats ----------
st = {}
N = len(rows); timed = [r for r in rows if r["lmin"] is not None]
st["moments"] = N; st["timed"] = len(timed); st["by_sport"] = Counter(r["sport"] for r in rows).most_common()
st["basis"] = Counter(BL[r["basis"]] for r in rows); st["basis_checked"] = Counter(BL[r["basis"]] + " / checked " + r["checked"] for r in rows)
st["unc_bands"] = Counter(("<=2" if r["unc"] <= 2 else "3-5" if r["unc"] <= 5 else "6-10" if r["unc"] <= 10 else ">10") for r in timed)
def fmt(m): return f"{m // 60:02d}:{m % 60:02d}"
def gapstats(Sset):
    s = sorted(Sset); g = [((s[(i + 1) % len(s)] - s[i]) % 1440 or 1440, s[i]) for i in range(len(s))]
    mx = max(g); stale = sum(x * x for x, _ in g) / 2 / 1440
    return {"covered": len(s), "pct": round(100 * len(s) / 1440, 1), "longest_gap_min": mx[0], "longest_gap_from": fmt(mx[1]), "longest_gap_to": fmt((mx[1] + mx[0]) % 1440),
            "gaps_over_30": sum(x > 30 for x, _ in g), "gaps_over_60": sum(x > 60 for x, _ in g), "avg_card_age_min": round(stale, 1)}
V = {r["lmin"] for r in timed}; U = {r["umin"] for r in timed}
tight = [r for r in timed if r["basis"] in "DRKS"]
st["real_venue"] = gapstats(V); st["real_london"] = gapstats(U); st["real_both"] = gapstats(V | U)
st["real_venue_tight_only"] = gapstats({r["lmin"] for r in tight}); st["real_both_tight_only"] = gapstats({r["lmin"] for r in tight} | {r["umin"] for r in tight})
win = set()
for r in timed:
    for d in range(-r["unc"], r["unc"] + 1): win.add((r["lmin"] + d) % 1440)
st["real_venue_within_uncertainty"] = len(win)
st["hour_venue"] = [sum(1 for r in timed if r["lmin"] // 60 == h) for h in range(24)]; st["hour_london"] = [sum(1 for r in timed if r["umin"] // 60 == h) for h in range(24)]
st["collisions_venue"] = len(timed) - len(V)
mm = [r["mm"] for r in rows if r.get("mm")]
res = Counter(m % 60 for m in mm)
st["match_minute"] = {"moments_with_minute": len(mm), "distinct_minutes": len(set(mm)), "residues_covered": len(res), "residues_missing": sorted(set(range(60)) - set(res)),
    "minute_of_hour_coverage": len(res) * 24, "minute_of_hour_pct": round(100 * len(res) / 60, 1), "moments_per_slot_median": statistics.median(res.values()), "moments_per_slot_max": max(res.values()),
    "elapsed_or_digit_mapping_coverage": len(set(mm)) * 2, "elapsed_pct": round(100 * len(set(mm)) * 2 / 1440, 1), "top_minutes": Counter(mm).most_common(6)}
days = Counter(r["date"][5:] for r in rows)
st["date"] = {"distinct_days": len(days), "pct_of_366": round(100 * len(days) / 366, 1), "max_on_one_day": days.most_common(3), "by_month": [sum(v for k, v in days.items() if int(k[:2]) == m) for m in range(1, 13)]}
nums = {r["num"] for r in rows if r["num"]}
st["digits"] = {"moments": sum(1 for r in rows if r["num"]), "distinct_times": len(nums)}
fill = {m for m in range(1440) if m % 60 in res}
st["hybrid_real_both_plus_minute_fill"] = len(V | U | fill)
st["hybrid_real_both_plus_digits"] = len(V | U | {int(n[:2]) * 60 + int(n[3:]) for n in nums})
random.seed(7); proj = {}
pairs = [(r["lmin"], r["umin"]) for r in timed]
for n in (241, 500, 1000, 2000, 5000):
    a = b = c = 0; T = 60
    for _ in range(T):
        sv, su = set(), set()
        for _ in range(n):
            l, u = random.choice(pairs); j = random.randint(-25, 25); sv.add((l + j) % 1440); su.add((u + j) % 1440)
        a += len(sv); b += len(su); c += len(sv | su)
    proj[n] = (round(a / T), round(b / T), round(c / T))
st["projection_distinct_minutes(venue,london,both)"] = proj
st["images"] = {TIER[k]: v for k, v in sorted(Counter(r["tier"] for r in rows).items())}
st["images_fullscreen_ok(moment/event,>=1600px)"] = sum(1 for r in rows if r["tier"] <= 2 and r["ix"] and r["ix"]["w"] >= 1600)
st["images_moment_ge1600"] = sum(1 for r in rows if r["tier"] == 1 and r["ix"]["w"] >= 1600)
st["images_by_era"] = {era: dict(Counter(TIER[r["tier"]] for r in rows if lo <= int(r["date"][:4]) < hi)) for era, lo, hi in (("pre1990", 0, 1990), ("1990-2004", 1990, 2005), ("2005+", 2005, 2100))}
st["images_football_vs_other"] = {"football": dict(Counter(TIER[r["tier"]] for r in rows if r["sport"] == "Football")), "other": dict(Counter(TIER[r["tier"]] for r in rows if r["sport"] != "Football"))}
st["timed_with_event_image"] = sum(1 for r in timed if r["tier"] <= 2)
st["licences"] = Counter((r["ix"]["lic"].split()[0] + " " + (r["ix"]["lic"].split()[1] if len(r["ix"]["lic"].split()) > 1 else "")) for r in rows if r["tier"] <= 2 and r["ix"]).most_common(6)
json.dump(st, open(os.path.join(CACHE := os.path.join(BASE, "cache"), "stats.json"), "w"), indent=1, default=str)
for k, v in st.items(): print(k, "=", v)
