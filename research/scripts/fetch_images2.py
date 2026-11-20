import json, time, sys, os, re, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.1 (feasibility study script; python-urllib)"
BASE = sys.argv[1]; CACHE = os.path.join(BASE, "cache")
def api(params, tries=7):
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode(params)
    delay = 4
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=40) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503): time.sleep(delay); delay = min(delay * 2, 60); continue
            return None
        except Exception: time.sleep(delay); delay = min(delay * 2, 60)
    return None
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
arts = []
for fn, wi in (("football.txt", 5), ("other.txt", 9)):
    for line in open(os.path.join(BASE, fn), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        w = line.rstrip("\n").split("|")[wi].strip()
        a = resolved.get(w, w).replace("SEARCH:", "")
        if a and a not in arts: arts.append(a)
path = os.path.join(CACHE, "artimages.json")
out = json.load(open(path)) if os.path.exists(path) else {}
strip = lambda s: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()
n = 0
for a in arts:
    if a in out: continue
    files = []; cont = {}
    for page in range(3):
        d = api({"action": "query", "generator": "images", "gimlimit": 50, "titles": a, "redirects": 1, "prop": "imageinfo", "iiprop": "size|url|mime|extmetadata",
                 "iiextmetadatafilter": "LicenseShortName|DateTimeOriginal|Artist|ImageDescription", "format": "json", "formatversion": 2, **cont})
        time.sleep(1.3)
        if not d: break
        for p in d.get("query", {}).get("pages", []):
            ii = (p.get("imageinfo") or [None])[0]
            if not ii: continue
            em = ii.get("extmetadata", {})
            files.append({"title": p["title"], "repo": p.get("imagerepository"), "mime": ii.get("mime"), "w": ii.get("width"), "h": ii.get("height"), "page": ii.get("descriptionurl"),
                "lic": strip(em.get("LicenseShortName", {}).get("value"))[:40], "date": strip(em.get("DateTimeOriginal", {}).get("value"))[:40],
                "artist": strip(em.get("Artist", {}).get("value"))[:50], "desc": strip(em.get("ImageDescription", {}).get("value"))[:140]})
        cont = d.get("continue") or {}
        if not cont: break
    out[a] = files; n += 1
    if n % 15 == 0: json.dump(out, open(path, "w"), ensure_ascii=False); print(n, len(out), "/", len(arts), flush=True)
json.dump(out, open(path, "w"), ensure_ascii=False); print("done", len(out), "/", len(arts), flush=True)
