extends Node

## Tracks joined players and owns the per-player InputMap actions
## (p1_jump, p2_left, ...), rebuilt from Settings whenever bindings change.

const MAX_PLAYERS := 4

var players: Dictionary = {}   # player_id -> PlayerInfo


func _ready() -> void:
	SignalBus.bindings_changed.connect(rebuild_all_actions)
	SignalBus.settings_changed.connect(_apply_deadzones)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func join(device_id: int) -> int:
	var existing := find_by_device(device_id)
	if existing:
		return existing.player_id
	if players.size() >= MAX_PLAYERS:
		return -1
	var info := PlayerInfo.new()
	info.player_id = _next_free_id()
	info.device_id = device_id
	info.color_index = _first_free_color(info.player_id - 1)
	players[info.player_id] = info
	_build_actions(info)
	SignalBus.player_joined.emit(info.player_id, device_id)
	return info.player_id


func leave(player_id: int) -> void:
	if not players.has(player_id):
		return
	players.erase(player_id)
	_clear_actions(player_id)
	SignalBus.player_left.emit(player_id)


func clear() -> void:
	for id in players.keys():
		leave(id)


## Online clients: take the roster the server sent. Only our own player
## needs input actions; the rest are driven by the server.
func replace_all(infos: Array[PlayerInfo]) -> void:
	for id in players.keys():
		_clear_actions(id)
	players.clear()
	for info in infos:
		players[info.player_id] = info
		if info.is_local():
			_build_actions(info)


func find_by_device(device_id: int) -> PlayerInfo:
	for info in players.values():
		if info.device_id == device_id:
			return info
	return null


func sorted_players() -> Array:
	var ids := players.keys()
	ids.sort()
	return ids.map(func(id): return players[id])


func cycle_color(player_id: int, step := 1) -> void:
	var info: PlayerInfo = players.get(player_id)
	if info == null:
		return
	var n := Palette.PLAYER_COLORS.size()
	var idx := info.color_index
	for i in n:
		idx = posmod(idx + step, n)
		if not _color_taken(idx, player_id):
			info.color_index = idx
			return


func reset_match_stats() -> void:
	for info in players.values():
		info.max_height = 0
		info.death_order = 0


# ── Input actions ────────────────────────────

func action(player_id: int, action_name: String) -> StringName:
	return StringName("p%d_%s" % [player_id, action_name])


func rebuild_all_actions() -> void:
	for info in players.values():
		_build_actions(info)


func _build_actions(info: PlayerInfo) -> void:
	var profile := Settings.profile_for_device(info.device_id)
	for a in Settings.ACTIONS:
		var name := action(info.player_id, a)
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		for ev in Settings.events_for(profile, a, info.device_id):
			InputMap.action_add_event(name, ev)
	_apply_deadzones()


func _clear_actions(player_id: int) -> void:
	for a in Settings.ACTIONS:
		var name := action(player_id, a)
		if InputMap.has_action(name):
			InputMap.erase_action(name)


func _apply_deadzones() -> void:
	var dz: float = Settings.get_value("deadzone")
	for info in players.values():
		for a in Settings.ACTIONS:
			var name := action(info.player_id, a)
			if InputMap.has_action(name):
				# Triggers want a lower threshold than sticks to feel responsive.
				InputMap.action_set_deadzone(name, dz if a in ["left", "right", "up", "down"] else 0.25)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected:
		var info := find_by_device(device)
		if info and get_tree().current_scene and get_tree().current_scene.name == "Lobby":
			leave(info.player_id)


func _next_free_id() -> int:
	for i in range(1, MAX_PLAYERS + 1):
		if not players.has(i):
			return i
	return -1


func _first_free_color(preferred: int) -> int:
	var n := Palette.PLAYER_COLORS.size()
	for i in n:
		var idx := (preferred + i) % n
		if not _color_taken(idx, -1):
			return idx
	return preferred


func _color_taken(idx: int, except_id: int) -> bool:
	for info in players.values():
		if info.player_id != except_id and info.color_index == idx:
			return true
	return false


# ── Rumble ───────────────────────────────────

func rumble(player_id: int, weak: float, strong: float, duration: float) -> void:
	if not Settings.get_value("rumble"):
		return
	var info: PlayerInfo = players.get(player_id)
	if info and not info.is_keyboard():
		Input.start_joy_vibration(info.device_id, weak, strong, duration)
