#!/usr/bin/env python3
"""Design report from Telemetry match records (scripts/core/telemetry.gd).

Reads match records, works out how the game is actually being played and
writes one self-contained HTML page: pace and lava pressure, how people die and
who kills them, what every ability is used for and how often it works, which
abilities winners lean on, how each block type plays, where players stall,
plus a list of things that look broken or lopsided.

Sources (pick one; default: this computer's own matches):
  report.py                      user://logs/matches.jsonl of the local game
  report.py --file a.jsonl ...   any JSONL files of records
  report.py --remote             the live D1 database (needs `npx wrangler login`)
  report.py --d1-local           the `wrangler dev` database (signaling/.wrangler)

Filters: --since 2026-10-01  --version 0.4  --mode solo|local|online
         --builds Web,Linux  (default: everything except "editor")  --all-builds
         --bots  (include tests/bot_matches.gd runs)  --only-bots
Output:  --out report.html (default tools/analytics/out/report.html)

Only the standard library is used.
"""

import argparse
import html
import json
import math
import os
import statistics
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIGNALING = ROOT / "signaling"
DB_NAME = "cakum-pakum-stats"
LOCAL_LOG = Path.home() / ".local/share/godot/app_userdata/Ultimate Cakum Pakum/logs/matches.jsonl"
ABILITIES = ["jump", "air_jump", "charge", "field", "shock", "pound"]
ABILITY_NAMES = {"jump": "Jump", "air_jump": "Double jump", "charge": "Charge jump", "field": "Gravity field",
                 "shock": "Shockwave", "pound": "Ground pound"}
BLOCK_NAMES = {"static_platform": "Steel", "breakable_block": "Concrete", "bounce_pad": "Bounce pad",
               "speed_block": "Speed", "conveyor_block": "Conveyor", "push_zone": "Push zone",
               "vanishing_block": "Vanishing", "ice_block": "Ice", "moving_platform": "Moving", "reverse_block": "Reverse"}


# ── Loading ──────────────────────────────────

# Anomalies that mean something is broken, not just that a match went badly
# (report --check, used in CI on bot matches).
BROKEN = ["Impossible position", "Event cap hit", "Stuck most of a match"]


