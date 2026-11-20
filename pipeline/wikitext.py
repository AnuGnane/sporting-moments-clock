"""Wikitext helpers for reading the cached football and Olympic pages.

The football box parsing (blocks, fields, team, pdate, ptime, CODES) is copied
from research/scripts/harvest_fb.py so that a harvested row can be traced back
to exactly the match box it came from. Do not "improve" these functions without
re-checking that every harvested row still matches one box.
"""
import json
import os
import re

MON = {m: i + 1 for i, m in enumerate("January February March April May June July August September October November December".split())}

CODES = {"FRA": "France", "BRA": "Brazil", "GER": "Germany", "FRG": "West Germany", "ITA": "Italy", "ARG": "Argentina", "ENG": "England", "ESP": "Spain", "NED": "Netherlands", "URU": "Uruguay", "POR": "Portugal", "CRO": "Croatia", "BEL": "Belgium",
         "SWE": "Sweden", "HUN": "Hungary", "TCH": "Czechoslovakia", "CZE": "Czech Republic", "URS": "Soviet Union", "RUS": "Russia", "YUG": "Yugoslavia", "AUT": "Austria", "SUI": "Switzerland", "POL": "Poland", "DEN": "Denmark", "ROU": "Romania", "BUL": "Bulgaria",
         "MEX": "Mexico", "USA": "United States", "CHI": "Chile", "PAR": "Paraguay", "COL": "Colombia", "PER": "Peru", "CRC": "Costa Rica", "CMR": "Cameroon", "NGA": "Nigeria", "GHA": "Ghana", "SEN": "Senegal", "MAR": "Morocco", "KOR": "South Korea", "JPN": "Japan",
         "AUS": "Australia", "TUR": "Turkey", "GRE": "Greece", "IRL": "Republic of Ireland", "NIR": "Northern Ireland", "SCO": "Scotland", "WAL": "Wales", "UKR": "Ukraine", "ISL": "Iceland", "SVK": "Slovakia", "SVN": "Slovenia", "ALG": "Algeria", "KSA": "Saudi Arabia",
         "CUB": "Cuba", "PRK": "North Korea", "GDR": "East Germany", "NOR": "Norway", "CHN": "China", "CAN": "Canada", "ECU": "Ecuador", "GEO": "Georgia", "ALB": "Albania", "SRB": "Serbia", "SCG": "Serbia and Montenegro", "JAM": "Jamaica", "RSA": "South Africa", "NZL": "New Zealand", "FIN": "Finland", "EGY": "Egypt", "ZAM": "Zambia", "COD": "DR Congo", "CIV": "Ivory Coast", "TUN": "Tunisia", "INH": "Dutch East Indies", "DEI": "Dutch East Indies", "ZAI": "Zaire", "HAI": "Haiti", "IRN": "Iran", "IRQ": "Iraq", "UAE": "United Arab Emirates", "HON": "Honduras", "BOL": "Bolivia", "QAT": "Qatar", "PAN": "Panama", "SLV": "El Salvador", "ISR": "Israel", "KUW": "Kuwait", "ANG": "Angola", "TOG": "Togo", "TRI": "Trinidad and Tobago", "BIH": "Bosnia and Herzegovina", "CIS": "CIS", "LVA": "Latvia", "MLI": "Mali"}


def blocks(txt):
    for m in re.finditer(r"\{\{\s*(?:#invoke:\s*)?[Ff]ootball ?box(?: collapsible)?", txt):
        i = m.start(); d = 0; j = i
        while j < len(txt) - 1:
            if txt[j:j + 2] == "{{": d += 1; j += 2
            elif txt[j:j + 2] == "}}":
                d -= 1; j += 2
                if d == 0: break
            else: j += 1
        yield i, txt[i:j]


def fields(b):
    out = {}; d = 0; cur = []; parts = []
    i = 2
    while i < len(b) - 2:
        two = b[i:i + 2]
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
    m = re.search(r"\((\d{1,2}):(\d\d)\s*\[*UTC", s)
    if m and re.search(r"small", s): return int(m[1]), int(m[2])
    m = re.search(r"(\d{1,2}):(\d\d)\s*([ap])\.?m", s, re.I)
    if m:
        h = int(m[1]) % 12 + (12 if m[3].lower() == "p" else 0); return h, int(m[2])
    m = re.search(r"(\d{1,2}):(\d\d)", s)
    if m: return int(m[1]), int(m[2])


