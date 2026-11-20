import json, os, re, sys
BASE = sys.argv[1]; C2 = os.path.join(BASE, "cache2"); idx = json.load(open(os.path.join(C2, "index.json")))
MONS = "January February March April May June July August September October November December".split()
out = []
def kind(t):
    tl = t.lower()
    if "marathon" in tl: return "hms"
    if any(k in tl for k in ("pole vault", "high jump", "long jump", "triple jump", "shot put")): return "metres"
    if "200 metres world" in tl or "100 metres hurdles" in tl: return "secs"
    return "ms"
for t, v in idx.items():
    if not v or "ecord progression" not in t: continue
    txt = open(os.path.join(C2, v[0]), encoding="utf-8").read().replace("&nbsp;", " ")
    k = kind(t)
    ev = re.sub(r"\s*world record progression\s*|World record progression\s*", "", t).strip()
    # section headings tell us men / women when the article covers both
    heads = [(m.start(), m.group(1).strip()) for m in re.finditer(r"\n==+\s*([^=\n]+?)\s*==+", txt)]
    for rm in re.finditer(r"\n\|-[^\n]*\n(.*?)(?=\n\|-|\n\|\})", txt, re.S):
        row = rm.group(1)
        if len(row) > 900: continue
        cells = row[:160]
        if k == "hms": m = re.search(r"(?<![\d:])([23]):(\d\d):(\d\d)", cells); dig = (int(m[1]), int(m[2])) if m else None
        elif k == "ms": m = re.search(r"(?<![\d:.])(\d{1,2}):(\d\d)(?:\.\d+)?(?![\d:])", cells); dig = (int(m[1]), int(m[2])) if m else None
        elif k == "metres": m = re.search(r"(?<![\d.])(\d{1,2})\.(\d\d)(?:\s*m\b|\s*\{\{|\s*\|)", cells); dig = (int(m[1]), int(m[2])) if m else None
        else: m = re.search(r"(?<![\d.])(\d\d)\.(\d\d)(?!\d)", cells); dig = (int(m[1]), int(m[2])) if m else None
        if not m or dig[0] > 23 or dig[1] > 59: continue
        rest = row[m.end():]
        nm = re.search(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", rest)
        if not nm: continue
        name = nm.group(1).strip()
        dm = re.search(r"(\d{1,2})\s+(" + "|".join(MONS) + r")\s+(\d{4})", row) or re.search(r"(" + "|".join(MONS) + r")\s+(\d{1,2}),\s+(\d{4})", row) or re.search(r"\{\{dts\|[^}]*?(\d{4})\|(\d{1,2})\|(\d{1,2})", row)
        if not dm: continue
        g = dm.groups()
        if g[0] in MONS: date = f"{int(g[2]):04d}-{MONS.index(g[0]) + 1:02d}-{int(g[1]):02d}"
        elif g[1] in MONS: date = f"{int(g[2]):04d}-{MONS.index(g[1]) + 1:02d}-{int(g[0]):02d}"
        else: date = f"{int(g[0]):04d}-{int(g[1]):02d}-{int(g[2]):02d}"
        h = [x[1] for x in heads if x[0] < rm.start()]
        sex = ""
        for hh in reversed(h):
            if re.search(r"women", hh, re.I): sex = "women's "; break
            if re.search(r"\bmen", hh, re.I): sex = "men's "; break
        mark = m.group(0).strip(" |{").strip()
        evn = ev if re.match(r"(Men|Women)", ev) else sex + ev
        out.append(dict(digits=f"{dig[0]:02d}:{dig[1]:02d}", mark=mark, athlete=name, event=evn.strip(), date=date, art=v[1]))
seen = set(); ded = []
for o in out:
    key = (o["event"], o["mark"], o["athlete"], o["date"])
    if key not in seen: seen.add(key); ded.append(o)
json.dump(ded, open(os.path.join(C2, "h_records.json"), "w"), ensure_ascii=False)
from collections import Counter
print("records", len(ded), "distinct digit times", len({o["digits"] for o in ded}))
print(sorted(Counter(o["digits"][:2] for o in ded).items()))
print(Counter(o["event"] for o in ded).most_common(40))
import random; random.seed(2)
for o in random.sample(ded, 14): print("  ", o["digits"], "|", o["mark"], "|", o["athlete"], "|", o["event"], "|", o["date"])