def load_files(paths):
    recs, skipped = [], 0
    for p in paths:
        with open(p, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    r = json.loads(line)
                except json.JSONDecodeError:
                    skipped += 1
                    continue
                if r.get("schema") == 1:
                    recs.append(r)
                else:
                    skipped += 1   # MatchLog records from before Telemetry
    return recs, skipped


def load_d1(remote):
    """Pages through the matches table with wrangler (it caps result size)."""
    recs, last = [], 0
    while True:
        sql = f"SELECT id, received_at, record FROM matches WHERE id > {last} ORDER BY id LIMIT 40"
        cmd = ["npx", "wrangler", "d1", "execute", DB_NAME, "--json", "--command", sql, "--remote" if remote else "--local"]
        out = subprocess.run(cmd, cwd=SIGNALING, capture_output=True, text=True)
        if out.returncode != 0:
            sys.exit("wrangler failed:\n" + out.stderr[-2000:])
        rows = json.loads(out.stdout)[0]["results"]
        if not rows:
            return recs
        for row in rows:
            r = json.loads(row["record"])
            r["received_at"] = row["received_at"]
            recs.append(r)
        last = rows[-1]["id"]


def keep(r, a):
    bot = r.get("tag") == "bot"
    if bot and not (a.bots or a.only_bots) or a.only_bots and not bot:
        return False
    if a.since and r.get("date", "") < a.since:
        return False
    if a.version and r.get("version") != a.version:
        return False
    if a.mode and r.get("mode") != a.mode:
        return False
    build = r.get("build", "")
    if a.builds:
        return build in a.builds.split(",")
    return a.all_builds or build != "editor"


# ── Analysis ─────────────────────────────────

def pct(n, d):
    return 100.0 * n / d if d else 0.0


def med(xs):
    return statistics.median(xs) if xs else 0.0


def analyse(recs):
    A = {"matches": len(recs), "modes": Counter(r["mode"] for r in recs),
         "versions": Counter(r.get("version", "?") for r in recs),
         "builds": Counter(r.get("build", "?") for r in recs),
         "durations": [r.get("duration", 0) for r in recs],
         "player_minutes": 0.0}

    use = Counter()                       # ability -> uses
    death_cause = Counter()
    ko_how = Counter()
    hits_how = Counter()                  # hits credited to another player
    death_heights, death_times, solo_heights = [], [], []
    shock = Counter()                     # shots, hit_player, hit_chunk, hit_block, rocket, empty
    field = Counter()                     # uses, whiffs (0 near), thrown_uses, chunks_thrown, cut
    field_held = []
    charge_ratios = []
    throw_hits = 0
    breaks = Counter()
    chains = []
    block_time, block_lands, block_offer = Counter(), Counter(), Counter()
    stall_block, stall_durations = Counter(), []
    deaths_after_block = Counter()        # block someone was last standing on when they died
    fx = Counter()
    win_use, lose_use = Counter(), Counter()
    win_min, lose_min = 0.0, 0.0
    heat = Counter()                      # (x bin, height bin) -> samples
    pace = defaultdict(list)              # t bin (10 s) -> leader heights
    lava_pace = defaultdict(list)
    gap = []                              # metres between a player and the lava, every sample
    anomalies = []
    by_group = defaultdict(list)

    for r in recs:
        per = r.get("per_player", {})
        roster = r.get("roster", [])
        dur = max(r.get("duration", 0), 0.001)
        A["player_minutes"] += dur * len(roster) / 60.0
        multi = r["mode"] != "solo"
        winner = r.get("winner", -1)
        for b, n in r.get("map", {}).get("blocks", {}).items():
            block_offer[b] += n
        mine = Counter()                  # (pid, ability) -> uses in this match
        last_chunk_thrower = {}
        for e in r.get("events", []):
            t, kind, pid = e[0], e[1], e[2]
            d = e[5] if len(e) > 5 else {}
            if kind in ABILITIES:
                use[kind] += 1
                mine[(pid, kind)] += 1
            if kind == "shock":
                shock["shots"] += 1
                shock["hit_player"] += d.get("players", 0) > 0
                shock["hit_chunk"] += d.get("chunks", 0) > 0
                shock["hit_block"] += d.get("blocks", 0) > 0
                shock["rocket"] += d.get("aim", [0, 0])[1] > 0.5
                shock["empty"] += not (d.get("players") or d.get("chunks") or d.get("blocks"))
            elif kind == "field":
                field["whiffs"] += d.get("near", 0) == 0
            elif kind == "field_end":
                field_held.append(d.get("held", 0))
                if d.get("thrown", 0):
                    field["thrown_uses"] += 1
                    field["chunks_thrown"] += d["thrown"]
                    last_chunk_thrower[pid] = t
                field["cut"] += bool(d.get("cut"))
            elif kind == "charge":
                charge_ratios.append(d.get("ratio", 0))
            elif kind == "hit":
                if d.get("by"):
                    hits_how[d.get("how")] += 1
                    if d.get("how") == "chunk" and t - last_chunk_thrower.get(d["by"], -99) < 2.0:
                        throw_hits += 1
            elif kind == "break":
                breaks[d.get("how") or "?"] += 1
            elif kind == "chain":
                chains.append(d.get("n", 3))
            elif kind == "stall":
                stall_durations.append(d.get("dur", 0))
                stall_block[d.get("block") or "air"] += d.get("dur", 0)
            elif kind in ("bounce", "reversed", "vanish", "conveyor_flip"):
                fx[kind] += 1
        for pid_s, pp in per.items():
            pid = int(pid_s)
            for b, s in pp.get("block_time", {}).items():
                block_time[b] += s
            for b, n in pp.get("block_lands", {}).items():
                block_lands[b] += n
            dth = pp.get("death")
            if dth:
                death_cause[dth["cause"]] += 1
                death_heights.append(dth.get("height_m", 0))
                death_times.append(dth.get("t", 0))
                deaths_after_block[dth.get("block") or "air"] += 1
                if dth.get("killer"):
                    ko_how[dth.get("how") or "?"] += 1
            if not multi:
                solo_heights.append(pp.get("max_m", 0))
            if multi:
                mins = dur / 60.0
                for ab in ABILITIES:
                    (win_use if pid == winner else lose_use)[ab] += mine[(pid, ab)]
                if pid == winner:
                    win_min += mins
                else:
                    lose_min += mins
            # Anomalies, per player
            if pp.get("stall_s", 0) > 0.5 * dur and dur > 40:
                anomalies.append(("Stuck most of a match", f"{_who(r, pid)} spent {pp['stall_s']:.0f} of {dur:.0f} s without climbing", r))
            if dth and dth.get("cause") == "lava" and dth.get("t", 99) < 8:
                anomalies.append(("Very early lava death", f"{_who(r, pid)} died to lava {dth['t']:.1f} s in", r))
        for s in r.get("samples", []):
            t, lava_m, _, row = s
            heights = [p[1] for p in row if p]
            if heights:
                pace[int(t // 10) * 10].append(max(heights))
                lava_pace[int(t // 10) * 10].append(lava_m)
            for p in row:
                if p:
                    heat[(int(math.floor(p[0] / 2)), int(p[1] // 10))] += 1
                    gap.append(p[1] - lava_m)
                    if p[1] - lava_m > 400:
                        anomalies.append(("Impossible position", f"{p[1]:.0f} m up with lava at {lava_m:.0f} m (t={t})", r))
        if r.get("abandoned"):
            A["abandoned"] = A.get("abandoned", 0) + 1
            anomalies.append(("Quit mid-match", f"{r['mode']} match left after {dur:.0f} s, best {r.get('best_height', 0)} m", r))
        if dur < 6 and not r.get("abandoned"):
            anomalies.append(("Very short match", f"{r['mode']} match lasted {dur:.1f} s", r))
        if r.get("events_dropped"):
            anomalies.append(("Event cap hit", "MAX_EVENTS reached; later events missing", r))
        by_group[(r.get("version", "?"), r.get("tuning_hash", "?"))].append(r)

    A.update(use=use, death_cause=death_cause, ko_how=ko_how, hits_how=hits_how, death_heights=death_heights,
             death_times=death_times, solo_heights=solo_heights, shock=shock, field=field, field_held=field_held,
             charge_ratios=charge_ratios, throw_hits=throw_hits, breaks=breaks, chains=chains,
             block_time=block_time, block_lands=block_lands, block_offer=block_offer, stall_block=stall_block,
             stall_durations=stall_durations, deaths_after_block=deaths_after_block, fx=fx,
             win_use=win_use, lose_use=lose_use, win_min=win_min, lose_min=lose_min, heat=heat,
             pace=pace, lava_pace=lava_pace, gap=gap, by_group=by_group)
    # De-duplicate anomaly floods (one line per kind + a count).
    grouped = defaultdict(list)
    for kind, text, r in anomalies:
        grouped[kind].append((text, r))
    A["anomalies"] = grouped
    A["notes"] = notes(A)
    return A


def _who(r, pid):
    for p in r.get("roster", []):
        if p["id"] == pid:
            return f"{p.get('name') or 'P%d' % pid} ({r['mode']}, {r.get('date', '')[:10]})"
    return f"P{pid}"


def notes(A):
    """Plain-language findings with the thresholds spelled out."""
    out = []
    pm = A["player_minutes"] or 1
    deaths = sum(A["death_cause"].values())
    if deaths:
        lava = pct(A["death_cause"]["lava"], deaths)
        kos = sum(A["ko_how"].values())
        out.append(("info", f"{lava:.0f}% of deaths are to the lava, {pct(A['death_cause']['side'], deaths):.0f}% off the side; "
                            f"{pct(kos, deaths):.0f}% are credited to another player's hit in the 5 s before."))
        multi = A["modes"]["local"] + A["modes"]["online"]
        if multi and pct(kos, deaths) < 15:
            out.append(("warn", "Sabotage rarely decides matches: under 15% of deaths follow another player's hit."))
    s = A["shock"]
    if s["shots"]:
        out.append(("info", f"Shockwave: {pct(s['hit_player'], s['shots']):.0f}% of shots hit a player, "
                            f"{pct(s['rocket'], s['shots']):.0f}% are aimed down (rocket jumps), {pct(s['empty'], s['shots']):.0f}% hit nothing."))
        if pct(s["empty"], s["shots"]) > 40:
            out.append(("warn", "Over 40% of shockwaves hit nothing - wasted or used just for the recoil."))
    f = A["field"]
    uses = A["use"]["field"]
    if uses:
        out.append(("info", f"Gravity field: {pct(f['whiffs'], uses):.0f}% go up with no chunk in reach; "
                            f"{pct(f['thrown_uses'], uses):.0f}% end in a throw ({f['chunks_thrown']} chunks, {A['throw_hits']} hit someone)."))
        if pct(f["whiffs"], uses) > 35:
            out.append(("warn", "Over a third of gravity fields grab nothing: players may not read when it is useful."))
    for ab in ABILITIES:
        per_min = A["use"][ab] / pm
        if ab not in ("jump", "air_jump") and per_min < 0.2 and A["matches"] >= 5:
            out.append(("warn", f"{ABILITY_NAMES[ab]} is barely used: {per_min:.2f} uses per player-minute."))
    if A["win_min"] > 2 and A["lose_min"] > 2:
        for ab in ABILITIES:
            w = A["win_use"][ab] / A["win_min"]
            l = A["lose_use"][ab] / A["lose_min"]
            if l > 0.1 and w / l > 1.6:
                out.append(("warn", f"Winners use {ABILITY_NAMES[ab]} {w / l:.1f}x as often as everyone else - check it isn't dominant."))
    if A["charge_ratios"]:
        low = pct(sum(1 for x in A["charge_ratios"] if x < 0.15), len(A["charge_ratios"]))
        full = pct(sum(1 for x in A["charge_ratios"] if x >= 0.99), len(A["charge_ratios"]))
        out.append(("info", f"Charge jumps: {full:.0f}% at full charge, {low:.0f}% released almost at once (<15%)."))
    if A["stall_durations"]:
        top = A["stall_block"].most_common(1)[0]
        out.append(("info", f"{len(A['stall_durations'])} stalls (8 s+ without climbing), median {med(A['stall_durations']):.0f} s; "
                            f"most stall time is spent on {BLOCK_NAMES.get(top[0], top[0])}."))
    return out


# ── HTML ─────────────────────────────────────

CSS = """
:root{--surface:#fcfcfb;--page:#f9f9f7;--ink:#0b0b0b;--ink2:#52514e;--muted:#898781;--grid:#e1e0d9;--axis:#c3c2b7;
--border:rgba(11,11,11,.10);--s1:#2a78d6;--s2:#eb6834;--warn:#fab219;--crit:#d03b3b;
--q1:#cde2fb;--q2:#9ec5f4;--q3:#6da7ec;--q4:#3987e5;--q5:#256abf;--q6:#184f95;--q7:#0d366b}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;
--grid:#2c2c2a;--axis:#383835;--border:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;
--q1:#0d366b;--q2:#104281;--q3:#184f95;--q4:#1c5cab;--q5:#2a78d6;--q6:#5598e7;--q7:#86b6ef}}
:root[data-theme="dark"]{--surface:#1a1a19;--page:#0d0d0d;--ink:#f0efec;--ink2:#c3c2b7;--grid:#2c2c2a;--axis:#383835;
--border:rgba(255,255,255,.10);--s1:#3987e5;--s2:#d95926;--q1:#0d366b;--q2:#104281;--q3:#184f95;--q4:#1c5cab;--q5:#2a78d6;--q6:#5598e7;--q7:#86b6ef}
*{box-sizing:border-box}body{margin:0;background:var(--page);color:var(--ink);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:36px 0 4px}
.sub{color:var(--ink2);margin:0 0 14px}.card{background:var(--surface);border:1px solid var(--border);border-radius:10px;padding:16px;margin:10px 0}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}.tile .v{font-size:28px;font-weight:600}.tile .k{color:var(--ink2);font-size:13px}
.grid2{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,420px),1fr));gap:10px}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}th,td{text-align:left;padding:5px 8px;border-bottom:1px solid var(--grid)}
th{color:var(--ink2);font-weight:600;font-size:13px}td.n,th.n{text-align:right}.overflow{overflow-x:auto}
.note{padding:8px 10px;border-radius:8px;margin:6px 0;border:1px solid var(--border);background:var(--surface)}
.note b{margin-right:6px}.note.warn b{color:var(--crit)}.note.info b{color:var(--s1)}
svg text{fill:var(--muted);font-size:12px}svg .lbl{fill:var(--ink2)}svg .val{fill:var(--ink);font-weight:600}
.bar{fill:var(--s1)}.bar2{fill:var(--s2)}.grid{stroke:var(--grid)}.axis{stroke:var(--axis)}
#tip{position:fixed;pointer-events:none;background:var(--surface);color:var(--ink);border:1px solid var(--border);border-radius:6px;
padding:4px 8px;font-size:13px;box-shadow:0 2px 8px rgba(0,0,0,.15);display:none;z-index:9}
details{margin:6px 0}summary{cursor:pointer;color:var(--ink2)}.legend{display:flex;gap:16px;color:var(--ink2);font-size:13px;margin-bottom:4px}
.sw{display:inline-block;width:12px;height:12px;border-radius:3px;margin-right:6px;vertical-align:-1px}
"""

JS = """
const tip=document.getElementById('tip');
document.addEventListener('mousemove',e=>{const t=e.target.closest('[data-tip]');
if(!t){tip.style.display='none';return}tip.textContent=t.dataset.tip;tip.style.display='block';
const x=Math.min(e.clientX+14,innerWidth-tip.offsetWidth-8);tip.style.left=x+'px';tip.style.top=(e.clientY+14)+'px'});
"""


def esc(s):
    return html.escape(str(s))


def hbars(items, unit="", fmt="{:.0f}", width=480, cls="bar"):
    """Horizontal bars: [(label, value, tooltip)]."""
    if not items:
        return "<p class='sub'>No data yet.</p>"
    vmax = max(v for _, v, _ in items) or 1
    row, lw = 26, 130
    h = row * len(items) + 4
    out = [f"<svg viewBox='0 0 {width} {h}' width='100%' role='img'>"]
    for i, (label, v, tipv) in enumerate(items):
        y = i * row + 4
        w = max((width - lw - 70) * v / vmax, 2 if v else 0)
        out.append(f"<text class='lbl' x='{lw - 8}' y='{y + 15}' text-anchor='end'>{esc(label)}</text>")
        out.append(f"<g data-tip='{esc(tipv)}'><rect x='{lw}' y='{y}' width='{width - lw}' height='{row - 4}' fill='transparent'/>"
                   f"<path class='{cls}' d='M{lw},{y + 3}h{max(w - 4, 0):.1f}a4,4 0 0 1 4,4v{row - 14}a4,4 0 0 1 -4,4h-{max(w - 4, 0):.1f}z'/></g>")
        out.append(f"<text class='val' x='{lw + w + 6:.1f}' y='{y + 15}'>{fmt.format(v)}{unit}</text>")
    out.append("</svg>")
    return "".join(out)


def pace_chart(pace, lava):
    ts = sorted(pace)
    if len(ts) < 2:
        return "<p class='sub'>Not enough samples yet.</p>"
    W, H, L, B = 520, 220, 40, 24
    lead = [med(pace[t]) for t in ts]
    lv = [med(lava[t]) for t in ts]
    lo = min(min(lv), 0)
    hi = max(max(lead), 1)
    X = lambda t: L + (W - L - 70) * (t - ts[0]) / (ts[-1] - ts[0])
    Y = lambda v: (H - B) - (H - B - 10) * (v - lo) / (hi - lo)
    out = [f"<div class='legend'><span><i class='sw' style='background:var(--s1)'></i>Leader height (median)</span>"
           f"<span><i class='sw' style='background:var(--s2)'></i>Lava (median)</span></div>",
           f"<svg viewBox='0 0 {W} {H}' width='100%' role='img'>"]
    for k in range(5):
        v = lo + (hi - lo) * k / 4
        out.append(f"<line class='grid' x1='{L}' x2='{W - 70}' y1='{Y(v):.1f}' y2='{Y(v):.1f}'/><text x='{L - 6}' y='{Y(v) + 4:.1f}' text-anchor='end'>{v:.0f} m</text>")
    for t in ts[:: max(1, len(ts) // 6)]:
        out.append(f"<text x='{X(t):.1f}' y='{H - 6}' text-anchor='middle'>{t // 60}:{t % 60:02d}</text>")
    for vals, cls, name in ((lead, "--s1", "Leader"), (lv, "--s2", "Lava")):
        pts = " ".join(f"{X(t):.1f},{Y(v):.1f}" for t, v in zip(ts, vals))
        out.append(f"<polyline points='{pts}' fill='none' stroke='var({cls})' stroke-width='2'/>")
        out.append(f"<text class='lbl' x='{X(ts[-1]) + 6:.1f}' y='{Y(vals[-1]) + 4:.1f}'>{name}</text>")
    for t, a, b in zip(ts, lead, lv):
        out.append(f"<rect x='{X(t) - 6:.1f}' y='10' width='12' height='{H - B - 10}' fill='transparent' "
                   f"data-tip='{t // 60}:{t % 60:02d}  leader {a:.0f} m, lava {b:.0f} m, gap {a - b:.0f} m (n={len(pace[t])})'/>")
    out.append("</svg>")
    return "".join(out)


def heatmap(heat):
    if not heat:
        return "<p class='sub'>No samples yet.</p>"
    xs = [k[0] for k in heat]
    ys = [k[1] for k in heat]
    x0, x1, y0, y1 = max(min(xs), -12), min(max(xs), 12), min(ys), max(ys)
    rows = y1 - y0 + 1
    cell_w, cell_h, L = 18, max(6, min(16, 420 // rows)), 50
    W, H = L + cell_w * (x1 - x0 + 1), cell_h * rows + 20
    vmax = math.log1p(max(heat.values()))
    out = [f"<svg viewBox='0 0 {W} {H}' width='100%' style='max-width:{W * 1.4:.0f}px' role='img'>"]
    for yb in range(y0, y1 + 1):
        y = (y1 - yb) * cell_h
        if (yb - y0) % max(1, rows // 8) == 0:
            out.append(f"<text x='{L - 6}' y='{y + cell_h - 1}' text-anchor='end'>{yb * 10} m</text>")
        for xb in range(x0, x1 + 1):
            n = heat.get((xb, yb), 0)
            if not n:
                continue
            step = 1 + min(6, int(6 * math.log1p(n) / vmax))
            out.append(f"<rect x='{L + (xb - x0) * cell_w}' y='{y}' width='{cell_w - 1}' height='{cell_h - 1}' rx='2' fill='var(--q{step})' "
                       f"data-tip='x {xb * 2}..{xb * 2 + 2} m, height {yb * 10}..{yb * 10 + 10} m: {n} samples'/>")
    out.append(f"<text x='{L}' y='{H - 4}'>left edge</text><text x='{W}' y='{H - 4}' text-anchor='end'>right edge</text></svg>")
    return "".join(out)


def table(head, rows, numeric_from=1):
    h = "".join(f"<th class='{'n' if i >= numeric_from else ''}'>{esc(c)}</th>" for i, c in enumerate(head))
    b = "".join("<tr>" + "".join(f"<td class='{'n' if i >= numeric_from else ''}'>{esc(c)}</td>" for i, c in enumerate(r)) + "</tr>" for r in rows)
    return f"<div class='overflow'><table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table></div>"


def histogram(values, step, unit):
    if not values:
        return "<p class='sub'>No data yet.</p>"
    c = Counter(int(v // step) for v in values)
    items = [(f"{k * step:g}-{(k + 1) * step:g}{unit}", c[k], f"{c[k]} ({pct(c[k], len(values)):.0f}%)") for k in range(min(c), max(c) + 1)]
    return hbars(items)


def render(A, title):
    pm = A["player_minutes"] or 1
    deaths = sum(A["death_cause"].values()) or 1
    s, f = A["shock"], A["field"]
    tiles = [("Matches", A["matches"]), ("Player-minutes", f"{pm:.0f}"),
             ("Median match", f"{med(A['durations']):.0f} s"),
             ("Quit mid-match", f"{pct(A.get('abandoned', 0), A['matches']):.0f}%"),
             ("Solo median climb", f"{med(A['solo_heights']):.0f} m" if A["solo_heights"] else "-"),
             ("Modes", ", ".join(f"{k} {v}" for k, v in A["modes"].most_common())),
             ("Versions", ", ".join(f"{k} ({v})" for k, v in A["versions"].most_common(3)))]
    P = [f"<main><h1>{esc(title)}</h1><p class='sub'>From {A['matches']} matches. Hover any bar or cell for exact numbers.</p>",
         "<div class='tiles'>" + "".join(f"<div class='card tile'><div class='v'>{esc(v)}</div><div class='k'>{esc(k)}</div></div>" for k, v in tiles) + "</div>"]

    P.append("<h2>Findings</h2><p class='sub'>Generated from the thresholds in report.py's notes(); a starting point, not a verdict.</p>")
    P += [f"<div class='note {k}'><b>{'Look at this' if k == 'warn' else 'Note'}</b>{esc(t)}</div>" for k, t in A["notes"]] or ["<p class='sub'>Nothing yet.</p>"]

    P.append("<h2>Pace and lava pressure</h2><p class='sub'>How fast the leader climbs against the lava, and how much room players usually have.</p><div class='grid2'>")
    P.append(f"<div class='card'><b>Climb vs lava over match time</b>{pace_chart(A['pace'], A['lava_pace'])}</div>")
    P.append(f"<div class='card'><b>Gap to the lava (all samples)</b>{histogram([g for g in A['gap'] if g < 60], 5, ' m')}</div></div>")

    P.append("<h2>How players die</h2><div class='grid2'>")
    names = {"lava": "Lava", "side": "Knocked off the side", "quit": "Disconnected"}
    P.append("<div class='card'><b>Cause of death</b>" + hbars([(names.get(k, k), v, f"{v} deaths, {pct(v, deaths):.0f}%") for k, v in A["death_cause"].most_common()]) + "</div>")
    how = {"shock": "Shockwave", "chunk": "Flying chunk", "push": "Jump shove", "?": "Unknown"}
    P.append("<div class='card'><b>Knock-outs by tool</b><p class='sub'>Deaths within 5 s of another player's hit.</p>" +
             hbars([(how.get(k, k), v, f"{v} KOs") for k, v in A["ko_how"].most_common()]) + "</div>")
    P.append(f"<div class='card'><b>Time of death</b>{histogram(A['death_times'], 30, ' s')}</div>")
    P.append("<div class='card'><b>Last block stood on before dying</b>" +
             hbars([(BLOCK_NAMES.get(k, k if k != 'air' else 'Air'), v, f"{v} deaths") for k, v in A["deaths_after_block"].most_common(8)]) + "</div></div>")

    P.append("<h2>Abilities</h2><p class='sub'>Uses per player-minute, and how often each one does something.</p><div class='grid2'>")
    P.append("<div class='card'><b>Uses per player-minute</b>" +
             hbars([(ABILITY_NAMES[a], A["use"][a] / pm, f"{A['use'][a]} uses") for a in ABILITIES], fmt="{:.1f}") + "</div>")
    eff = [
        ["Shockwave", s["shots"], f"{pct(s['hit_player'], s['shots']):.0f}% hit a player", f"{pct(s['hit_chunk'], s['shots']):.0f}% moved chunks",
         f"{pct(s['rocket'], s['shots']):.0f}% rocket jumps", f"{pct(s['empty'], s['shots']):.0f}% hit nothing"],
        ["Gravity field", A["use"]["field"], f"{pct(f['whiffs'], A['use']['field']):.0f}% grabbed nothing",
         f"median {med(A['field_held']):.0f} held", f"{pct(f['thrown_uses'], A['use']['field']):.0f}% thrown",
         f"{pct(f['cut'], A['use']['field']):.0f}% cut short by a hit"],
        ["Charge jump", A["use"]["charge"], f"median {med(A['charge_ratios']) * 100:.0f}% charge",
         f"{pct(sum(1 for x in A['charge_ratios'] if x >= .99), len(A['charge_ratios'])):.0f}% full", "", ""],
        ["Ground pound", A["use"]["pound"], f"{A['breaks']['pound']} concrete broken", "", "", ""],
    ]
    P.append("<div class='card'><b>Does it work?</b>" + table(["Ability", "Uses", "", "", "", ""], eff, 1) + "</div></div>")
    if A["win_min"] and A["lose_min"]:
        rows = []
        for a in ABILITIES:
            w, l = A["win_use"][a] / A["win_min"], A["lose_use"][a] / A["lose_min"]
            rows.append([ABILITY_NAMES[a], f"{w:.2f}", f"{l:.2f}", f"{w / l:.2f}x" if l else "-"])
        P.append("<div class='card'><b>Winners vs everyone else (multiplayer)</b><p class='sub'>Uses per minute alive. A ratio well above 1 is a candidate for dominant play; well below, a trap.</p>"
                 + table(["Ability", "Winners", "Others", "Ratio"], rows) + "</div>")
    P.append("<div class='card'><b>Hits on other players</b>" +
             hbars([(how.get(k, k), v, f"{v} hits") for k, v in A["hits_how"].most_common()]) + "</div>")

    P.append("<h2>Blocks</h2><p class='sub'>What the map offered, where players actually spend their time, and where they get stuck.</p>")
    offer = sum(A["block_offer"].values()) or 1
    stood = sum(A["block_time"].values()) or 1
    stall_total = sum(A["stall_block"].values()) or 1
    rows = []
    for b in sorted(set(A["block_offer"]) | set(A["block_time"]), key=lambda b: -A["block_time"][b]):
        share_t, share_o = pct(A["block_time"][b], stood), pct(A["block_offer"][b], offer)
        rows.append([BLOCK_NAMES.get(b, b), f"{share_o:.1f}%", f"{share_t:.1f}%", f"{share_t / share_o:.2f}" if share_o else "-",
                     A["block_lands"][b], f"{pct(A['stall_block'][b], stall_total):.0f}%", A["deaths_after_block"][b]])
    P.append("<div class='card'>" + table(["Block", "Of map", "Of standing time", "Time / map", "Landings", "Of stall time", "Deaths after"], rows) +
             "<p class='sub'>Time / map below 1: players avoid or quickly leave it; above 1: they linger.</p></div>")
    P.append("<div class='grid2'><div class='card'><b>Concrete broken by</b>" +
             hbars([({"jump": "Jumping off", "pound": "Ground pound", "shock": "Shockwave", "chunk": "Flying chunk"}.get(k, k), v, f"{v} breaks")
                    for k, v in A["breaks"].most_common()]) + "</div>")
    fxn = {"bounce": "Bounce pad launches", "reversed": "Controls reversed", "vanish": "Vanishing triggered", "conveyor_flip": "Conveyor flipped"}
    P.append("<div class='card'><b>Block effects triggered (per player-minute)</b>" +
             hbars([(fxn.get(k, k), v / pm, f"{v} total") for k, v in A["fx"].most_common()], fmt="{:.2f}") +
             f"<p class='sub'>Chain reactions (3+ breaks in 0.45 s): {len(A['chains'])}, longest x{max(A['chains'], default=0)}.</p></div></div>")

    P.append("<h2>Where players are</h2><div class='card'><b>Position heatmap</b><p class='sub'>Every half-second sample, 2 m x 10 m cells, log scale. Shows the routes people take and how far up the map gets explored.</p>" + heatmap(A["heat"]) + "</div>")

    P.append("<h2>Looks broken or odd</h2>")
    if not A["anomalies"]:
        P.append("<p class='sub'>Nothing flagged.</p>")
    for kind, items in A["anomalies"].items():
        lis = "".join(f"<li>{esc(t)}</li>" for t, _ in items[:20])
        P.append(f"<details class='card'><summary><b>{esc(kind)}</b> - {len(items)}</summary><ul>{lis}</ul></details>")

    P.append("<h2>By version and tuning</h2><p class='sub'>Compare before and after a tweak: each row is one build version + set of tuning constants.</p>")
    rows = []
    for (ver, th), rs in sorted(A["by_group"].items(), key=lambda kv: kv[1][0].get("date", "")):
        ds = [d for r in rs for d in (p.get("death") for p in r.get("per_player", {}).values()) if d]
        rows.append([f"{ver} / {th}", len(rs), f"{med([r.get('duration', 0) for r in rs]):.0f} s",
                     f"{med([p.get('max_m', 0) for r in rs if r['mode'] == 'solo' for p in r['per_player'].values()]):.0f} m",
                     f"{pct(sum(1 for d in ds if d['cause'] == 'lava'), len(ds)):.0f}%",
                     f"{pct(sum(1 for d in ds if d.get('killer')), len(ds)):.0f}%"])
    P.append("<div class='card'>" + table(["Version / tuning", "Matches", "Median length", "Solo median climb", "Lava deaths", "KO deaths"], rows) + "</div>")
    P.append("</main><div id='tip'></div>")
    return (f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
            f"<title>Gameplay Report</title><style>{CSS}</style></head><body>{''.join(P)}<script>{JS}</script></body></html>")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", nargs="+")
    ap.add_argument("--remote", action="store_true")
    ap.add_argument("--d1-local", action="store_true")
    ap.add_argument("--since")
    ap.add_argument("--version")
    ap.add_argument("--mode", choices=["solo", "local", "online"])
    ap.add_argument("--builds")
    ap.add_argument("--all-builds", action="store_true")
    ap.add_argument("--bots", action="store_true")
    ap.add_argument("--only-bots", action="store_true")
    ap.add_argument("--save", help="also write the loaded records to this JSONL file")
    ap.add_argument("--out", default=str(Path(__file__).parent / "out" / "report.html"))
    ap.add_argument("--check", nargs="?", const=",".join(BROKEN), metavar="KINDS",
                    help="exit 1 if any of these anomaly kinds turn up (default: %s)" % ", ".join(BROKEN))
    a = ap.parse_args()

    skipped = 0
    if a.remote or a.d1_local:
        recs = load_d1(a.remote)
        source = "live database" if a.remote else "local wrangler database"
    else:
        files = a.file or [LOCAL_LOG]
        recs, skipped = load_files(files)
        source = ", ".join(os.path.basename(str(p)) for p in files)
    if a.save:
        with open(a.save, "w", encoding="utf-8") as f:
            for r in recs:
                f.write(json.dumps(r) + "\n")
    recs = [r for r in recs if keep(r, a)]
    A = analyse(recs)
    Path(a.out).parent.mkdir(parents=True, exist_ok=True)
    Path(a.out).write_text(render(A, f"Gameplay report - {source}"), encoding="utf-8")
    print(f"{len(recs)} matches ({skipped} old/unreadable lines skipped) -> {a.out}")
    for k, t in A["notes"]:
        print(("! " if k == "warn" else "- ") + t)
    if a.check:
        kinds = {k.strip() for k in a.check.split(",")}
        found = {k: v for k, v in A["anomalies"].items() if k in kinds}
        for kind, items in found.items():
            print(f"BROKEN: {kind} x{len(items)}: {items[0][0] if isinstance(items[0], tuple) else items[0]}")
        sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
