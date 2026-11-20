#!/usr/bin/env python3
"""Writes app/Resources/credits.json from data/overrides/images.csv.

One entry per photo bundled in app/Resources/images, with the ids of every moment
that uses it (from the CSV and from moments.json). Run by an Xcode build phase
before each build; safe to run by hand. Standard library only.

If images.csv is missing (for example a copy of app/ on its own), the existing
credits.json is kept. The file is only rewritten when its contents change.
"""

import csv
import json
import os
import sys
import tempfile
from pathlib import Path

APP = Path(__file__).resolve().parent.parent
CSV_PATH = APP.parent / "data" / "overrides" / "images.csv"
RESOURCES = APP / "Resources"
IMAGES = RESOURCES / "images"
MOMENTS = RESOURCES / "moments.json"
OUTPUT = RESOURCES / "credits.json"


def warn(message):
    # Xcode shows lines starting "warning:" as build warnings.
    print(f"warning: make_credits: {message}", file=sys.stderr)


def moment_ids_by_file():
    """Ids of the moments in moments.json that use each photo file."""
    if not MOMENTS.exists():
        return {}
    with MOMENTS.open(encoding="utf-8") as f:
        moments = json.load(f).get("moments", [])
    by_file = {}
    for moment in moments:
        image = moment.get("image") or {}
        if image.get("file"):
            by_file.setdefault(image["file"], set()).add(moment["id"])
    return by_file


def build():
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        rows = [row for row in csv.DictReader(f) if row["local_file"].strip()]
    bundled = {p.name for p in IMAGES.iterdir()} if IMAGES.is_dir() else set()
    used_by = moment_ids_by_file()

    rows_by_file = {}
    for row in rows:
        file = row["local_file"].strip()
        if file in bundled:
            rows_by_file.setdefault(file, []).append(row)

    photos = []
    for file in sorted(rows_by_file):
        group = rows_by_file[file]
        # The row named after the file (M0095.jpg is M0095's photo) describes it best.
        main = next((r for r in group if f"{r['id']}.jpg" == file), group[0])
        ids = {r["id"] for r in group} | used_by.get(file, set())
        photos.append({
            "file": file,
            "moments": sorted(ids),
            "author": main["author"].strip(),
            "licence": main["licence"].strip(),
            "licenceURL": main["licence_url"].strip() or None,
            "commonsFile": main["commons_file"].strip(),
            "commonsPage": main["commons_page"].strip() or None,
        })

    for file in sorted(bundled - set(rows_by_file)):
        if not file.startswith("."):
            warn(f"{file} is bundled but has no row in images.csv, so it has no credit")
    for file in sorted(set(used_by) - set(rows_by_file)):
        warn(f"{file} is used in moments.json but has no credit")
    return {"version": 1, "photos": photos}


def write_if_changed(data):
    text = json.dumps(data, ensure_ascii=False, indent=1) + "\n"
    if OUTPUT.exists() and OUTPUT.read_text(encoding="utf-8") == text:
        return False
    # Write beside the target, then rename: two targets may run this at once.
    fd, temp = tempfile.mkstemp(dir=RESOURCES, prefix=".credits.", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(temp, 0o644)
    os.replace(temp, OUTPUT)
    return True


def main():
    if not CSV_PATH.exists():
        warn(f"{CSV_PATH} not found; keeping the existing credits.json")
        return
    data = build()
    changed = write_if_changed(data)
    print(f"make_credits: {len(data['photos'])} photos, {'written' if changed else 'unchanged'}")


if __name__ == "__main__":
    main()
