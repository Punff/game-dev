// The daily climb: one map per UTC day (the game seeds it from the date),
// unlimited tries, your best counts. Accounts only (Bearer token); you race
// your friends' best runs as ghosts.
//
//   POST /v1/daily {day, height, duration, version, ghost}
//        -> {ok, best, improved, rank, of}   (rank among you and your friends today)
//        Keeps the run only if it beats your best for that day.
//   GET  /v1/daily?day=YYYY-MM-DD[&ghosts=1]
//        -> {day, rows: [{rank, name, value, you}], me: {rank, value} | null,
//            ghosts?: [{name, you, height, version, ghost}]}
//        You and your friends who have climbed that day, best first.
//
// Like match uploads, results come from the player's own game: the checks
// only keep out the impossible and the oversized.

import { accountFromRequest } from "./auth.js";

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const MAX_GHOST = 200_000;         // bytes of JSON (~10 min of run at 10 points/s)
const MAX_POINTS = 2 * 6000;
const MAX_GHOSTS = 6;
const CLIMB_LIMIT = (seconds) => 20 + seconds * 8;   // m, as in stats.js

export async function handleDaily(request, env, reply, url) {
  const me = await accountFromRequest(request, env);
  if (!me) return reply(401, { error: "Log in to race your friends on the daily climb.", unauthorized: true });
  if (request.method === "POST") return postRun(request, env, reply, me);
  if (request.method === "GET") return getDay(url, env, reply, me);
  return null;
}

// A day the game could be playing right now: yesterday, today or tomorrow
// (UTC), so a run that started before midnight still counts.
function dayOk(day) {
  if (!DAY_RE.test(day || "")) return false;
  const t = Date.parse(day + "T00:00:00Z");
  return Number.isFinite(t) && Math.abs(t - Date.now()) < 2 * 86400_000;
}

async function postRun(request, env, reply, me) {
  const text = await request.text();
  if (text.length > MAX_GHOST + 2000) return reply(413, { error: "run too large" });
  let run;
  try {
    run = JSON.parse(text);
  } catch {
    return reply(400, { error: "not JSON" });
  }
  if (!dayOk(run?.day)) return reply(400, { error: "bad day" });
  const duration = Number(run.duration);
  if (!Number.isFinite(duration) || duration < 0 || duration > 7200) return reply(400, { error: "bad duration" });
  const height = run.height;
  if (!Number.isInteger(height) || height < 0 || height > CLIMB_LIMIT(duration)) return reply(400, { error: "impossible height" });
  const pts = run.ghost?.pts;
  if (!Array.isArray(pts) || pts.length > MAX_POINTS || pts.length % 2 || !pts.every(Number.isInteger)) {
    return reply(400, { error: "bad ghost" });
  }
  const step = Number(run.ghost.step);
  if (!(step >= 0.05 && step <= 1)) return reply(400, { error: "bad ghost" });
  const ghost = JSON.stringify({ step, pts });
  const version = typeof run.version === "string" ? run.version.slice(0, 32) : null;

  const before = await env.DB.prepare("SELECT height, duration FROM daily_runs WHERE day = ? AND account_id = ?")
    .bind(run.day, me.id).first();
  const improved = !before || height > before.height || (height === before.height && duration < before.duration);
  if (improved) {
    await env.DB.prepare(
      `INSERT INTO daily_runs (day, account_id, height, duration, version, ghost) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
       ON CONFLICT (day, account_id) DO UPDATE SET height = ?3, duration = ?4, version = ?5, ghost = ?6,
         tries = tries + 1, updated_at = datetime('now')`,
    ).bind(run.day, me.id, height, duration, version, ghost).run();
  } else {
    await env.DB.prepare("UPDATE daily_runs SET tries = tries + 1 WHERE day = ? AND account_id = ?").bind(run.day, me.id).run();
  }
  const rows = await board(env, run.day, me);
  const mine = rows.find((r) => r.you);
  return reply(200, { ok: true, best: mine ? mine.value : height, improved, rank: mine?.rank ?? null, of: rows.length });
}

async function getDay(url, env, reply, me) {
  const day = url.searchParams.get("day");
  if (!DAY_RE.test(day || "")) return reply(400, { error: "bad day" });
  const withGhosts = url.searchParams.get("ghosts") === "1";
  const rows = await board(env, day, me, withGhosts);
  const mine = rows.find((r) => r.you);
  const out = { day, rows: rows.map(({ rank, name, value, you }) => ({ rank, name, value, you })), me: mine ? { rank: mine.rank, value: mine.value } : null };
  if (withGhosts) {
    out.ghosts = rows.slice(0, MAX_GHOSTS).filter((r) => r.ghost).map((r) => ({
      name: r.name, you: r.you, height: r.value, version: r.version, ghost: JSON.parse(r.ghost),
    }));
    // Your own always comes along, even if you're not in the top few.
    if (mine?.ghost && !out.ghosts.some((g) => g.you)) {
      out.ghosts.push({ name: mine.name, you: true, height: mine.value, version: mine.version, ghost: JSON.parse(mine.ghost) });
    }
  }
  return reply(200, out);
}

// You and your accepted friends who have a run that day, best first (higher,
// then quicker); ties share the better place.
async function board(env, day, me, withGhosts = false) {
  const { results } = await env.DB.prepare(
    `SELECT d.account_id, acc.username AS name, d.height, d.duration, d.version${withGhosts ? ", d.ghost" : ""}
     FROM daily_runs d JOIN accounts acc ON acc.id = d.account_id
     WHERE d.day = ?1 AND (d.account_id = ?2 OR d.account_id IN (
       SELECT CASE WHEN a = ?2 THEN b ELSE a END FROM friends WHERE (a = ?2 OR b = ?2) AND status = 'accepted'))
     ORDER BY d.height DESC, d.duration ASC`,
  ).bind(day, me.id).all();
  const rows = [];
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    const rank = i > 0 && r.height === results[i - 1].height ? rows[i - 1].rank : i + 1;
    rows.push({ rank, name: r.name, value: r.height, you: r.account_id === me.id, version: r.version, ghost: r.ghost });
  }
  return rows;
}
