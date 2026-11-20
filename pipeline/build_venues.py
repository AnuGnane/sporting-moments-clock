"""Build data/overrides/venues.csv: venue time zone and place for every harvested row.

Football rows are traced back to the exact match box in the cached Wikipedia
page named by their time_source (same date, same kickoff, both team names in the
caption). The box's stadium field gives "Stadium, City" and the city gives the
IANA zone, so hosts spanning several zones are resolved per venue.

Olympic rows use the event infobox venue and the host city.

Rows that cannot be traced fall back to a host zone with a blank place.

Usage: python3 pipeline/build_venues.py [--check]
  --check  also prints the box time field cross check (stated UTC offset in the
           match box against the zone chosen here).
"""
import csv
import datetime as dt
import os
import re
import sys
import urllib.parse
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import wikitext as wt  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE2 = os.path.join(ROOT, "research", "cache2")
SRC = os.path.join(ROOT, "data", "sporting_moments_v2.csv")
OUT = os.path.join(ROOT, "data", "overrides", "venues.csv")

# City (as displayed in the match box) to IANA zone. Every city in a harvested
# match box is listed; an unknown city stops the build rather than guessing.
CITY_TZ = {
    # Qatar 2022
    "Al Rayyan": "Asia/Qatar", "Al Khor": "Asia/Qatar", "Al Wakrah": "Asia/Qatar", "Doha": "Asia/Qatar", "Lusail": "Asia/Qatar",
    # Germany
    "Munich": "Europe/Berlin", "Gelsenkirchen": "Europe/Berlin", "Leverkusen": "Europe/Berlin", "Mönchengladbach": "Europe/Berlin", "Augsburg": "Europe/Berlin",
    "Kaiserslautern": "Europe/Berlin", "Stuttgart": "Europe/Berlin", "Leipzig": "Europe/Berlin", "Sinsheim": "Europe/Berlin", "Cologne": "Europe/Berlin",
    "Dresden": "Europe/Berlin", "Düsseldorf": "Europe/Berlin", "Nuremberg": "Europe/Berlin", "Hanover": "Europe/Berlin", "Berlin": "Europe/Berlin",
    "Hamburg": "Europe/Berlin", "Wolfsburg": "Europe/Berlin", "Frankfurt": "Europe/Berlin", "Dortmund": "Europe/Berlin",
    # France
    "Nice": "Europe/Paris", "Paris": "Europe/Paris", "Saint-Denis": "Europe/Paris", "Marseille": "Europe/Paris", "Bordeaux": "Europe/Paris",
    "Toulouse": "Europe/Paris", "Saint-Étienne": "Europe/Paris", "Le Havre": "Europe/Paris", "Colombes": "Europe/Paris", "Villeneuve-d'Ascq": "Europe/Paris",
    "Lille": "Europe/Paris", "Lyon": "Europe/Paris", "Décines-Charpieu": "Europe/Paris", "Nantes": "Europe/Paris", "Strasbourg": "Europe/Paris",
    "Montpellier": "Europe/Paris", "Grenoble": "Europe/Paris", "Antibes": "Europe/Paris", "Valenciennes": "Europe/Paris", "Reims": "Europe/Paris",
    "Lens": "Europe/Paris", "Rennes": "Europe/Paris",
    # United Kingdom
    "Liverpool": "Europe/London", "London": "Europe/London", "Sheffield": "Europe/London", "Manchester": "Europe/London", "Sunderland": "Europe/London",
    "Birmingham": "Europe/London", "Cardiff": "Europe/London", "Glasgow": "Europe/London",
    # Brazil 2014: several zones, all UTC-3 in June 2014 but named per city
    "São Paulo": "America/Sao_Paulo", "Brasília": "America/Sao_Paulo", "Rio de Janeiro": "America/Sao_Paulo", "Belo Horizonte": "America/Sao_Paulo",
    "Porto Alegre": "America/Sao_Paulo", "Salvador": "America/Bahia", "Recife": "America/Recife", "Fortaleza": "America/Fortaleza",
    # Canada 2015
    "Vancouver": "America/Vancouver", "Edmonton": "America/Edmonton", "Moncton": "America/Moncton", "Ottawa": "America/Toronto", "Montreal": "America/Toronto",
    # USA 1994, 2016, 2024, Copa
    "Orlando": "America/New_York", "Foxborough": "America/New_York", "East Rutherford": "America/New_York", "Washington, D.C.": "America/New_York",
    "Miami Gardens": "America/New_York", "Dallas": "America/Chicago", "Chicago": "America/Chicago", "Pasadena": "America/Los_Angeles",
    "Stanford": "America/Los_Angeles", "Carson": "America/Los_Angeles",
    # Russia 2018
    "Samara": "Europe/Samara", "Kazan": "Europe/Moscow", "Moscow": "Europe/Moscow", "Saint Petersburg": "Europe/Moscow", "Sochi": "Europe/Moscow",
    "Nizhny Novgorod": "Europe/Moscow", "Rostov-on-Don": "Europe/Moscow",
    # Korea and Japan 2002
    "Daegu": "Asia/Seoul", "Daejeon": "Asia/Seoul", "Gwangju": "Asia/Seoul", "Seogwipo": "Asia/Seoul", "Jeonju": "Asia/Seoul", "Seoul": "Asia/Seoul",
    "Suwon": "Asia/Seoul", "Ulsan": "Asia/Seoul",
    "Niigata": "Asia/Tokyo", "Kobe": "Asia/Tokyo", "Yokohama": "Asia/Tokyo", "Ōita": "Asia/Tokyo", "Rifu": "Asia/Tokyo", "Saitama": "Asia/Tokyo", "Fukuroi": "Asia/Tokyo",
    # Mexico 1970, 1986
    "Mexico City": "America/Mexico_City", "Puebla": "America/Mexico_City", "Guadalajara": "America/Mexico_City", "Querétaro": "America/Mexico_City",
    "León": "America/Mexico_City", "Toluca": "America/Mexico_City", "San Nicolás de los Garza": "America/Monterrey",
    # Chile 1962, Argentina, Uruguay
    "Arica": "America/Santiago", "Santiago": "America/Santiago", "Rancagua": "America/Santiago", "Viña del Mar": "America/Santiago",
    "Buenos Aires": "America/Argentina/Buenos_Aires", "Montevideo": "America/Montevideo",
    # Rest of Europe
    "Bucharest": "Europe/Bucharest", "Istanbul": "Europe/Istanbul", "Baku": "Asia/Baku",
    "Barcelona": "Europe/Madrid", "Madrid": "Europe/Madrid", "Seville": "Europe/Madrid", "Alicante": "Europe/Madrid",
    "Geneva": "Europe/Zurich", "Basel": "Europe/Zurich", "Lausanne": "Europe/Zurich", "Zurich": "Europe/Zurich", "Bern": "Europe/Zurich",
    "Enschede": "Europe/Amsterdam", "Rotterdam": "Europe/Amsterdam", "Amsterdam": "Europe/Amsterdam",
    "Donetsk": "Europe/Kyiv", "Kyiv": "Europe/Kyiv", "Vienna": "Europe/Vienna",
    "Lisbon": "Europe/Lisbon", "Porto": "Europe/Lisbon", "Faro/Loulé": "Europe/Lisbon",
    "Solna": "Europe/Stockholm", "Norrköping": "Europe/Stockholm", "Gothenburg": "Europe/Stockholm", "Malmö": "Europe/Stockholm",
    "Brussels": "Europe/Brussels", "Bruges": "Europe/Brussels", "Athens": "Europe/Athens", "Copenhagen": "Europe/Copenhagen",
    "Budapest": "Europe/Budapest", "Belgrade": "Europe/Belgrade", "Gdańsk": "Europe/Warsaw", "Warsaw": "Europe/Warsaw",
    "Milan": "Europe/Rome", "Rome": "Europe/Rome", "Florence": "Europe/Rome", "Naples": "Europe/Rome", "Trieste": "Europe/Rome", "Turin": "Europe/Rome",
    "Genoa": "Europe/Rome", "Verona": "Europe/Rome", "Bologna": "Europe/Rome", "Bari": "Europe/Rome",
    # South Africa 2010
    "Cape Town": "Africa/Johannesburg", "Johannesburg": "Africa/Johannesburg", "Bloemfontein": "Africa/Johannesburg", "Durban": "Africa/Johannesburg",
    "Port Elizabeth": "Africa/Johannesburg", "Pretoria": "Africa/Johannesburg", "Rustenburg": "Africa/Johannesburg",
    # Oceania and Asia
    "Auckland": "Pacific/Auckland", "Wellington": "Pacific/Auckland",
    "Adelaide": "Australia/Adelaide", "Brisbane": "Australia/Brisbane", "Melbourne": "Australia/Melbourne", "Sydney": "Australia/Sydney",
    "Shanghai": "Asia/Shanghai", "Guangzhou": "Asia/Shanghai", "Beijing": "Asia/Shanghai", "Tokyo": "Asia/Tokyo", "Sapporo": "Asia/Tokyo",
    "Atlanta": "America/New_York",
}

