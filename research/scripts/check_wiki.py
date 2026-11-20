import json, os, re, sys, urllib.parse
BASE = sys.argv[1]; which = sys.argv[2]
CACHE = os.path.join(BASE, "cache")
resolved = json.load(open(os.path.join(CACHE, "resolved.json")))
MONTHS = ["January","February","March","April","May","June","July","August","September","October","November","December"]
def load(t):
    p = os.path.join(CACHE, urllib.parse.quote(t, safe="") + ".txt")
    return open(p, encoding="utf-8").read() if os.path.exists(p) else None
def clean(s):
    s = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", s); s = re.sub(r"[\[\]]", "", s)
    s = re.sub(r"<ref.*", "", s)
    return s.strip()[:70]
if which == "football":
    for line in open(os.path.join(BASE, "football.txt"), encoding="utf-8"):
        if line.startswith("#"): continue
        f = line.rstrip("\n").split("|")
        title, date, tz, ko, minute, wiki = f[:6]
        y, m, d = date.split("-"); mon = MONTHS[int(m)-1]
        txt = load(wiki)
        if txt is None: print(f"-- NOART | {date} {ko} | {title[:40]} | {wiki}"); continue
        pairs = []
        for mt in re.finditer(r"\|\s*date\s*=\s*([^\n]+)", txt):
            seg = txt[mt.end(): mt.end()+500]
            tm = re.search(r"\|\s*time\s*=\s*([^\n]+)", seg)
            ds = mt.group(1)
            if re.search(rf"\b{int(d)}\b", ds) and (mon in ds or mon[:3] in ds or re.search(rf"\|\s*0?{int(m)}\s*\|", ds)):
                pairs.append((clean(ds), clean(tm.group(1)) if tm else "?"))
        # infobox kickoff fields
        other = [clean(x) for x in re.findall(r"\|\s*(?:time|kick-?off)\s*=\s*([^\n]+)", txt)][:2] if not pairs else []
        res = resolved.get(wiki, "")
        flag = "" if res == wiki else f" [{res}]"
        print(f"{date} {ko} m{minute:6} | {title[:38]:38} | {pairs[:2] or ('ANY', other)}{flag}")
else:
    for line in open(os.path.join(BASE, "other.txt"), encoding="utf-8"):
        if line.startswith("#"): continue
        f = line.rstrip("\n").split("|")
        sport, title, date, tz, start, gclock, clock, basis, unc, wiki = f[:10]
        txt = load(wiki)
        if txt is None: print(f"-- NOART | {title[:40]} | {wiki}"); continue
        txt2 = re.sub(r"\{\{nbsp\}\}|&nbsp;| ", " ", txt)
        hits = []
        cands = []
        for t in (clock, start):
            if not t: continue
            h, mi = t.split(":"); h = int(h)
            cands += [f"{h}:{mi}", f"{h:02d}:{mi}", f"{(h-1)%12+1}:{mi}", f"{(h-1)%12+1}.{mi}"]
        for c in dict.fromkeys(cands):
            for mt in re.finditer(r"(?<!\d)" + re.escape(c) + r"(?!\d)", txt2):
                s = txt2[max(0, mt.start()-70): mt.end()+45].replace("\n", " ")
                hits.append(f"<{c}> …{s}…")
                if len(hits) >= 3: break
            if len(hits) >= 3: break
        if not hits:
            for mt in re.finditer(r"(?<!\d)\d{1,2}[:.]\d{2}\s*(?:[ap]\.?m\b|[AP]M\b|[A-Z]{2,4}T\b|local)", txt2):
                s = txt2[max(0, mt.start()-60): mt.end()+40].replace("\n", " ")
                hits.append("?? …" + s + "…")
                if len(hits) >= 3: break
        res = resolved.get(wiki, "")
        flag = "" if res == wiki else f" [{res}]"
        print(f"## {date} start={start or '-'} clock={clock or '-'} {basis} | {title[:45]}{flag}")
        for h in hits: print("     " + h[:230])
