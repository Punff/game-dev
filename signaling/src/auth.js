// Username + password accounts. No email: a forgotten password is reset by
// hand (tools/hash.mjs, see README).
//
//   POST /v1/auth/register {username, password, client}  -> {token, username}
//   POST /v1/auth/login    {username, password, client}  -> {token, username}
//   POST /v1/auth/logout   (Bearer token)                -> {ok}
//   GET  /v1/auth/me       (Bearer token)                -> {username} | 401
//
// Logging in links the computer (client) to the account, so online matches
// it plays as a guest count for the account, and merges whatever that
// computer earned anonymously into it.

import { hashPassword, iterations, randomHex, sameHex, sha256Hex } from "./password.js";

const USERNAME_RE = /^[A-Za-z0-9_-]{3,16}$/;
const CLIENT_RE = /^[0-9a-f]{16}$/;
const SESSION_DAYS = 180;
const MAX_FAILURES = 10;          // per username...
const MAX_IP_FAILURES = 50;       // ...and per IP (a LAN party shares one)...
const FAILURE_WINDOW_MIN = 15;    // ...in this many minutes

export async function handleAuth(request, env, reply, path) {
  if (path === "/v1/auth/me" && request.method === "GET") {
    const acc = await accountFromRequest(request, env);
    return acc ? reply(200, { username: acc.username }) : reply(401, { error: "not logged in" });
  }
  if (path === "/v1/auth/logout" && request.method === "POST") {
    const token = bearer(request);
    if (token) {
      const hash = await sha256Hex(token);
      const s = await env.DB.prepare("SELECT account_id FROM sessions WHERE token_hash = ?").bind(hash).first();
      const body = await readJson(request);
      const stmts = [env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(hash)];
      if (s && CLIENT_RE.test(body?.client || "")) {
        stmts.push(env.DB.prepare("DELETE FROM devices WHERE client = ? AND account_id = ?").bind(body.client, s.account_id));
      }
      await env.DB.batch(stmts);
    }
    return reply(200, { ok: true });
  }
  if (request.method !== "POST" || (path !== "/v1/auth/register" && path !== "/v1/auth/login")) return null;

  const body = await readJson(request);
  const username = typeof body?.username === "string" ? body.username.trim() : "";
  const password = typeof body?.password === "string" ? body.password : "";
  const client = CLIENT_RE.test(body?.client || "") ? body.client : null;
  if (!USERNAME_RE.test(username)) return reply(400, { error: "Usernames are 3-16 letters, digits, _ or -." });
  if (password.length < 8 || password.length > 128) return reply(400, { error: "Passwords are 8-128 characters." });

  let account;
  if (path === "/v1/auth/register") {
    const salt = randomHex(16);
    const rounds = iterations(env);
    const hash = await hashPassword(password, salt, rounds);
    try {
      const ins = await env.DB.prepare("INSERT INTO accounts (username, pass_hash, salt, iterations) VALUES (?, ?, ?, ?)")
        .bind(username, hash, salt, rounds).run();
      account = { id: ins.meta.last_row_id, username };
    } catch (err) {
      if (String(err).includes("UNIQUE")) return reply(409, { error: "That username is taken." });
      throw err;
    }
  } else {
    const ip = request.headers.get("CF-Connecting-IP") || "local";
    const keys = [`u:${username.toLowerCase()}`, `ip:${ip}`];
    const fails = await env.DB.prepare(
      `SELECT SUM(key = ?1) AS user, SUM(key = ?2) AS ip FROM login_attempts WHERE key IN (?1, ?2) AND at > datetime('now', ?3)`,
    ).bind(keys[0], keys[1], `-${FAILURE_WINDOW_MIN} minutes`).first();
    if (fails && (fails.user >= MAX_FAILURES || fails.ip >= MAX_IP_FAILURES)) {
      return reply(429, { error: "Too many tries. Wait a few minutes." });
    }
    const row = await env.DB.prepare("SELECT id, username, pass_hash, salt, iterations FROM accounts WHERE username = ?")
      .bind(username).first();
    // Hash even for an unknown name, so the answer takes as long either way.
    const hash = await hashPassword(password, row?.salt || "00".repeat(16), row?.iterations || iterations(env));
    if (!row || !sameHex(hash, row.pass_hash)) {
      await env.DB.batch([
        env.DB.prepare("INSERT INTO login_attempts (key) VALUES (?), (?)").bind(keys[0], keys[1]),
        env.DB.prepare("DELETE FROM login_attempts WHERE at < datetime('now', '-1 day')"),
      ]);
      return reply(401, { error: "Wrong username or password." });
    }
    account = { id: row.id, username: row.username };
    if (row.iterations !== iterations(env)) {   // the setting changed: re-hash while we have the password
      const salt = randomHex(16);
      await env.DB.prepare("UPDATE accounts SET pass_hash = ?, salt = ?, iterations = ? WHERE id = ?")
        .bind(await hashPassword(password, salt, iterations(env)), salt, iterations(env), row.id).run();
    }
  }

  const token = randomHex(32);
  const stmts = [
    env.DB.prepare(`INSERT INTO sessions (token_hash, account_id, expires_at) VALUES (?, ?, datetime('now', '+${SESSION_DAYS} days'))`)
      .bind(await sha256Hex(token), account.id),
    // The account's own leaderboard row, even before it has played.
    env.DB.prepare("INSERT INTO players (client, account_id, name) VALUES (?, ?, ?) ON CONFLICT (client) DO UPDATE SET name = excluded.name")
      .bind(accountKey(account.id), account.id, account.username),
  ];
  if (client) stmts.push(...linkDevice(env, client, account));
  await env.DB.batch(stmts);
  return reply(200, { token, username: account.username });
}

