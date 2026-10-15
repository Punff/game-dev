extends Node

var _registry: Dictionary = {}

func _ready() -> void:
	register(preload("res://blocks/static_platform/StaticPlatform.tscn"))
	register(preload("res://blocks/bounce_pad/BouncePad.tscn"))
	register(preload("res://blocks/speed_block/SpeedBlock.tscn"))
	register(preload("res://blocks/breakable_block/BreakableBlock.tscn"))
	register(preload("res://blocks/conveyor_block/ConveyorBlock.tscn"))
	register(preload("res://blocks/push_zone/PushZone.tscn"))
	register(preload("res://blocks/vanishing_block/VanishingBlock.tscn"))
	register(preload("res://blocks/ice_block/IceBlock.tscn"))
	register(preload("res://blocks/moving_platform/MovingPlatform.tscn"))
	register(preload("res://blocks/reverse_block/ReverseBlock.tscn"))

func register(scene: PackedScene) -> void:
	var t = scene.instantiate()
	if not t.has_method("on_player_land"):
		push_error("BlockRegistry: Scene is not a valid block: " + scene.resource_path)
		t.free()
		return
		
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
	if pool.is_empty(): return null
	
	var total = pool.reduce(func(a, b): return a + b["weight"], 0.0)
	var roll = randf() * total
	var cum = 0.0
	for e in pool:
		cum += e["weight"]
		if roll <= cum: return e["scene"]
	return pool[-1]["scene"]
