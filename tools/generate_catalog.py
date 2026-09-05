from pathlib import Path
import json, re

ROOT = Path(__file__).resolve().parents[1]
PACKS = [("town", ROOT / "assets" / "town"), ("expansion", ROOT / "assets" / "expansion")]


def category_for(fam: str) -> str:
    if fam.startswith("roof_"):
        return "Roofs"
    if fam.startswith("castle_"):
        return "Castle"
    if fam.startswith(("building_", "balcony_", "structure_")):
        return "Buildings"
    if fam.startswith("furrow") or fam.startswith("fence_") or fam == "well":
        return "Farms"
    if fam.startswith(("tree_", "rocks_")):
        return "Nature"
    if fam == "bridge" or fam.startswith("grass_path"):
        return "Paths"
    if fam.startswith(("water_", "grass_river", "grass_water")):
        return "Water"
    if fam.startswith(("grass_", "cliff", "dirt_")):
        return "Terrain"
    return "Decor"


def friendly(name: str) -> str:
    s = name.replace("_", " ")
    s = re.sub(r"([a-z])([A-Z])", r"\1 \2", s)
    s = re.sub(r"(Beige|Brown|Green|Purple)", r" \1", s)
    return " ".join(w.capitalize() for w in s.split())

families = {}
for pack, folder in PACKS:
    for p in sorted(folder.glob("*.png")):
        m = re.match(r"(.+)_([NESW])\.png$", p.name)
        if not m:
            continue
        fam, orientation = m.groups()
        entry = families.setdefault(fam, {"family": fam, "pack": pack, "orientations": {}})
        entry["orientations"][orientation] = f"res://assets/{pack}/{p.name}"

assets = []
for fam in sorted(families):
    e = families[fam]
    e["category"] = category_for(fam)
    e["display_name"] = friendly(fam)
    assets.append(e)

catalog = {
    "categories": ["Terrain", "Paths", "Water", "Buildings", "Roofs", "Castle", "Farms", "Nature", "Decor"],
    "assets": assets,
}
(ROOT / "assets").mkdir(exist_ok=True)
(ROOT / "assets" / "catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
print(f"Generated catalog with {len(assets)} asset families")
