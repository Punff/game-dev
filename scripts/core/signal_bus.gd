extends Node

# ─────────────────────────────────────────────
#  SIGNAL BUS
#  Central hub for global decoupled communication.
# ─────────────────────────────────────────────

# ── Player Signals ───────────────────────────
signal player_joined(player_id: int, device_id: int)
signal player_left(player_id: int)
signal player_ready_state_changed(player_id: int, is_ready: bool)
signal player_died(player_id: int)

# ── Match Signals ────────────────────────────
signal match_start_requested(mode_id: String)
signal match_started()
signal match_ended(results: Dictionary)

# ── Game Event Signals ───────────────────────
signal block_broken(pos: Vector2)
signal chain_reaction_occurred(count: int)

# ── UI/System Signals ────────────────────────
signal game_paused(is_paused: bool)
signal menu_back_requested()
signal toggle_fps_requested()
