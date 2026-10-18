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

## Project layout

```
blocks/            Block base class + one script per block type (self-drawn)
scripts/core/      Autoloads: Settings (persisted options + bindings), PlayerManager
                   (joined players, per-player InputMap actions), MatchManager (scene
                   flow), Sfx (silent hook: drop audio files named after events into
                   assets/sfx/), Grit (film-grain overlay), SignalBus, Palette
scripts/game/      Game loop, MapPlanner (pure level generator), MapGeneration
                   (streams blocks), camera, lava, background, HUD
scripts/player/    Player controller
scripts/ui/        Code-built menus sharing one theme (UiTheme)
shaders/           background.gdshader, lava.gdshader
tests/             Headless test suite + screenshot helper
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

Screenshots of any scene (dev helper):

```bash
SHOT_SCENE=res://scenes/game.tscn SHOT_OUT=/tmp/shot SHOT_PLAYERS=2 SHOT_TIMES=5 \
  godot --path . res://tests/screenshot.tscn
```

See `WEB_BUILD.md` for the browser build and `MACOS_BUILD.md` for macOS.
