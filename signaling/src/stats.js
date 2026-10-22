// Stats and leaderboards, on the same Worker as room signaling. Plain HTTP
// (JSON), stored in D1 (binding DB, schema in migrations/).
//
//   POST /v1/matches              a finished (or abandoned) match's Telemetry record
//                                 -> {ok, id, rank?, best?, new_best?}   (rank: solo runs by an account)
//   GET  /v1/leaderboard?board=height|wins&limit=15&me=<client>[&around=me]
//                                 -> {board, rows: [{rank, name, value, you}], me: {rank, value} | null}
//                                    around=me: `limit` rows centred on the viewer's place
//                                    (the top of the board if they aren't on it)
//   GET  /v1/players/<client>     -> {player: {...totals, account, rank_height, rank_wins} | null}
//   /v1/auth/...                  accounts, see auth.js
//   /v1/friends..., /v1/presence  friends and invites, see friends.js
//
// Everyone's matches are stored (that's the design data), but only accounts
// are ranked. A request with "Authorization: Bearer <token>" speaks for that
// account; otherwise a computer counts for the account logged in on it (the
// devices table), or for its own anonymous row.
//
// The host's game runs the match, so a determined player can still send
// made-up results. The checks below only keep out the obviously impossible
// and the accidental floods.

import { accountForClient, accountFromRequest, accountKey, handleAuth, linkDevice } from "./auth.js";
import { handleFriends } from "./friends.js";

const MAX_BODY = 1_500_000;
const CLIENT_RE = /^[0-9a-f]{16}$/;
const MODES = new Set(["solo", "local", "online"]);
const MIN_GAP_SECONDS = 5;        // between two uploads from one client
const CLIMB_LIMIT = (seconds) => 20 + seconds * 8;   // m: well past anything a ball can climb

export async function handleApi(request, env, cors) {
  const url = new URL(request.url);
  const reply = (status, data) =>
    new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json", ...cors } });

  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (!env.DB) return reply(503, { error: "stats storage isn't set up" });

  try {
    if (url.pathname.startsWith("/v1/auth/")) {
      const res = await handleAuth(request, env, reply, url.pathname);
      if (res) return res;
    }
    if (url.pathname.startsWith("/v1/friends") || url.pathname === "/v1/presence") {
      const res = await handleFriends(request, env, reply, url.pathname);
      if (res) return res;
    }
    if (url.pathname === "/v1/matches" && request.method === "POST") return await postMatch(request, env, reply);
    if (url.pathname === "/v1/leaderboard" && request.method === "GET") return await getLeaderboard(request, url, env, reply);
    const m = url.pathname.match(/^\/v1\/players\/([0-9a-f]{16})$/);
    if (m && request.method === "GET") return await getPlayer(request, m[1], env, reply);
  } catch (err) {
    console.error(err);
    return reply(500, { error: "server error" });
  }
  return reply(404, { error: "not found" });
}

