# Audit, 2026-10-22

A full pass over the game: code read end to end, every screen screenshotted
(menus, lobbies, matches at 1 and 4 players, pause, results, sandbox), the
test suite and bot matches run, and this computer's match log analysed.
Fixes are on the `audit-pass` branch; each item says whether it's done.

**Data:** the live database wasn't reachable (`wrangler` isn't logged in on
this machine), so the numbers come from this computer's 9 recorded matches
plus bot runs. Real solo runs climb about 2.6 m/s, last 20-120 s and every
death is to the lava. That's too little to retune anything from, so nothing
here changes movement, abilities or lava. Run
`python3 tools/analytics/report.py --remote` after `npx wrangler login` for
the real picture. Bot matches are too crude to stand in for players (8-19 s,
best ~10 m).

## Bugs

| # | What | Status |
|---|---|---|
| 1 | Pause could open in the 1.4 s between the last knock-out and the results. Results then appeared over the open pause menu; both listened for Esc, and closing pause unpaused the game under the results. | Fixed: no pausing once the match is decided; results close pause (also for online guests) |
| 2 | Leaving the match in that same window (Pause → Main menu) made `end_match` fire on the main menu afterwards, leaving the match state at ENDED. | Fixed |
| 3 | A vanishing block came back solid around a ball passing through it (trapped or flung it). | Fixed: waits until nobody is inside |
| 4 | Gravity-field floor sometimes never formed: jump off concrete, hold the field, and now and then all the chunks gathered under you but stayed "phasing" (never reached their slots), so you sank through them. Chunks passed through the ball on the way but still collided with each other, and jammed short of their slots. Measured on the `_test_field_holds_player` setup: 6 of 60 runs failed; it's also why that test failed now and then. | Fixed: on the way to its slot a chunk passes through everything, other chunks too. 0 of 60 failures after, and you stay up longer. (Making chunks solid once under your feet was tried first and made it worse: 11 of 60.) |
| 5 | Stats requests stalled while the game was paused, and the results screen pauses it, so the solo rank often never showed. | Fixed earlier (ui-rework) |
| 6 | Results leaked its nodes whenever a match ended without reaching it (the "resources still in use at exit" error). | Fixed earlier (ui-rework) |
| 7 | The Fullscreen toggle flipped the window instead of setting it, so after leaving fullscreen another way (Esc in a browser) it did the opposite of what it showed. | Fixed |
| 8 | Sandbox station signs sat ~560 px up, above what the camera shows: their text was always cut off. | Fixed (new station card) |
| 9 | Online players were all "P1..P4" everywhere, though names were sent to the host. | Fixed: names on balls, HUD, lobby, results |
| 10 | The online lobby's name label wasn't uppercased like the rest of the card. | Fixed |
| 11 | `MapPlanner` has a `DOOR` template that's never picked. | Left: harmless; delete or add to `_pick_template` |
| 12 | Tests that add a new `class_name` file can fail to parse until the project is imported once (`godot --headless --import`); same for an open editor. | Left: note for whoever adds classes |

| 13 | Map planner: some seeds (about 1 map in 15) had rows with no guaranteed route; for seed 230 nothing above 3 m was. | Fixed on `roadmap`: 0 in 59k rows |
| 14 | A chunk breaking concrete did so inside the physics step: the new chunks couldn't report contacts, so chain reactions stopped after one link. | Fixed on `roadmap` |
| 15 | Chain-reaction history carried over between matches, so later matches could fire chains and hit-stops on stale breaks. | Fixed on `roadmap` |
| 16 | Vanishing blocks timed themselves on render frames: on a slow or fast machine they vanished at different moments. | Fixed on `roadmap` (physics ticks) |
| 17 | A login made while the startup session check was still out could be renamed to the previous account. | Fixed on `roadmap` |
| 18 | Offline, every failed server request logged a JSON parse error. | Fixed on `roadmap` |

## Improvements made

- **HUD height readout.** The leader's height, big, top left, in their
  colour. Solo shows your best under it, a BEST mark on the altitude track and
  a "New best!" callout when you pass it. (There was no number on screen
  during a match.)
- **How to play.** Station notes moved into a card in the corner with your
  current keys (it updates when a pad is plugged in or out) and a goal per
  station that ticks off: stand on the high step, reach the ledge, break two
  slabs, throw chunks with the field, knock the dummy off, stand on every
  block. Progress shows top left; numbered posts mark stations in the world;
  the debug event feed only shows with [F3].
- **Solo starts straight away** instead of going through the couch lobby.
- **F11** toggles fullscreen anywhere.
- **Online names** (see bug 9).

## Recommendations (not done)

- **Sound.** The game is silent apart from menu music: every event calls
  `Sfx.play()` but `assets/sfx/` is empty. This is the biggest gap in feel.
  Event names are listed in `scripts/core/sfx.gd`. (A synthesised placeholder
  set was tried and removed on request.)
- **Real data.** Log in wrangler and run the report against the live
  database before touching tuning; the roadmap's ability and block questions
  need it.
- **Smarter bots.** Current bots die in seconds, so bot runs can't compare
  tuning changes yet (roadmap 4).
- **Lobby restyle.** The couch and online lobbies still use the old
  centred layout; they'd match the menu better as kit pieces (sleeve card for
  the room code, `UiChip` for ready).
- **Countdown / go.** Could reuse the stamped-sleeve title style for "GO!"
  for consistency with the menus.
