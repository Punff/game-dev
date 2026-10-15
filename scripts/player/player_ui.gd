extends Node2D

@export var player_id:    int   = 1
@export var side_offset:  float = 380.0
@export var follow_speed: float = 6.0
@export var ring_radius:  float = 18.0

var _player:      Node    = null
var _label:       Label   = null
var _initial_y:   float   = 0.0
var _ref_set:     bool    = false
var _max_height:  float   = 0.0
var _target:      Vector2 = Vector2.ZERO
var _cooldown:    float   = 1.0
var _pl_color:    Color   = Color.WHITE
var _time:        float   = 0.0

func _ready() -> void:
	var nodes: Array = get_tree().get_nodes_in_group("player%d" % player_id)
	if not nodes.is_empty():
		_player = nodes[0]
		_target = _player.global_position
		if _player.has_method("get_player_color"):
			_pl_color = _player.get_player_color()

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override("outline_size", 2)
	_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.4))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.position = Vector2(-30.0, -ring_radius - 64.0)
	add_child(_label)

func _process(delta: float) -> void:
	_time += delta

	if not is_instance_valid(_player):
		var nodes: Array = get_tree().get_nodes_in_group("player%d" % player_id)
		if not nodes.is_empty():
			_player = nodes[0]
			_target = _player.global_position
			_ref_set = false
		return

	if not _ref_set:
		_initial_y = _player.global_position.y
		_ref_set = true

	var height: float = (_initial_y - _player.global_position.y) / 100.0
	if height > _max_height:
		_max_height = height

	if _player.has_method("get_player_color"):
		_pl_color = _player.get_player_color()
	_label.add_theme_color_override("font_color", _pl_color)

	if _player.has_method("get_gravity_field_cooldown_progress"):
		_cooldown = _player.get_gravity_field_cooldown_progress()

	_label.text = "%dm" % int(_max_height)

	var sign: float = -1.0 if player_id == 1 else 1.0
	_target = _player.global_position + Vector2(sign * side_offset, -20.0)
	global_position = global_position.lerp(_target, follow_speed * delta)

	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(_player):
		return

	var c = _pl_color
	var pulse = 0.5 + 0.5 * sin(_time * 2.5)

	var glow = Color(c.r, c.g, c.b, 0.06 + 0.04 * pulse)
	draw_arc(Vector2.ZERO, ring_radius + 4.0, 0.0, TAU, 48, glow, 5.0)

	draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.12), 2.5)

	if _cooldown < 1.0:
		var arc_end = -PI * 0.5 + TAU * _cooldown
		var breathe = 0.45 + 0.2 * sin(_time * 3.0)
		draw_arc(Vector2.ZERO, ring_radius, -PI * 0.5, arc_end, 48,
			Color(c.r, c.g, c.b, breathe), 3.0)

		if _cooldown > 0.03:
			var lead = Vector2(cos(arc_end), sin(arc_end)) * ring_radius
			draw_circle(lead, 2.5, Color(c.r, c.g, c.b, 0.85))
	else:
		var ready_alpha = 0.65 + 0.35 * pulse
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48,
			Color(c.r, c.g, c.b, ready_alpha), 3.0)

		var angle = _time * 1.2
		var dot = Vector2(cos(angle), sin(angle)) * ring_radius
		draw_circle(dot, 3.5, Color(c.r, c.g, c.b, 0.95))
		draw_circle(dot, 6.0, Color(c.r, c.g, c.b, 0.2))

	var remaining = _player.jumps_remaining
	var max_j = _player.max_jumps
	var dot_y = -ring_radius - 12.0
	var spacing = 11.0
	var start_x = -(max_j - 1) * spacing * 0.5

	for i in range(max_j):
		var pos = Vector2(start_x + i * spacing, dot_y)
		if i < remaining:
			draw_circle(pos, 4.0, Color(c.r, c.g, c.b, 0.9))
			draw_circle(pos, 6.0, Color(c.r, c.g, c.b, 0.2))
		else:
			draw_circle(pos, 4.0, Color(c.r, c.g, c.b, 0.12))
			draw_arc(pos, 4.0, 0.0, TAU, 16, Color(c.r, c.g, c.b, 0.45), 1.5)

func reset() -> void:
	_max_height = 0.0
	_ref_set = false

func _on_level_restart() -> void:
	reset()
