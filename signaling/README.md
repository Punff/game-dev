# Room signaling service

A tiny Cloudflare Worker that lets players find each other by room code and
swap WebRTC connection details. Gameplay goes straight between the players'
browsers, so this only handles a few small messages per player, once.
Room signaling stores nothing; the stats API (below) keeps match records and
leaderboards in a D1 database.

Runs on the free Workers plan (100,000 requests/day; a Durable Object bills 20
WebSocket messages as one request). If a limit is ever hit, new room joins fail
until the daily reset at 00:00 UTC. Nothing is charged and running matches are
unaffected.

## Run it locally

```bash
cd signaling
npm install
npm run dev          # ws://127.0.0.1:8787
```

Point the game at it with `-- --signaling=ws://127.0.0.1:8787` (desktop), or
open the web build with `?signaling=ws://127.0.0.1:8787` in the page URL.

## Deploy (once, free account)

1. Make a free account at https://dash.cloudflare.com.
2. `cd signaling`, then `npx wrangler login` (opens the browser to approve).
3. `npx wrangler deploy`. It prints the address, something like
   `https://cakum-pakum-signaling.<your-subdomain>.workers.dev`.
4. Put that address in `SIGNALING_URL` in `scripts/core/net.gd`, with `wss://`
   instead of `https://`, and re-export the web build.

## Settings (`wrangler.toml` → `[vars]`)

- `ICE_SERVERS`: the STUN/TURN list sent to every player. Google STUN by
  default. A TURN relay for players on strict networks can be added here later
  and goes live on `npx wrangler deploy`, with no new game build.
- `ALLOWED_ORIGINS`: optional, e.g. `https://*.itch.zone,https://*.itch.io` to
  only accept your itch.io page (desktop builds send no origin and are always
  allowed). Empty = allow all.

## Stats and leaderboards

`src/stats.js` serves plain HTTP under `/v1/` from the same Worker: match
uploads, leaderboards and player totals, stored in D1 (free: 5 GB, 100,000
row writes/day). See `docs/analytics.md` for what's recorded and how to read it.

Set up once:

1. `npx wrangler d1 create cakum-pakum-stats` and put the printed
   `database_id` in `wrangler.toml` (`[[d1_databases]]`).
2. `npx wrangler d1 migrations apply cakum-pakum-stats --remote`
3. `npx wrangler deploy`

The game derives the address from `SIGNALING_URL` (`wss://` → `https://`), so
no new game build is needed for the address. Until the database exists,
`/v1/` answers 503 and the game keeps uploads queued.

Locally: `npx wrangler d1 migrations apply cakum-pakum-stats --local`, then
`npm run dev`; the game started with `--signaling=ws://127.0.0.1:8787` uses it.

API (JSON):

- `POST /v1/matches`: a Telemetry record. Returns `{ok, id}`, plus `rank`,
  `best` and `new_best` for solo runs.
- `GET /v1/leaderboard?board=height|wins&limit=15&me=<client id>`
- `GET /v1/players/<client id>`

## Protocol

See the comment at the top of `src/index.js`.
