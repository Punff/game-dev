extends Node

## Central hub for decoupled, game-wide events.

# Players
signal player_joined(player_id: int, device_id: int)
signal player_left(player_id: int)
signal player_died(player_id: int)

# Match
signal match_started()
signal match_ended(results: Dictionary)

# Gameplay events
signal block_broken(pos: Vector2)
signal chain_reaction_occurred(count: int, pos: Vector2)
signal screen_shake_requested(strength: float)

# UI / system
signal game_paused(is_paused: bool)
signal settings_changed()
signal bindings_changed()
