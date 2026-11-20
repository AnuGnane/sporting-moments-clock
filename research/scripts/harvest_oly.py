import json, os, re, sys
BASE = sys.argv[1]; C2 = os.path.join(BASE, "cache2"); idx = json.load(open(os.path.join(C2, "index.json")))
MON = {m: i + 1 for i, m in enumerate("January February March April May June July August September October November December".split())}
CITY = {1996: "Atlanta", 2000: "Sydney", 2004: "Athens", 2008: "Beijing", 2012: "London", 2016: "Rio", 2020: "Tokyo", 2024: "Paris"}
def dur(s):
    s = s.strip()
    m = re.fullmatch(r"(\d):(\d\d):(\d\d)(?:\.\d+)?", s)
    if m: return int(m[1]) * 60 + int(m[2]) + int(m[3]) / 60
    m = re.fullmatch(r"(\d{1,2}):(\d\d)(?:\.\d+)?", s)
    if m: return int(m[1]) + int(m[2]) / 60
    return 0.3 if re.fullmatch(r"\d{1,2}\.\d+", s) else None
out = []; miss = 0; WHY = []
for t, v in idx.items():
    m0 = re.match(r"(Athletics|Swimming) at the (\d{4}) Summer Olympics – (Men's|Women's) (.+)", t)
    if not v or not m0 or int(m0.group(2)) not in CITY: continue
    sport, y, g, ev = m0.group(1), int(m0.group(2)), m0.group(3), m0.group(4)
    txt = open(os.path.join(C2, v[0]), encoding="utf-8").read().replace("&nbsp;", " ").replace("{{nbsp}}", " ")
    gm = re.search(r"\|\s*gold\s*=\s*([^\n]+)", txt); wv = re.search(r"\|\s*win_value\s*=\s*([^\n<{|]+)", txt)
    if not gm: miss += 1; continue
    names = re.findall(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", gm.group(1))
    gold = names[0] if names else re.sub(r"[{}\[\]|]", " ", gm.group(1)).strip()
    noc = re.search(r"\|\s*goldNOC\s*=\s*([A-Z]{3})", txt)
    if "relay" in ev and noc: gold = noc.group(1)
    win = wv.group(1).strip() if wv else ""
    win = re.sub(r"\s*(WR|OR|AR|NR|\(.*)$", "", win).strip()
    tm = dt = None
    head = txt[:3000]
    cands = [c for c in re.findall(r"\|\s*dates\s*=\s*([^\n]+)", head) + re.findall(r"\|\s*date\s*=\s*([^\n]+)", head) if any(re.search(rf"\d{{1,2}}\s+{k}|{k}\s+\d{{1,2}}", c) for k in MON)]
    im = cands[0] if cands else None
    if im:
        ds = im
        seg = [z for z in re.split(r"<br\s*/?>|\n|\|", ds) if any(k in z for k in MON)]
        fin = [x for x in seg if re.search(r"(?<![a-z])finals?\b", x, re.I)] or seg[-1:]
        x = fin[-1]
        mm_ = re.search(r"(\d{1,2})\s+([A-Z][a-z]+)\s*(\d{4})?", x) ; mm2 = re.search(r"([A-Z][a-z]+)\s+(\d{1,2})(?!\d)", x)
        sd = re.search(r"(\d{4})\|(\d{1,2})\|(\d{1,2})", x)
        yy = y if y != 2020 else 2021
        if sd: dt = (int(sd[1]), int(sd[2]), int(sd[3]))
        elif mm_ and mm_[2] in MON:
            rng = re.search(r"\d{1,2}\s*[–-]\s*(\d{1,2})\s+" + mm_[2], x)
            dt = (yy, MON[mm_[2]], int(rng[1]) if rng else int(mm_[1]))
        elif mm2 and mm2[1] in MON: dt = (yy, MON[mm2[1]], int(mm2[2]))
    if dt:
        mname = [k for k, v_ in MON.items() if v_ == dt[1]][0]
        pats = [rf"\b{dt[2]}\s+{mname}", rf"{mname}\s+{dt[2]}\b"]
        for row in re.split(r"\n\|-", txt):
            if "Final" not in row or "flagIOC" in row or len(row) > 600 or not any(re.search(p, row) for p in pats): continue
            times = re.findall(r"(?<![\d:.])(\d{1,2}):(\d\d)(?![\d:.])", row)
            labels = re.findall(r"(Finals?|Semi-?finals?|Heats?|Round \d|Quarter-?finals?|Preliminar\w+|Repechage\w*)", row)
            labels = ["Final" if l.startswith("Final") else l for l in labels]
            if labels and len(times) == len(labels) and "Final" in labels: tm = times[labels.index("Final")]
            elif len(times) == 1: tm = times[0]
            if tm: break
        if not tm:
            got = set()
            for row in re.split(r"\n\|-", txt):
                if not re.search(r"Finals?\b", row) or "flagIOC" in row or len(row) > 600: continue
                times = re.findall(r"(?<![\d:.])(\d{1,2}):(\d\d)(?![\d:.])", row)
                labels = ["Final" if l.startswith("Final") else l for l in re.findall(r"(Finals?|Semi-?finals?|Heats?|Round \d|Quarter-?finals?|Preliminar\w+|Repechage\w*)", row)]
                if labels and len(times) == len(labels) and "Final" in labels: got.add(times[labels.index("Final")])
                elif len(times) == 1 and labels == ["Final"]: got.add(times[0])
            if len(got) == 1: tm = got.pop()
        if not tm:
            for p in pats:
                pm = re.search(r"final[^.\n]{0,80}?" + p + r"[^.\n]{0,60}?\bat\s+(\d{1,2}):(\d\d)", txt, re.I) or re.search(p + r"[^.\n]{0,40}?\bat\s+(\d{1,2}):(\d\d)[^.\n]{0,40}final", txt, re.I)
                if pm: tm = (pm[1], pm[2]); break
    if not tm or not dt or not dt[1]:
        miss += 1; WHY.append((t[-34:], 'nodate' if not dt else 'notime', (im or '')[:70])); continue
    d = dur(win) if win else None
    start = int(tm[0]) * 60 + int(tm[1]); fin = start + (round(d) if d and d >= 1 else 0)
    evn = ev.replace("metres", "metres").replace("metre ", "metres ")
    cap = f"Gold for {gold} in the {g.lower().replace('men', 'men')} {evn}, {CITY[y]} {y}" + (f", in {win}" if win else "")
    out.append(dict(sport=sport, moment=cap, date=f"{dt[0]:04d}-{dt[1]:02d}-{dt[2]:02d}", start=f"{int(tm[0]):02d}:{tm[1]}", gclock=win, mm=None, local=f"{(fin // 60) % 24:02d}:{fin % 60:02d}",
                    unc=4 if not d or d < 60 else 3, basis="S", art=v[1], kind="olympic final"))
json.dump(out, open(os.path.join(C2, "h_olympic.json"), "w"), ensure_ascii=False)
from collections import Counter
print("olympic moments", len(out), "missed", miss, "distinct minutes", len({o["local"] for o in out}), sorted(Counter(o["local"][:2] for o in out).items()))
import random; random.seed(5)
for o in out:
    if any(k in o["moment"] for k in ("Bolt in the men's 100 metres, Beijing", "Phelps in the men's 100 metres butterfly", "Ingebrigtsen in the men's 5000", "McKeon in the women's 50", "El Guerrouj in the men's 1500", "Farah in the men's 10,000 metres, London", "Kipchoge in the men's marathon")): print("  ", o["date"], o["start"], "->", o["local"], "|", o["moment"])

from collections import Counter as C2_
print(C2_(w[1] for w in WHY))
for w in [w for w in WHY if w[1]=="nodate"][:4]+[w for w in WHY if w[1]=="notime"][:4]: print(w)
