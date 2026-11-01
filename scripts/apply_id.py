"""Writes scripts/id_strings.py into both catalogs and fails if any key lacks an id translation or specifiers differ.
Usage: python3 scripts/apply_id.py   (run scripts/sync_strings.sh first when keys changed)"""
import json, re, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from id_strings import ID, SAME
spec = lambda s: sorted(re.sub(r"%\d+\$", "%", m) for m in re.findall(r"%(?:\d+\$)?(?:lld|@|d)", s))
bad = []
for app in ("RentroAdmin", "RentroTracker"):
    p = f"Apps/{app}/Resources/Localizable.xcstrings"
    cat = json.load(open(p))
    for k, v in cat["strings"].items():
        t = k if k in SAME else ID.get(k)
        if t is None: bad.append(f"{app}: missing id for {k!r}"); continue
        if spec(k) != spec(t): bad.append(f"{app}: specifier mismatch {k!r} -> {t!r}")
        v["localizations"] = {"id": {"stringUnit": {"state": "translated", "value": t}}}
        v.pop("shouldTranslate", None)
    json.dump(cat, open(p, "w"), ensure_ascii=False, indent=2, sort_keys=True); open(p, "a").write("\n")
print("\n".join(bad) or "all keys translated, specifiers match")
sys.exit(1 if bad else 0)
