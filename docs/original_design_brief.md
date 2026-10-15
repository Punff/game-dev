# Race-to-Top PvP Game — Implementation Instructions

## Agent Rules
- No preamble. No summaries. Do the task and stop.
- Make reasonable assumptions, state them in one line.
- If something is broken: say what, say why, say the fix.
- Do not rewrite things not asked to change.
- Test each step before moving to the next.

---

## What This Game Is

Two-player co-op/PvP platformer. Race to the top. No health, no damage. Fun lives in two loops:

- **Flow loop** — jump combos, momentum, traversal
- **Chaos loop** — sabotage, PvP, blocks that mess with the other player

Every block must serve at least one of these.

---

## Priority Order — Do Not Skip

```
1. Block base class
2. Block registry
3. StaticPlatform (pipeline proof)
4. Map generator — row memory + rhythm + streaming
5. BouncePad, SpeedBlock
6. BreakableBlock, ConveyorBlock, PushZone
7. VanishingBlock
8. Remaining blocks
```

---

## Part 1 — Block System

### 1.1 Base Class

File: `res://blocks/Block.gd`

```gdscript
class_name Block extends StaticBody2D

@export var block_id: String
@export var block_category: String   # "static" | "physics" | "trigger" | "sabotage"
@export var grid_size: Vector2i = Vector2i(2, 1)
@export var spawn_weight: float = 1.0
@export var min_spacing: int = 0
@export var can_stack: bool = true
@export var texture: Texture2D
@export var tint: Color = Color.WHITE

func on_player_land(player: Player) -> void: pass
func on_player_stand(player: Player, delta: float) -> void: pass
func on_player_leave(player: Player) -> void: pass
func on_activate(source: Player, target: Player) -> void: pass
```

Rules:
- Every block extends Block
- Override only the `on_*` methods needed
- No logic in base class

### 1.2 Block Registry

File: `res://blocks/BlockRegistry.gd` — register as AutoLoad.

```gdscript
class_name BlockRegistry extends Node

var _registry: Dictionary = {}

func register(scene: PackedScene) -> void:
	var t = scene.instantiate()
	_registry[t.block_id] = {
		"scene": scene, "category": t.block_category,
		"weight": t.spawn_weight, "grid_size": t.grid_size,
		"min_spacing": t.min_spacing
	}
	t.free()

func get_by_category(cat: String) -> Array:
	return _registry.values().filter(func(b): return b["category"] == cat)

func get_weighted_random(cat: String = "") -> PackedScene:
	var pool = _registry.values() if cat == "" else get_by_category(cat)
	var total = pool.reduce(func(a, b): return a + b["weight"], 0.0)
	var roll = randf() * total
	var cum = 0.0
	for e in pool:
		cum += e["weight"]
		if roll <= cum: return e["scene"]
	return pool[-1]["scene"]
```

### 1.3 Adding a Block — Checklist

```
[ ] Scene at res://blocks/your_block/YourBlock.tscn
[ ] Script extends Block
[ ] Set block_id (unique, snake_case)
[ ] Set block_category
[ ] Set spawn_weight, grid_size, min_spacing
[ ] Override only needed on_* methods
[ ] Assign texture in inspector
[ ] Register in BlockRegistry
[ ] Test in isolated test scene before touching generator
```

---

## Part 2 — Block Roster

### StaticPlatform
```gdscript
class_name StaticPlatform extends Block
func _ready() -> void:
	block_id = "static_platform"
	block_category = "static"
	spawn_weight = 3.0
```

### BouncePad
```gdscript
class_name BouncePad extends Block
@export var bounce_force: float = 900.0
func _ready() -> void:
	block_id = "bounce_pad"
	block_category = "physics"
	spawn_weight = 1.2
func on_player_land(player: Player) -> void:
	player.velocity.y = -bounce_force
```
Flow: vertical burst, combo starter. Chaos: can launch opponent off edge.

