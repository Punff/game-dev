class_name MapPlanner
extends RefCounted

## Pure, deterministic level layout. Produces rows of platform descriptions
## (no nodes), so it can be unit-tested headless and seeded for replays.
##
## Every row is guaranteed to contain at least one "anchor" platform (static,
## non-moving, non-vanishing) that is reachable from an anchor in the row
## below, using a jump envelope simulated from the Player's real constants.

const HALF_WIDTH := 640.0          ## playable column is [-HALF_WIDTH, HALF_WIDTH]
const EDGE_MARGIN := 24.0
const MIN_WIDTH := 110.0
const MAX_SPECIAL_WIDTH := 200.0   ## bouncy / speed / reverse stay small
const ROW_SPACING_MIN := 30.0      ## min horizontal space between platforms of one row
const V_MARGIN := 16.0             ## px of jump height we never rely on

const BIOMES := [
	# name, starts at (px above start), gap range, block weights
	{"name": "Rubble", "from": 0.0, "gap": Vector2(165, 210), "charge_rows": 0.0,
		"weights": {"static": 40, "breakable": 20, "bouncy": 10, "moving": 10, "conveyor": 10, "vanishing": 10}},
	{"name": "Inferno", "from": 6000.0, "gap": Vector2(175, 222), "charge_rows": 0.05,
		"weights": {"static": 28, "bouncy": 12, "breakable": 15, "speed": 18, "reverse": 12, "push": 10, "moving": 5}},
	{"name": "Void", "from": 14000.0, "gap": Vector2(185, 228), "charge_rows": 0.1,
		"weights": {"static": 18, "ice": 22, "reverse": 15, "conveyor": 14, "speed": 10, "vanishing": 14, "moving": 7}},
	{"name": "Storm", "from": 24000.0, "gap": Vector2(190, 228), "charge_rows": 0.15,
		"weights": {"static": 14, "moving": 18, "reverse": 10, "ice": 14, "speed": 16, "bouncy": 8, "vanishing": 12, "push": 8}},
]

enum T { ZIGZAG, STAIR, WIDE, CHOKE, BRIDGE, DOOR, SAFE, SCATTER }
const FLOW := [T.ZIGZAG, T.STAIR, T.WIDE, T.SCATTER]
const PVP := [T.CHOKE, T.BRIDGE, T.DOOR]

var rng := RandomNumberGenerator.new()
var rows: Array = []              ## generated rows, oldest first
var cursor_y := 0.0               ## y of the last generated row (negative = up)
var _pvp_streak := 0
var _prev_anchors: Array = []

static var _env_double: PackedVector2Array
static var _env_charged: PackedVector2Array


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	_ensure_envelopes()


## Creates the wide starting floor at y and resets state.
func start(floor_y: float, floor_width := 1000.0) -> Dictionary:
	rows.clear()
	cursor_y = floor_y
	_pvp_streak = 0
	var floor := _plat(-floor_width * 0.5, floor_width * 0.5, "static")
	var row := {"y": floor_y, "platforms": [floor], "biome": "Rubble", "template": T.SAFE}
	_prev_anchors = [floor]
	rows.append(row)
	return row


## Generates rows until cursor_y <= target_y. Returns the new rows.
func generate_until(target_y: float) -> Array:
	var out: Array = []
	while cursor_y > target_y:
		out.append(_next_row())
	return out


func biome_at(height_px: float) -> Dictionary:
	var b: Dictionary = BIOMES[0]
	for candidate in BIOMES:
		if height_px >= candidate.from:
			b = candidate
	return b


# ── Row generation ───────────────────────────

func _next_row() -> Dictionary:
	var start_y: float = rows[0].y
	var biome := biome_at(start_y - cursor_y)
	var gap := minf(rng.randf_range(biome.gap.x, biome.gap.y), max_rise(false) - V_MARGIN - 18.0)
	var charged_row: bool = rng.randf() < biome.charge_rows
	if charged_row:
		gap = rng.randf_range(260.0, 300.0)
	var y := cursor_y - gap
	var height := start_y - y
	var tmpl := _pick_template(height)
	var plats := _build_template(tmpl, y)
	_resolve_overlaps(plats)
	_assign_types(plats, biome, tmpl)
	_ensure_reachable(plats, gap, charged_row)
	_fit_moving(plats)

	var anchors := plats.filter(func(p): return p.anchor_ok and p.reachable)
	if not anchors.is_empty():
		_prev_anchors = anchors
	var row := {"y": y, "platforms": plats, "biome": biome.name, "template": tmpl, "gap": gap, "charged": charged_row}
	rows.append(row)
	cursor_y = y
	return row