async function postMatch(request, env, reply) {
  const text = await request.text();
  if (text.length > MAX_BODY) return reply(413, { error: "record too large" });
  let rec;
  try {
    rec = JSON.parse(text);
  } catch {
    return reply(400, { error: "not JSON" });
  }
  const problem = validate(rec);
  if (problem) return reply(400, { error: problem });

  const last = await env.DB.prepare(
    "SELECT (julianday('now') - julianday(received_at)) * 86400 AS ago FROM matches WHERE client = ? ORDER BY id DESC LIMIT 1",
  ).bind(rec.client).first();
  if (last && last.ago < MIN_GAP_SECONDS) return reply(429, { error: "slow down" });

  const ins = await env.DB.prepare(
    `INSERT INTO matches (client, version, build, mode, players, duration, winner, best_height, tuning_hash, record)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(rec.client, str(rec.version, 32), str(rec.build, 32), rec.mode, rec.players, rec.duration,
    rec.winner | 0, rec.best_height | 0, str(rec.tuning_hash, 16), text).run();

  const result = { ok: true, id: ins.meta.last_row_id };

  // An uploader who is logged in vouches for its own computer.
  const uploader = await accountFromRequest(request, env);
  if (uploader && (await accountForClient(env, rec.client))?.id !== uploader.id) {
    await env.DB.batch(linkDevice(env, rec.client, uploader));
  }
  if (rec.mode === "local" || rec.abandoned) return reply(200, result);

  // Totals for everyone in the match who has an id of their own: their
  // account's row if one is logged in on their computer, else their own.
  const solo = rec.mode === "solo";
  const updates = [];
  let mine = null;   // the uploader's row key and best before this run (solo)
  for (const r of rec.roster) {
    if (!CLIENT_RE.test(r.client || "")) continue;
    const pp = rec.per_player[String(r.id)];
    const acc = await accountForClient(env, r.client);
    const key = acc ? accountKey(acc.id) : r.client;
    const height = Math.max(0, pp.max_m | 0);
    const cause = pp.death?.cause;
    if (solo && r.client === rec.client) {
      const before = await env.DB.prepare("SELECT best_solo FROM players WHERE client = ?").bind(key).first();
      mine = { key, ranked: !!acc, before: before?.best_solo ?? null };
    }
    updates.push(env.DB.prepare(
      `INSERT INTO players (client, account_id, name, solo_runs, best_solo, best_solo_at, online_matches, online_wins, kos,
                            deaths_lava, deaths_side, total_climb, play_seconds)
       VALUES (?1, ?12, ?2, ?3, ?4, CASE WHEN ?4 > 0 THEN datetime('now') END, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
       ON CONFLICT (client) DO UPDATE SET
         name = ?2, last_seen = datetime('now'),
         solo_runs = solo_runs + ?3,
         best_solo_at = CASE WHEN ?4 > best_solo THEN datetime('now') ELSE best_solo_at END,
         best_solo = MAX(best_solo, ?4),
         online_matches = online_matches + ?5, online_wins = online_wins + ?6, kos = kos + ?7,
         deaths_lava = deaths_lava + ?8, deaths_side = deaths_side + ?9,
         total_climb = total_climb + ?10, play_seconds = play_seconds + ?11`,
    ).bind(key, acc ? acc.username : cleanName(r.name), solo ? 1 : 0, solo ? height : 0, solo ? 0 : 1,
      !solo && rec.winner === r.id ? 1 : 0, pp.kos | 0, cause === "lava" ? 1 : 0, cause === "side" ? 1 : 0,
      height, Math.min(rec.duration, 7200), acc ? acc.id : null));
  }
  if (updates.length) await env.DB.batch(updates);

  if (mine?.ranked) {
    const me = await env.DB.prepare("SELECT best_solo FROM players WHERE client = ?").bind(mine.key).first();
    result.rank = await rankOf(env, "best_solo", me.best_solo);
    result.best = me.best_solo;
    result.new_best = mine.before === null || me.best_solo > mine.before;
  }
  return reply(200, result);
}

// Place among accounts for a value of `col` (ties share the better place).
async function rankOf(env, col, value) {
  const above = await env.DB.prepare(`SELECT COUNT(*) AS n FROM players WHERE account_id IS NOT NULL AND ${col} > ?`).bind(value).first();
  return above.n + 1;
}

// Who a read request is about: the Bearer token's account, else the account
// logged in on `client`.
async function viewer(request, env, client) {
  return (await accountFromRequest(request, env)) || (CLIENT_RE.test(client || "") ? await accountForClient(env, client) : null);
}

function validate(rec) {
  if (!rec || typeof rec !== "object") return "bad record";
  if (rec.schema !== 1) return "unknown schema";
  if (!CLIENT_RE.test(rec.client || "")) return "bad client id";
  if (!MODES.has(rec.mode)) return "bad mode";
  if (!Number.isInteger(rec.players) || rec.players < 1 || rec.players > 4) return "bad player count";
  if (typeof rec.duration !== "number" || rec.duration < 0 || rec.duration > 7200) return "bad duration";
  if (!Array.isArray(rec.roster) || rec.roster.length !== rec.players) return "bad roster";
  if (!rec.per_player || typeof rec.per_player !== "object") return "bad per_player";
  if ((rec.mode === "solo") !== (rec.players === 1)) return "mode and player count disagree";
  for (const r of rec.roster) {
    const pp = rec.per_player[String(r.id)];
    if (!pp) return "missing player results";
    if (typeof pp.max_m !== "number" || pp.max_m < 0 || pp.max_m > CLIMB_LIMIT(rec.duration)) return "impossible height";
  }
  return null;
}

async function getLeaderboard(request, url, env, reply) {
  const board = url.searchParams.get("board") === "wins" ? "wins" : "height";
  const col = board === "wins" ? "online_wins" : "best_solo";
  const tiebreak = board === "wins" ? "online_matches ASC" : "best_solo_at ASC";
  const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") || "15", 10) || 15, 1), 50);
  const acc = await viewer(request, env, url.searchParams.get("me"));
  const myKey = acc ? accountKey(acc.id) : null;
  let me = null;
  if (acc) {
    const row = await env.DB.prepare(`SELECT ${col} AS value FROM players WHERE client = ?`).bind(myKey).first();
    if (row && row.value > 0) me = { rank: await rankOf(env, col, row.value), value: row.value };
  }
  const ranked = `FROM players WHERE account_id IS NOT NULL AND ${col} > 0`;
  let offset = 0;
  if (url.searchParams.get("around") === "me" && me) {
    const total = (await env.DB.prepare(`SELECT COUNT(*) AS n ${ranked}`).first()).n;
    offset = Math.max(0, Math.min(me.rank - 1 - Math.floor((limit - 1) / 2), total - limit));
  }
  const { results } = await env.DB.prepare(
    `SELECT client, name, ${col} AS value ${ranked} ORDER BY ${col} DESC, ${tiebreak} LIMIT ? OFFSET ?`,
  ).bind(limit, offset).all();
  // Places, with ties sharing the better one (as rankOf counts them).
  const rows = [];
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    let rank = offset + i + 1;
    if (i > 0 && r.value === results[i - 1].value) rank = rows[i - 1].rank;
    else if (i === 0 && offset > 0) rank = await rankOf(env, col, r.value);
    rows.push({ rank, name: r.name, value: r.value, you: r.client === myKey });
  }
  return reply(200, { board, rows, me });
}

async function getPlayer(request, client, env, reply) {
  const acc = await viewer(request, env, client);
  const p = await env.DB.prepare("SELECT * FROM players WHERE client = ?").bind(acc ? accountKey(acc.id) : client).first();
  if (!p) return reply(200, { player: null });
  const rank = async (col) => (acc && p[col] > 0 ? await rankOf(env, col, p[col]) : null);
  p.rank_height = await rank("best_solo");
  p.rank_wins = await rank("online_wins");
  p.account = acc ? acc.username : null;
  delete p.client;
  delete p.account_id;
  return reply(200, { player: p });
}

function str(v, max) {
  return typeof v === "string" ? v.slice(0, max) : null;
}

function cleanName(n) {
  const s = (typeof n === "string" ? n : "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 16).trim();
  return s || "Ball";
}
