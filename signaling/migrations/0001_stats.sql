-- Match records and per-player stats. Apply with
--   npx wrangler d1 migrations apply cakum-pakum-stats --remote   (or --local)

-- One row per finished match, uploaded by the host (or the solo player).
-- `record` is the full Telemetry JSON; the columns are copies of its
-- headline fields so common queries don't have to parse it.
CREATE TABLE matches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  received_at TEXT NOT NULL DEFAULT (datetime('now')),
  client TEXT NOT NULL,
  version TEXT,
  build TEXT,
  mode TEXT,
  players INTEGER,
  duration REAL,
  winner INTEGER,
  best_height INTEGER,
  tuning_hash TEXT,
  record TEXT NOT NULL
);
CREATE INDEX matches_received ON matches(received_at);
CREATE INDEX matches_client ON matches(client, received_at);

-- Running totals per player id (Settings.client_id). Only solo runs and
-- online matches count: couch players share a computer.
CREATE TABLE players (
  client TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  first_seen TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen TEXT NOT NULL DEFAULT (datetime('now')),
  solo_runs INTEGER NOT NULL DEFAULT 0,
  best_solo INTEGER NOT NULL DEFAULT 0,
  best_solo_at TEXT,
  online_matches INTEGER NOT NULL DEFAULT 0,
  online_wins INTEGER NOT NULL DEFAULT 0,
  kos INTEGER NOT NULL DEFAULT 0,
  deaths_lava INTEGER NOT NULL DEFAULT 0,
  deaths_side INTEGER NOT NULL DEFAULT 0,
  total_climb INTEGER NOT NULL DEFAULT 0,
  play_seconds REAL NOT NULL DEFAULT 0
);
CREATE INDEX players_best_solo ON players(best_solo DESC);
CREATE INDEX players_online_wins ON players(online_wins DESC);
