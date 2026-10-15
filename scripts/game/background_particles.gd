extends Node2D

# ─────────────────────────────────────────────
#  BACKGROUND PARTICLES - SPIDER-VERSE STYLE
# ─────────────────────────────────────────────

@export_group("Debris Shards")
@export var shard_count:  int   = 30 # Reduced from 120
@export var shard_color:  Color = Color(0.6, 0.8, 1.0, 0.2)

@export_group("Stars")
@export var star_count:   int   = 25 # Reduced from 80
@export var star_color:   Color = Color(0.85, 0.9, 1.0, 0.6)

@export_group("Embers")
@export var ember_count:  int   = 15 # Reduced from 55
@export var ember_color:  Color = Color(1.0, 0.35, 0.05, 0.7)
@export var ember_color_hot: Color = Color(1.0, 0.75, 0.1, 0.9)

var _shards: Array = []
var _stars:  Array = []
var _embers: Array = []

var _hw: float = 600.0   
var _hh: float = 400.0   
var _prev_player_x: float = 0.0

func _ready() -> void:
	var vp := get_viewport_rect()
	position = vp.size / 2
	_hw = vp.size.x * 0.6
	_hh = vp.size.y * 0.6

	for i in shard_count: _shards.append(_make_shard(true))
	for i in star_count:  _stars.append(_make_star(true))
	for i in ember_count: _embers.append(_make_ember(true))

# ─────────────────────────────────────────────
#  FACTORIES
# ─────────────────────────────────────────────

func _make_shard(random_pos: bool = false) -> Dictionary:
	return {
		"pos":    Vector2(
			randf_range(-_hw, _hw),
			randf_range(-_hh, _hh) if random_pos else _hh),
		"speed":          randf_range(80.0, 240.0),
		"length":         randf_range(10.0, 35.0),
		"width":          randf_range(1.5, 3.5),
		"drift":          randf_range(-20.0, 20.0),
		"timer":          randf() * PI,
		"tint":           randf_range(0.8, 1.1),
		"angle":          randf_range(-0.15, 0.15),
	}

func _make_star(random_pos: bool = false) -> Dictionary:
	return {
		"pos":    Vector2(
			randf_range(-_hw, _hw),
			randf_range(-_hh, _hh) if random_pos else _hh),
		"size":            randf_range(1.2, 3.0),
		"twinkle_timer":  randf() * TAU,
		"twinkle_speed":  randf_range(0.8, 2.0),
		"parallax_depth": randf_range(0.015, 0.05),
		"drift_y":        randf_range(4.0, 12.0),
		"type":           randi() % 3,
	}

func _make_ember(random_pos: bool = false) -> Dictionary:
	return {
		"pos":    Vector2(
			randf_range(-_hw, _hw),
			randf_range(0.0, _hh) if random_pos else _hh),
		"rise_speed":   randf_range(25.0, 85.0),
		"drift_speed":  randf_range(-30.0, 30.0),
		"life":         randf() if random_pos else 0.0,
		"life_speed":   randf_range(0.06, 0.18),
		"size":         randf_range(1.5, 4.0),
		"hot":          randf() > 0.6,
		"wobble":       randf() * TAU,
		"wobble_speed": randf_range(2.0, 5.0),
	}

# ─────────────────────────────────────────────
#  UPDATE
# ─────────────────────────────────────────────

func _process(delta: float) -> void:
	var players = get_tree().get_nodes_in_group("player")
	var player_vel_y: float = 0.0
	var dx: float = 0.0
	
	if players.size() > 0:
		var p = players[0]
		player_vel_y = p.velocity.y
		dx = p.global_position.x - _prev_player_x
		_prev_player_x = p.global_position.x

	var vertical_pull: float = abs(player_vel_y) * 0.08
	_update_shards(delta, vertical_pull)
	_update_stars(delta, dx)
	_update_embers(delta)
	queue_redraw()

