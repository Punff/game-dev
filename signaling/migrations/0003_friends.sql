-- Friends, presence and room invites (src/friends.js). Accounts only.

-- One row per pair, smaller account id first. `requested_by` is who asked;
-- the other one accepts.
CREATE TABLE friends (
  a INTEGER NOT NULL,
  b INTEGER NOT NULL,
  status TEXT NOT NULL,           -- 'pending' | 'accepted'
  requested_by INTEGER NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (a, b)
);
CREATE INDEX friends_b ON friends(b);

-- Where a logged-in game is, refreshed by a heartbeat about once a minute.
-- Online = seen in the last ~2 minutes. `room` is only shown to friends.
CREATE TABLE presence (
  account_id INTEGER PRIMARY KEY,
  status TEXT NOT NULL,           -- 'menu' | 'room' | 'match'
  room TEXT,
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- "Come and play": a friend's room code, shown to them for a few minutes.
CREATE TABLE invites (
  from_id INTEGER NOT NULL,
  to_id INTEGER NOT NULL,
  room TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (from_id, to_id)
);
CREATE INDEX invites_to ON invites(to_id);
