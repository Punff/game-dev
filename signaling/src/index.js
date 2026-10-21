// Room signaling for Ultimate Cakum Pakum online play.
//
// Browsers only come here to find each other: a room code, then the WebRTC
// offer / answer / candidate messages. Gameplay goes straight between the
// players, so a match costs this service nothing after everyone connects.
//
//   GET /create        WebSocket: open a new room and become its host (id 1)
//   GET /join/<CODE>   WebSocket: join that room as a guest (id 2, 3, ...)
//
// Messages are JSON. Server -> client:
//   {type: "welcome", code, id, ice}           right after connecting
//   {type: "peer_joined", id}                  to the host
//   {type: "peer_left", id}                    to the host
//   {type: "offer" | "answer" | "candidate", from, ...}   relayed
//   {type: "error", reason}                    then the socket closes
// Client -> server:
//   {type: "offer" | "answer" | "candidate", to, ...}
//
// Plain HTTP under /v1/ is the stats and leaderboard API (src/stats.js).

import { DurableObject } from "cloudflare:workers";
import { handleApi } from "./stats.js";

const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O or 1/I
const CODE_LEN = 5;
const MAX_PLAYERS = 4;
const MAX_MESSAGE = 16 * 1024;
const RELAYED = new Set(["offer", "answer", "candidate"]);

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname.startsWith("/v1/")) {
      if (!originAllowed(request, env)) return new Response("Forbidden", { status: 403 });
      return handleApi(request, env, corsHeaders(request));
    }
    if (request.headers.get("Upgrade") !== "websocket") {
      return new Response("Ultimate Cakum Pakum signaling - connect with a WebSocket.", { status: 426 });
    }
    if (!originAllowed(request, env)) {
      return new Response("Forbidden", { status: 403 });
    }
    const url = new URL(request.url);
    if (url.pathname === "/create") {
      // A fresh code is almost always free; retry the rare collision.
      for (let i = 0; i < 5; i++) {
        const code = randomCode();
        const res = await room(env, code).fetch(new Request(`https://room/create?code=${code}`, request));
        if (res.status !== 409) return res;
      }
      return new Response("Busy, try again", { status: 503 });
    }
    const join = url.pathname.match(/^\/join\/([A-Za-z0-9]{1,12})$/);
    if (join) {
      const code = join[1].toUpperCase();
      return room(env, code).fetch(new Request(`https://room/join?code=${code}`, request));
    }
    return new Response("Not found", { status: 404 });
  },
};

// One Durable Object per room code. It keeps the open sockets (each tagged
// with its player id) plus a counter so an id is never handed out twice in a
// room - a guest who drops signaling may still be in the game. Idle rooms
// hibernate; the counter is wiped when the host leaves.
export class Room extends DurableObject {
  async fetch(request) {
    const url = new URL(request.url);
    const code = url.searchParams.get("code");
    const sockets = this.ctx.getWebSockets();
    const ids = sockets.map((ws) => idOf(ws));

    let id;
    if (url.pathname === "/create") {
      if (sockets.length > 0) return new Response("Code taken", { status: 409 });
      id = 1;
      await this.ctx.storage.put("nextId", 2);
    } else {
      if (!ids.includes(1)) return refuse("No room with that code.");
      if (sockets.length >= MAX_PLAYERS) return refuse("That room is full.");
      id = (await this.ctx.storage.get("nextId")) ?? 2;
      await this.ctx.storage.put("nextId", id + 1);
    }

    const [client, server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ id });
    server.send(JSON.stringify({ type: "welcome", code, id, ice: iceServers(this.env) }));
    if (id !== 1) this.sendTo(1, { type: "peer_joined", id });
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== "string" || message.length > MAX_MESSAGE) return;
    let data;
    try {
      data = JSON.parse(message);
    } catch {
      return;
    }
    if (!RELAYED.has(data.type) || !Number.isInteger(data.to)) return;
    const from = idOf(ws);
    const to = data.to;
    // Guests may only talk to the host; the host may talk to anyone.
    if (from !== 1 && to !== 1) return;
    delete data.to;
    data.from = from;
    this.sendTo(to, data);
  }

  async webSocketClose(ws, code, reason) {
    this.left(ws);
    try {
      ws.close(code, reason);
    } catch {
      // already closed
    }
  }

  async webSocketError(ws) {
    this.left(ws);
  }

  left(ws) {
    const id = idOf(ws);
    if (id === 1) {
      this.ctx.storage.deleteAll();
      for (const other of this.ctx.getWebSockets()) {
        if (other === ws) continue;
        try {
          other.send(JSON.stringify({ type: "error", reason: "The host closed the room." }));
          other.close(1000, "host left");
        } catch {
          // gone already
        }
      }
    } else {
      this.sendTo(1, { type: "peer_left", id });
    }
  }

  sendTo(id, data) {
    for (const ws of this.ctx.getWebSockets()) {
      if (idOf(ws) === id) {
        try {
          ws.send(JSON.stringify(data));
        } catch {
          // closing
        }
      }
    }
  }
}

function room(env, code) {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

function idOf(ws) {
  return ws.deserializeAttachment()?.id ?? 0;
}

function randomCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LEN));
  return Array.from(bytes, (b) => CODE_CHARS[b % CODE_CHARS.length]).join("");
}

function iceServers(env) {
  try {
    return JSON.parse(env.ICE_SERVERS);
  } catch {
    return [{ urls: ["stun:stun.l.google.com:19302"] }];
  }
}

function originAllowed(request, env) {
  const allowed = (env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  if (allowed.length === 0) return true;
  const origin = request.headers.get("Origin");
  if (!origin) return true; // desktop builds send none
  return allowed.some((a) => origin === a || (a.startsWith("*.") && origin.endsWith(a.slice(1))));
}

// The web build calls the API from the itch.io page's origin.
function corsHeaders(request) {
  return {
    "Access-Control-Allow-Origin": request.headers.get("Origin") || "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

// A refusal still needs a WebSocket so the game can show the reason. The
// close waits a moment: hanging up in the same instant can drop the message
// before the game reads it.
function refuse(reason) {
  const [client, server] = Object.values(new WebSocketPair());
  server.accept();
  server.send(JSON.stringify({ type: "error", reason }));
  setTimeout(() => {
    try {
      server.close(1000, "refused");
    } catch {
      // the game closed it first
    }
  }, 2000);
  return new Response(null, { status: 101, webSocket: client });
}
