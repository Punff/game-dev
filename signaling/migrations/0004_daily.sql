-- The daily climb (src/daily.js): everyone plays the same map each UTC day.
-- One row per account per day: its best run, with the ghost (positions
-- through the run) so friends can race it.
CREATE TABLE daily_runs (
  day TEXT NOT NULL,              -- 'YYYY-MM-DD' (UTC)
  account_id INTEGER NOT NULL,
  height INTEGER NOT NULL,        -- m
  duration REAL NOT NULL,         -- s
  version TEXT,                   -- game version: a ghost only fits the map it was made on
  ghost TEXT,                     -- JSON {"step": s, "pts": [x, y, ...]} (px)
  tries INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (day, account_id)
);
CREATE INDEX daily_runs_day ON daily_runs(day, height DESC);
