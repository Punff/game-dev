# Room signaling service

A tiny Cloudflare Worker that lets players find each other by room code and
swap WebRTC connection details. Gameplay goes straight between the players'
browsers, so this only handles a few small messages per player, once.
It stores nothing.

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

## Protocol

See the comment at the top of `src/index.js`.
