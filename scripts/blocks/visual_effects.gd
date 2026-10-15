# ─────────────────────────────────────────────
#  VisualEffects.gd
#  Comic book / cel-shaded effects. White lines.
# ─────────────────────────────────────────────


# ─────────────────────────────────────────────
#  JUMP WAVE — radiating speed lines on jump
# ─────────────────────────────────────────────
class JumpWaveEffect extends Node2D:
	var max_radius: float = 120.0
	var base_color: Color = Color.WHITE
	const LINE_COUNT: int = 16
	var _t:     float = 0.0
	var _seeds: Array = []

	func _ready() -> void:
		for i in LINE_COUNT:
			_seeds.append({
				"angle":  (TAU / LINE_COUNT) * i + randf_range(-0.12, 0.12),
				"length": randf_range(0.55, 1.0),
				"width":  randf_range(1.5, 3.0),
			})

	func _process(delta: float) -> void:
		_t += delta * 3.2
		queue_redraw()
		if _t >= 1.0:
			queue_free()

	func _draw() -> void:
		var ease_t: float = 1.0 - pow(1.0 - _t, 2.0)
		var alpha:  float = 1.0 - _t
		for s in _seeds:
			var inner: float   = max_radius * ease_t * 0.3
			var outer: float   = max_radius * ease_t * s["length"]
			var dir:   Vector2 = Vector2(cos(s["angle"]), sin(s["angle"]))
			draw_line(dir * inner, dir * outer, Color(1.0, 1.0, 1.0, alpha), s["width"])


# ─────────────────────────────────────────────
#  GRAVITY FIELD — hand-drawn uneven ring
#  Segments of varying length + gap, slow rotate.
# ─────────────────────────────────────────────
class GravityFieldEffect extends Node2D:
	var radius: float = 200.0
	var _t:     float = 0.0
	var _segs:  Array = []   # pre-built segment definitions

	func _ready() -> void:
		# Build irregular arc segments that together roughly cover the circle.
		# Each segment has a start angle offset and arc length — hand-drawn feel.
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var angle: float = 0.0
		while angle < TAU:
			var arc_len: float = rng.randf_range(0.18, 0.55)   # radians
			var gap:     float = rng.randf_range(0.04, 0.18)
			_segs.append({
				"start":  angle,
				"len":    arc_len,
				"width":  rng.randf_range(1.2, 3.0),
				"wobble": rng.randf_range(0.0, TAU),   # per-segment phase
			})
			angle += arc_len + gap

	func _process(delta: float) -> void:
		_t += delta * 1.8   # slow rotation
		queue_redraw()

	func _draw() -> void:
		var pulse: float = sin(_t * 2.2) * 0.5 + 0.5
		var r:     float = radius + sin(_t * 1.3) * 6.0
		var base_alpha: float = 0.18 + pulse * 0.10

		for seg in _segs:
			var seg_r:  float = r + sin(_t * 3.0 + seg["wobble"]) * 4.0
			var alpha:  float = base_alpha + sin(_t + seg["wobble"]) * 0.05
			var start:  float = seg["start"] + _t * 0.4
			draw_arc(Vector2.ZERO, seg_r, start, start + seg["len"],
				int(max(4.0, seg["len"] * 12.0)),
				Color(1.0, 1.0, 1.0, alpha), seg["width"])


# ─────────────────────────────────────────────
#  CHARGE EFFECT — lines rush inward, ring builds
#  Cleaner than before: lines rush from a fixed
#  orbit radius to the center, respawn at edge.
# ─────────────────────────────────────────────
class ChargeEffect extends Node2D:
	const LINE_COUNT: int = 18
	var _ratio: float = 0.0
	var _t:     float = 0.0
	var _seeds: Array = []

	func _ready() -> void:
		for i in LINE_COUNT:
			_seeds.append({
				"angle":   (TAU / LINE_COUNT) * i + randf_range(-0.2, 0.2),
				"phase":   randf(),          # stagger start positions
				"length":  randf_range(10.0, 22.0),
				"width":   randf_range(1.2, 2.8),
				"orbit":   randf_range(45.0, 75.0),   # spawn radius
			})

	func update_charge(ratio: float) -> void:
		_ratio = ratio

	func _process(delta: float) -> void:
		if _ratio > 0.0:
			_t += delta * (3.0 + _ratio * 5.0)
			queue_redraw()

	func _draw() -> void:
		if _ratio <= 0.02:
			return

		for s in _seeds:
			var travel: float = fmod(s["phase"] + _t * 0.35, 1.0)
			var dist:   float = s["orbit"] * (1.0 - travel)
			if dist < 4.0:
				continue
			var dir:   Vector2 = Vector2(cos(s["angle"]), sin(s["angle"]))
			var tip:   Vector2 = dir * dist
			var tail:  Vector2 = dir * min(dist + s["length"], s["orbit"])
			# Alpha stays subtle — max 0.35, fades in with ratio
			var alpha: float   = _ratio * (0.2 + travel * 0.15)
			draw_line(tail, tip, Color(1.0, 1.0, 1.0, alpha), s["width"])