func _pick_template(height: float) -> int:
	if height < 1500.0:
		return FLOW[rng.randi() % FLOW.size()]
	if _pvp_streak >= 2:
		_pvp_streak = 0
		return T.SAFE if rng.randf() < 0.35 else FLOW[rng.randi() % FLOW.size()]
	if rng.randf() < 0.06:
		return T.SAFE
	if rng.randf() < 0.3 + clampf(height / 30000.0, 0.0, 0.25):
		_pvp_streak += 1
		return PVP[rng.randi() % PVP.size()]
	_pvp_streak = 0
	return FLOW[rng.randi() % FLOW.size()]


func _build_template(tmpl: int, y: float) -> Array:
	var w := HALF_WIDTH * 2.0
	var sway := sin(y * 0.0013) * w * 0.08
	var l := -HALF_WIDTH + EDGE_MARGIN + maxf(sway, 0.0)
	var r := HALF_WIDTH - EDGE_MARGIN + minf(sway, 0.0)
	var mid := (l + r) * 0.5
	var pw := w * rng.randf_range(0.18, 0.24)
	var sw := w * rng.randf_range(0.14, 0.18)
	var nw := w * rng.randf_range(0.11, 0.14)
	var out: Array = []
	match tmpl:
		T.ZIGZAG:
			var inset := rng.randf_range(0.0, w * 0.08)
			out = [_plat(l + inset, l + inset + pw, "flow"), _plat(r - inset - pw, r - inset, "flow")]
		T.STAIR:
			out = [_plat(l, l + sw, "flow"), _plat(mid - sw * 0.5, mid + sw * 0.5, "flow"), _plat(r - sw, r, "flow")]
		T.WIDE:
			var off := rng.randf_range(-w * 0.18, w * 0.18)
			out = [_plat(mid + off - pw * 0.65, mid + off + pw * 0.65, "flow")]
		T.SCATTER:
			var n := rng.randi_range(2, 4)
			var seg := (r - l) / n
			for i in n:
				var ww := rng.randf_range(MIN_WIDTH, minf(seg - ROW_SPACING_MIN, w * 0.2))
				var x0 := l + seg * i + rng.randf_range(0.0, seg - ww - ROW_SPACING_MIN)
				out.append(_plat(x0, x0 + ww, "flow"))
		T.CHOKE:
			out = [_plat(mid - nw * 0.5, mid + nw * 0.5, "choke")]
		T.BRIDGE:
			out = [_plat(l, l + pw, "wall"), _plat(mid - nw * 0.5, mid + nw * 0.5, "choke"), _plat(r - pw, r, "wall")]
		T.DOOR:
			var dw := w * 0.3
			out = [_plat(l, l + dw, "wall"), _plat(r - dw, r, "wall")]
		T.SAFE:
			out = [_plat(mid - pw * 1.1, mid + pw * 1.1, "safe")]
	return out


func _plat(x0: float, x1: float, role: String) -> Dictionary:
	return {"x0": x0, "x1": x1, "role": role, "type": "static", "travel": 0.0, "reachable": false, "anchor_ok": true}


func _resolve_overlaps(plats: Array) -> void:
	plats.sort_custom(func(a, b): return a.x0 < b.x0)
	var i := 0
	while i < plats.size():
		var p: Dictionary = plats[i]
		p.x0 = maxf(p.x0, -HALF_WIDTH + EDGE_MARGIN)
		p.x1 = minf(p.x1, HALF_WIDTH - EDGE_MARGIN)
		if i > 0 and p.x0 < plats[i - 1].x1 + ROW_SPACING_MIN:
			p.x0 = plats[i - 1].x1 + ROW_SPACING_MIN
		if p.x1 - p.x0 < MIN_WIDTH:
			plats.remove_at(i)
			continue
		i += 1


