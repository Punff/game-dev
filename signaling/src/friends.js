// Friends, presence and room invites. Accounts only (Bearer token).
//
//   GET  /v1/friends                     -> {friends: [{name, online, status, room}],
//                                            incoming: [name], outgoing: [name],
//                                            invites: [{from, room}]}
//   POST /v1/friends/request {username}  ask; accepts at once if they'd asked you
//   POST /v1/friends/accept  {username}
//   POST /v1/friends/remove  {username}  unfriend, decline or take back a request
//   POST /v1/friends/invite  {username, room}   a friend's game shows it for a few minutes
//   POST /v1/presence        {status: menu|room|match, room?}   the game's heartbeat
//
// There's no push: games poll GET /v1/friends while the menu is up. Presence
// is a heartbeat (about once a minute), so "online" means seen recently.

import { accountFromRequest } from "./auth.js";

const ONLINE_SECONDS = 150;
const INVITE_SECONDS = 300;
const MAX_FRIENDS = 100;
const ROOM_RE = /^[A-Z0-9]{1,12}$/;
const STATUSES = new Set(["menu", "room", "match"]);

export async function handleFriends(request, env, reply, path) {
  const me = await accountFromRequest(request, env);
  if (!me) return reply(401, { error: "Log in to use friends.", unauthorized: true });

  if (path === "/v1/friends" && request.method === "GET") return reply(200, await listFor(env, me));
  if (request.method !== "POST") return null;
  const body = await readJson(request);

  if (path === "/v1/presence") {
    const status = STATUSES.has(body?.status) ? body.status : "menu";
    const room = status === "room" && ROOM_RE.test(body?.room || "") ? body.room : null;
    await env.DB.prepare(
      `INSERT INTO presence (account_id, status, room, updated_at) VALUES (?1, ?2, ?3, datetime('now'))
       ON CONFLICT (account_id) DO UPDATE SET status = ?2, room = ?3, updated_at = datetime('now')`,
    ).bind(me.id, status, room).run();
    return reply(200, { ok: true });
  }

  const other = await env.DB.prepare("SELECT id, username FROM accounts WHERE username = ?")
    .bind(String(body?.username || "").trim()).first();
  if (!other) return reply(404, { error: "No player with that name." });
  if (other.id === me.id) return reply(400, { error: "That's you." });
  const [a, b] = me.id < other.id ? [me.id, other.id] : [other.id, me.id];
  const pair = await env.DB.prepare("SELECT status, requested_by FROM friends WHERE a = ? AND b = ?").bind(a, b).first();

  if (path === "/v1/friends/request") {
    if (pair?.status === "accepted") return reply(200, { ok: true, status: "accepted" });
    if (pair && pair.requested_by !== me.id) {   // they'd already asked: that's a yes
      await env.DB.prepare("UPDATE friends SET status = 'accepted' WHERE a = ? AND b = ?").bind(a, b).run();
      return reply(200, { ok: true, status: "accepted" });
    }
    if (pair) return reply(200, { ok: true, status: "pending" });
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM friends WHERE a = ?1 OR b = ?1").bind(me.id).first();
    if (count.n >= MAX_FRIENDS) return reply(400, { error: "That's a lot of friends. Remove some first." });
    await env.DB.prepare("INSERT INTO friends (a, b, status, requested_by) VALUES (?, ?, 'pending', ?)").bind(a, b, me.id).run();
    return reply(200, { ok: true, status: "pending" });
  }
  if (path === "/v1/friends/accept") {
    if (!pair || pair.requested_by === me.id) return reply(400, { error: "No request from them." });
    await env.DB.prepare("UPDATE friends SET status = 'accepted' WHERE a = ? AND b = ?").bind(a, b).run();
    return reply(200, { ok: true, status: "accepted" });
  }
  if (path === "/v1/friends/remove") {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM friends WHERE a = ? AND b = ?").bind(a, b),
      env.DB.prepare("DELETE FROM invites WHERE (from_id = ?1 AND to_id = ?2) OR (from_id = ?2 AND to_id = ?1)").bind(me.id, other.id),
    ]);
    return reply(200, { ok: true });
  }
  if (path === "/v1/friends/invite") {
    if (pair?.status !== "accepted") return reply(400, { error: "You can only invite friends." });
    if (!ROOM_RE.test(body?.room || "")) return reply(400, { error: "Bad room code." });
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO invites (from_id, to_id, room) VALUES (?1, ?2, ?3)
         ON CONFLICT (from_id, to_id) DO UPDATE SET room = ?3, created_at = datetime('now')`,
      ).bind(me.id, other.id, body.room),
      env.DB.prepare("DELETE FROM invites WHERE created_at < datetime('now', ?)").bind(`-${INVITE_SECONDS} seconds`),
    ]);
    return reply(200, { ok: true });
  }
  return null;
}

async function listFor(env, me) {
  const { results } = await env.DB.prepare(
    `SELECT acc.username AS name, f.status, f.requested_by, p.status AS presence, p.room,
            (julianday('now') - julianday(p.updated_at)) * 86400 AS ago
     FROM friends f
     JOIN accounts acc ON acc.id = CASE WHEN f.a = ?1 THEN f.b ELSE f.a END
     LEFT JOIN presence p ON p.account_id = acc.id
     WHERE f.a = ?1 OR f.b = ?1
     ORDER BY acc.username COLLATE NOCASE`,
  ).bind(me.id).all();
  const out = { friends: [], incoming: [], outgoing: [], invites: [] };
  for (const r of results) {
    if (r.status === "pending") {
      (r.requested_by === me.id ? out.outgoing : out.incoming).push(r.name);
      continue;
    }
    const online = r.ago !== null && r.ago < ONLINE_SECONDS;
    out.friends.push({ name: r.name, online, status: online ? r.presence : "offline", room: online && r.presence === "room" ? r.room : null });
  }
  // Online friends first, then by name.
  out.friends.sort((x, y) => (y.online - x.online) || x.name.localeCompare(y.name, undefined, { sensitivity: "base" }));
  const inv = await env.DB.prepare(
    `SELECT acc.username AS name, i.room FROM invites i JOIN accounts acc ON acc.id = i.from_id
     WHERE i.to_id = ? AND i.created_at > datetime('now', ?) ORDER BY i.created_at DESC`,
  ).bind(me.id, `-${INVITE_SECONDS} seconds`).all();
  out.invites = inv.results.map((r) => ({ from: r.name, room: r.room }));
  return out;
}

async function readJson(request) {
  try {
    return await request.json();
  } catch {
    return null;
  }
}
