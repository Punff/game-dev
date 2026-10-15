extends Node2D

## Streams the level: asks MapPlanner for rows ahead of the highest player
## and frees blocks that have sunk into the lava.

const STREAM_AHEAD := 2600.0
const CLEANUP_BELOW_LAVA := 500.0

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
	"hazard": HazardBlock,
}

@export var map_seed := 0

var planner: MapPlanner
var floor_y := 0.0
var _blocks: Array[Block] = []


func generate(start_floor_y: float) -> void:
	for b in _blocks:
		if is_instance_valid(b):
			b.queue_free()
	_blocks.clear()
	planner = MapPlanner.new(map_seed)
	floor_y = start_floor_y
	_spawn_row(planner.start(floor_y))
	_stream_to(floor_y - STREAM_AHEAD)
	Player.world_half_width = MapPlanner.HALF_WIDTH + 20.0


func height_of(y: float) -> float:
	return floor_y - y


func biome_at_y(y: float) -> Dictionary:
	return planner.biome_at(height_of(y)) if planner else MapPlanner.BIOMES[0]


## Called by the game each frame with the highest player y and the lava surface.
func update_stream(highest_y: float, lava_y: float) -> void:
	if planner == null:
		return
	if planner.cursor_y > highest_y - STREAM_AHEAD:
		_stream_to(highest_y - STREAM_AHEAD)
	var limit := lava_y + CLEANUP_BELOW_LAVA
	for i in range(_blocks.size() - 1, -1, -1):
		var b := _blocks[i]
		if not is_instance_valid(b):
			_blocks.remove_at(i)
		elif b.position.y > limit:
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
		match p.role:
			"contest": block.toughness *= 1.6   # worth fighting over, not instantly gone
			"floor": block.toughness = 4.0
		if block is MovingPlatform:
			block.travel = p.travel
			block.speed = randf_range(0.7, 1.2)
		elif block is SpeedBlock or block is ConveyorBlock:
			block.direction = p.get("dir", 1.0)
		add_child(block)
		_blocks.append(block)