# Olympic infobox venue link target -> (place, zone). Host city is the fallback.
OLY_VENUE = {
    "Centennial Olympic Stadium": ("Centennial Olympic Stadium, Atlanta", "America/New_York"),
    "Turner Field": ("Centennial Olympic Stadium, Atlanta", "America/New_York"),
    "Stadium Australia": ("Stadium Australia, Sydney", "Australia/Sydney"),
    "ANZ Stadium": ("Stadium Australia, Sydney", "Australia/Sydney"),
    "Athens Olympic Stadium": ("Athens Olympic Stadium, Athens", "Europe/Athens"),
    "Beijing National Stadium": ("Beijing National Stadium, Beijing", "Asia/Shanghai"),
    "Beijing National Aquatics Center": ("Beijing National Aquatics Center, Beijing", "Asia/Shanghai"),
    "Beijing National Aquatics Centre": ("Beijing National Aquatics Center, Beijing", "Asia/Shanghai"),
    "Olympic Stadium (London)": ("Olympic Stadium, London", "Europe/London"),
    "London Stadium": ("Olympic Stadium, London", "Europe/London"),
    "Estádio Olímpico João Havelange": ("Estádio Olímpico João Havelange, Rio de Janeiro", "America/Sao_Paulo"),
    "Estádio Olímpico Nilton Santos": ("Estádio Olímpico João Havelange, Rio de Janeiro", "America/Sao_Paulo"),
    "Sambadrome Marquês de Sapucaí": ("Sambadrome, Rio de Janeiro", "America/Sao_Paulo"),
    "Japan National Stadium": ("Japan National Stadium, Tokyo", "Asia/Tokyo"),
    "Stade de France": ("Stade de France, Saint-Denis", "Europe/Paris"),
    "Tokyo Aquatics Centre": ("Tokyo Aquatics Centre, Tokyo", "Asia/Tokyo"),
}
# Host zone by Olympic year, used when the venue is not a stadium or is missing.
OLY_HOST = {1996: "America/New_York", 2000: "Australia/Sydney", 2004: "Europe/Athens", 2008: "Asia/Shanghai", 2012: "Europe/London",
            2016: "America/Sao_Paulo", 2020: "Asia/Tokyo", 2024: "Europe/Paris"}
