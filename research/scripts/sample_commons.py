import json, time, sys, re, urllib.parse, urllib.request, urllib.error
UA = "SportsClockResearch/0.1 (feasibility study script; python-urllib)"
sample = json.load(open(sys.argv[1] + "/cache/sample.json"))
out = {}
for i, q in sample:
    params = {"action": "query", "generator": "search", "gsrsearch": q + " filetype:bitmap", "gsrnamespace": 6, "gsrlimit": 6, "prop": "imageinfo",
              "iiprop": "size|extmetadata", "iiextmetadatafilter": "DateTimeOriginal", "format": "json", "formatversion": 2}
    url = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(params)
    for attempt in range(5):
        try:
            d = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=40))
            hits = [(p["title"][5:70], (p.get("imageinfo") or [{}])[0].get("width"), re.sub(r"<[^>]+>", "", ((p.get("imageinfo") or [{}])[0].get("extmetadata") or {}).get("DateTimeOriginal", {}).get("value", ""))[:12])
                    for p in sorted(d.get("query", {}).get("pages", []), key=lambda x: x.get("index", 9))]
            out[i] = hits; print(i, q, "->", len(hits), flush=True)
            for h in hits: print("     ", h, flush=True)
            break
        except urllib.error.HTTPError as e:
            ra = e.headers.get("retry-after"); time.sleep(int(ra) + 2 if ra and ra.isdigit() else 50)
    else: print(i, q, "FAILED", flush=True)
    time.sleep(8)
json.dump(out, open(sys.argv[1] + "/cache/sample_out.json", "w"))
