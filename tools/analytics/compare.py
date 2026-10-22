#!/usr/bin/env python3
"""Side by side: headline numbers from two sets of match records.

The before-and-after check for a change: run the same bot matches (fixed
seeds) on both sides of it, then compare.

    TELEMETRY_LOG=/tmp/before.jsonl godot --headless --path . res://tests/bot_matches.tscn -- --matches=12
    (make the change)
    TELEMETRY_LOG=/tmp/after.jsonl  godot --headless --path . res://tests/bot_matches.tscn -- --matches=12
    python3 tools/analytics/compare.py /tmp/before.jsonl /tmp/after.jsonl

Matches are paired by map seed where both sides have it, so a difference
is the change, not a different map. A change of more than 15% (and more
than a hair in absolute terms) is flagged.
"""

import json
import statistics
import sys
from collections import Counter


def load(path):
    out = []
    with open(path) as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return out


def metrics(recs):
    if not recs:
        return {}
    pp = [p for r in recs for p in r.get("per_player", {}).values()]
    deaths = [p["death"] for p in pp if p.get("death")]
    causes = Counter(d.get("cause") for d in deaths)
    hows = Counter(d.get("how") or "-" for d in deaths)
    events = Counter(e[1] for r in recs for e in r.get("events", []))
    minutes = sum(r.get("duration", 0) * r.get("players", 1) for r in recs) / 60.0 or 1.0
    m = {
        "matches": len(recs),
        "match length (s), median": statistics.median(r.get("duration", 0) for r in recs),
        "best height (m), median": statistics.median(r.get("best_height", 0) for r in recs),
        "height per player (m), mean": statistics.mean(p.get("max_m", 0) for p in pp),
        "climb rate (m/s), mean": statistics.mean(p.get("max_m", 0) / max(r.get("duration", 1), 1) for r in recs for p in r["per_player"].values()),
        "deaths: lava %": 100.0 * causes.get("lava", 0) / max(len(deaths), 1),
        "deaths: side %": 100.0 * causes.get("side", 0) / max(len(deaths), 1),
        "deaths after a hit %": 100.0 * sum(v for k, v in hows.items() if k != "-") / max(len(deaths), 1),
        "stalls per player": sum(p.get("stalls", 0) for p in pp) / max(len(pp), 1),
        "near lava (s) per player": statistics.mean(p.get("near_lava_s", 0) for p in pp),
    }
    for kind in ["jump", "air_jump", "charge", "shock", "field", "break", "chain", "bounce", "map_event"]:
        m["%s per player-min" % kind] = events.get(kind, 0) / minutes
    hits = [e for r in recs for e in r.get("events", []) if e[1] == "hit" and len(e) > 5]
    m["own / stray debris hits per player-min"] = sum(1 for e in hits if e[5].get("how") == "chunk" and e[5].get("by", 0) == 0) / minutes
    m["hits from players per player-min"] = sum(1 for e in hits if e[5].get("by", 0) != 0) / minutes
    return m


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    a, b = load(sys.argv[1]), load(sys.argv[2])
    seeds_a = {r.get("seed"): r for r in a}
    seeds_b = {r.get("seed"): r for r in b}
    both = [s for s in seeds_a if s in seeds_b and s not in (None, 0)]
    if both:
        a = [seeds_a[s] for s in both]
        b = [seeds_b[s] for s in both]
        print("Paired by map seed: %d matches on each side.\n" % len(both))
    else:
        print("No shared map seeds: comparing all %d vs %d matches.\n" % (len(a), len(b)))
    ma, mb = metrics(a), metrics(b)
    width = max(len(k) for k in ma)
    print("%-*s %10s %10s %9s" % (width, "", "before", "after", "change"))
    for k in ma:
        va, vb = ma[k], mb.get(k, 0)
        change = ""
        if isinstance(va, (int, float)) and va:
            pct = 100.0 * (vb - va) / abs(va)
            flag = "  <" if abs(pct) > 15 and abs(vb - va) > 0.05 else ""
            change = "%+.0f%%%s" % (pct, flag)
        print("%-*s %10.2f %10.2f %9s" % (width, k, va, vb, change))


if __name__ == "__main__":
    main()
