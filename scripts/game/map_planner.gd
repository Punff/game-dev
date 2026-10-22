class_name MapPlanner
extends RefCounted

## Pure, deterministic level layout. Produces rows of platform descriptions
## (no nodes), so it can be unit-tested headless and seeded for replays.
##
## Rows are loose: platforms are scattered across a wide arena at jittered
## heights, with lots of breakable concrete. Every row is still guaranteed to
## contain at least one "anchor" (a block that can't vanish, move or shatter)
## reachable from an anchor below, using a jump envelope simulated from the
## Player's real constants.

const HALF_WIDTH := 800.0         ## playable column is [-HALF_WIDTH, HALF_WIDTH]
const EDGE_MARGIN := 30.0
const MIN_WIDTH := 140.0
const MAX_WIDTH := 340.0
const MAX_SPECIAL_WIDTH := 200.0   ## bouncy / speed / reverse stay small
const ROW_SPACING_MIN := 140.0     ## min horizontal space between platforms of one row
const TALL := 110.0                ## height of big concrete slabs
const CLEARANCE := 64.0            ## min vertical gap between stacked platforms
const V_MARGIN := 16.0             ## px of jump height we never rely on
## Walls at the ends of the start floor: a blast at the start shoves you into
## one instead of off into the lava 13 m below (half of all multiplayer
## deaths used to happen before anyone got 10 m up). Low enough to hop over.
const START_WALL := Vector2(50.0, 60.0)

const BIOMES := [
	# name, starts at (px above start), row gap range, chance of a charge-jump row, block weights
	{"name": "Rubble", "from": 0.0, "gap": Vector2(190, 235), "charge_rows": 0.04,
		"weights": {"static": 26, "breakable": 48, "bouncy": 8, "moving": 8, "conveyor": 8, "vanishing": 10}},
	{"name": "Inferno", "from": 9000.0, "gap": Vector2(195, 240), "charge_rows": 0.08,
		"weights": {"static": 20, "breakable": 42, "bouncy": 8, "speed": 14, "reverse": 10, "push": 8, "moving": 6}},
	{"name": "Void", "from": 21000.0, "gap": Vector2(200, 240), "charge_rows": 0.12,
		"weights": {"static": 14, "breakable": 38, "ice": 16, "reverse": 10, "conveyor": 10, "vanishing": 12, "moving": 8}},
	{"name": "Storm", "from": 36000.0, "gap": Vector2(205, 240), "charge_rows": 0.16,
		"weights": {"static": 10, "breakable": 38, "moving": 14, "reverse": 8, "ice": 10, "speed": 12, "bouncy": 6, "vanishing": 10, "push": 8}},
]

enum T { SCATTER, DEMOLITION, WIDE, CHOKE, DOOR, SAFE, CONTEST, PAIR }

var rng := RandomNumberGenerator.new()
var rows: Array = []              ## generated rows, oldest first
var cursor_y := 0.0               ## y of the last generated row (negative = up)
var _prev_anchors: Array = []
var _prev_row: Array = []
var _since_contest := 0
var _next_contest := 4
## Designer runs: build the map as if this many px had already been climbed
## (start inside a later biome). Heights the player sees still count from 0.
var height_offset := 0.0

static var _env_double: PackedVector2Array
static var _env_charged: PackedVector2Array


func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	_ensure_envelopes()


## Creates the wide starting floor at y (its top surface) and resets state.
func start(floor_y: float, floor_width := 1100.0) -> Dictionary:
	rows.clear()
	cursor_y = floor_y
	var floor := _plat(-floor_width * 0.5, floor_width * 0.5, "floor", floor_y, Block.HEIGHT)
	floor.reachable = true
	var plats := [floor]
	for side: float in [-1.0, 1.0]:
		var outer: float = side * floor_width * 0.5
		var wall := _plat(minf(outer, outer - side * START_WALL.x), maxf(outer, outer - side * START_WALL.x), "wall", floor_y - START_WALL.y, START_WALL.y)
		wall.reachable = true
		plats.append(wall)
	var row := {"y": floor_y, "platforms": plats, "biome": "Rubble", "template": T.SAFE, "charged": false}
	_prev_anchors = [floor]
	_prev_row = plats
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


static func top_of(p: Dictionary) -> float:
	return p.y - p.h * 0.5


# ── Row generation ───────────────────────────

