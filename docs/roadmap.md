# Roadmap

Ideas we've agreed on but aren't building yet. Each has a short note on what
exists today and what it depends on. Order is a suggestion, not a commitment.

## 1. Menus and UI (one rework, do these together)

The menus today are overlays: `MenuBase.build_overlay()` dims the screen and
centres a panel (Settings, Leaderboard, Account, Pause and Results all work
this way). Most of the items below are one job: a new menu shell.

- **Main menu redo.** No pop-ups. The main menu list stays on the left, and
  the selected entry's submenu opens in the right side of the same screen.
  Needs a "panel host" in place of `open_sub()` overlays, and controller and
  keyboard focus that moves between the list and the right panel.
- **Play menu.** Singleplayer, Local and Online all move under Play. That's
  also where new game modes will go later.
- **Popup system redo.** Replace the overlay pattern with the panel host above
  wherever it fits. Keep real pop-ups only for in-game moments (Pause,
  Results), and polish those too.
- **Settings redo.** Rebuild Settings inside the new shell. Today it's
  `scripts/ui/settings_menu.gd` (two tabs, rows built in code). Rethink the
  grouping, control remapping and how it looks.
- **Profile section.** Account, totals and rank (today in `LeaderboardMenu` and
  `AccountMenu`) get their own place in the menu, built so character
  customisation can slot in later (ball colour/skin, trail, name tag).
- **Login on start.** On first launch (or when logged out), show login /
  create account / "play without an account" before the main menu. Remember
  the choice so it doesn't nag. `Stats.login()/register()` and the session
  check already exist.
- **Leaderboard after every match.** Results screen shows the relevant board
  (solo: Highest Climb around your place; online: wins), not just your rank.
  `EndScreen._on_rank()` already gets the server's reply; it needs a slice of
  the board around the player (new `GET /v1/leaderboard?around=me`).
- **How to play polish.** Placement of items and text in the sandbox
  (`scripts/game/sandbox.gd`), general polish.

Depends on: nothing. Do the shell first, then move each screen into it.

## 2. Online

- **Ping in the lobby.** Guests and host see each player's ping in the
  online lobby. In a match `Net.lead_time` already gives about one round
  trip, but no packets flow in the lobby, so this needs a small ping/pong RPC
  every second or so, shown in `scripts/ui/lobby_slot.gd`.
- **Friends.** Add friends by username, see who's online, join or invite
  into their room without typing a code. Needs on the server: a `friends`
  table (requests, accepted), presence (online / in room `CODE`), probably a
  Durable Object per user or a small "presence" one, since D1 alone can't push
  invites. Needs accounts (done).

Depends on: accounts (done). Friends UI fits the new menu shell.

## 3. Map generation

Tweaking, more control, more variety. Today `MapPlanner` builds rows from
templates, with four height biomes (`MapPlanner.BIOMES`) that set gaps and
block weights.

- More distinct biomes (look and rules, not just numbers).
- Events (a gust, a quake, a falling slab, the lava surging) to break up the climb.
- New blocks.
- Designer control: seed and biome overrides to test a stretch of map
  directly, maybe a simple map preview tool.
- Use the telemetry: block share vs standing time, stalls per block, deaths
  after a block, and the heatmap (`tools/analytics/report.py`) show which
  blocks and stretches work.

Keep to the game-feel rules: physics-driven chaos, platforms float, no
scripted "neatness".

## 4. Testing and AI

The match data makes a real test suite possible:

- Smarter bots (`tests/bot_matches.gd`) that use abilities the way players
  do (from the recorded events), so bot runs give believable numbers for a
  tuning change.
- Regression checks: run N bot matches before and after a change and compare
  the report's numbers (`--version` / tuning hash already split them).
- Replays from records (seed + per-tick inputs) to reproduce bugs. That needs
  inputs recorded, which today we don't.
- Automatic "looks broken" checks from the report's anomalies, run in CI on
  bot matches.

## 5. Abilities

They work and feel fine, but haven't been examined as a set. Questions:

- What each one is for in the flow of a match (climb, escape, sabotage,
  combo), and whether two overlap.
- What the data says: use rates, hit rates, gravity-field whiffs, rocket
  jumps, winners vs others (report → Abilities).
- Candidate new abilities and what they'd replace or add, maybe as
  pick-ups or loadouts instead of everyone having everything.

Keep to the game-feel rules: don't retune what players already like without
testing it; make one change at a time and play it.