# Infobox venue link target that names a city, not a venue (marathons, walks).
OLY_CITY_ONLY = {"Paris": "Paris", "Sapporo": "Sapporo", "Beijing": "Beijing", "2012 Olympic Marathon Course": "London"}

# Host zone for a football competition page, used only if a box cannot be traced.
# Multi zone hosts are deliberately absent, so they fail loudly instead.
FOOTBALL_HOST_FALLBACK = {}

NORM = lambda s: s.replace("–", " to ").replace("-", " ")


def page_title(url):
    return urllib.parse.unquote(url.split("/wiki/", 1)[1]).replace("_", " ")


def split_place(stadium_field):
    s = wt.strip_links(stadium_field)
    s = re.sub(r"\s+", " ", s).strip()
    if ", " not in s:
        return s, ""
    stadium, city = s.split(", ", 1)
    # 'Miami Gardens, Florida' and 'East Rutherford, New Jersey': drop the state
    if city not in CITY_TZ and ", " in city:
        city = city.split(", ")[0]
    return stadium.strip(), city.strip()


def football_boxes(by_title, title, cache):
    if title in cache:
        return cache[title]
    out = []
    f = by_title.get(title)
    if f:
        txt = open(os.path.join(CACHE2, f), encoding="utf-8").read()
        for pos, b in wt.blocks(txt):
            fl = wt.fields(b)
            d = wt.pdate(fl.get("date", ""))
            tm = wt.ptime(fl.get("time", "")) if fl.get("time") else None
            if not d or not tm or "team1" not in fl:
                continue
            out.append(dict(date="%04d-%02d-%02d" % d, ko="%02d:%02d" % tm, t1=wt.team(fl["team1"]), t2=wt.team(fl["team2"]),
                            stadium=fl.get("stadium", ""), time=fl.get("time", "")))
    cache[title] = out
    return out


