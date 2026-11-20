import json, os, re, sys
from datetime import date
BASE = sys.argv[1]; CACHE = os.path.join(BASE, "cache")
af = json.load(open(os.path.join(CACHE, "artfiles.json"))); fi = json.load(open(os.path.join(CACHE, "fileinfo.json")))
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
rows = json.load(open(os.path.join(CACHE, "rows.json")))
MON = {m: i+1 for i, m in enumerate(["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"])}
def pdate(s):
    if not s: return None
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        try: return date(int(m[1]), int(m[2]), int(m[3]))
        except ValueError: pass
    m = re.search(r"(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?,?\s+(\d{4})", s)
    if m and m[2].lower() in MON: return date(int(m[3]), MON[m[2].lower()], int(m[1]))
    m = re.search(r"([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})", s)
    if m and m[1].lower() in MON: return date(int(m[3]), MON[m[1].lower()], int(m[2]))
    m = re.search(r"(1[89]\d\d|20\d\d)", s)
    return int(m[1]) if m else None
MULTI = re.compile(r"(knockout|Group|season|Tour de France|Ashes series|playoffs|Pool|qualif|Trophy|T20 World Cup$|tour to|Hour record|FA Cup$|El Clásico|derby|Tournoi|Men's singles$|Championships – Men's singles$)", re.I)
def classify(r):
    art = resolved.get(r["wiki"], r["wiki"]).replace("SEARCH:", "")
    y, mo, d = map(int, r["date"].split("-")); ev = date(y, mo, d)
    cands = []
    STOP = {"The","World","Cup","Final","England","Germany","Brazil","Italy","Super","Saturday","Olympic","Wembley","Miracle","Century","Game","Series","Grand","National","Masters","Tour","London","Paris","Berlin","Beijing","Liverpool","Manchester","City","Champions","League","Euros","Wimbledon","Open","Ice","Jungle","Manila","Mans","Cubs","Red","Sox"}
    kws = [w for w in re.findall(r"[A-ZÀ-Ý][a-zà-ÿ]{3,}", r["moment"]) if w not in STOP]
    for f in af.get(art, []):
        x = fi.get(f)
        if not x or x.get("repo") != "shared" or x.get("mime") not in ("image/jpeg", "image/png") or (x.get("w") or 0) < 700: continue
        pd = pdate(x["date"]) or pdate(x["desc"]) or pdate(f)
        day = isinstance(pd, date) and abs((pd - ev).days) <= 1
        yr = (pd.year if isinstance(pd, date) else pd) == y
        kw = any(k.lower() in (f + " " + x["desc"]).lower() for k in kws)
        cands.append((day, yr, x["w"], f, x, kw))
    is_person = not re.search(r"\d{4}", art) and not MULTI.search(art)
    single = bool(re.search(str(y), art)) and not MULTI.search(art)
    best = None; tier = "D"
    days = [c for c in cands if c[0]]; yrs = [c for c in cands if c[1] and not c[0]]
    if days: best = max(days, key=lambda c: (c[5], c[2])); tier = "A"
    elif yrs and single: best = max(yrs, key=lambda c: c[2]); tier = "B"
    elif yrs: best = max(yrs, key=lambda c: c[2]); tier = "B?"
    elif cands: best = max(cands, key=lambda c: c[2]); tier = "C"
    return tier, best, len(cands), art
if __name__ == "__main__":
    from collections import Counter
    cnt = Counter()
    for r in rows:
        tier, best, n, art = classify(r); cnt[tier] += 1
        if best:
            _, _, w, f, x, kw = best
            print(f"{r['id']} {tier:2} {'K' if kw else ' '} n={n:2} | {r['moment'][:30]:30} | {f[5:60]:55} | {x['date'][:12]:12} | {w} | {x['lic'][:12]} | {x['desc'][:50]}")
        else: print(f"{r['id']} {tier:2} n= 0 | {r['moment'][:30]:30} | [{art[:40]}]")
    print(cnt)
