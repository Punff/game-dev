class_name StaticPlatform extends Block

func _ready() -> void:
	super._ready()
	block_id = "static_platform"
	block_category = "static"
	spawn_weight = 3.0