def olympic_venue(by_title, title, year):
    f = by_title.get(title)
    venue = None
    if f:
        txt = open(os.path.join(CACHE2, f), encoding="utf-8").read()
        m = re.search(r"\|\s*venue\s*=\s*([^\n]+)", txt[:4000])
        venue = m.group(1) if m else None
    host = OLY_HOST.get(year)
    if venue:
        for tgt in wt.link_targets(venue):
            tgt = tgt.replace("\xa0", " ")
            if tgt in OLY_VENUE:
                return OLY_VENUE[tgt][0], OLY_VENUE[tgt][1], "venue"
            if tgt in OLY_CITY_ONLY:
                return OLY_CITY_ONLY[tgt], host, "city"
        plain = wt.strip_links(venue)
        if plain in OLY_CITY_ONLY:
            return OLY_CITY_ONLY[plain], host, "city"
    return "", host, "fallback"


def build(check=False):
    by_title = wt.load_index(CACHE2)
    rows = list(csv.DictReader(open(SRC, encoding="utf-8-sig")))
    harvested = [r for r in rows if r["set"] == "harvested"]
    cache = {}
    out = []
    stats = {"venue": 0, "city": 0, "fallback": 0}
    problems = []
    xcheck = []
    for r in harvested:
        title = page_title(r["time_source"])
        if r["sport"] == "Football":
            cands = [b for b in football_boxes(by_title, title, cache) if b["date"] == r["date"] and b["ko"] == r["scheduled_start_local"]]
            cands = [b for b in cands if NORM(b["t1"]) in r["moment"] and NORM(b["t2"]) in r["moment"]]
            if len(cands) == 1 and cands[0]["stadium"]:
                b = cands[0]
                stadium, city = split_place(b["stadium"])
                tz = CITY_TZ.get(city)
                if not tz:
                    raise SystemExit(f"{r['id']}: no zone for city {city!r} (stadium field {b['stadium']!r})")
                place = f"{stadium}, {city}" if stadium and city else ""
                out.append((r["id"], tz, place)); stats["venue" if place else "city"] += 1
                # Cross check: the UTC kickoff implied by our zone and the harvested
                # local kickoff must equal one the box states (when it states any).
                stated = wt.stated_utc_kickoffs(b["time"])
                if stated:
                    h, m = map(int, r["scheduled_start_local"].split(":"))
                    y, mo, d = map(int, r["date"].split("-"))
                    local = dt.datetime(y, mo, d, h, m, tzinfo=ZoneInfo(tz))
                    zone_off = int(local.utcoffset().total_seconds() // 60)
                    our_utc = (h * 60 + m - zone_off) % 1440
                    stats["xchecked"] = stats.get("xchecked", 0) + 1
                    if our_utc not in stated:
                        xcheck.append((r["id"], title, r["date"], r["scheduled_start_local"], tz, zone_off, b["time"][:160]))
            else:
                tz = FOOTBALL_HOST_FALLBACK.get(title)
                problems.append((r["id"], title, len(cands)))
                if tz:
                    out.append((r["id"], tz, "")); stats["fallback"] += 1
        else:
            m = re.search(r"(\d{4}) Summer Olympics", title)
            year = int(m.group(1)) if m else None
            place, tz, how = olympic_venue(by_title, title, year)
            if not tz:
                problems.append((r["id"], title, 0)); continue
            out.append((r["id"], tz, place)); stats[how] += 1
    for _, tz, _ in out:
        ZoneInfo(tz)  # raises if unknown
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["id", "venue_tz", "place"])
        w.writerows(out)
    print(f"venues.csv: {len(out)} of {len(harvested)} harvested rows")
    print(f"  per match venue (stadium and city): {stats['venue']}")
    print(f"  city only (no stadium): {stats['city']}")
    print(f"  host fallback, blank place: {stats['fallback']}")
    if problems:
        print(f"  unresolved: {len(problems)}")
        for p in problems: print("   ", p)
    print(f"  football rows whose box time names a zone or UTC offset: {stats.get('xchecked', 0)}; "
          f"disagreeing with the zone chosen here and the harvested kickoff: {len(xcheck)}")
    if check:
        seen = set()
        for x in xcheck:
            key = (x[1], x[2], x[3])
            if key in seen: continue
            seen.add(key)
            print("   ", x)
    return out, stats, problems, xcheck


if __name__ == "__main__":
    build(check="--check" in sys.argv)
