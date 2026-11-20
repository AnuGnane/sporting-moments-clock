import json, time, sys, os, re, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.1 (feasibility study script; python-urllib)"
BASE = sys.argv[1]; CACHE = os.path.join(BASE, "cache")
def api(host, params, tries=8):
    url = f"https://{host}/w/api.php?" + urllib.parse.urlencode(params)
    delay = 5
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=40) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503): time.sleep(delay); delay = min(delay * 2, 60); continue
            return None
        except Exception: time.sleep(delay); delay = min(delay * 2, 60)
    return None
rows = []
for fn, wi, qi in (("football.txt", 5, 6), ("other.txt", 9, 10)):
    for line in open(os.path.join(BASE, fn), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        f = line.rstrip("\n").split("|"); rows.append((f[wi].strip(), f[qi].strip()))
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
# (a) free lead images of the Wikipedia articles
pi_path = os.path.join(CACHE, "pageimages.json")
pi = json.load(open(pi_path)) if os.path.exists(pi_path) else {}
arts = sorted({resolved.get(w, w).replace("SEARCH:", "") for w, _ in rows if w})
todo = [a for a in arts if a not in pi]
for i in range(0, len(todo), 40):
    b = todo[i:i+40]
    d = api("en.wikipedia.org", {"action": "query", "prop": "pageimages", "piprop": "original|name", "pilicense": "free", "pilimit": 50,
        "titles": "|".join(b), "format": "json", "formatversion": 2})
    time.sleep(2)
    if not d: continue
    for p in d["query"]["pages"]:
        o = p.get("original")
        pi[p["title"]] = {"file": p.get("pageimage"), "url": o.get("source") if o else None, "w": o.get("width") if o else None, "h": o.get("height") if o else None}
    json.dump(pi, open(pi_path, "w"), ensure_ascii=False)
print("pageimages", len(pi), flush=True)
# (b) Commons file search per moment
cs_path = os.path.join(CACHE, "commons.json")
cs = json.load(open(cs_path)) if os.path.exists(cs_path) else {}
qs = list(dict.fromkeys(q for _, q in rows if q))
n = 0
for q in qs:
    if q in cs: continue
    d = api("commons.wikimedia.org", {"action": "query", "generator": "search", "gsrsearch": q + " filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 8,
        "prop": "imageinfo", "iiprop": "size|url|extmetadata", "iiextmetadatafilter": "LicenseShortName|DateTimeOriginal|Artist", "format": "json", "formatversion": 2})
    time.sleep(2.2)
    if d is None: print("FAIL", q, flush=True); continue
    hits = []
    for p in sorted(d.get("query", {}).get("pages", []), key=lambda x: x.get("index", 99)):
        ii = (p.get("imageinfo") or [{}])[0]; em = ii.get("extmetadata", {})
        strip = lambda s: re.sub(r"<[^>]+>", "", s or "")[:60]
        hits.append({"title": p["title"], "w": ii.get("width"), "h": ii.get("height"), "url": ii.get("descriptionurl"),
            "lic": strip(em.get("LicenseShortName", {}).get("value")), "date": strip(em.get("DateTimeOriginal", {}).get("value")), "artist": strip(em.get("Artist", {}).get("value"))})
    cs[q] = hits; n += 1
    if n % 10 == 0:
        json.dump(cs, open(cs_path, "w"), ensure_ascii=False); print(n, len(cs), "/", len(qs), flush=True)
json.dump(cs, open(cs_path, "w"), ensure_ascii=False)
print("done commons", len(cs), "/", len(qs), flush=True)
