# Ultimate Cakum Pakum

Couch-party vertical brawl for 1–4 players, inspired by Upperz. Climb a wide, randomly generated wreck of
concrete and steel, smash it apart, throw the debris at each other and stay
ahead of the rising slag. Last one standing wins; solo runs chase a saved
best height.

Core toys: double jump, charge jump (keeps charging off ledges, fire it
mid-air), ground pound (fast-fall shatters concrete), aimed shockwave
(knockback, shatters concrete, launches debris, rocket-jump downward) and a
gravity field (grab debris, stack it under you, hurl it on release). Fast
debris knocks players around and smashes more concrete — chain reactions.
There are no side walls: shove someone far enough off the edge and they're out.
Every few rows the route funnels onto one contested platform (or a tight pair).

Godot **4.7**, GL Compatibility renderer (same look on desktop and web).

## Controls (defaults — remap in Settings → Controls)

| Action | Keyboard left | Keyboard right | Gamepad |
|---|---|---|---|
| Move | A / D | ← / → | Left stick, D-pad |
| Jump (double jump) | W, Space | ↑ | A |
| Aim up / down, fast fall | W / S | ↑ / ↓ | Left stick |
| Charge jump (hold, release) | Q, L-Shift | R-Shift, L | RT, RB |
| Gravity field (hold) | E | / , K | LT, LB |
| Shockwave (aimed) | F | . , J | B, X |
| Pause | Esc / P | Esc / P | Start |

Two people can share one keyboard; every gamepad is its own player.
In the lobby press your jump key/button to join, again to ready up,
left/right to change colour.

## Online

The host runs the real match; each computer brings one player (either keyboard half or
any gamepad).

How it stays responsive for guests:

- **Your own ball reacts instantly.** A guest's game simulates its own ball the moment a
  key is pressed, numbering every tick of controls (a *frame*) and sending the last six
  each tick so a lost packet costs nothing.
- **The host stays in charge.** It plays each guest's frames in order, one step per frame
  (waiting a moment for a late one), and every snapshot says which frame it has used up
  to. The guest compares that with where it had its ball after the same frame; if they
  differ (a hit, a shove, debris that wasn't where it looked), it rewinds to the host's
  version, replays its frames since then silently, and eases the drawing over.
- **Everything else is shown as the host has it**: players at 60 Hz, drawn a few ticks in
  the past so there's always a pair of snapshots to blend between; debris at 30 Hz.
  Blocks only break and vanish when the host says so. A guest's world clock (moving
  platforms, vanishing blocks) runs ahead by its lead, so the predicted ball meets things
  where the host will have them.
- With *Show FPS* on, guests also see that lead in ms (about one round trip).

- **Rooms** (browsers anywhere, the itch.io build): Online → Create room shows a code;
  friends pick Join room and type it. The creator's game hosts the match, so their tab
  must stay open and in front. Connections go straight between players over WebRTC;
  the free Cloudflare service in `signaling/` only introduces them (see its README to
  run or deploy it). Desktop builds use Godot's WebRTC add-on in `addons/webrtc`.
  There's no TURN relay yet, so a few strict networks can't connect directly.
- **Direct connect** (LAN / dedicated server, over WebSocket): Online → Direct connect.
  Host (desktop only) and others join `ws://<your IP>:7777`, or run a dedicated server
  that any build can join:

```bash
godot --headless --path . -- --server --port=7777
```

Not there yet: sounds other players cause (guests hear only their own ball), a TURN relay,
and rejoining a match in progress. Debris a guest holds with a gravity field still moves
as the host has it, so it trails a little behind their ball on a slow connection.

Smoke tests (bots join, play a whole match and check the results come back):

```bash
godot --headless --path . res://tests/net_bot.tscn -- --name=bot1
godot --headless --path . res://tests/net_bot.tscn -- --room=create --code-file=room.txt --signaling=ws://127.0.0.1:8787
godot --headless --path . res://tests/net_bot.tscn -- --room=room.txt --signaling=ws://127.0.0.1:8787
```

To try a bad connection on one machine, give every process `--lag=80 --jitter=30 --loss=5`
(ms, ms, % of unreliable packets dropped). Bots print how often their ball had to be
corrected; add `--calm` (no abilities) to measure prediction alone - it should be close
to zero.

## Project layout

```
blocks/            Block base class + one script per block type (self-drawn)
scripts/core/      Autoloads: Settings (persisted options + bindings), PlayerManager
                   (joined players, per-player InputMap actions), MatchManager (scene
                   flow), Net (online: rooms over WebRTC via RoomLink, or direct
                   WebSocket; snapshots), Sfx (silent hook: drop audio files named after events into
                   assets/sfx/), Grit (film-grain overlay), SignalBus, Palette
scripts/game/      Game loop, MapPlanner (pure level generator), MapGeneration
                   (streams blocks), camera, lava, background, HUD
scripts/player/    Player controller
scripts/ui/        Code-built menus sharing one theme (UiTheme)
shaders/           background.gdshader, lava.gdshader
tests/             Headless test suite, screenshot helper, online bot (net_bot)
signaling/         Cloudflare Worker that matches room codes for online play
addons/webrtc/     Godot's WebRTC extension (desktop only; browsers have it built in)
```

## Tests

```bash
godot --headless --path . res://tests/run_tests.tscn
```

Covers: level generator invariants over 60 seeds × ~150 rows (bounds, no
overlaps, every row reachable from the one below using a jump envelope
simulated from the player's real constants), determinism per seed, input
binding round-trips and remaps reaching the InputMap, a bot that performs
the jumps the generator relies on with the real physics, a full game-scene
smoke test and a 4-player random-input "chaos" run.

### Sandbox ("How to play")

The main menu's How to play is a practice level: one station per move, a
target dummy and every block type, no lava. `[F3]` shows live stats, and an
event log (jumps, landings with impact speed / air time / peak, charge
launches, fields, shockwaves, breaks) is shown on screen and saved to
`user://logs/sandbox.log`. It can be driven by a script for testing moves
precisely - see the header of `scripts/game/sandbox.gd` for the commands:

```bash
godot --headless --path . res://scenes/sandbox.tscn -- --sandbox-script=res://tests/sandbox/tour.txt
```

### Benchmark

A 4-player match with random inputs that climbs and smashes concrete every
1.5 s; prints frame time (avg / p95 / p99 / max) and a breakdown by how many
chunks are alive. `--fixed-fps 60` runs it flat out so the numbers are the
work done. Without `--headless` it includes drawing; `BENCH_WINDOW=2560x1440`
mimics a browser on a high-DPI screen, `BENCH_HIDE=grit,background,lava`
shows what a layer costs.

```bash
godot --headless --fixed-fps 60 --path . res://tests/bench.tscn
BENCH_WINDOW=2560x1440 godot --fixed-fps 60 --path . res://tests/bench.tscn
```

Screenshots of any scene (dev helper):

```bash
SHOT_SCENE=res://scenes/game.tscn SHOT_OUT=/tmp/shot SHOT_PLAYERS=2 SHOT_TIMES=5 \
  godot --path . res://tests/screenshot.tscn
```

See `WEB_BUILD.md` for the browser build and `MACOS_BUILD.md` for macOS.
