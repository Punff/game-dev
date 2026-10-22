extends Node2D

## Streams the level: asks MapPlanner for rows ahead of the highest player
## and frees blocks that have sunk into the lava.

const STREAM_AHEAD := 2600.0
const CLEANUP_BELOW_LAVA := 500.0
const STREAM_STEP := 300.0          ## most map built per physics tick

var BLOCK_TYPES := {
	"static": StaticPlatform,
	"bouncy": BouncePad,
	"speed": SpeedBlock,
	"breakable": BreakableBlock,
	"conveyor": ConveyorBlock,
	"push": PushZone,
	"vanishing": VanishingBlock,
	"ice": IceBlock,
	"moving": MovingPlatform,
	"reverse": ReverseBlock,
}

@export var map_seed := 0
## Designer runs: start the map this many px up (see MapPlanner.height_offset).
var height_offset := 0.0

var planner: MapPlanner
var floor_y := 0.0
var _blocks: Array[Block] = []
var _by_net_id := {}
var _next_net_id := 0
## How many of each block type the map has built (Telemetry: what was on offer).
var type_counts := {}


func _physics_process(delta: float) -> void:
	Block.clock += delta


func block_by_net_id(id: int) -> Block:
	var b: Block = _by_net_id.get(id)
	return b if is_instance_valid(b) else null


func generate(start_floor_y: float) -> void:
	for b in _blocks:
		if is_instance_valid(b):
			b.queue_free()
	_blocks.clear()
	_by_net_id.clear()
	_next_net_id = 0
	Block.clock = 0.0
	planner = MapPlanner.new(map_seed)
	planner.height_offset = height_offset
	floor_y = start_floor_y
	_spawn_row(planner.start(floor_y))
	_stream_to(floor_y - STREAM_AHEAD)
	Player.world_half_width = MapPlanner.HALF_WIDTH + 20.0


func height_of(y: float) -> float:
	return floor_y - y + height_offset


func biome_at_y(y: float) -> Dictionary:
	return planner.biome_at(height_of(y)) if planner else MapPlanner.BIOMES[0]


## Called by the game each frame with the highest player y and the lava surface.
func update_stream(highest_y: float, lava_y: float) -> void:
	if planner == null:
		return
	if planner.cursor_y > highest_y - STREAM_AHEAD:
		# A few rows per tick at most, so a big launch doesn't build half a
		# screen of blocks in one frame (the buffer ahead is plenty).
		_stream_to(maxf(highest_y - STREAM_AHEAD, planner.cursor_y - STREAM_STEP))
	# The lava creeps up slowly: tidying up below it now and then is plenty.
	if Engine.get_physics_frames() % 10 != 0:
		return
	var limit := lava_y + CLEANUP_BELOW_LAVA
	for i in range(_blocks.size() - 1, -1, -1):
		var b := _blocks[i]
		if not is_instance_valid(b):
			_blocks.remove_at(i)
		elif b.position.y > limit:
			_by_net_id.erase(b.net_id)
			b.queue_free()
			_blocks.remove_at(i)
	for f in get_tree().get_nodes_in_group("fragments"):
		if f.global_position.y > limit:
			f.queue_free()


func _stream_to(target_y: float) -> void:
	for row in planner.generate_until(target_y):
		_spawn_row(row)


func _spawn_row(row: Dictionary) -> void:
	for p in row.platforms:
		var block: Block = BLOCK_TYPES.get(p.type, StaticPlatform).new()
		var w: float = p.x1 - p.x0
		block.position = Vector2((p.x0 + p.x1) * 0.5, p.y)
		block.set_block_size(Vector2(w, p.h))
		if block is MovingPlatform:
			block.travel = p.travel
			# From the position rather than randf() so every peer agrees.
			block.speed = 0.7 + posmod(hash(Vector2i(block.position)), 1000) / 2000.0
		elif block is SpeedBlock or block is ConveyorBlock:
			block.direction = p.get("dir", 1.0)
		type_counts[block.block_id] = type_counts.get(block.block_id, 0) + 1
		_next_net_id += 1
		block.net_id = _next_net_id
		_by_net_id[_next_net_id] = block
		add_child(block)
		_blocks.append(block)
