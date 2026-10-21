# Gameplay analytics

The loop: play (or let bots play) → every match is recorded → records go to a
local file and the stats server → `tools/analytics/report.py` turns them into a
design report → tweak → compare the before and after in the same report.

```
 game (host / solo)                          signaling Worker (Cloudflare)
 ┌──────────────────────┐   POST /v1/matches  ┌───────────────────────────┐
 │ Telemetry  ─ record ─┼────────────────────▶│ D1: matches (full record) │
 │   │                  │                     │     players (totals)      │
 │   └▶ user://logs/    │◀── GET leaderboard ─┤                           │
 │      matches.jsonl   │    GET players/<id> └─────────────┬─────────────┘
 └──────────────────────┘                                   │ wrangler d1
            │ --file                                        ▼ --remote
            └────────────────▶ tools/analytics/report.py ──▶ report.html
```

## What gets recorded

`scripts/core/telemetry.gd` records every match on the host (or offline
game). Online guests record nothing: the host sees everything. The test suite
is skipped unless `MATCH_LOG_IN_TESTS` is set.

A record (schema 1) is one JSON object:

| Field | What |
|---|---|
| `date`, `version`, `build`, `client`, `tag` | When, which game version (`config/version`), `editor` / `Web` / `Linux` / ..., the uploader's id, `"bot"` for bot runs |
| `mode`, `players`, `seed` | `solo` / `local` / `online`, player count, map seed (replay the same map) |
| `tuning`, `tuning_hash` | Movement, ability and lava constants in effect; the hash groups matches played under identical tuning |
| `roster` | Per player: `id`, `client` (only solo and online players have one), `name`, `device` (`kb` / `pad` / `net`) |
| `duration`, `winner`, `best_height` | Result |
| `map` | `blocks`: how many of each block type the map built; `rows` |
| `samples` | Every 0.5 s: `[t, lava m, lava px/s, [[x m, height m, state] or null per player]]`. State: `g` ground, `a` air, `c` charging, `f` field |
| `events` | `[t, kind, player id, x m, height m, details?]`, see below |
| `per_player` | Per player: `place`, `max_m`, `death` (`t`, `cause`, `killer`, `how`, `height_m`, `block`), `kos`, `air_s`, `near_lava_s`, `stall_s`, `stalls`, `block_time` (s per block type), `block_lands` |

Events:

| Kind | Details |
|---|---|
| `jump`, `air_jump` | |
| `charge` | `ratio` (0–1), `ground` (released on the ground or mid-air) |
| `field` | `near`: chunks in reach when it went up (0 = whiff) |
| `field_end` | `held`, `thrown`, `dur`, `cut` (ended by a hit) |
| `shock` | `players`, `chunks`, `blocks` hit, `aim` [x, y], `ground` |
| `pound` | `impact` speed |
| `hit` | On the victim: `by` (player id, 0 = nobody), `how` (`shock` / `chunk` / `push`), `force` |
| `break` | Concrete broken; `how` (`jump` / `pound` / `shock` / `chunk`), credited player |
| `chain` | `n` breaks within 0.45 s |
| `death` | `cause` (`lava` / `side` / `quit`), `killer`, `how` |
| `stall` | 8 s+ without beating your best height by 1 m: `dur`, `best_m`, `block` stood on |
| `bounce`, `reversed`, `vanish`, `conveyor_flip` | Block effects triggered |

A death counts as a knock-out for the last player who hit the victim within
5 s (2 s for a jump shove). Chunks carry `Fragment.credit`: whoever threw
them, or whoever broke the block they came from, so chain reactions credit the
player who started them.

### Adding something new to track

