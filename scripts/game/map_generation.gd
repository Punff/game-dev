extends Node2D

const Player = preload("res://scripts/player/player.gd")

@export_group("Map Settings")
@export var map_width: int = 1600

@export_group("Block Scenes")
@export var destructible_block_scene: PackedScene
@export var regular_block_scene:      PackedScene
@export var bouncy_block_scene:       PackedScene
@export var ice_block_scene:          PackedScene
@export var reverse_block_scene:      PackedScene
@export var moving_platform_scene:    PackedScene
@export var conveyor_block_scene:     PackedScene
@export var speed_block_scene:        PackedScene
@export var vanishing_block_scene:    PackedScene
@export var push_zone_scene:          PackedScene

class Biome:
	var name: String
	var height_start: float
	var height_end: float
	var gap_min: float
	var gap_max: float
	var palette: Dictionary
	func _init(n, s, e, g_min, g_max, pal):
		name = n; height_start = s; height_end = e
		gap_min = g_min; gap_max = g_max; palette = pal

var _biomes: Array = []

func _init_biomes() -> void:
	# Updated palettes with vanishing blocks and push zones
	_biomes.append(Biome.new("Rubble", 0.0, 0.25, 200.0, 280.0,
		{"regular": 35, "destructible": 20, "bouncy": 15, "moving": 10, "conveyor": 10, "vanishing": 10}))
	_biomes.append(Biome.new("Inferno", 0.25, 0.55, 240.0, 320.0,
		{"regular": 25, "bouncy": 15, "destructible": 15, "speed": 20, "reverse": 15, "push_zone": 10}))
	_biomes.append(Biome.new("Void", 0.55, 0.80, 280.0, 380.0,
		{"ice": 25, "reverse": 20, "regular": 15, "conveyor": 15, "speed": 10, "vanishing": 15}))
	_biomes.append(Biome.new("Storm", 0.80, 1.0, 320.0, 450.0,
		{"moving": 20, "reverse": 10, "ice": 15, "speed": 20, "bouncy": 10, "vanishing": 15, "push_zone": 10}))

# ── State ──
var generated_blocks: Array = []
var current_height:   float = 0.0
var _rng              := RandomNumberGenerator.new()
var _gen_cursor:      float = 0.0
var _last_platforms:  Array = []
var _pvp_streak:      int   = 0

# ── Constants ──
const STREAM_AHEAD:   float = 3000.0
const CLEANUP_BEHIND: float = 4000.0
const MAX_JUMP_REACH: float = 600.0
const DEPTH_SCALE:    float = 20000.0
const MAX_PVP_STREAK: int   = 2
const MIN_PLATFORM_WIDTH: float = 140.0
const MAX_SPECIAL_WIDTH:  float = 180.0

const T_ZIGZAG = 0
const T_STAIR  = 1
const T_WIDE   = 2
const T_CHOKE  = 3
const T_BRIDGE = 4
const T_DOOR   = 5
const T_SAFE   = 6

const FLOW_TEMPLATES = [T_ZIGZAG, T_STAIR, T_WIDE]
const PVP_TEMPLATES  = [T_CHOKE, T_BRIDGE, T_DOOR]

func _ready() -> void:
	_rng.randomize()
	_init_biomes()

func generate_map() -> void:
	_gen_cursor = 0.0
	_last_platforms.clear()
	_pvp_streak = 0
	
	# Create a wide starting platform
	_create_platform(Vector2(0, 50), map_width * 0.8, "regular")
	_last_platforms = [{"x": -map_width * 0.4, "width": map_width * 0.8, "role": "safe"}]
	
	_generate_rows_up_to(-STREAM_AHEAD)

func _process(_delta: float) -> void:
	if get_tree().get_nodes_in_group("player").is_empty(): return
	var highest = _get_highest_player_y()
	if highest < _gen_cursor + STREAM_AHEAD:
		_generate_rows_up_to(highest - STREAM_AHEAD)
	cleanup_below(_get_lowest_player_y() + CLEANUP_BEHIND)

