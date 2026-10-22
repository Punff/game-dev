# Abilities, examined as a set (2026-10-22)

What each move is for, where they overlap, what the data says so far, and
candidate changes. Nothing here has been changed in the game: per the
roadmap, one change at a time, tested with players.

**Data:** this computer's 10 readable matches (8 solo, 2 online, ~9
player-minutes). The live database wasn't reachable. Treat every number
below as a hint until `report.py --remote` agrees.

## What each one is for

| Move | Climb | Escape | Sabotage | Breaks concrete | Notes |
|---|---|---|---|---|---|
| Jump / double jump | core | yes | shove on take-off (200 px) | jumping off it | 55 / min combined: the game is mostly this |
| Charge jump | big gaps (the planner makes 4-16% of rows need it) | | | | 12% of charges are full; mostly a variable-height jump |
| Fast fall / pound | | | | landing at 800+ px/s | 1.8 pounds / min |
| Gravity field | hover; packs chunks into a floor | slows a fall | throw chunks | thrown chunks | 3.1 / min; 93% grab something, 21% end in a throw |
| Shockwave | rocket jump (aim down) | rocket jump | knockback | yes | 0.3 / min, 0 hits on players |

## Overlaps

- **Shockwave vs field throw.** Both knock players and break concrete. The
  field also climbs, floats and catches you, so it wins on every axis but
  range. That probably explains why the shockwave is barely used.
- **Shockwave rocket jump vs charge jump.** Both are "go up now". The
  charge is free and reliable; the rocket costs the blast's cooldown.
- **Field floor vs double jump.** The field is a third jump once there's
  debris. It's the most distinctive thing in the game, and it's used that
  way (79% of fields end without a throw).

## What the numbers suggest (to check with real data)

1. **The shockwave isn't pulling its weight.** 3 uses in 9 minutes. Before
   buffing it, find out whether people know about it (How to play has a
   station now, with a goal), and look at online matches, where it should
   matter most.
2. **Your own debris hits you a lot.** 28 hits in 9 solo minutes, all from
   chunks (there's nobody else). Breaking concrete under yourself and getting
   knocked by the pieces may feel random. Worth watching: deaths within a few
   seconds of a self-hit.
3. **Sabotage rarely decides matches** (0 of the deaths followed a hit).
   The two online matches are too few to say anything about PvP.
4. **Charges are mostly partial.** Fine if intended; if full charges should
   matter more, the meter could tick or the release could flash at full.

## Candidate changes (one at a time)

- **Make the shockwave the escape tool:** a bigger rocket jump when aimed
  down, so it answers "the lava is right there", which no other move does.
  Measure: shock use / min and near-lava time, before and after.
- **Own debris goes easier on you:** chunks you broke don't knock you for
  ~0.3 s after the break (throws already have this grace). Measure: self-hits
  and deaths after a self-hit.
- **Loadouts or pick-ups** (roadmap): if two moves keep overlapping, let
  players choose one of field / shockwave per match, or find a third as a
  pick-up. Large change; only after the two above.

## Riding debris (live runs, October)

The field's debris used to be a launch pad: stepping off chunks it was
lifting handed you their speed, the field then pulled them faster to keep
up, and a field was worth 10-18 m (a full charge jump is 5.7 m). Letting go
while steering sideways threw the floor from under you and took you out of
the arena with it. Now:

- Debris stays solid, and riding it up is fine, but one field's debris
  gives at most `RIDE_BUDGET` (5 m) of height, lifts and being carried
  alike; after that the field stops lifting chunks under you.
- No lift leaves you rising faster than a charge jump (`RIDE_PEAK`), and
  debris never flings or carries you sideways faster than you run
  (`RIDE_SIDE`).
- On keyboard jump and up are one key (W). An up that comes with a jump
  doesn't aim the field, so jumping during a field keeps the floor under
  you (it used to fly up over your head). With no jump left, W aims up.

## How to measure a change

```bash
TELEMETRY_LOG=/tmp/before.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=24
# change one thing
TELEMETRY_LOG=/tmp/after.jsonl godot --headless --fixed-fps 60 --path . res://tests/bot_matches.tscn -- --matches=24
python3 tools/analytics/compare.py /tmp/before.jsonl /tmp/after.jsonl
```

The bots use abilities at rough rates, not like people, so they answer "did
anything break or swing wildly", not "is it more fun". After a bot check,
play it, then compare real matches by version in `report.py`.