func _next_row() -> Dictionary:
	var start_y: float = rows[0].y
	var biome := biome_at(start_y - cursor_y + height_offset)
	var gap := minf(rng.randf_range(biome.gap.x, biome.gap.y), max_rise(false) - V_MARGIN - 40.0)
	var charged_row: bool = rng.randf() < biome.charge_rows
	if charged_row:
		gap = rng.randf_range(300.0, 360.0)
	var y := cursor_y - gap
	var tmpl := _pick_template(start_y - y + height_offset)
	var plats := _build_template(tmpl, y)
	_resolve_overlaps(plats)
	_assign_types(plats, biome, tmpl)
	_fit_moving(plats)
	_keep_clear_of_previous(plats)
	_ensure_reachable(plats, charged_row, gap)

	var anchors := plats.filter(func(p): return p.anchor_ok and p.reachable)
	if not anchors.is_empty():
		_prev_anchors = anchors
	_prev_row = plats
	var row := {"y": y, "platforms": plats, "biome": biome.name, "template": tmpl, "gap": gap, "charged": charged_row}
	rows.append(row)
	# Measure the next gap from the highest anchor if the route ended up lower
	# than the row (repairs and jitter), so gaps never silently stack up.
	var highest_anchor := INF
	for a in anchors:
		highest_anchor = minf(highest_anchor, top_of(a))
	cursor_y = y
	if highest_anchor != INF and highest_anchor > y + 60.0:
		cursor_y = highest_anchor - 30.0
	return row


func _pick_template(height: float) -> int:
	# Every few rows the whole route funnels through one platform (or a tight
	# pair) so everyone ends up fighting over the same spot.
	_since_contest += 1
	if height > 900.0 and _since_contest >= _next_contest:
		_since_contest = 0
		_next_contest = rng.randi_range(3, 6)
		return T.CONTEST if rng.randf() < 0.65 else T.PAIR
	var r := rng.randf()
	if height < 900.0 or r < 0.6:
		return T.SCATTER
	if r < 0.8:
		return T.DEMOLITION
	if r < 0.88:
		return T.WIDE
	if r < 0.95:
		return T.CHOKE
	return T.SAFE


func _rand_width() -> float:
	# Skewed toward mid-size slabs, occasionally a long one.
	return lerpf(MIN_WIDTH, MAX_WIDTH, pow(rng.randf(), 1.6))


func _build_template(tmpl: int, y: float) -> Array:
	var l := -HALF_WIDTH + EDGE_MARGIN
	var r := HALF_WIDTH - EDGE_MARGIN
	var out: Array = []
	match tmpl:
		T.SCATTER:
			var n := rng.randi_range(2, 4)
			var seg := (r - l) / n
			for i in n:
				if rng.randf() < 0.2:
					continue   # leave holes now and then
				var w := minf(_rand_width(), seg - ROW_SPACING_MIN)
				var x0 := l + seg * i + rng.randf_range(0.0, seg - w - ROW_SPACING_MIN)
				out.append(_plat(x0, x0 + w, "flow", y + rng.randf_range(-30, 30), Block.HEIGHT))
		T.DEMOLITION:
			# A knot of big concrete slabs at staggered heights, plus a way around.
			var cx := rng.randf_range(l + 380.0, r - 380.0)
			var k := rng.randi_range(2, 3)
			var x := cx - 260.0 * k * 0.5
			for i in k:
				var w := rng.randf_range(170.0, 240.0)
				out.append(_plat(x, x + w, "demolition", y + rng.randf_range(-35, 20), TALL if rng.randf() < 0.6 else Block.HEIGHT))
				x += w + ROW_SPACING_MIN + rng.randf_range(0, 40)
			var side_w := _rand_width()
			if cx > 0.0:
				out.append(_plat(l + rng.randf_range(0, 200), l + rng.randf_range(0, 200) + side_w, "flow", y + rng.randf_range(-25, 25), Block.HEIGHT))
			else:
				out.append(_plat(r - side_w - rng.randf_range(0, 200), r - rng.randf_range(0, 200), "flow", y + rng.randf_range(-25, 25), Block.HEIGHT))
		T.WIDE:
			var cx := rng.randf_range(l + 300.0, r - 300.0)
			var w := rng.randf_range(420.0, 560.0)
			out.append(_plat(cx - w * 0.5, cx + w * 0.5, "safe", y, Block.HEIGHT))
		T.CHOKE:
			var cx := rng.randf_range(-300.0, 300.0)
			out.append(_plat(cx - 100.0, cx + 100.0, "choke", y, Block.HEIGHT))
			if rng.randf() < 0.5:
				out.append(_plat(l, l + 260.0, "wall", y - 40.0, TALL))
				out.append(_plat(r - 260.0, r, "wall", y - 40.0, TALL))
		T.DOOR:
			var dw := rng.randf_range(600.0, 800.0)
			out.append(_plat(l, l + dw, "wall", y, Block.HEIGHT))
			out.append(_plat(r - dw, r, "wall", y, Block.HEIGHT))
		T.SAFE:
			var cx := rng.randf_range(-250.0, 250.0)
			out.append(_plat(cx - 260.0, cx + 260.0, "safe", y, Block.HEIGHT))
		T.CONTEST:
			# One king-of-the-hill platform; it's the only way up.
			var cx := rng.randf_range(-420.0, 420.0)
			var w := rng.randf_range(200.0, 280.0)
			out.append(_plat(cx - w * 0.5, cx + w * 0.5, "contest", y, Block.HEIGHT))
		T.PAIR:
			# Two small platforms side by side, barely apart: shove-fest.
			var cx := rng.randf_range(-380.0, 380.0)
			var w := rng.randf_range(150.0, 200.0)
			var g := rng.randf_range(ROW_SPACING_MIN, ROW_SPACING_MIN + 40.0)
			out.append(_plat(cx - g * 0.5 - w, cx - g * 0.5, "contest", y + rng.randf_range(-20, 20), Block.HEIGHT))
			out.append(_plat(cx + g * 0.5, cx + g * 0.5 + w, "contest", y + rng.randf_range(-30, 30), Block.HEIGHT))
	return out