func _get_highest_player_y() -> float:
	var best = INF
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p): best = min(best, p.global_position.y)
	return best if best < INF else 0.0

func _get_lowest_player_y() -> float:
	var best = -INF
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p): best = max(best, p.global_position.y)
	return best if best > -INF else 0.0

func _generate_rows_up_to(target_y: float) -> void:
	while _gen_cursor > target_y:
		var gap = _generate_row(_gen_cursor)
		_gen_cursor -= gap
		current_height = _gen_cursor

func _generate_row(y: float) -> float:
	var depth_frac = clamp(abs(y) / DEPTH_SCALE, 0.0, 0.99)
	var biome      = _get_biome_at(depth_frac)
	var tmpl       = _select_template(depth_frac)
	var platforms  = _build_template(tmpl, y)

	# Row memory — guarantee reachable path
	if not _has_reachable_path(platforms):
		platforms.append({"x": -80.0, "width": 160.0, "role": "standard"})

	var resolved_types = []
	for plat in platforms:
		resolved_types.append(_resolve_block_type(biome.palette, plat.role, _rng))

	# Reachability rule for vanishing blocks (Part 5)
	for i in range(platforms.size()):
		var type = resolved_types[i]
		if type == "vanishing":
			var without = platforms.duplicate()
			without.remove_at(i)
			if not _has_reachable_path(without):
				type = "regular"
		_create_platform(Vector2(platforms[i].x + platforms[i].width * 0.5, y), platforms[i].width, type)

	_last_platforms = platforms

	return _get_gap(biome, tmpl)

func _select_template(depth_frac: float) -> int:
	if depth_frac < 0.12:
		return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

	if _pvp_streak >= MAX_PVP_STREAK:
		_pvp_streak = 0
		if _rng.randf() < 0.3: return T_SAFE
		return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

	if _rng.randf() < 0.07: return T_SAFE

	if _rng.randf() < 0.35 + depth_frac * 0.30:
		_pvp_streak += 1
		return PVP_TEMPLATES[_rng.randi() % PVP_TEMPLATES.size()]

	return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

func _build_template(tmpl: int, y: float = 0.0) -> Array:
	var H  = map_width * 0.45
	var PW = map_width * 0.22
	var SW = map_width * 0.19
	var NW = map_width * 0.15

	# Zig-zag edge calculation: edges shift over height to create a winding path
	var zigzag_offset = sin(y * 0.0015) * (map_width * 0.08)
	var left_edge  = -H + zigzag_offset
	var right_edge =  H + zigzag_offset

	var results = []

	match tmpl:
		T_ZIGZAG:
			results = [
				{"x": left_edge,           "width": PW, "role": "standard"},
				{"x": right_edge - PW,     "width": PW, "role": "standard"},
			]
		T_STAIR:
			results = [
				{"x": left_edge,                "width": SW, "role": "step"},
				{"x": (left_edge + right_edge) * 0.5 - SW * 0.5, "width": SW, "role": "step"},
				{"x": right_edge - SW,          "width": SW, "role": "step"},
			]
		T_WIDE:
			var offset = _rng.randf_range(-H * 0.2, H * 0.2)
			results = [
				{"x": (left_edge + right_edge) * 0.5 + offset - PW * 0.6, "width": PW * 1.2, "role": "standard"},
			]
		T_CHOKE:
			results = [
				{"x": (left_edge + right_edge) * 0.5 - NW * 0.5, "width": NW, "role": "choke"},
			]
		T_BRIDGE:
			results = [
				{"x": left_edge,                                "width": PW, "role": "wall"},
				{"x": (left_edge + right_edge) * 0.5 - NW * 0.5, "width": NW, "role": "choke"},
				{"x": right_edge - PW,                         "width": PW, "role": "wall"},
			]
		T_DOOR:
			var dw = map_width * 0.25
			results = [
				{"x": left_edge,      "width": dw, "role": "wall"},
				{"x": right_edge - dw, "width": dw, "role": "wall"},
			]
		T_SAFE:
			results = [
				{"x": (left_edge + right_edge) * 0.5 - PW * 1.1, "width": PW * 2.2, "role": "safe"},
			]

	# Add central PvP platform every few rows to create a focal point for combat
	if int(abs(y) / 450.0) % 4 == 0 and _rng.randf() < 0.5:
		var center_x = (left_edge + right_edge) * 0.5
		results.append({"x": center_x - 160.0, "width": 320.0, "role": "pvp"})

	return results

