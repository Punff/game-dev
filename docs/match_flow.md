# Match flow: why multiplayer matches are short (2026-10-22)

What a multiplayer match should be: **a race with clashes**. The climb is the
core. Offense is natural and stays, but it shouldn't decide the match before
the climb starts, and a better climber shouldn't be able to leave everyone
behind with nothing anyone can do.

What the matches actually look like is in the numbers below.

**Data:** the live D1 database on 2026-10-22: 237 matches, all v1.1.0. 169 are
multiplayer (158 couch matches on the web build, 11 online), 143
player-minutes. 68 are solo.

**Reproduce:**
```bash
python3 tools/analytics/report.py --remote --all-builds   # "Match shape (multiplayer)" + Findings
python3 tools/analytics/abilities.py --remote             # ability use by distance to the nearest player
```

## Findings

### 1. Matches are short, and end one of two ways
- Multiplayer length: median 14 s; 10th–90th percentile 5–48 s.
- Solo, for comparison: median 39 s, with half the runs climbing 89 m+.
- 91 of 169 multiplayer matches are over in under 15 s.

### 2. The opening brawl is a spawn problem
- Spawns are `min(200, 800 / n)` px apart (`game.gd` `_spawn_players`): 4 m with two players.
- The shockwave reaches 9 m (`Player.SHOCK_RANGE`).
- The 1100 px start floor hangs over a 13 m drop (`LAVA_START_BELOW`) with nothing to land on.
- The result:
  - 52% of all blasts (397 of 760) come in the first 5 s.
  - 36% of deaths (87 of 245) are players who never got above 10 m; a quarter of deaths are below the start floor.
  - The first death comes at 9 s (median), and 55% of first deaths are a blast knock-out into the lava.
- The first thing you can do in a match is also the strongest.

### 3. The runaway is a reach problem
- From about 10 s in, the height spread between players is 9–11 m (median). Every ability reaches at most 9 m.
- The map is a single ladder: there's nowhere to cut across, nothing to slow the player in front, and nothing to catch up with.
- The lava only chases the lowest player (`Lava.update_lava(lowest)`), so a leader never feels it.
- Winner's lead over the runner-up: 5 m median, 13 m+ in a quarter of matches.
- Once you're 10 m ahead, the match is decided unless you make a mistake.

### 4. The map is a ladder you barely touch
- Players are in the air 65% of the time in multiplayer and 80% solo. They stand on a block for 0.3–0.45 s per landing.

| Block | Of map | Of standing time | Of landings |
|---|---|---|---|
| Steel (static) | 52% | 85% | 75% |
| Concrete (breakable) | 29% | 7% | 9% |
| Conveyor | 5% | 4% | 4% |
| Bounce pad | 5% | 0% | 6% |
| Vanishing | 4% | 1% | 2% |
| Moving, ice, speed, reverse, push | 4% | 4% | 3% |

- Rows are always within a double jump: the gap is 190–235 px (`MapPlanner.BIOMES`), and only 4% of Rubble rows need a charge jump.
- So you never need an ability to climb, and the only choice is which platform to use, which barely matters.
- A block that works over time (conveyor, ice, speed) gets 0.4 s to do it. Only the bounce pad, which acts instantly, is felt.
- That's the "predictable, flowy, not that interesting" feeling: a rhythm of jumps, where the map is the ground between them.

### 5. Most of the content is never seen in multiplayer
- Best height in multiplayer: median 28 m, 90th percentile 110 m.
- Inferno starts at 180 m, and only 4 of 169 multiplayer matches reached it. Multiplayer is essentially all Rubble, whose blocks are mostly steel, concrete, conveyors and bounce pads.
- Map events start at 25 s (`MapEvents.FIRST_AFTER`); 72% of matches are over by then. Rubble's event pool is only the slab.
- Solo reaches Inferno in 22 of 68 runs.

### 6. Abilities in multiplayer
- **Shockwave** is the PvP weapon: 5.3 uses per player-minute, 78% hit someone, 84% aimed sideways.
  - People fire nearly every time it's ready once someone is within 6 m (0.35 shots/s, against a cap of 0.4/s).
  - They fire much less at 6–9 m (0.15/s), and almost never beyond that.
  - This replaces the "barely used" reading in `abilities.md`, which came from 9 local minutes.
- **Gravity field** is a movement and rescue tool: 1.1 uses per player-minute, 79% catch no chunks, 10% end in a throw.
  - The user uses it to climb, to catch the slab, and as a clutch save.

## What we changed (2026-10-22, one commit each)

| Change | Where | Knobs |
|---|---|---|
| Walls at the start floor's ends; spawns spread out (about 8 m apart with two players) | `MapPlanner.start`, `game.gd` | `START_WALL`, `SPAWN_SPACING`, `SPAWN_SPREAD` |
| Biomes come 3x sooner with 2+ players (Inferno at 54 m) | `MapPlanner.biome_scale` | `MULTI_BIOME_SCALE` |
| The slab always targets whoever is highest; a 15 m lead held for 4 s calls one down (at most every 20 s: about once per long match, by the live data) | `map_events.gd` | `LEAD_SLAB`, `LEAD_HOLD`, `LEAD_SLAB_GAP` |
| Catch-up pads: dead until the leader is 6 m past, then gold; they launch anyone but the leader ~11 m through the platforms above | `blocks/catchup_pad.gd`, `MapPlanner._place_pad` | `PAD_ARM`, `LAUNCH_VELOCITY`, `PAD_FROM`, `PAD_EVERY` |
| Field and blast recharge up to 1.5x faster 15 m behind the leader | `Player.cooldown_rate` | `CATCHUP_FROM`, `CATCHUP_FULL`, `CATCHUP_RATE` |

Bots, 48 matches on the same seeds, before all of it → after:
- first death: 5 s → 11 s
- blasts in the first 5 s: 64% → 46%
- match length (median): 16 s → 19 s
- best height (median): 9 m → 15 m

People would probably move further; the bots fight harder at the start than
people do (93% of bot deaths happened below 10 m).

The runaway changes (slab, pads, cooldowns) barely show in bot runs: bot
matches end before anyone builds a real lead (6 lead slabs and 1 pad launch
in 32 multiplayer matches). These need playing; then check the live numbers
with `report.py --remote --since 2026-10-23`:
- **winner's lead** and **height spread at 20/30 s** should come down;
- **match length** should go up;
- **catchup** events, and `map_event` with `why: "lead"`, show how often each fires.

## Later (ideas, not built)

- **Meeting points.** Map sections that alternate fast climbing with spots that funnel everyone together. The CONTEST and PAIR rows already exist; first measure whether clashes actually happen there.
- **Risky fast routes that need an ability:** a charge jump, a field floor, a rocket jump. They'd make the climb about choices, and give a skilful trailing player a way back.
- **Blocks that act over time, or make you wait** (a timed door, a lift), so the map holds you long enough to matter.
- **Map events sooner in multiplayer,** and aimed at the leader (quakes already crack concrete around them).
