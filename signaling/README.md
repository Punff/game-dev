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

API (JSON). Requests from a logged-in game carry `Authorization: Bearer <token>`.

- `POST /v1/auth/register` and `POST /v1/auth/login`, with
  `{username, password, client}`. Returns `{token, username}`.
- `POST /v1/auth/logout` and `GET /v1/auth/me`.
- `POST /v1/matches`: a Telemetry record. Returns `{ok, id}`, plus `rank`,
  `best` and `new_best` for solo runs by an account.
- `GET /v1/leaderboard?board=height|wins&limit=15&me=<client id>`: accounts only.
  Each row has its `rank`. Add `&around=me` for `limit` rows centred on the
  viewer's place (the results screen uses this).
- `GET /v1/players/<client id>`
- Friends (accounts only, Bearer token), see `src/friends.js`:
  `GET /v1/friends` (friends with online status and room, requests,
  invites), `POST /v1/friends/request|accept|remove {username}`,
  `POST /v1/friends/invite {username, room}`, and the game's heartbeat
  `POST /v1/presence {status, room}` (about once a minute while logged in;
  "online" = seen in the last 2.5 minutes). No push: the game polls while
  the menu or a room is open. Needs migration `0003_friends.sql`:
  `npx wrangler d1 migrations apply cakum-pakum-stats --remote`.

### Resetting a forgotten password

There's no email, so the admin does it:

```bash
cd signaling
node tools/hash.mjs <username> <new password>     # prints the SQL
npx wrangler d1 execute cakum-pakum-stats --remote --command "<that SQL>"
```

This sets the new password and logs the account out everywhere.

`PBKDF2_ITERATIONS` in `wrangler.toml` sets the password hashing cost: 15,000
fits the free plan's CPU limit. Raise it on the paid plan; accounts are
re-hashed at their next login.

## Protocol

See the comment at the top of `src/index.js`.
