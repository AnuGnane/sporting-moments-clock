import json, os, re, sys
BASE = sys.argv[1]; C2 = os.path.join(BASE, "cache2"); idx = json.load(open(os.path.join(C2, "index.json")))
MON = {m: i + 1 for i, m in enumerate("January February March April May June July August September October November December".split())}
CODES = {"FRA":"France","BRA":"Brazil","GER":"Germany","FRG":"West Germany","ITA":"Italy","ARG":"Argentina","ENG":"England","ESP":"Spain","NED":"Netherlands","URU":"Uruguay","POR":"Portugal","CRO":"Croatia","BEL":"Belgium",
 "SWE":"Sweden","HUN":"Hungary","TCH":"Czechoslovakia","CZE":"Czech Republic","URS":"Soviet Union","RUS":"Russia","YUG":"Yugoslavia","AUT":"Austria","SUI":"Switzerland","POL":"Poland","DEN":"Denmark","ROU":"Romania","BUL":"Bulgaria",
 "MEX":"Mexico","USA":"United States","CHI":"Chile","PAR":"Paraguay","COL":"Colombia","PER":"Peru","CRC":"Costa Rica","CMR":"Cameroon","NGA":"Nigeria","GHA":"Ghana","SEN":"Senegal","MAR":"Morocco","KOR":"South Korea","JPN":"Japan",
 "AUS":"Australia","TUR":"Turkey","GRE":"Greece","IRL":"Republic of Ireland","NIR":"Northern Ireland","SCO":"Scotland","WAL":"Wales","UKR":"Ukraine","ISL":"Iceland","SVK":"Slovakia","SVN":"Slovenia","ALG":"Algeria","KSA":"Saudi Arabia",
 "CUB":"Cuba","PRK":"North Korea","GDR":"East Germany","NOR":"Norway","CHN":"China","CAN":"Canada","ECU":"Ecuador","GEO":"Georgia","ALB":"Albania","SRB":"Serbia","SCG":"Serbia and Montenegro","JAM":"Jamaica","RSA":"South Africa","NZL":"New Zealand","FIN":"Finland","EGY":"Egypt","ZAM":"Zambia","COD":"DR Congo","CIV":"Ivory Coast","TUN":"Tunisia","INH":"Dutch East Indies","DEI":"Dutch East Indies","ZAI":"Zaire","HAI":"Haiti","IRN":"Iran","IRQ":"Iraq","UAE":"United Arab Emirates","HON":"Honduras","BOL":"Bolivia","QAT":"Qatar","PAN":"Panama","SLV":"El Salvador","ISR":"Israel","KUW":"Kuwait","ANG":"Angola","TOG":"Togo","TRI":"Trinidad and Tobago","BIH":"Bosnia and Herzegovina","CIS":"CIS","LVA":"Latvia","MLI":"Mali"}
def blocks(txt):
    for m in re.finditer(r"\{\{\s*(?:#invoke:\s*)?[Ff]ootball ?box(?: collapsible)?", txt):
        i = m.start(); d = 0; j = i
        while j < len(txt) - 1:
            if txt[j:j+2] == "{{": d += 1; j += 2
            elif txt[j:j+2] == "}}":
                d -= 1; j += 2
                if d == 0: break
            else: j += 1
        yield i, txt[i:j]
def fields(b):
    out = {}; d = 0; cur = []; parts = []
    i = 2
    while i < len(b) - 2:
        two = b[i:i+2]
        if two in ("{{", "[["): d += 1; cur.append(two); i += 2
        elif two in ("}}", "]]"): d -= 1; cur.append(two); i += 2
        elif b[i] == "|" and d == 0: parts.append("".join(cur)); cur = []; i += 1
        else: cur.append(b[i]); i += 1
    parts.append("".join(cur))
    for p in parts:
        if "=" in p:
            k, v = p.split("=", 1); out[k.strip().lower()] = v.strip()
    return out
