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
| `inputs` | Offline matches: per player id, its controls as a flat `[frame, packed, frame, packed, ...]` list, one pair whenever they change (8 button bits, two signed axes, see `PlayerInput.pack`). With `seed`, `time_scale` and `map_events`, enough to play the match again: `tests/replay.tscn` |

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

### Fast runs and replays

Add `--fixed-fps 60` to any headless run (tests, bots, replays): the game
then runs as fast as the CPU allows with exactly the same physics steps,
instead of waiting on the clock. The test suite takes seconds instead of
minutes, and twelve bot matches about five.

Offline match records carry each player's controls (`inputs`), so a match
can be played again on the same map:

```bash
REPLAY_FILE=~/.local/share/godot/app_userdata/"Ultimate Cakum Pakum"/logs/matches.jsonl \
  godot --path . res://tests/replay.tscn                        # watch the last match
REPLAY_FILE=/tmp/bots.jsonl REPLAY_ALL=1 godot --headless --fixed-fps 60 --path . res://tests/replay.tscn
```

The second checks every record replays exactly (heights and knock-out times)
and exits 1 if one doesn't. That needs gameplay to be deterministic: no
global random numbers in gameplay code (seed a RandomNumberGenerator from
the block / player / map), timers on physics ticks or the game clock
(`Block.clock`), never real time.

### Before and after a change

Bot matches use fixed map seeds (`--seed-base=N`, default 1000), so two runs
play the same maps:

```bash
TELEMETRY_LOG=/tmp/before.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=12
# ...make the change...
TELEMETRY_LOG=/tmp/after.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=12
python3 tools/analytics/compare.py /tmp/before.jsonl /tmp/after.jsonl
```

`compare.py` pairs matches by seed and flags changes over 15%.
`report.py --check` exits 1 when records show something broken (impossible
positions, a player stuck most of a match, the event cap hit). CI
(`.github/workflows/checks.yml`) runs the tests and six bot matches through
it on every push.

The bots climb with the map planner's own jump policy (see
`tests/bot_matches.gd`): good enough to compare changes, not to stand in for
people. They reach roughly 20-40 m; people go much further.

## Leaderboards, accounts and player stats

Only **accounts** (username and password) are ranked. Anyone can play and
their matches still go into the analytics, but they don't appear on the
boards until they log in. Settings → Share Stats Online turns all uploads off.

- **Log in / create an account:** main menu → Leaderboard → Log in / Create
  account. Usernames are 3–16 letters, digits, `_` or `-`, matched regardless
  of capitals; passwords are 8+ characters. There's no email: a forgotten
  password is reset by hand (see `signaling/README.md`).
- The game keeps only a session token (Settings `auth_token`, valid 180 days),
  never the password. Logging in on a computer also links its id
  (`Settings.client_id()`) to the account and folds in whatever that computer
  earned anonymously.
- **Highest Climb**: best solo run per account.
- **Online Wins**: online matches won. Guests send their computer's id to the
  host when joining; the server credits whichever account is logged in on
  that computer, so the host never sees anyone's token.
- Couch (local) matches go into the analytics but not into anyone's stats:
  players share one computer, so there's no telling who is who.

After a solo run, the results screen shows your place, or a reminder to log in.

**Passwords** are hashed with PBKDF2-SHA256 and a per-account salt. The round
count (`PBKDF2_ITERATIONS` in `signaling/wrangler.toml`) is 15,000 to fit the
free plan's 10 ms of CPU per request. That's well below today's
recommendations, so raise it to 100,000 if the Worker ever moves to the paid
plan; each account is re-hashed at its next login. Failed logins are limited
to 10 per username and 50 per IP every 15 minutes.

**Trust:** the host's game decides results, so someone determined can still
submit made-up numbers. The server rejects impossible heights for the match
length and more than one upload every 5 s per computer. Making it trustworthy
would need the server to check replays or run matches itself.

## Server setup (once)

See `signaling/README.md` → Stats. In short:

```bash
cd signaling
npx wrangler d1 create cakum-pakum-stats      # paste the database_id into wrangler.toml
npx wrangler d1 migrations apply cakum-pakum-stats --remote   # applies 0001 and 0002
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