## `top` is the walkable surface; the dictionary stores the block centre.
func _plat(x0: float, x1: float, role: String, top: float, h: float) -> Dictionary:
	return {"x0": x0, "x1": x1, "y": top + h * 0.5, "h": h, "role": role, "type": "static", "travel": 0.0, "reachable": false, "anchor_ok": true}


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
		match p.role:
			"safe", "choke":
				if rng.randf() < 0.7:
					t = "static"
			"contest":
				t = "static" if rng.randf() < 0.8 else "ice"
			"demolition", "wall":
				t = "breakable" if rng.randf() < 0.85 else "static"
		if p.h > Block.HEIGHT and t != "breakable":
			t = "breakable" if rng.randf() < 0.7 else "static"
		p.type = t
		if t in ["bouncy", "speed", "reverse", "push", "ice", "vanishing", "conveyor"]:
			p.h = Block.HEIGHT
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


## Pushes platforms up if they'd sit too close on top of one in the row below.
func _keep_clear_of_previous(plats: Array) -> void:
	for p in plats:
		for q in _prev_row:
			if p.x1 + p.travel + 40.0 < q.x0 - q.travel or p.x0 - p.travel - 40.0 > q.x1 + q.travel:
				continue
			var clearance: float = top_of(q) - (p.y + p.h * 0.5)
			if clearance < CLEARANCE:
				p.y -= CLEARANCE - clearance


## Marks reachable platforms; if no anchor is reachable, repairs the row.
func _ensure_reachable(plats: Array, charged: bool, gap: float) -> void:
	for p in plats:
		p.reachable = can_reach_any(_prev_anchors, p, charged)
	if plats.any(func(p): return p.reachable and p.anchor_ok):
		return
	# 1) A reachable platform with a tricky type becomes plain steel.
	for p in plats:
		if p.reachable:
			p.type = "static"
			p.anchor_ok = true
			p.travel = 0.0
			return
	# 2) Otherwise drop a stepping stone near a previous anchor: scan outward
	#    beside it, then over it, for the first spot that is reachable and in
	#    bounds - at a random width, then the narrowest (a wide anchor near
	#    the walls, like the start floor, leaves little room beside it).
	var sources := _prev_anchors.duplicate()
	sources.shuffle()
	for w in [rng.randf_range(MIN_WIDTH, 260.0), MIN_WIDTH]:
		for src in sources:
			var rise := minf(gap, max_rise(charged) - V_MARGIN - 50.0) * rng.randf_range(0.8, 1.0)
			var y: float = top_of(src) - rise
			var spots: Array = []
			for k in 14:
				spots.append(src.x1 + 40.0 + k * 30.0)
				spots.append(src.x0 - 40.0 - k * 30.0 - w)
			var over: float = src.x0
			while over + w <= src.x1:
				spots.append(over)
				over += 60.0
			for x0: float in spots:
				if x0 < -HALF_WIDTH + EDGE_MARGIN or x0 + w > HALF_WIDTH - EDGE_MARGIN:
					continue
				var step := _plat(x0, x0 + w, "step", y, Block.HEIGHT)
				if not can_reach_any([src], step, charged):
					continue
				step.reachable = true
				_keep_clear_of_previous([step])
				if not can_reach_any([src], step, charged):
					continue
				for i in range(plats.size() - 1, -1, -1):
					var p: Dictionary = plats[i]
					if p.x1 + p.travel + ROW_SPACING_MIN > step.x0 and p.x0 - p.travel - ROW_SPACING_MIN < step.x1:
						plats.remove_at(i)
				plats.append(step)
				plats.sort_custom(func(l, r): return l.x0 < r.x0)
				return
	push_error("MapPlanner: could not place a reachable stepping stone")


static func can_reach_any(sources: Array, p: Dictionary, charged: bool) -> bool:
	for src in sources:
		var dy := maxf(top_of(src) - top_of(p), 0.0)
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
		var w: float = minf(p.x1 - p.x0, 260.0)
		var travel := minf((hi - lo - w) * 0.5, 240.0)
		if travel < 70.0:
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
		var stop_dist := vx * vx / (2.0 * Player.AIR_ACCEL * Player.AIR_BRAKE)
		if above or x + stop_dist < d_free:
			vx = move_toward(vx, Player.SPEED, Player.AIR_ACCEL * dt)
		else:
			vx = move_toward(vx, 0.0, Player.AIR_ACCEL * Player.AIR_BRAKE * dt)
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