func _update_shards(delta: float, vertical_pull: float) -> void:
	for i in _shards.size():
		var p: Dictionary = _shards[i]
		p.timer += delta * 2.0
		p.pos.y -= (p.speed + vertical_pull) * delta
		p.pos.x += p.drift * delta * sin(p.timer)
		if p.pos.y < -_hh: _shards[i] = _make_shard(false)

func _update_stars(delta: float, player_dx: float) -> void:
	for i in _stars.size():
		var s: Dictionary = _stars[i]
		s.twinkle_timer += delta * s.twinkle_speed
		s.pos.x -= player_dx * s.parallax_depth
		s.pos.y += s.drift_y * delta
		if s.pos.x < -_hw: s.pos.x = _hw
		elif s.pos.x > _hw: s.pos.x = -_hw
		if s.pos.y > _hh: _stars[i] = _make_star(false)

func _update_embers(delta: float) -> void:
	for i in _embers.size():
		var e: Dictionary = _embers[i]
		e.wobble += delta * e.wobble_speed
		e.pos.y  -= e.rise_speed * delta
		e.pos.x  += e.drift_speed * delta * sin(e.wobble)
		e.life   += e.life_speed * delta
		if e.life >= 1.0 or e.pos.y < -_hh: _embers[i] = _make_ember(false)

# ─────────────────────────────────────────────
#  DRAW
# ─────────────────────────────────────────────

func _draw() -> void:
	_draw_stars()
	_draw_embers()
	_draw_shards()

func _draw_stars() -> void:
	for s in _stars:
		var twinkle: float = sin(s.twinkle_timer) * 0.4 + 0.6
		var alpha: float   = twinkle * 0.65
		var c := Color(0.9, 0.95, 1.0, alpha)
		var r: float = s.size * twinkle
		
		if s.type == 0: # Sharp cross
			draw_line(s.pos - Vector2(r * 2.0, 0), s.pos + Vector2(r * 2.0, 0), c, 1.2)
			draw_line(s.pos - Vector2(0, r * 2.0), s.pos + Vector2(0, r * 2.0), c, 1.2)
		elif s.type == 1: # Small diamond
			var pts = [s.pos + Vector2(0, -r*1.5), s.pos + Vector2(r, 0), s.pos + Vector2(0, r*1.5), s.pos + Vector2(-r, 0)]
			draw_colored_polygon(PackedVector2Array(pts), c)
		else: # Glowy dot
			draw_circle(s.pos, r * 0.5, c)
			draw_circle(s.pos, r * 1.5, Color(c.r, c.g, c.b, alpha * 0.2))

func _draw_embers() -> void:
	for e in _embers:
		var fade: float = 1.0 - pow(e.life, 1.5)
		var base: Color = ember_color_hot if e.hot else ember_color
		var c := Color(base.r, base.g, base.b, base.a * fade)
		
		if e.hot:
			var sz = e.size * fade
			if sz < 2.0:
				draw_circle(e.pos, 1.5, Color(1.0, 1.0, 0.6, fade))
			else:
				var pts = [e.pos + Vector2(-sz, 0), e.pos + Vector2(0, -sz*1.5), e.pos + Vector2(sz, 0), e.pos + Vector2(0, sz*1.5)]
				draw_colored_polygon(PackedVector2Array(pts), Color(1.0, 1.0, 0.6, fade))
		else:
			draw_circle(e.pos, e.size * 0.8 * fade, c)
			if fade > 0.6:
				draw_line(e.pos, e.pos + Vector2(e.drift_speed * 0.1, e.rise_speed * 0.1), Color(c.r, c.g, c.b, fade * 0.3), 1.2)

func _draw_shards() -> void:
	for p in _shards:
		var c := Color(shard_color.r * p.tint, shard_color.g * p.tint, shard_color.b, shard_color.a)
		var stretch := Vector2(p.angle * p.length, p.length + abs(p.drift) * 0.2)
		draw_line(p.pos, p.pos + stretch, c, p.width)