def strip_links(s):
    """'[[A|B]], [[C]]' -> 'B, C'. Drops refs, templates and HTML."""
    s = re.sub(r"<ref[^>]*/>|<ref.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"\{\{efn[^{}]*(\{\{[^{}]*\}\}[^{}]*)*\}\}", "", s, flags=re.S)
    s = re.sub(r"<[^>]+>", " ", s)
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", r"\1", s)
    s = re.sub(r"\{\{[^{}]*\}\}", "", s)
    s = s.replace("\xa0", " ")
    return re.sub(r"\s+", " ", s).strip(" ,")


def link_targets(s):
    return [m.group(1).strip() for m in re.finditer(r"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]", s)]


def load_index(cache2):
    idx = json.load(open(os.path.join(cache2, "index.json"), encoding="utf-8"))
    by_title = {}
    for t, v in idx.items():
        if v:
            by_title.setdefault(v[1], v[0])
            by_title.setdefault(t, v[0])
    return by_title


ABBR_OFFSETS = {"CEST": [120], "CET": [60], "WEST": [60], "WET": [0], "BST": [60], "GMT": [0], "EEST": [180], "EET": [120], "MSK": [180], "MSD": [240],
                "SAMT": [240], "TRT": [180], "AZT": [240], "BRT": [-180], "ART": [-180], "UYT": [-180], "CLT": [-240, -180], "CLST": [-180],
                "EDT": [-240], "EST": [-300], "CDT": [-300], "CST": [-360, 480], "MDT": [-360], "MST": [-420], "PDT": [-420], "PST": [-480],
                "ADT": [-180], "AEDT": [660], "AEST": [600], "ACST": [570], "NZST": [720], "KST": [540], "JST": [540], "SAST": [120], "AST": [180]}


def stated_utc_kickoffs(time_field):
    """All UTC kickoff minutes (mod 1440) the box time field supports.

    Each 'HH:MM ABBR' or 'HH:MM (UTC+n)' pair gives one candidate. Empty when
    the field names no zone at all.
    """
    s = time_field.replace("&nbsp;", " ").replace("{{nbsp}}", " ").replace("−", "-").replace("–", "-")
    s = re.sub(r"<ref[^>]*/>|<ref.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"\{\{efn.*", "", s, flags=re.S)
    s = re.sub(r"\{\{\s*(CES?T)\s*\|\s*(\d{1,2}:\d\d)[^}]*\}\}", r"\2 \1", s)
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", r"\1", s)
    s = re.sub(r"<[^>]+>|\{\{small\||\}\}", " ", s)
    out = set()
    for t in re.finditer(r"(?<![\d+-])(\d{1,2})[:.](\d\d)(?!\d)(?:\s*([ap])\.?\s*m\.?(?![a-z]))?", s, re.I):
        h = int(t[1])
        if t[3]:
            h = h % 12 + (12 if t[3].lower() == "p" else 0)
        rest = s[t.end():t.end() + 40]
        m = re.match(r"\s*\(?\s*UTC\s*([+-])\s*(\d{1,2})(?::?(\d\d))?", rest)
        if m:
            offs = [(int(m[2]) * 60 + int(m[3] or 0)) * (1 if m[1] == "+" else -1)]
        else:
            a = re.match(r"\s*\(?\s*([A-Z]{3,5})\b", rest)
            offs = ABBR_OFFSETS.get(a[1], []) if a else []
            if a and a[1] in ABBR_OFFSETS:
                m2 = re.match(r"\s*\(?\s*[A-Z]{3,5}\s*\)?\s*\(\s*UTC\s*([+-])\s*(\d{1,2})(?::?(\d\d))?", rest)
                if m2:
                    offs = [(int(m2[2]) * 60 + int(m2[3] or 0)) * (1 if m2[1] == "+" else -1)]
        for o in offs:
            out.add((h * 60 + int(t[2]) - o) % 1440)
    return out


def stated_utc_offset(time_field):
    """Return the UTC offset in minutes written in a football box time field, or None.

    Only explicit 'UTC+2', 'UTC−03:00' style text counts. If the field carries a
    second time in brackets the offset may belong to that time, so the caller
    gets (offset, time_it_belongs_to) where time_it_belongs_to is (h, m) or None.
    """
    s = time_field.replace("&nbsp;", " ").replace("{{nbsp}}", " ").replace("−", "-").replace("–", "-")
    s = re.sub(r"<ref[^>]*/>|<ref.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"\{\{efn.*", "", s, flags=re.S)
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]", r"\1", s)
    offs = list(re.finditer(r"UTC\s*([+-])\s*(\d{1,2})(?::?(\d\d))?", s))
    if not offs:
        return None
    m = offs[-1]
    off = (int(m[2]) * 60 + int(m[3] or 0)) * (1 if m[1] == "+" else -1)
    times = list(re.finditer(r"(?<![\d+-])(\d{1,2})[:.](\d\d)(?!\d)(?:\s*([ap])\.?\s*m\.?(?![a-z]))?", s[:m.start()], re.I))
    if not times:
        return off, None
    t = times[-1]
    h = int(t[1])
    if t[3]:
        h = h % 12 + (12 if t[3].lower() == "p" else 0)
    return off, (h, int(t[2]))