// The account behind the request's Bearer token, or null.
export async function accountFromRequest(request, env) {
  const token = bearer(request);
  if (!token) return null;
  return await env.DB.prepare(
    `SELECT a.id, a.username FROM sessions s JOIN accounts a ON a.id = s.account_id
     WHERE s.token_hash = ? AND s.expires_at > datetime('now')`,
  ).bind(await sha256Hex(token)).first();
}

// The account logged in on a computer, or null.
export async function accountForClient(env, client) {
  return await env.DB.prepare(
    "SELECT a.id, a.username FROM devices d JOIN accounts a ON a.id = d.account_id WHERE d.client = ?",
  ).bind(client).first();
}

// Leaderboard row key for an account (anonymous rows use the client id).
export function accountKey(id) {
  return `a${id}`;
}

// Links `client` to the account and folds that computer's anonymous totals
// into the account's row.
export function linkDevice(env, client, account) {
  return [
    env.DB.prepare("INSERT INTO devices (client, account_id) VALUES (?, ?) ON CONFLICT (client) DO UPDATE SET account_id = excluded.account_id, linked_at = datetime('now')")
      .bind(client, account.id),
    env.DB.prepare(
      `INSERT INTO players (client, account_id, name, solo_runs, best_solo, best_solo_at, online_matches, online_wins, kos,
                            deaths_lava, deaths_side, total_climb, play_seconds)
       SELECT ?1, ?2, ?3, solo_runs, best_solo, best_solo_at, online_matches, online_wins, kos,
              deaths_lava, deaths_side, total_climb, play_seconds FROM players WHERE client = ?4
       ON CONFLICT (client) DO UPDATE SET
         solo_runs = solo_runs + excluded.solo_runs,
         best_solo_at = CASE WHEN excluded.best_solo > best_solo THEN excluded.best_solo_at ELSE best_solo_at END,
         best_solo = MAX(best_solo, excluded.best_solo),
         online_matches = online_matches + excluded.online_matches, online_wins = online_wins + excluded.online_wins,
         kos = kos + excluded.kos, deaths_lava = deaths_lava + excluded.deaths_lava, deaths_side = deaths_side + excluded.deaths_side,
         total_climb = total_climb + excluded.total_climb, play_seconds = play_seconds + excluded.play_seconds`,
    ).bind(accountKey(account.id), account.id, account.username, client),
    env.DB.prepare("DELETE FROM players WHERE client = ?").bind(client),
  ];
}

function bearer(request) {
  const h = request.headers.get("Authorization") || "";
  return h.startsWith("Bearer ") ? h.slice(7).trim() : null;
}

async function readJson(request) {
  try {
    const text = await request.text();
    return text.length < 4096 ? JSON.parse(text) : null;
  } catch {
    return null;
  }
}