func _assign_types(plats: Array, biome: Dictionary, _tmpl: int) -> void:
	for p in plats:
		var t := _weighted(biome.weights)
		if p.role in ["safe", "choke"] and rng.randf() < 0.75:
			t = "static"
		p.type = t
		if t in ["bouncy", "speed", "reverse"] and p.x1 - p.x0 > MAX_SPECIAL_WIDTH:
			var c: float = (p.x0 + p.x1) * 0.5
			var hw := rng.randf_range(MIN_WIDTH, MAX_SPECIAL_WIDTH) * 0.5
			p.x0 = c - hw
			p.x1 = c + hw
		if t in ["speed", "conveyor"]:
			p["dir"] = 1.0 if rng.randf() < 0.5 else -1.0
		p.anchor_ok = not t in ["moving", "vanishing", "breakable"]


func _weighted(weights: Dictionary) -> String:
	var total := 0
	for v in weights.values():
		total += v
	var roll := rng.randi_range(0, total - 1)
	for k in weights:
		roll -= weights[k]
		if roll < 0:
			return k
	return "static"


## Marks reachable platforms; if no anchor is reachable, repairs the row.
func _ensure_reachable(plats: Array, dy: float, charged: bool) -> void:
	for p in plats:
		p.reachable = _reachable_from_any(p, dy, charged)
	if plats.any(func(p): return p.reachable and p.anchor_ok):
		return
	# 1) A reachable platform with a tricky type becomes a plain one.
	for p in plats:
		if p.reachable:
			p.type = "static"
			p.anchor_ok = true
			return
	# 2) Otherwise drop a stepping stone beside a previous anchor: scan
	#    outward from it for the first spot that is reachable and in bounds.
	var w := rng.randf_range(MIN_WIDTH, 160.0)
	var sources := _prev_anchors.duplicate()
	sources.shuffle()
	for src in sources:
		for k in 12:
			for side in [1.0, -1.0]:
				var x0: float = src.x1 + 30.0 + k * 25.0 if side > 0 else src.x0 - 30.0 - k * 25.0 - w
				if x0 < -HALF_WIDTH + EDGE_MARGIN or x0 + w > HALF_WIDTH - EDGE_MARGIN:
					continue
				if not can_reach(src.x0, src.x1, x0, x0 + w, dy, charged):
					continue
				var step := _plat(x0, x0 + w, "step")
				step.reachable = true
				for i in range(plats.size() - 1, -1, -1):
					var p: Dictionary = plats[i]
					if p.x1 + ROW_SPACING_MIN > step.x0 and p.x0 - ROW_SPACING_MIN < step.x1:
						plats.remove_at(i)
				plats.append(step)
				plats.sort_custom(func(l, r): return l.x0 < r.x0)
				return
	push_error("MapPlanner: could not place a reachable stepping stone (dy %.0f)" % dy)


func _reachable_from_any(p: Dictionary, dy: float, charged: bool) -> bool:
	return can_reach_any(_prev_anchors, p, dy, charged)


static func can_reach_any(sources: Array, p: Dictionary, dy: float, charged: bool) -> bool:
	for src in sources:
		if can_reach(src.x0, src.x1, p.x0, p.x1, dy, charged):
			return true
	return false


## Gives moving platforms a lane they can slide in without touching neighbours.
func _fit_moving(plats: Array) -> void:
	for i in plats.size():
		var p: Dictionary = plats[i]
		if p.type != "moving":
			continue
		var lo: float = -HALF_WIDTH + EDGE_MARGIN if i == 0 else plats[i - 1].x1 + plats[i - 1].travel + ROW_SPACING_MIN
		var hi: float = HALF_WIDTH - EDGE_MARGIN if i == plats.size() - 1 else plats[i + 1].x0 - ROW_SPACING_MIN
		var w: float = minf(p.x1 - p.x0, 180.0)
		var travel := minf((hi - lo - w) * 0.5, 170.0)
		if travel < 50.0:
			p.type = "static"
			p.anchor_ok = true
			continue
		var c: float = (lo + hi) * 0.5
		p.x0 = c - w * 0.5
		p.x1 = c + w * 0.5
		p.travel = travel


# ── Jump envelope ────────────────────────────