def team(s):
    m = re.search(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", s)
    if m: return re.sub(r"\s*\{\{.*", "", m.group(1)).strip()
    m = re.search(r"\|\s*([A-Z]{3})\s*(?:\||\}\})", s)
    if m: return CODES.get(m.group(1), m.group(1))
    return re.sub(r"[\[\]{}']", "", s)[:25]
def pdate(s):
    m = re.search(r"(\d{4})\|(\d{1,2})\|(\d{1,2})", s)
    if m: return int(m[1]), int(m[2]), int(m[3])
    m = re.search(r"(\d{1,2})\s+([A-Z][a-z]+)\s+(\d{4})", s)
    if m and m[2] in MON: return int(m[3]), MON[m[2]], int(m[1])
    m = re.search(r"([A-Z][a-z]+)\s+(\d{1,2}),\s+(\d{4})", s)
    if m and m[1] in MON: return int(m[3]), MON[m[1]], int(m[2])
OFF = {"CEST": 2, "CET": 1, "BST": 1, "WEST": 1, "IST": 1, "GMT": 0, "WET": 0, "UTC": 0, "EEST": 3, "EET": 2, "TRT": 3, "MSD": 4, "MSK": 3, "AZT": 4}
def ptime(s):
    s = s.replace("&nbsp;", " ").replace("{{nbsp}}", " ")
    m = re.search(r"\{\{\s*(CES?T)\s*\|\s*(\d{1,2}):(\d\d)\s*(?:\|\s*localtz\s*=\s*([A-Z]+))?", s)
    if m:
        h = int(m[2]); mi = int(m[3])
        if m[4] and m[4] in OFF: h += OFF[m[4]] - OFF[m[1]]
        return h % 24, mi
    m = re.search(r"\((\d{1,2}):(\d\d)\s*\[*UTC", s)  # local time given in brackets
    if m and re.search(r"small", s): return int(m[1]), int(m[2])
    m = re.search(r"(\d{1,2}):(\d\d)\s*([ap])\.?m", s, re.I)
    if m:
        h = int(m[1]) % 12 + (12 if m[3].lower() == "p" else 0); return h, int(m[2])
    m = re.search(r"(\d{1,2}):(\d\d)", s)
    if m: return int(m[1]), int(m[2])
def goals(s):
    out = []; s = re.sub(r"<ref.*?(/>|</ref>)", "", s, flags=re.S)
    for chunk in re.split(r"<br\s*/?>|\n\*?|\{\{plainlist\|", s):
        g = re.search(r"\{\{\s*goal\s*\|([^}]*)\}\}", chunk, re.I)
        if not g: continue
        names = re.findall(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", chunk[:g.start()])
        name = names[-1].strip() if names else re.sub(r"[*'\s]+", " ", chunk[:g.start()]).strip()[:30]
        args = [a.strip() for a in g.group(1).split("|")]
        k = 0
        while k < len(args):
            if re.fullmatch(r"\d{1,3}(\+\d{1,2})?", args[k]):
                note = args[k + 1].lower() if k + 1 < len(args) and not re.fullmatch(r"\d{1,3}(\+\d{1,2})?", args[k + 1]) else ""
                out.append((name, args[k], "pen" if "pen" in note else "og" if "o.g" in note or "og" in note else ""))
            k += 1
    return out
def comp(title):
    y = re.search(r"\d{4}", title).group(0) if re.search(r"\d{4}", title) else ""
    if "Women's World Cup" in title: c = "Women's World Cup"
    elif "World Cup" in title: c = "World Cup"
    elif "Women's Euro" in title: c = "Women's Euro"
    elif "Champions League" in title: c = "Champions League"
    elif "European Cup" in title: c = "European Cup"
    elif "Euro" in title or "Nations' Cup" in title: c = "European Championship"
    elif "Copa América" in title: c = "Copa América"
    else: c = title
    return y, c
matches = {}
LST = json.load(open(os.path.join(C2, "lst.json")))
for t, v in idx.items():
    if not v or not (re.search(r"(final|knockout stage)", t) or t in LST) or "Olympics" in t or "World Championships" in t or "Cricket" in t or "Rugby" in t or "Snooker" in t or "Davis" in t: continue
    txt = open(os.path.join(C2, v[0]), encoding="utf-8").read()
    y, c = comp(LST[t][0] if t in LST else t)
    heads = [(m.start(), m.group(1).strip(), m.group(2).strip()) for m in re.finditer(r"\n(={2,4})\s*([^=\n]+?)\s*=+", txt)]
    for pos, b in blocks(txt):
        f = fields(b)
        d = pdate(f.get("date", "")); tm = ptime(f.get("time", "")) if f.get("time") else None
        if not d or not tm or "team1" not in f: continue
        rnd = LST[t][1] if t in LST else ("final" if "knockout" not in t else "")
        if not rnd:
            h2 = [h for h in heads if h[0] < pos and h[1] == "=="]
            rnd = re.sub(r"s$", "", h2[-1][2].lower()) if h2 else "knockout"
            rnd = {"semi-final": "semi final", "quarter-final": "quarter final", "third place play-off": "third place match", "third place playoff": "third place match", "match for third place": "third place match"}.get(rnd, rnd)
        t1, t2 = team(f["team1"]), team(f["team2"])
        key = (d, frozenset((t1, t2)))
        g1, g2 = goals(f.get("goals1", "")), goals(f.get("goals2", ""))
        pens = None
        ps = re.search(r"(\d+)\s*[–-]\s*(\d+)", f.get("penaltyscore", ""))
        if ps: pens = t1 if int(ps[1]) > int(ps[2]) else t2
        rec = dict(date=d, ko=tm, t1=t1, t2=t2, g1=g1, g2=g2, pens=pens, comp=c, year=y, round=rnd, art=v[1], final="final" in t.lower() and "knockout" not in t)
        if key not in matches or (rec["final"] and len(g1) + len(g2) >= len(matches[key]["g1"]) + len(matches[key]["g2"])) or len(g1) + len(g2) > len(matches[key]["g1"]) + len(matches[key]["g2"]):
            matches[key] = rec
out = []
for mt in matches.values():
    y, mo, dd = mt["date"]; modern = y >= 2018; ht = 15 if y >= 1980 else 10; s1 = 3 if modern else 2; s2 = 6 if modern else 4
    def clock(off): 
        tot = mt["ko"][0] * 60 + mt["ko"][1] + off; return f"{(tot // 60) % 24:02d}:{tot % 60:02d}"
    lab = f"{mt['year']} {mt['comp']} {mt['round']}"
    for side, gl in ((1, mt["g1"]), (2, mt["g2"])):
        us, them = (mt["t1"], mt["t2"]) if side == 1 else (mt["t2"], mt["t1"])
        for name, minute, note in gl:
            b, _, e = minute.partition("+"); b = int(b); e = int(e or 0); m = b + e
            if b > 122: continue
            if b <= 45: off, unc = m, 2
            elif b <= 90: off, unc = m + s1 + ht, 4
            elif b <= 105: off, unc = m + s1 + ht + s2 + 5, 6
            else: off, unc = m + s1 + ht + s2 + 8, 7
            if y < 1980: unc += 2
            cap = (f"{name} own goal gives {us} a goal against {them}" if note == "og" else f"{name} scores {'from the spot ' if note == 'pen' else ''}for {us} against {them}") + f", {lab}"
            out.append(dict(sport="Football", moment=cap, date=f"{y:04d}-{mo:02d}-{dd:02d}", start=f"{mt['ko'][0]:02d}:{mt['ko'][1]:02d}", gclock=(f"{b}+{e}" if e else str(b)) + " min", mm=m, local=clock(off), unc=unc, basis="K", art=mt["art"], kind="goal"))
    if mt["pens"]:
        out.append(dict(sport="Football", moment=f"{mt['pens']} beat {mt['t2'] if mt['pens'] == mt['t1'] else mt['t1']} on penalties, {lab}", date=f"{y:04d}-{mo:02d}-{dd:02d}", start=f"{mt['ko'][0]:02d}:{mt['ko'][1]:02d}",
            gclock="Penalty shootout", mm=None, local=clock(174 if modern else (165 if y >= 1980 else 160)), unc=8, basis="K", art=mt["art"], kind="pens"))
json.dump(out, open(os.path.join(C2, "h_football.json"), "w"), ensure_ascii=False)
from collections import Counter
print("matches", len(matches), "moments", len(out), Counter(m["comp"] for m in matches.values()).most_common())
print("distinct minutes", len({o["local"] for o in out}), "hours", sorted(Counter(o["local"][:2] for o in out).items()))
import random; random.seed(3)
for o in random.sample(out, 4): print("  ", o["date"], o["start"], o["gclock"], "->", o["local"], "|", o["moment"][:95])
for o in out:
    if o["date"] in ("2022-12-09",) and o["start"] == "22:00": print("  *", o["date"], o["start"], o["gclock"], "->", o["local"], "|", o["moment"][:90])
