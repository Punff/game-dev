-- Username + password accounts. Only accounts are ranked on the leaderboards;
-- anonymous computers keep their own `players` row (client = their id) until
-- they log in, when it's merged into the account's row (client = 'a<id>').

CREATE TABLE accounts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  pass_hash TEXT NOT NULL,        -- PBKDF2-SHA256, hex
  salt TEXT NOT NULL,             -- hex
  iterations INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Logged-in sessions. Only the SHA-256 of the token is kept.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  account_id INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  expires_at TEXT NOT NULL
);
CREATE INDEX sessions_account ON sessions(account_id);

-- Which account is logged in on which computer (Settings.client_id). Online
-- guests are credited through this: the host's record only names their client.
CREATE TABLE devices (
  client TEXT PRIMARY KEY,
  account_id INTEGER NOT NULL,
  linked_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Failed logins, to slow down password guessing (per username and per IP).
CREATE TABLE login_attempts (
  key TEXT NOT NULL,
  at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX login_attempts_key ON login_attempts(key, at);

ALTER TABLE players ADD COLUMN account_id INTEGER;
CREATE UNIQUE INDEX players_account ON players(account_id);
