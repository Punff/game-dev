extends Node

const MAX_PLAYERS = 4

var active_players: Dictionary = {}

func _ready() -> void:
	pass

func join_player(device_id: int) -> int:
	for p_id in active_players:
		if active_players[p_id].device_id == device_id:
			return p_id

	if active_players.size() >= MAX_PLAYERS:
		return -1

	var new_id = _get_next_available_id()
	var player_data = PlayerData.new()
	player_data.player_id = new_id
	player_data.device_id = device_id
	player_data.color = _get_default_color(new_id)
	player_data.name = "Player %d" % new_id

	active_players[new_id] = player_data

	_map_input_actions(new_id, device_id)

	SignalBus.player_joined.emit(new_id, device_id)
	return new_id

func _map_input_actions(player_id: int, device_id: int) -> void:
	var prefix = "p%d_" % player_id
	var actions = ["jump", "left", "right", "up", "down", "charge", "gravity", "shockwave"]

	for action_suffix in actions:
		var action_name = prefix + action_suffix

		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

		var is_first_device = true
		for p_id in active_players:
			if p_id == player_id and active_players[p_id].device_id != device_id:
				is_first_device = false

		if is_first_device:
			InputMap.action_erase_events(action_name)

		if device_id == -1:
			_add_default_keyboard_events(action_name, player_id)
		else:
			_add_gamepad_events(action_name, device_id, action_suffix)

func _add_default_keyboard_events(action_name: String, player_id: int) -> void:
	var event = InputEventKey.new()
	match action_name:
		"p1_jump":   event.physical_keycode = KEY_UP
		"p1_up":     event.physical_keycode = KEY_W
		"p1_left":   event.physical_keycode = KEY_LEFT
		"p1_right":  event.physical_keycode = KEY_RIGHT
		"p1_down":    event.physical_keycode = KEY_DOWN
		"p1_charge":  event.physical_keycode = KEY_SHIFT
		"p1_gravity": event.physical_keycode = KEY_CTRL
		"p1_shockwave": event.physical_keycode = KEY_Z

		"p2_jump":   event.physical_keycode = KEY_W
		"p2_up":     event.physical_keycode = KEY_UP
		"p2_left":   event.physical_keycode = KEY_A
		"p2_right":  event.physical_keycode = KEY_D
		"p2_down":    event.physical_keycode = KEY_S
		"p2_charge":  event.physical_keycode = KEY_Q
		"p2_gravity": event.physical_keycode = KEY_E
		"p2_shockwave": event.physical_keycode = KEY_F

		"p3_jump":   event.physical_keycode = KEY_KP_8
		"p3_up":     event.physical_keycode = KEY_KP_9
		"p3_left":   event.physical_keycode = KEY_KP_4
		"p3_right":  event.physical_keycode = KEY_KP_6
		"p3_down":    event.physical_keycode = KEY_KP_5
		"p3_charge":  event.physical_keycode = KEY_KP_1
		"p3_gravity": event.physical_keycode = KEY_KP_3
		"p3_shockwave": event.physical_keycode = KEY_KP_2

		"p4_jump":   event.physical_keycode = KEY_I
		"p4_up":     event.physical_keycode = KEY_U
		"p4_left":   event.physical_keycode = KEY_J
		"p4_right":  event.physical_keycode = KEY_L
		"p4_down":    event.physical_keycode = KEY_K
		"p4_charge":  event.physical_keycode = KEY_H
		"p4_gravity": event.physical_keycode = KEY_O
		"p4_shockwave": event.physical_keycode = KEY_Y

		_: return

	InputMap.action_add_event(action_name, event)

func _add_gamepad_events(action_name: String, device_id: int, action_suffix: String) -> void:
	var events = InputMap.action_get_events(action_name)

	match action_suffix:
		"jump":
			_add_joy_button_if_missing(action_name, device_id, JOY_BUTTON_A)
		"left":
			_add_joy_axis_if_missing(action_name, device_id, JOY_AXIS_LEFT_X, -1.0)
		"right":
			_add_joy_axis_if_missing(action_name, device_id, JOY_AXIS_LEFT_X, 1.0)
		"down":
			_add_joy_button_if_missing(action_name, device_id, JOY_BUTTON_X)
		"up":
			_add_joy_axis_if_missing(action_name, device_id, JOY_AXIS_LEFT_Y, -1.0)
		"charge":
			_add_joy_button_if_missing(action_name, device_id, JOY_BUTTON_RIGHT_SHOULDER)
			_add_joy_axis_if_missing(action_name, device_id, JOY_AXIS_TRIGGER_RIGHT, 1.0)
		"gravity":
			_add_joy_button_if_missing(action_name, device_id, JOY_BUTTON_LEFT_SHOULDER)
			_add_joy_axis_if_missing(action_name, device_id, JOY_AXIS_TRIGGER_LEFT, 1.0)
		"shockwave":
			_add_joy_button_if_missing(action_name, device_id, JOY_BUTTON_B)

func _add_joy_button_if_missing(action: String, device: int, button: int) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.device == device and ev.button_index == button:
			return
	var ev = InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = button
	InputMap.action_add_event(action, ev)

func _add_joy_axis_if_missing(action: String, device: int, axis: int, value: float) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and ev.device == device and ev.axis == axis and sign(ev.axis_value) == sign(value):
			return
	var ev = InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)

func leave_player(player_id: int) -> void:
	if active_players.has(player_id):
		active_players.erase(player_id)
		SignalBus.player_left.emit(player_id)

func _get_next_available_id() -> int:
	for i in range(1, MAX_PLAYERS + 1):
		if not active_players.has(i):
			return i
	return -1

func _get_default_color(id: int) -> Color:
	return get_available_colors()[id - 1]

func get_available_colors() -> Array[Color]:
	return [
		Color(0.9, 0.2, 0.2), # Red
		Color(0.2, 0.9, 0.2), # Green
		Color(0.2, 0.2, 0.9), # Blue
		Color(0.9, 0.9, 0.2), # Yellow
		Color(0.2, 0.9, 0.9), # Cyan
		Color(0.9, 0.2, 0.9), # Magenta
		Color(1.0, 0.5, 0.0), # Orange
		Color(0.5, 0.0, 0.5)  # Purple
	]

func cycle_player_color(player_id: int) -> void:
	if not active_players.has(player_id):
		return
	
	var colors = get_available_colors()
	var current_color = active_players[player_id].color
	
	# Get all currently taken colors
	var taken_colors = []
	for p_id in active_players:
		if p_id != player_id:
			taken_colors.append(active_players[p_id].color)
	
	var idx = 0
	for i in range(colors.size()):
		if colors[i].is_equal_approx(current_color):
			idx = i
			break
	
	# Try next colors until we find one not taken
	for i in range(colors.size()):
		idx = (idx + 1) % colors.size()
		var candidate = colors[idx]
		
		var is_taken = false
		for taken in taken_colors:
			if taken.is_equal_approx(candidate):
				is_taken = true
				break
		
		if not is_taken:
			active_players[player_id].color = candidate
			return

func get_player_data(player_id: int) -> Dictionary:
	return active_players.get(player_id, {})

func is_device_joined(device_id: int) -> bool:
	for p_id in active_players:
		if active_players[p_id].device_id == device_id:
			return true
	return false
