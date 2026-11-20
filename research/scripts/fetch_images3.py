import json, time, sys, os, re, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.1 (feasibility study script; python-urllib)"
BASE = sys.argv[1]; CACHE = os.path.join(BASE, "cache")
def api(params, tries=9):
    data = urllib.parse.urlencode(params).encode()
    delay = 5
    for i in range(tries):
        try:
            req = urllib.request.Request("https://en.wikipedia.org/w/api.php", data=data, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=60) as r: return json.load(r)
        except urllib.error.HTTPError as e:
            ra = e.headers.get("retry-after")
            print("HTTP", e.code, "retry-after", ra, flush=True)
            time.sleep(min(int(ra) + 1 if ra and ra.isdigit() else delay, 90)); delay = min(delay * 2, 60)
        except Exception as ex:
            print("ERR", ex, flush=True); time.sleep(delay); delay = min(delay * 2, 60)
    return None
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
arts = []
for fn, wi in (("football.txt", 5), ("other.txt", 9)):
    for line in open(os.path.join(BASE, fn), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        w = line.rstrip("\n").split("|")[wi].strip()
        a = resolved.get(w, w).replace("SEARCH:", "")
        if a and a not in arts: arts.append(a)
# step 1: file names per article
p1 = os.path.join(CACHE, "artfiles.json")
af = json.load(open(p1)) if os.path.exists(p1) else {}
todo = [a for a in arts if a not in af]
for i in range(0, len(todo), 25):
    b = todo[i:i+25]; cont = {}; got = {t: [] for t in b}
    while True:
        d = api({"action": "query", "prop": "images", "imlimit": 500, "titles": "|".join(b), "redirects": 1, "format": "json", "formatversion": 2, **cont})
        time.sleep(2)
        if not d: break
        q = d.get("query", {}); m = {}
        for n in q.get("normalized", []) + q.get("redirects", []): m[n["to"]] = n["from"]
        for p in q.get("pages", []):
            k = p["title"]
            for _ in range(3): k = m.get(k, k) if k not in got else k
            if k in got: got[k] += [x["title"] for x in p.get("images", [])]
        cont = d.get("continue") or {}
        if not cont: break
    af.update(got); json.dump(af, open(p1, "w"), ensure_ascii=False); print("files", len(af), "/", len(arts), flush=True)
# step 2: imageinfo for bitmap files
p2 = os.path.join(CACHE, "fileinfo.json")
fi = json.load(open(p2)) if os.path.exists(p2) else {}
BAD = re.compile(r"(flag|icon|logo|kit[ _]|pictogram|symbol|crystal|ambox|edit-clear|commons-|wik|question|map|location|soccer[ _]?ball|football pictogram|medal|jersey|\.svg$|\.gif$|\.ogg$|\.ogv$|\.webm$|\.pdf$|\.tiff?$)", re.I)
files = sorted({f for v in af.values() for f in v if not BAD.search(f)})
todo = [f for f in files if f not in fi]
print("bitmap candidates", len(files), "todo", len(todo), flush=True)
strip = lambda s: re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()
for i in range(0, len(todo), 45):
    b = todo[i:i+45]
    d = api({"action": "query", "titles": "|".join(b), "prop": "imageinfo", "iiprop": "size|url|mime|extmetadata",
             "iiextmetadatafilter": "LicenseShortName|DateTimeOriginal|Artist|ImageDescription", "format": "json", "formatversion": 2})
    time.sleep(2)
    if not d: continue
    m = {n["to"]: n["from"] for n in d.get("query", {}).get("normalized", [])}
    for p in d.get("query", {}).get("pages", []):
        ii = (p.get("imageinfo") or [None])[0]
        k = m.get(p["title"], p["title"])
        if not ii: fi[k] = None; continue
        em = ii.get("extmetadata", {})
        fi[k] = {"repo": p.get("imagerepository"), "mime": ii.get("mime"), "w": ii.get("width"), "h": ii.get("height"), "page": ii.get("descriptionurl"),
            "lic": strip(em.get("LicenseShortName", {}).get("value"))[:40], "date": strip(em.get("DateTimeOriginal", {}).get("value"))[:40],
            "artist": strip(em.get("Artist", {}).get("value"))[:50], "desc": strip(em.get("ImageDescription", {}).get("value"))[:140]}
    json.dump(fi, open(p2, "w"), ensure_ascii=False); print("info", len(fi), "/", len(files), flush=True)
print("done", flush=True)
