import json, time, sys, os, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.2 (feasibility study script; python-urllib)"
BASE = sys.argv[1]; C2 = os.path.join(BASE, "cache2")
def api(params, tries=9):
    data = urllib.parse.urlencode(params).encode(); delay = 5
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request("https://en.wikipedia.org/w/api.php", data=data, headers={"User-Agent": UA}), timeout=60) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            ra = e.headers.get("retry-after"); time.sleep(min(int(ra) + 1 if ra and ra.isdigit() else delay, 90)); delay = min(delay * 2, 60)
        except Exception: time.sleep(delay); delay = min(delay * 2, 60)
    return None
T = []
wc = [1930,1934,1938,1954,1958,1962,1966,1970,1974,1978,1982,1986,1990,1994,1998,2002,2006,2010,2014,2018,2022]
T += [f"{y} FIFA World Cup final" for y in wc] + [f"{y} FIFA World Cup knockout stage" for y in wc] + ["Uruguay v Brazil (1950 FIFA World Cup)"]
T += ["1960 European Nations' Cup final", "1964 European Nations' Cup final"] + [f"UEFA Euro {y} final" for y in range(1968, 2025, 4)] + [f"UEFA Euro {y} knockout stage" for y in range(1996, 2025, 4)]
T += [f"{y} European Cup final" for y in range(1956, 1993)] + [f"{y} UEFA Champions League final" for y in range(1993, 2026)]
T += [f"{y} FIFA Women's World Cup final" for y in (1991,1995,1999,2003,2007,2011,2015,2019,2023)] + [f"{y} FIFA Women's World Cup knockout stage" for y in (2011,2015,2019,2023)]
T += [f"UEFA Women's Euro {y} final" for y in (2013,2017,2022,2025)] + [f"{y} Copa América final" for y in (2015,2019,2021,2024)] + ["Copa América Centenario final"]
ev = ["100 metres","200 metres","400 metres","800 metres","1500 metres","5000 metres","10,000 metres","marathon","400 metres hurdles","3000 metres steeplechase","4 × 100 metres relay","4 × 400 metres relay"]
for y in (1996,2000,2004,2008,2012,2016,2020,2024):
    for g in ("Men's","Women's"):
        T += [f"Athletics at the {y} Summer Olympics – {g} {e}" for e in ev]
        T.append(f"Athletics at the {y} Summer Olympics – {g} " + ("110 metres hurdles" if g == "Men's" else "100 metres hurdles"))
sw = ["50 metre freestyle","100 metre freestyle","200 metre freestyle","400 metre freestyle","800 metre freestyle","1500 metre freestyle","100 metre backstroke","200 metre backstroke","100 metre breaststroke","200 metre breaststroke",
      "100 metre butterfly","200 metre butterfly","200 metre individual medley","400 metre individual medley","4 × 100 metre freestyle relay","4 × 200 metre freestyle relay","4 × 100 metre medley relay"]
for y in (2008, 2020):
    for g in ("Men's","Women's"): T += [f"Swimming at the {y} Summer Olympics – {g} {e}" for e in sw]
T += ["Mile run world record progression","Marathon world record progression","1500 metres world record progression","800 metres world record progression","3000 metres steeplechase world record progression",
      "5000 metres world record progression","Men's pole vault world record progression","Women's pole vault world record progression","Men's high jump world record progression","Women's high jump world record progression",
      "Men's long jump world record progression","Women's long jump world record progression","Men's triple jump world record progression","Men's 200 metres world record progression","Women's 100 metres hurdles world record progression",
      "Men's shot put world record progression","3000 metres world record progression","World record progression 400 metres freestyle","World record progression 200 metres freestyle","World record progression 800 metres freestyle",
      "World record progression 1500 metres freestyle","World record progression 400 metres individual medley","World record progression 200 metres individual medley","World record progression 200 metres butterfly",
      "World record progression 200 metres backstroke","World record progression 200 metres breaststroke","World record progression 4 × 100 metres freestyle relay","World record progression 4 × 200 metres freestyle relay","World record progression 4 × 100 metres medley relay"]
T += open(os.path.join(BASE, "extra_titles.txt"), encoding="utf-8").read().splitlines() if os.path.exists(os.path.join(BASE, "extra_titles.txt")) else []
T = [t for t in dict.fromkeys(T) if t.strip()]
ip = os.path.join(C2, "index.json"); idx = json.load(open(ip)) if os.path.exists(ip) else {}
todo = [t for t in T if t not in idx]; print(len(T), "titles", len(todo), "todo", flush=True)
for i in range(0, len(todo), 12):
    b = todo[i:i+12]
    d = api({"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": "|".join(b), "redirects": 1, "format": "json", "formatversion": 2})
    time.sleep(1.2)
    if not d: continue
    q = d.get("query", {}); m = {}
    for n in q.get("normalized", []) + q.get("redirects", []): m[n["from"]] = n["to"]
    pages = {p["title"]: p for p in q.get("pages", [])}
    for t in b:
        f = t
        for _ in range(3): f = m.get(f, f)
        p = pages.get(f)
        if p is None: continue
        if p.get("missing"): idx[t] = None; continue
        if not p.get("revisions"):
            d2 = api({"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main", "titles": f, "format": "json", "formatversion": 2}); time.sleep(1.2)
            try: p = d2["query"]["pages"][0]
            except Exception: continue
            if not p.get("revisions"): continue
        fn = f"{len(idx):04d}.txt"; open(os.path.join(C2, fn), "w", encoding="utf-8").write(p["revisions"][0]["slots"]["main"]["content"]); idx[t] = [fn, f]
    json.dump(idx, open(ip, "w"), ensure_ascii=False)
print("done", len(idx), "missing", sum(v is None for v in idx.values()), flush=True)
