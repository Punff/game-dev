#!/usr/bin/env python3
"""How abilities get used, people next to bots: the check that
tests/bot_matches.gd plays like people do (its SHOCK_RATE and friends).

    python3 tools/analytics/abilities.py --remote --bots /tmp/bots.jsonl
    python3 tools/analytics/abilities.py --file people.jsonl --bots /tmp/bots.jsonl

People's matches are the multiplayer ones (2+ players) not tagged "bot";
bots' are the tagged ones from the --bots file. Per side: uses per
player-minute, what blasts are aimed at and from how far, how fields go,
and how often each is used by distance to the nearest other player - the
numbers the bots' tables are fitted to.
"""

import argparse
import collections
import math
import sys

import report

BANDS = [(0, 3), (3, 6), (6, 9), (9, 15), (15, math.inf)]


def multiplayer(recs, bots):
    return [r for r in recs if (r.get("tag") == "bot") == bots and r.get("players", 1) >= 2]


def foe_dist(r, t, pid, x, h):
    """m to the nearest other living player, at the sample closest to t."""
    S = r.get("samples", [])
    if not S:
        return None
    s = min(S, key=lambda s: abs(s[0] - t))
    ids = [p["id"] for p in r["roster"]]
    ds = [math.hypot(o[0] - x, o[1] - h) for i, o in enumerate(s[3]) if o is not None and ids[i] != pid]
    return min(ds) if ds else None


def quartiles(xs):
    if not xs:
        return "-"
    xs = sorted(xs)
    return " / ".join("%.1f" % xs[min(len(xs) - 1, int(p * len(xs)))] for p in (0.25, 0.5, 0.75))


def band(d):
    return next(b for b in BANDS if b[0] <= d < b[1])


def profile(recs, name):
    if not recs:
        print(f"== {name}: no matches")
        return
    mins = sum(r["duration"] * r["players"] for r in recs) / 60.0
    count = collections.Counter()
    shock_d, shock_aim, shock_hit, shock_t = [], collections.Counter(), 0, []
    field_near, field_dur, field_thrown = [], [], 0
    charge_ratio, charge_air = [], 0
    near_time, near_shock, near_field = collections.Counter(), collections.Counter(), collections.Counter()
    for r in recs:
        ids = [p["id"] for p in r["roster"]]
        for s in r.get("samples", []):
            for i, me in enumerate(s[3]):
                ds = [math.hypot(o[0] - me[0], o[1] - me[1]) for j, o in enumerate(s[3]) if o is not None and j != i] if me else []
                if ds:
                    near_time[band(min(ds))] += 0.5
        for e in r.get("events", []):
            t, kind, pid, x, h = e[:5]
            d = e[5] if len(e) > 5 else {}
            count[kind] += 1
            if kind in ("shock", "field"):
                fd = foe_dist(r, t, pid, x, h)
                if fd is not None:
                    (near_shock if kind == "shock" else near_field)[band(fd)] += 1
            if kind == "shock":
                shock_t.append(t)
                if fd is not None:
                    shock_d.append(fd)
                ay = d.get("aim", [0, 0])[1]
                shock_aim["down" if ay > 0.5 else "up" if ay < -0.5 else "side"] += 1
                shock_hit += d.get("players", 0) > 0
            elif kind == "field":
                field_near.append(d.get("near", 0))
            elif kind == "field_end":
                field_dur.append(d.get("dur", 0))
                field_thrown += d.get("thrown", 0) > 0
            elif kind == "charge":
                charge_ratio.append(d.get("ratio", 0))
                charge_air += not d.get("ground")
    durs = sorted(r["duration"] for r in recs)
    print(f"== {name}: {len(recs)} matches, {mins:.0f} player-min, median match {durs[len(durs) // 2]:.0f} s")
    print("  per player-minute: " + ", ".join(f"{k} {count[k] / mins:.1f}" for k in ["jump", "air_jump", "charge", "shock", "field", "pound"]))
    n = max(count["shock"], 1)
    aim = ", ".join(f"{k} {v / n:.0%}" for k, v in sorted(shock_aim.items()))
    print(f"  shock: nearest player {quartiles(shock_d)} m (quartiles), aim {aim}, hits someone {shock_hit / n:.0%}, first {min(shock_t, default=0):.1f} s")
    n = max(count["field"], 1)
    print(f"  field: catches nothing {sum(v == 0 for v in field_near) / n:.0%}, lasts {quartiles(field_dur)} s, thrown {field_thrown / max(len(field_dur), 1):.0%}")
    print(f"  charge: let go at {quartiles(charge_ratio)} of full, mid-air {charge_air / max(count['charge'], 1):.0%}")
    print("  by nearest player (m):   time   shocks/s  fields/s")
    for b in BANDS:
        label = f"{b[0]}-{b[1]}" if b[1] != math.inf else f"{b[0]}+"
        tm = near_time[b]
        print(f"    {label:>6}            {tm:6.0f}s   {near_shock[b] / max(tm, 1):.3f}    {near_field[b] / max(tm, 1):.3f}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", nargs="+", help="people's match records (JSONL)")
    ap.add_argument("--remote", action="store_true", help="people's matches from the live D1 database")
    ap.add_argument("--bots", help="bot run records (TELEMETRY_LOG of tests/bot_matches.tscn)")
    a = ap.parse_args()
    if a.remote:
        people = report.load_d1(True)
    elif a.file:
        people = report.load_files(a.file)[0]
    else:
        sys.exit("people's matches: --remote or --file")
    profile(multiplayer(people, False), "people")
    if a.bots:
        profile(multiplayer(report.load_files([a.bots])[0], True), "bots")


if __name__ == "__main__":
    main()
