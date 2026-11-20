import json, time, sys, os, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.1 (feasibility study script; python-urllib)"
BASE = sys.argv[1]
CACHE = os.path.join(BASE, "cache")
def api(host, params, tries=7):
    url = f"https://{host}/w/api.php?" + urllib.parse.urlencode(params)
    delay = 4
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code in (429, 503):
                time.sleep(delay); delay = min(delay * 2, 60); continue
            raise
        except Exception as e:
            time.sleep(delay); delay = min(delay * 2, 60)
    return None
titles = []
for fn, idx in (("football.txt", 5), ("other.txt", 9)):
    for line in open(os.path.join(BASE, fn), encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        t = line.rstrip("\n").split("|")[idx].strip()
        if t and t not in titles: titles.append(t)
resolved_path = os.path.join(CACHE, "resolved.json")
resolved = json.load(open(resolved_path)) if os.path.exists(resolved_path) else {}
def safe(t): return urllib.parse.quote(t, safe="") + ".txt"
todo = [t for t in titles if t not in resolved]
print(len(titles), "titles,", len(todo), "to fetch", flush=True)
for i in range(0, len(todo), 12):
    batch = todo[i:i+12]
    d = api("en.wikipedia.org", {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
        "titles": "|".join(batch), "redirects": 1, "format": "json", "formatversion": 2})
    time.sleep(1.5)
    if not d: print("FAIL", batch, flush=True); continue
    q = d.get("query", {})
    m = {}
    for n in q.get("normalized", []): m[n["from"]] = n["to"]
    for n in q.get("redirects", []): m[n["from"]] = n["to"]
    pages = {p["title"]: p for p in q.get("pages", [])}
    for t in batch:
        final = t
        for _ in range(3): final = m.get(final, final)
        p = pages.get(final)
        if p and not p.get("missing") and p.get("revisions"):
            txt = p["revisions"][0]["slots"]["main"]["content"]
            open(os.path.join(CACHE, safe(t)), "w", encoding="utf-8").write(txt)
            resolved[t] = final
        elif p and not p.get("missing"):
            # content truncated by batch limit: fetch alone
            d2 = api("en.wikipedia.org", {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                "titles": final, "redirects": 1, "format": "json", "formatversion": 2})
            time.sleep(1.5)
            try:
                txt = d2["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
                open(os.path.join(CACHE, safe(t)), "w", encoding="utf-8").write(txt); resolved[t] = final
            except Exception: print("NOCONTENT", t, flush=True)
        else:
            s = api("en.wikipedia.org", {"action": "query", "list": "search", "srsearch": t, "srlimit": 1, "format": "json"})
            time.sleep(1.5)
            try:
                hit = s["query"]["search"][0]["title"]
                d2 = api("en.wikipedia.org", {"action": "query", "prop": "revisions", "rvprop": "content", "rvslots": "main",
                    "titles": hit, "redirects": 1, "format": "json", "formatversion": 2})
                time.sleep(1.5)
                txt = d2["query"]["pages"][0]["revisions"][0]["slots"]["main"]["content"]
                open(os.path.join(CACHE, safe(t)), "w", encoding="utf-8").write(txt)
                resolved[t] = "SEARCH:" + hit
            except Exception as e:
                print("MISSING", t, e, flush=True)
    json.dump(resolved, open(resolved_path, "w"), ensure_ascii=False, indent=0)
print("done", len(resolved), flush=True)
