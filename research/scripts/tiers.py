import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
T1 = {"M001","M019","M024","M025","M026","M085","M096","M122","M149","M170","M176","M180","M191","M218","M221","M228","M229","M230","M231","M238","M260","M265"}
# auto "photo from the day" hits that are not really of the event (parades, stamps, exteriors, wrong match)
DEMOTE3 = {"M163","M067","M068","M069","M074","M083","M086","M087","M108","M127","M211","M094"}
DEMOTE4 = {"M031"}
PROMOTE2 = {"M235","M021","M162","M208","M187","M158","M053","M054"}
FILE = {"M024": "File:Maradona mano de dios.jpg", "M053": "File:1999 UEFA Champions League celebration (edited).jpg", "M054": "File:1999 UEFA Champions League celebration (edited).jpg"}
def assign(rows, classify, af, fi, resolved):
    out = {}
    for r in rows:
        tier, best, n, art = classify(r)
        i = r["id"]
        t = {"A": 2, "B": 3, "B?": 3, "C": 3, "D": 4}[tier]
        if i in T1: t = 1
        elif i in DEMOTE3: t = 3
        elif i in DEMOTE4: t = 4
        elif i in PROMOTE2: t = 2
        f = x = None
        if best: f, x = best[3], best[4]
        if i == "M122":
            for g in af.get(art, []):
                if "Montiel" in g and fi.get(g): f, x = g, fi[g]
        if i in FILE and fi.get(FILE[i]): f, x = FILE[i], fi[FILE[i]]
        if t == 4: f = x = None
        out[i] = (t, f, x)
    return out