1. Call `Telemetry.ev("my_event", player, {"detail": value})` where it happens
   (it does nothing when no match is being recorded, so it's safe anywhere).
2. If it's continuous (time spent doing X), track it in `Telemetry._track()`
   and add the total to `per_player` in `_on_ended()`.
3. Count it in `analyse()` in `tools/analytics/report.py` and add a chart or a
   line to `notes()`.
4. Add it to the tables above. Bump `SCHEMA` only if an existing field changes
   meaning; new fields don't need it.

For a new block, the generic tracking already covers it (map share, standing
time, landings, stalls, deaths after). Add an event if it has an effect worth
counting, like `bounce`.

## The report

```bash
python3 tools/analytics/report.py                      # this computer's matches
python3 tools/analytics/report.py --remote             # everyone's (live D1, needs `npx wrangler login`)
python3 tools/analytics/report.py --remote --since 2026-11-01 --mode online
python3 tools/analytics/report.py --remote --save all.jsonl    # keep a snapshot to re-run offline
python3 tools/analytics/report.py --file all.jsonl --version 0.5
```

Writes `tools/analytics/out/report.html` (git-ignored). Editor builds and bot
runs are left out unless you pass `--all-builds` / `--bots`. Sections:

- **Findings**: plain-language notes with their thresholds, e.g. "over a
  third of gravity fields grab nothing", "winners use X 1.8x as often".
- **Pace and lava pressure**: leader height against the lava over match time,
  and how close players usually are to it.
- **How players die**: cause, knock-outs by tool, time of death, last block stood on.
- **Abilities**: uses per player-minute; a "does it work?" table (shockwave hit
  rate and rocket jumps, field whiffs and throws, charge levels, pounds that
  break concrete); winners vs everyone else (dominant tools have a high
  ratio, traps a low one); hits on other players by tool.
- **Blocks**: share of the map vs share of standing time (players avoid or
  linger), landings, share of stall time, deaths after standing on it, what
  breaks concrete, block effects, chain reactions.
- **Where players are**: heatmap of every position sample.
- **Looks broken or odd**: stuck most of a match, very early lava deaths,
  impossible positions, very short matches, event cap hit.
- **By version and tuning**: headline numbers per version + tuning hash, so a
  tweak's before and after sit side by side.

## Bots

```bash
TELEMETRY_LOG=/tmp/bots.jsonl godot --headless --path . res://tests/bot_matches.tscn -- --matches=12
python3 tools/analytics/report.py --file /tmp/bots.jsonl --only-bots --all-builds
```

Crude climbing bots (they jump toward the next platform, charge for big gaps,
blast and throw at anyone close). They're for checking that the pipeline
works and for a rough first look at a tuning change; they don't stand in
for people. Their records are tagged `"bot"` and only upload to a local server
(`BOT_UPLOAD=1` and `--signaling=ws://127.0.0.1:8787`).

## Leaderboards and player stats

Each computer gets a random id (`Settings.client_id()`) and a name, which is
editable in Settings → Leaderboard Name and defaults to `Ball-XXXX`. Settings →
Share Stats Online turns all uploads off.

- **Highest Climb**: best solo run per id.
- **Online Wins**: online matches won. Guests send their id and name to the host
  when joining, so the host's record credits everyone.
- Couch (local) matches go into the analytics but not into anyone's stats:
  players share one computer, so there's no telling who is who.

The main menu's Leaderboard screen shows both boards, your rank and your totals.
After a solo run the results screen shows your place.

**Trust:** nobody signs in, and the host's game decides results, so someone
determined can submit made-up numbers. The server rejects impossible heights
for the match length and more than one upload every 5 s per id. Making it
trustworthy would need the server to check replays or run matches itself.

## Server setup (once)

See `signaling/README.md` → Stats. In short:

```bash
cd signaling
npx wrangler d1 create cakum-pakum-stats      # paste the database_id into wrangler.toml
npx wrangler d1 migrations apply cakum-pakum-stats --remote
npx wrangler deploy
```

Useful queries:

```bash
npx wrangler d1 execute cakum-pakum-stats --remote --command \
  "SELECT version, mode, COUNT(*), ROUND(AVG(duration)) FROM matches GROUP BY 1, 2"
npx wrangler d1 execute cakum-pakum-stats --remote --command \
  "SELECT json_extract(record, '$.tuning_hash') h, COUNT(*) FROM matches GROUP BY h"
```

Free plan headroom: 5 GB of storage (a record is roughly 5–100 KB, so tens of
thousands of matches) and 100,000 row writes a day (one match is 2–5 writes).
