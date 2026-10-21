// Stats and leaderboards, on the same Worker as room signaling. Plain HTTP
// (JSON), stored in D1 (binding DB, schema in migrations/).
//
//   POST /v1/matches              a finished (or abandoned) match's Telemetry record
//                                 -> {ok, id, rank?, best?}   (rank: solo runs)
//   GET  /v1/leaderboard?board=height|wins&limit=15&me=<client>
//                                 -> {board, rows: [{name, value, you}], me: {rank, value} | null}
//   GET  /v1/players/<client>     -> {player: {...totals, rank_height, rank_wins} | null}
//
// Nobody signs in, and the host's game runs the match, so a determined player
// can send made-up results. The checks below only keep out the obviously
// impossible and the accidental floods.

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
    if (url.pathname === "/v1/matches" && request.method === "POST") return await postMatch(request, env, reply);
    if (url.pathname === "/v1/leaderboard" && request.method === "GET") return await getLeaderboard(url, env, reply);
    const m = url.pathname.match(/^\/v1\/players\/([0-9a-f]{16})$/);
    if (m && request.method === "GET") return await getPlayer(m[1], env, reply);
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
  if (rec.mode === "local" || rec.abandoned) return reply(200, result);

  // Totals for everyone in the match who has an id of their own.
  const updates = [];
  let before = null;
  for (const r of rec.roster) {
    if (!CLIENT_RE.test(r.client || "")) continue;
    const pp = rec.per_player[String(r.id)];
    const solo = rec.mode === "solo";
    const height = Math.max(0, pp.max_m | 0);
    const cause = pp.death?.cause;
    if (solo && r.client === rec.client) {
      before = await env.DB.prepare("SELECT best_solo FROM players WHERE client = ?").bind(r.client).first();
    }
    updates.push(env.DB.prepare(
      `INSERT INTO players (client, name, solo_runs, best_solo, best_solo_at, online_matches, online_wins, kos,
                            deaths_lava, deaths_side, total_climb, play_seconds)
       VALUES (?1, ?2, ?3, ?4, CASE WHEN ?4 > 0 THEN datetime('now') END, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
       ON CONFLICT (client) DO UPDATE SET
         name = ?2, last_seen = datetime('now'),
         solo_runs = solo_runs + ?3,
         best_solo_at = CASE WHEN ?4 > best_solo THEN datetime('now') ELSE best_solo_at END,
         best_solo = MAX(best_solo, ?4),
         online_matches = online_matches + ?5, online_wins = online_wins + ?6, kos = kos + ?7,
         deaths_lava = deaths_lava + ?8, deaths_side = deaths_side + ?9,
         total_climb = total_climb + ?10, play_seconds = play_seconds + ?11`,
    ).bind(r.client, cleanName(r.name), solo ? 1 : 0, solo ? height : 0, solo ? 0 : 1,
      !solo && rec.winner === r.id ? 1 : 0, pp.kos | 0, cause === "lava" ? 1 : 0, cause === "side" ? 1 : 0,
      height, Math.min(rec.duration, 7200)));
  }
  if (updates.length) await env.DB.batch(updates);

  if (rec.mode === "solo") {
    const me = await env.DB.prepare("SELECT best_solo FROM players WHERE client = ?").bind(rec.client).first();
    if (me) {
      const above = await env.DB.prepare("SELECT COUNT(*) AS n FROM players WHERE best_solo > ?").bind(me.best_solo).first();
      result.rank = above.n + 1;
      result.best = me.best_solo;
      result.new_best = !before || me.best_solo > before.best_solo;
    }
  }
  return reply(200, result);
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

async function getLeaderboard(url, env, reply) {
  const board = url.searchParams.get("board") === "wins" ? "wins" : "height";
  const col = board === "wins" ? "online_wins" : "best_solo";
  const tiebreak = board === "wins" ? "online_matches ASC" : "best_solo_at ASC";
  const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") || "15", 10) || 15, 1), 50);
  const me = url.searchParams.get("me") || "";
  const { results } = await env.DB.prepare(
    `SELECT client, name, ${col} AS value FROM players WHERE ${col} > 0 ORDER BY ${col} DESC, ${tiebreak} LIMIT ?`,
  ).bind(limit).all();
  const out = { board, rows: results.map((r) => ({ name: r.name, value: r.value, you: r.client === me })), me: null };
  if (CLIENT_RE.test(me)) {
    const row = await env.DB.prepare(`SELECT ${col} AS value FROM players WHERE client = ?`).bind(me).first();
    if (row && row.value > 0) {
      const above = await env.DB.prepare(`SELECT COUNT(*) AS n FROM players WHERE ${col} > ?`).bind(row.value).first();
      out.me = { rank: above.n + 1, value: row.value };
    }
  }
  return reply(200, out);
}

async function getPlayer(client, env, reply) {
  const p = await env.DB.prepare("SELECT * FROM players WHERE client = ?").bind(client).first();
  if (!p) return reply(200, { player: null });
  const rank = async (col) =>
    p[col] > 0 ? (await env.DB.prepare(`SELECT COUNT(*) AS n FROM players WHERE ${col} > ?`).bind(p[col]).first()).n + 1 : null;
  delete p.client;
  p.rank_height = await rank("best_solo");
  p.rank_wins = await rank("online_wins");
  return reply(200, { player: p });
}

function str(v, max) {
  return typeof v === "string" ? v.slice(0, max) : null;
}

function cleanName(n) {
  const s = (typeof n === "string" ? n : "").replace(/[\u0000-\u001f\u007f]/g, "").trim().slice(0, 16).trim();
  return s || "Ball";
}