## Simulates a running double jump (optionally starting with a full charged
## jump) and records (horizontal distance, rise) samples.
static func simulate(charged: bool) -> PackedVector2Array:
	var dt := 1.0 / 60.0
	var vx := Player.SPEED * 0.5
	var vy := -(Player.CHARGE_VELOCITY if charged else Player.JUMP_VELOCITY)
	var x := 0.0
	var y := 0.0
	var second := false
	var out := PackedVector2Array()
	for i in 240:
		vx = move_toward(vx, Player.SPEED, Player.AIR_ACCEL * dt)
		vy = minf(vy + Player.GRAVITY * dt, Player.MAX_FALL)
		if not second and vy >= 0.0:
			vy = -Player.JUMP_VELOCITY
			second = true
		x += vx * dt
		y += vy * dt
		out.append(Vector2(x, -y))
		if -y < -200.0:
			break
	return out


static func _ensure_envelopes() -> void:
	if _env_double.is_empty():
		_env_double = simulate(false)
		_env_charged = simulate(true)


static func max_rise(charged: bool) -> float:
	_ensure_envelopes()
	var m := 0.0
	for p in (_env_charged if charged else _env_double):
		m = maxf(m, p.y)
	return m


## Furthest horizontal distance at which you can still be at least `dy` higher.
static func reach_h(dy: float, charged: bool) -> float:
	_ensure_envelopes()
	var best := -1.0
	for p in (_env_charged if charged else _env_double):
		if p.y >= dy:
			best = p.x
	return best


## Simulates the "wait, then drift in" policy a player uses to reach a ledge
## that is `d_free` px away horizontally and `dy` px higher: run toward the
## ledge but stay out from under it until you're above its top, then drift
## over. Returns how far past the take-off point you can still be at height
## >= dy (i.e. the furthest landing spot), or -1 if you never get that high.
static func simulate_ledge(d_free: float, dy: float, charged: bool) -> float:
	var dt := 1.0 / 60.0
	var vx := Player.SPEED * 0.5
	var vy := -(Player.CHARGE_VELOCITY if charged else Player.JUMP_VELOCITY)
	var x := 0.0
	var rise := 0.0
	var second := false
	var above := false
	var best := -1.0
	for i in 240:
		vy = minf(vy + Player.GRAVITY * dt, Player.MAX_FALL)
		if not second and vy >= 0.0:
			vy = -Player.JUMP_VELOCITY
			second = true
		rise -= vy * dt
		if rise >= dy + 2.0:
			above = true
		var stop_dist := vx * vx / (2.0 * Player.AIR_ACCEL * 0.6)
		if above or x + stop_dist < d_free:
			vx = move_toward(vx, Player.SPEED, Player.AIR_ACCEL * dt)
		else:
			vx = move_toward(vx, 0.0, Player.AIR_ACCEL * 0.6 * dt)
		x += vx * dt
		if above and rise >= dy:
			best = x
		if above and rise < dy:
			break
		if second and vy > 0.0 and rise < dy and not above:
			break
	return best


static var _ledge_cache: Dictionary = {}


## Cached, quantised simulate_ledge (rounded conservatively).
static func ledge_reach(d_free: float, dy: float, charged: bool) -> float:
	var di := ceili(maxf(d_free, 0.0) / 10.0)
	var yi := ceili(dy / 5.0)
	var key := Vector3i(di, yi, 1 if charged else 0)
	if not _ledge_cache.has(key):
		_ledge_cache[key] = simulate_ledge(di * 10.0, yi * 5.0, charged)
	return _ledge_cache[key]


## Can a player standing on [ax0, ax1] land on [bx0, bx1] which is `dy` higher?
static func can_reach(ax0: float, ax1: float, bx0: float, bx1: float, dy: float, charged := false) -> bool:
	if dy + V_MARGIN > max_rise(charged):
		return false
	var r := Player.RADIUS + 6.0
	# Take off from the spot closest to the target that isn't under it,
	# land at least `r` inside the target's edge.
	var d_free := INF
	if ax0 < bx0 - r:
		d_free = minf(d_free, (bx0 - r) - minf(ax1, bx0 - r))
	if ax1 > bx1 + r:
		d_free = minf(d_free, maxf(ax0, bx1 + r) - (bx1 + r))
	if d_free == INF:
		return false   # fully covered by the target: you'd bonk your head
	var reach := ledge_reach(d_free * 1.1, dy + V_MARGIN, charged)
	return reach >= (d_free + 2.0 * r) * 1.15
