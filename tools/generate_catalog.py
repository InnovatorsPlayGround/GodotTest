from pathlib import Path
import json, re

ROOT = Path(__file__).resolve().parents[1]
PACKS = [("town", ROOT / "assets" / "town"), ("expansion", ROOT / "assets" / "expansion")]
ORDER = ["Terrain", "Paths", "Water", "Buildings", "Roofs", "Castle", "Farms", "Nature", "Decor"]


def category_for(fam: str) -> str:
    n = fam.lower().replace("-", "_")
    if "roof" in n:
        return "Roofs"
    if any(k in n for k in ("castle", "wall", "gate", "tower")):
        return "Castle"
    if any(k in n for k in ("building", "balcony", "structure", "house", "arch")):
        return "Buildings"
    if any(k in n for k in ("farm", "furrow", "fence", "well", "crop", "field", "plant")):
        return "Farms"
    if any(k in n for k in ("tree", "rock", "bush", "shrub")):
        return "Nature"
    if any(k in n for k in ("path", "road", "bridge", "stairs", "step")):
        return "Paths"
    if any(k in n for k in ("water", "river", "stream")):
        return "Water"
    if any(k in n for k in ("grass", "cliff", "dirt", "ground", "slope", "hill", "corner")):
        return "Terrain"
    return "Decor"


def friendly(name: str) -> str:
    s = name.replace("_", " ").replace("-", " ")
    s = re.sub(r"([a-z0-9])([A-Z])", r"\1 \2", s)
    s = re.sub(r"\s+", " ", s).strip()
    return " ".join(w.capitalize() for w in s.split())

families = {}
for pack, folder in PACKS:
    for p in sorted(folder.glob("*.png")):
        m = re.match(r"(.+)_([NESW])\.png$", p.name, re.IGNORECASE)
        if not m:
            continue
        fam, orientation = m.groups()
        orientation = orientation.upper()
        entry = families.setdefault(fam, {"family": fam, "pack": pack, "orientations": {}})
        entry["orientations"][orientation] = f"res://assets/{pack}/{p.name}"

assets = []
counts = {cat: 0 for cat in ORDER}
for fam in sorted(families, key=str.lower):
    e = families[fam]
    e["category"] = category_for(fam)
    e["display_name"] = friendly(fam)
    counts[e["category"]] += 1
    assets.append(e)

categories = [cat for cat in ORDER if counts[cat] > 0]
catalog = {"categories": categories, "assets": assets, "counts": counts}
(ROOT / "assets").mkdir(exist_ok=True)
(ROOT / "assets" / "catalog.json").write_text(json.dumps(catalog, indent=2), encoding="utf-8")
print(f"Generated catalog with {len(assets)} asset families")
for cat in categories:
    print(f"  {cat}: {counts[cat]}")