### SpeedBlock
```gdscript
class_name SpeedBlock extends Block
@export var boost_direction: float = 1.0   # 1.0 right, -1.0 left
@export var boost_force: float = 300.0
func _ready() -> void:
	block_id = "speed_block"
	block_category = "trigger"
	spawn_weight = 1.0
func on_player_stand(player: Player, _delta: float) -> void:
	player.velocity.x = boost_direction * boost_force
```
Visual: arrow on block showing direction. Flow: combo extension. Chaos: blast opponent off ledge.

### BreakableBlock
```gdscript
class_name BreakableBlock extends Block
var _uses: int = 1
func _ready() -> void:
	block_id = "breakable_block"
	block_category = "trigger"
	spawn_weight = 1.0
func on_player_land(_player: Player) -> void:
	_uses -= 1
	if _uses <= 0:
		queue_free()   # add crack animation before this
```
Cross it first → opponent falls through.

### ConveyorBlock
```gdscript
class_name ConveyorBlock extends Block
@export var direction: float = 1.0
@export var speed: float = 180.0
var _base_direction: float
func _ready() -> void:
	block_id = "conveyor_block"
	block_category = "sabotage"
	grid_size = Vector2i(3, 1)
	spawn_weight = 0.8
	_base_direction = direction
func on_player_stand(player: Player, _delta: float) -> void:
	player.velocity.x += direction * speed
func receive_shockwave() -> void:
	direction *= -1.0
	_play_reverse_anim()
func _play_reverse_anim() -> void:
	pass  # flip belt UV scroll direction
```
Shockwave integration: shockwave is a radial Area2D emitted by the player. On `body_entered`, check `if body is ConveyorBlock` → call `receive_shockwave()`. Reversal is permanent toggle, not timed.

### PushZone
```gdscript
class_name PushZone extends Block
@export var push_direction: float = 1.0
@export var push_force: float = 250.0
func _ready() -> void:
	block_id = "push_zone"
	block_category = "sabotage"
	grid_size = Vector2i(2, 2)
	spawn_weight = 0.7
func on_player_stand(player: Player, delta: float) -> void:
	player.velocity.x += push_direction * push_force * delta
```
Semi-transparent zone. Place near edges for sabotage.

### VanishingBlock
```gdscript
class_name VanishingBlock extends Block
@export var visible_time: float = 0.8    # seconds before disappearing after step
@export var respawn_time: float = 3.0
var _timer: float = 0.0
var _state: String = "solid"   # "solid" | "fading" | "gone" | "respawning"
func _ready() -> void:
	block_id = "vanishing_block"
	block_category = "trigger"
	spawn_weight = 0.9
func on_player_land(_player: Player) -> void:
	if _state == "solid":
		_state = "fading"
		_timer = visible_time
func _process(delta: float) -> void:
	match _state:
		"fading":
			_timer -= delta
			modulate.a = _timer / visible_time
			if _timer <= 0.0:
				_state = "gone"
				_timer = respawn_time
				set_collision_layer_value(1, false)
				modulate.a = 0.15
		"gone":
			_timer -= delta
			if _timer <= 0.0:
				_state = "solid"
				set_collision_layer_value(1, true)
				modulate.a = 1.0
```
Rules:
- Never place as the ONLY platform in a reachability path — generator must validate around this
- Dashed visual outline so players can identify it before stepping
- Fading alpha warns player it's about to go
- Respawns after `respawn_time` — can be used by either player again

### IceBlock (future)
Reduces friction while standing. Player slides, hard to stop. Role is control-removal, not speed gain. Different from SpeedBlock.

### MovingPlatform (future)
Oscillates on a fixed path. Set path in inspector as two Vector2 points.

### TrapBlock (future)
Looks like StaticPlatform. Activates a debuff (slow, knockback) on first contact.

---

## Part 3 — Map Generator

File: `res://generation/MapGenerator.gd`

### Do Not Touch
- Biome class and `_init_biomes()`
- `_resolve_block_type()`
- `_get_block_scene()`
- `_create_platform()`
- All `@export` block scenes