func _has_reachable_path(platforms: Array) -> bool:
	if _last_platforms.is_empty(): return true
	for prev in _last_platforms:
		var pc = prev.x + prev.width * 0.5
		for next in platforms:
			if abs(pc - next.x) < MAX_JUMP_REACH: return true
			if abs(pc - (next.x + next.width)) < MAX_JUMP_REACH: return true
	return false

func _get_gap(biome: Biome, tmpl: int) -> float:
	match tmpl:
		T_SAFE:  return biome.gap_min * 0.5
		T_CHOKE: return biome.gap_min * 0.7
		_:       return _rng.randf_range(biome.gap_min, biome.gap_max)

func _get_biome_at(frac: float) -> Biome:
	for b in _biomes:
		if frac >= b.height_start and frac < b.height_end: return b
	return _biomes.back()

func _resolve_block_type(palette: Dictionary, role: String, rng: RandomNumberGenerator) -> String:
	if role in ["safe", "choke"]:
		if rng.randf() < 0.8: return "regular"
	var total = 0
	for v in palette.values(): total += v
	var roll = rng.randi_range(0, total - 1)
	var cum = 0
	for k in palette.keys():
		cum += palette[k]
		if roll < cum: return k
	return "regular"

func _create_platform(pos: Vector2, length: float, type: String) -> void:
	var w = max(length, MIN_PLATFORM_WIDTH)
	if type in ["bouncy", "speed", "reverse"]: w = min(w, MAX_SPECIAL_WIDTH)
	var h = 64.0
	
	var new_rect = Rect2(pos.x - w * 0.5, pos.y - h * 0.5, w, h)
	# Add a small buffer margin to prevent near-overlaps
	var check_rect = new_rect.grow(10.0)
	
	# Check against recent blocks (efficiency: only check last 20 blocks)
	var check_count = min(generated_blocks.size(), 20)
	for i in range(generated_blocks.size() - 1, generated_blocks.size() - 1 - check_count, -1):
		var b = generated_blocks[i]
		if not is_instance_valid(b): continue
		
		var bw = 128.0
		var bh = 64.0
		# Get actual size if possible
		if b.has_method("get_node"):
			var shape = b.get_node_or_null("CollisionShape2D")
			if shape and shape.shape is RectangleShape2D:
				bw = shape.shape.size.x
				bh = shape.shape.size.y
		
		var b_rect = Rect2(b.global_position.x - bw * 0.5, b.global_position.y - bh * 0.5, bw, bh)
		if check_rect.intersects(b_rect):
			return # Skip spawning if it overlaps

	var scene = _get_block_scene(type)
	if not scene: return
	var block = scene.instantiate()
	block.global_position = pos
	if block.has_method("set_block_size"):
		block.set_block_size(Vector2(w, h))
	add_child(block)
	generated_blocks.append(block)

func _get_block_scene(type: String) -> PackedScene:
	match type:
		"destructible": return destructible_block_scene
		"bouncy":       return bouncy_block_scene
		"ice":          return ice_block_scene
		"reverse":      return reverse_block_scene
		"moving":       return moving_platform_scene
		"conveyor":     return conveyor_block_scene
		"speed":        return speed_block_scene
		"vanishing":    return vanishing_block_scene
		"push_zone":    return push_zone_scene
	return regular_block_scene

func cleanup_below(y_level: float) -> void:
	var to_remove = []
	for b in generated_blocks:
		if is_instance_valid(b) and b.global_position.y > y_level:
			to_remove.append(b)
	for b in to_remove:
		generated_blocks.erase(b)
		b.queue_free()

func get_height() -> float: return current_height