# ─────────────────────────────────────────────
#  MOVEMENT LINES — horizontal speed lines
#  Spawn on player, drift opposite to movement.
#  Add as child of player, call set_velocity(v).
# ─────────────────────────────────────────────
class MovementLines extends Node2D:
	const LINE_COUNT: int = 3   # was 6
	var _vel:   Vector2 = Vector2.ZERO
	var _lines: Array   = []
	var _t:     float   = 0.0

	func _ready() -> void:
		for i in LINE_COUNT:
			_lines.append(_make_line(true))

	func set_velocity(v: Vector2) -> void:
		_vel = v

	func _make_line(random_y: bool = false) -> Dictionary:
		return {
			"y":      randf_range(-14.0, 14.0) if random_y else randf_range(-14.0, 14.0),
			"length": randf_range(6.0, 14.0),
			"x":      randf_range(-8.0, 8.0),
			"phase":  randf(),
		}

	func _process(delta: float) -> void:
		var speed: float = _vel.length()
		if speed < 200.0:   # higher threshold — only fast movement
			queue_redraw()
			return
		_t += delta * (speed * 0.012)
		for i in _lines.size():
			var dir: Vector2 = -_vel.normalized()
			_lines[i]["x"] += dir.x * speed * delta * 0.4
			_lines[i]["y"] += dir.y * speed * delta * 0.15
			if abs(_lines[i]["x"]) > 35.0 or abs(_lines[i]["y"]) > 25.0:
				_lines[i] = _make_line(true)
		queue_redraw()

	func _draw() -> void:
		var speed: float = _vel.length()
		if speed < 200.0:
			return
		# Max alpha 0.2 — just a hint, not obstructive
		var alpha: float = clamp((speed - 200.0) / 400.0, 0.0, 0.20)
		var dir:   Vector2 = -_vel.normalized()
		for l in _lines:
			var pos:  Vector2 = Vector2(l["x"], l["y"])
			var tail: Vector2 = pos + dir * l["length"]
			draw_line(pos, tail, Color(1.0, 1.0, 1.0, alpha), 1.0)


# ─────────────────────────────────────────────
#  LANDING IMPACT — small burst on floor hit
#  Add to get_parent(), set global_position.
#  Short horizontal lines fan out sideways.
# ─────────────────────────────────────────────
class LandingImpact extends Node2D:
	const LINE_COUNT: int = 12
	var _t:     float = 0.0
	var _seeds: Array = []

	func _ready() -> void:
		for i in LINE_COUNT:
			var side:  float = 1.0 if i < LINE_COUNT / 2 else -1.0
			var idx:   int   = i % (LINE_COUNT / 2)
			var angle: float = (PI * 0.12) + (PI * 0.35 / (LINE_COUNT / 2)) * idx
			_seeds.append({
				"angle":  angle * side,
				"length": randf_range(14.0, 34.0),
				"width":  randf_range(1.8, 3.5),
			})

	func _process(delta: float) -> void:
		_t += delta * 5.0
		queue_redraw()
		if _t >= 1.0:
			queue_free()

	func _draw() -> void:
		var ease_t: float = 1.0 - pow(1.0 - _t, 2.0)
		var alpha:  float = 1.0 - _t
		for s in _seeds:
			var dir:   Vector2 = Vector2(cos(s["angle"]), sin(s["angle"]))
			var inner: float   = 6.0 + ease_t * 8.0
			var outer: float   = inner + s["length"] * ease_t
			draw_line(dir * inner, dir * outer,
				Color(1.0, 1.0, 0.85, alpha), s["width"])

		# Dust puff
		var r := 4.0 + ease_t * 14.0
		draw_circle(Vector2.DOWN * r * 0.4, r, Color(1.0, 1.0, 1.0, alpha * 0.12))


class ShockwaveEffect extends Node2D:
	var direction: Vector2 = Vector2.RIGHT
	var max_distance: float = 300.0
	var _t: float = 0.0

	func _process(delta: float) -> void:
		_t += delta * 2.8
		queue_redraw()
		if _t >= 1.0: queue_free()

	func _draw() -> void:
		var prog = min(_t, 1.0)
		var alpha = max(1.0 - _t, 0.0)
		var base = direction.angle()
		var half_spread = PI * 0.25
		var r = max_distance * prog

		var c = Color(1, 1, 1, alpha)

		# Bright leading edge
		draw_arc(Vector2.ZERO, r, base - half_spread, base + half_spread, 24, Color(1, 1, 1, alpha * 0.7), 3.0)

		# Trailing arcs (fading behind the front)
		for i in 4:
			var frac = 1.0 - float(i + 1) * 0.12
			var ar = r * frac
			var a = alpha * (0.4 - i * 0.08)
			if a <= 0: break
			draw_arc(Vector2.ZERO, ar, base - half_spread, base + half_spread, 20, Color(1, 1, 1, a), max(1.0, 2.5 - i * 0.5))

		# Radial spokes inside the quarter
		for i in 6:
			var frac = float(i) / 5.0
			var a = base - half_spread + half_spread * 2.0 * frac
			var dir = Vector2(cos(a), sin(a))
			var inner = r * 0.1
			var outer = r * (0.85 + frac * 0.1)
			var sw = max(0.5, 2.0 - i * 0.25)
			draw_line(dir * inner, dir * outer, Color(1, 1, 1, alpha * 0.25), sw)

		# Central burst
		if prog < 0.4:
			var fa = (1.0 - prog / 0.4)
			draw_circle(Vector2.ZERO, 12.0 + prog * 20.0, Color(1, 1, 1, fa * 0.35))