### 3.1 Full Rewrite

```gdscript
extends Node2D

@export_group("Map Settings")
@export var map_width: int = 1000

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
	_biomes.append(Biome.new("Rubble", 0.0, 0.25, 120.0, 160.0,
		{"regular": 40, "destructible": 20, "bouncy": 15, "moving": 10, "conveyor": 15}))
	_biomes.append(Biome.new("Inferno", 0.25, 0.55, 130.0, 180.0,
		{"regular": 25, "bouncy": 20, "destructible": 20, "speed": 20, "reverse": 15}))
	_biomes.append(Biome.new("Void", 0.55, 0.80, 140.0, 200.0,
		{"ice": 30, "reverse": 25, "regular": 20, "conveyor": 15, "speed": 10}))
	_biomes.append(Biome.new("Storm", 0.80, 1.0, 150.0, 220.0,
		{"moving": 25, "reverse": 20, "ice": 15, "speed": 25, "bouncy": 15}))

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
const MAX_JUMP_REACH: float = 380.0
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
	var platforms  = _build_template(tmpl)

	# Row memory — guarantee reachable path
	if not _has_reachable_path(platforms):
		platforms.append({"x": -80.0, "width": 160.0, "role": "standard"})

	_last_platforms = platforms

	for plat in platforms:
		var type = _resolve_block_type(biome.palette, plat.role, _rng)
		_create_platform(Vector2(plat.x, y), plat.width, type)

	return _get_gap(biome, tmpl)

func _select_template(depth_frac: float) -> int:
	# Early game: pure flow
	if depth_frac < 0.12:
		return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

	# PvP streak cap: force a break
	if _pvp_streak >= MAX_PVP_STREAK:
		_pvp_streak = 0
		if _rng.randf() < 0.3: return T_SAFE
		return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

	# Occasional rest regardless of depth
	if _rng.randf() < 0.07: return T_SAFE

	# PvP probability grows with depth (35% → 65%)
	if _rng.randf() < 0.35 + depth_frac * 0.30:
		_pvp_streak += 1
		return PVP_TEMPLATES[_rng.randi() % PVP_TEMPLATES.size()]

	return FLOW_TEMPLATES[_rng.randi() % FLOW_TEMPLATES.size()]

func _build_template(tmpl: int) -> Array:
	var H  = map_width * 0.45   # usable half-width
	var PW = map_width * 0.24   # standard platform
	var SW = map_width * 0.19   # step platform
	var NW = map_width * 0.15   # narrow/choke

	match tmpl:
		T_ZIGZAG:
			return [
				{"x": -H,     "width": PW, "role": "standard"},
				{"x": H - PW, "width": PW, "role": "standard"},
			]
		T_STAIR:
			return [
				{"x": -H,          "width": SW, "role": "step"},
				{"x": -SW * 0.5,   "width": SW, "role": "step"},
				{"x":  H - SW,     "width": SW, "role": "step"},
			]
		T_WIDE:
			var offset = _rng.randf_range(-H * 0.25, H * 0.25)
			return [
				{"x": offset - PW * 0.6, "width": PW * 1.2, "role": "standard"},
			]
		T_CHOKE:
			return [
				{"x": -NW * 0.5, "width": NW, "role": "choke"},
			]
		T_BRIDGE:
			return [
				{"x": -H,        "width": PW, "role": "wall"},
				{"x": -NW * 0.5, "width": NW, "role": "choke"},
				{"x":  H - PW,   "width": PW, "role": "wall"},
			]
		T_DOOR:
			var dw = map_width * 0.28
			return [
				{"x": -H,      "width": dw, "role": "wall"},
				{"x":  H - dw, "width": dw, "role": "wall"},
			]
		T_SAFE:
			return [
				{"x": -PW * 1.1, "width": PW * 2.2, "role": "safe"},
			]
	return []

# ── Row memory ──
func _has_reachable_path(platforms: Array) -> bool:
	if _last_platforms.is_empty(): return true
	for prev in _last_platforms:
		var pc = prev.x + prev.width * 0.5
		for next in platforms:
			if abs(pc - next.x) < MAX_JUMP_REACH: return true
			if abs(pc - (next.x + next.width)) < MAX_JUMP_REACH: return true
	return false

# ── Rhythm ──
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
	var scene = _get_block_scene(type)
	if not scene: return
	var block = scene.instantiate()
	block.global_position = pos
	if block.has_method("set_block_size"):
		var w = max(length, MIN_PLATFORM_WIDTH)
		if type in ["bouncy", "speed", "reverse"]: w = min(w, MAX_SPECIAL_WIDTH)
		block.set_block_size(Vector2(w, 64))
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
```

