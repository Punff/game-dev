extends BaseMenu

const MAX_PLAYERS := 4

@onready var player_row: HBoxContainer = $CenterContainer/VBoxContainer/PlayerRow
@onready var start_button: Button = $CenterContainer/VBoxContainer/ButtonRow/StartButton

var _slot_panels: Array = []

func _ready() -> void:
	PlayerManager.active_players.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SignalBus.player_joined.connect(_on_player_changed)
	SignalBus.player_left.connect(_on_player_changed)
	start_button.disabled = true
	_build_slots()
	_update_player_display()

func _build_slots() -> void:
	for i in MAX_PLAYERS:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(200, 280)
		panel.size_flags_horizontal = Control.SIZE_EXPAND
		panel.size_flags_vertical = Control.SIZE_EXPAND

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.size_flags_horizontal = Control.SIZE_EXPAND
		vbox.size_flags_vertical = Control.SIZE_EXPAND
		vbox.add_theme_constant_override("separation", 8)

		var circle := Control.new()
		circle.custom_minimum_size = Vector2(72, 72)
		circle.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		circle.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var player_label := Label.new()
		player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		player_label.add_theme_font_size_override("font_size", 30)
		player_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 0.6))

		var status_label := Label.new()
		status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		status_label.text = "Press A/Enter to join"
		status_label.add_theme_font_size_override("font_size", 20)
		status_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 0.5))

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.1, 0.1, 0.85)
		style.border_color = Color(0.15, 0.2, 0.2, 0.6)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_bottom_left = 8
		panel.add_theme_stylebox_override("panel", style)

		var c0 := CenterContainer.new()
		c0.size_flags_horizontal = Control.SIZE_EXPAND; c0.add_child(circle)
		var c1 := CenterContainer.new()
		c1.size_flags_horizontal = Control.SIZE_EXPAND; c1.add_child(player_label)
		var c2 := CenterContainer.new()
		c2.size_flags_horizontal = Control.SIZE_EXPAND; c2.add_child(status_label)
		vbox.add_child(c0)
		vbox.add_child(c1)
		vbox.add_child(c2)
		panel.add_child(vbox)
		player_row.add_child(panel)

		circle.set_meta("state", "empty")
		circle.set_meta("color", Color.GRAY)
		circle.draw.connect(_on_circle_draw.bind(circle))
		circle.queue_redraw()

		_slot_panels.append({
			panel = panel,
			circle = circle,
			player_label = player_label,
			status_label = status_label,
			style = style,
		})

func _on_circle_draw(control: Control) -> void:
	var color = control.get_meta("color", Color.GRAY)
	var state = control.get_meta("state", "empty")
	_draw_circle(control, color, state)

func _update_player_display() -> void:
	var all_ready := true
	var idx := 0
	for p_id in PlayerManager.active_players:
		var p = PlayerManager.active_players[p_id]
		var slot = _slot_panels[idx]

		slot.player_label.text = "PLAYER %d" % p_id
		slot.player_label.add_theme_color_override("font_color", p.color)
		slot.style.bg_color = Color(0.08, 0.12, 0.12, 0.9) if not p.is_ready else Color(0.05, 0.18, 0.1, 0.95)
		slot.style.border_color = p.color.darkened(0.3) if not p.is_ready else p.color

		if p.is_ready:
			slot.status_label.text = "Ready!"
			slot.status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6, 0.9))
		else:
			slot.status_label.text = "Ready? Press A/Enter"
			slot.status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5, 1))
			all_ready = false

		slot.circle.set_meta("state", "joined")
		slot.circle.set_meta("color", p.color)
		slot.circle.queue_redraw()
		slot.panel.add_theme_stylebox_override("panel", slot.style)
		idx += 1

	for i in range(idx, MAX_PLAYERS):
		var slot = _slot_panels[i]
		slot.player_label.text = ""
		slot.player_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 0.6))
		slot.status_label.text = "Press A/Enter to join"
		slot.status_label.add_theme_color_override("font_color", Color(0.4, 0.5, 0.5, 0.5))
		slot.style.bg_color = Color(0.05, 0.1, 0.1, 0.85)
		slot.style.border_color = Color(0.15, 0.2, 0.2, 0.6)
		slot.circle.set_meta("state", "empty")
		slot.circle.set_meta("color", Color.GRAY)
		slot.circle.queue_redraw()
		slot.panel.add_theme_stylebox_override("panel", slot.style)

	start_button.disabled = not all_ready or idx == 0

func _draw_circle(control: Control, color: Color, state: String) -> void:
	var size = control.custom_minimum_size
	var center = size * 0.5
	var radius = min(center.x, center.y) - 4
	if state == "empty":
		control.draw_circle(center, radius, Color(0.2, 0.25, 0.25, 0.6))
		control.draw_circle(center, radius * 0.7, Color(0.1, 0.15, 0.15, 0.8))
	else:
		control.draw_circle(center, radius, Color.WHITE)
		control.draw_circle(center, radius - 2, color)
		control.draw_arc(center, radius - 2, 0, TAU, 32, Color(1, 1, 1, 0.2), 1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return

	var device_id := -1
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		device_id = event.device

	var existing_pid := -1
	for p_id in PlayerManager.active_players:
		if PlayerManager.active_players[p_id].device_id == device_id:
			existing_pid = p_id
			break

	if event.is_action_pressed("ui_accept"):
		if existing_pid == -1:
			PlayerManager.join_player(device_id)
		else:
			var p = PlayerManager.active_players[existing_pid]
			if p.is_ready and not start_button.disabled:
				_on_start_pressed()
				return
			p.is_ready = not p.is_ready
			SignalBus.player_ready_state_changed.emit(existing_pid, p.is_ready)
			_update_player_display()
		return

	if existing_pid != -1 and event is InputEventJoypadButton and event.button_index == JOY_BUTTON_Y and event.pressed:
		PlayerManager.cycle_player_color(existing_pid)
		_update_player_display()

func _on_player_changed(p_id: int = -1, d_id: int = -1) -> void:
	_update_player_display()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	SignalBus.match_start_requested.emit.call_deferred("survival")

func _on_back_pressed() -> void:
	PlayerManager.active_players.clear()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
