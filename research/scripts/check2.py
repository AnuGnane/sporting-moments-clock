import json, os, re, sys, urllib.parse
BASE = sys.argv[1]
CACHE = os.path.join(BASE, "cache")
MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]
def load(t):
    for pre in ("", "X_"):
        p = os.path.join(CACHE, pre + urllib.parse.quote(t, safe="") + ".txt")
        if os.path.exists(p): return open(p, encoding="utf-8").read()
    return None
def clean(s):
    s = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", s); s = re.sub(r"[\[\]]", "", s); s = re.sub(r"<ref.*", "", s)
    return s.replace("&nbsp;", " ").strip()[:40]
for line in open(os.path.join(BASE, "football.txt"), encoding="utf-8"):
    if line.startswith("#"): continue
    f = line.rstrip("\n").split("|")
    title, date, tz, ko, minute, wiki = f[:6]
    y, m, d = date.split("-"); mon = MONTHS[int(m)-1]
    txt = load(wiki)
    if txt is None: print("NOART", title[:40]); continue
    dated, anyt = [], []
    for mt in re.finditer(r"\|\s*(?:time|kick-?off)\s*=\s*([^\n|]+)", txt):
        back = txt[max(0, mt.start()-700): mt.start()]
        fwd = txt[mt.end(): mt.end()+250]
        val = clean(mt.group(1))
        if not re.search(r"\d", val): continue
        anyt.append(val)
        pat = rf"(\b{int(d)}\s+{mon}\s+{y}|{mon}\s+{int(d)},\s+{y}|\|{y}\|0?{int(m)}\|0?{int(d)}\b)"
        if re.search(pat, back[-350:]) or re.search(pat, fwd):
            teams = re.findall(r"team[12]\s*=\s*([^\n|]+)", back[-350:] + fwd)
            dated.append(val + " " + "/".join(clean(t)[:14] for t in teams[:2]))
    ok = any(ko in x for x in dated) or (not dated and any(ko in x for x in anyt[:3]) and len(set(anyt)) <= 2)
    print(("OK   " if ok else "CHECK") + f" {date} {ko} | {title[:34]:34} | dated={dated[:4]} any={list(dict.fromkeys(anyt))[:3] if not ok else ''}")