---

## Part 4 — Map Design Intent

Visual reference (bottom = start, top = finish):

```
STORM    moving ↔          [gap]         moving ↔
         speed →   moving ↔    vanishing   ice
                   reverse ↓              ← PvP: send opponent down

VOID     ice · slip    regular    reverse ↓
         conveyor ← (shockwave flips direction)
         [choke] vanishing (ice) ← PvP: slide off edge
         regular   conveyor   regular

INFERNO  bouncy ↑   regular    destructible
         [choke] speed → ← PvP: blast into gap
         speed ←      [gap]      speed →   ← door
         regular · rest

RUBBLE   regular    destructible
         conveyor → ← PvP: push opponent off
         regular   regular   vanishing   regular
         regular   vanishing   regular   ← bridge
         regular · safe start
```

Key design rules visible here:
- Platforms are varied in width — not all the same size
- Platforms stagger vertically within a row — not all at same height
- Rest rows (wide regular) appear after hard PvP rows — rhythm
- Vanishing blocks never appear as the only path in a row
- PvP moments grow in frequency and intensity toward Storm

---

## Part 5 — Vanishing Block in Generation

The generator does not currently pick vanishing blocks from the palette. Add it to biomes where it makes sense, then handle the reachability rule.

### Add to palettes:
```gdscript
# Rubble — light intro
{"regular": 35, "destructible": 20, "bouncy": 15, "moving": 10, "conveyor": 10, "vanishing": 10}

# Void — chaos escalates
{"ice": 25, "reverse": 20, "regular": 15, "conveyor": 15, "speed": 10, "vanishing": 15}

# Storm — maximum chaos
{"moving": 20, "reverse": 15, "ice": 15, "speed": 20, "bouncy": 10, "vanishing": 20}
```

### Reachability rule for vanishing blocks:

After `_build_template()` and before placing, if a platform resolves to `"vanishing"`:
- Check if removing it would still leave `_has_reachable_path()` true
- If removing it breaks reachability → demote it to `"regular"` for this placement
- This prevents a vanishing block from being the only way through a row

```gdscript
# In _generate_row, after resolving types, before _create_platform:
for i in range(platforms.size()):
	var type = resolved_types[i]
	if type == "vanishing":
		var without = platforms.duplicate()
		without.remove_at(i)
		if not _has_reachable_path(without):
			type = "regular"
	_create_platform(Vector2(platforms[i].x, y), platforms[i].width, type)
```

---

## Test Order

```
1. Block base + registry: get_by_category returns entries, weighted random varies
2. StaticPlatform: player lands, collision correct, pipeline works
3. Generator open rows: no unreachable jumps across 3+ consecutive rows
4. Streaming: chunks generate ahead, free behind, no crash
5. Rhythm: tight rows followed by a wide rest — count and verify
6. BouncePad: launches player, feels good
7. SpeedBlock: boosts horizontally, arrow visible
8. BreakableBlock: breaks on second land, opponent falls through
9. ConveyorBlock: pushes, shockwave flips, visual confirms direction
10. VanishingBlock: fades, disappears, respawns, never sole path
11. Full run: climb all four biomes, PvP opportunities present in each
```
