class_name PushZone extends Block

@export var push_direction: float = 1.0
@export var push_force: float = 1500.0 # Adjusted for delta-based push

func _ready() -> void:
	super._ready()
	block_id = "push_zone"
	block_category = "sabotage"
	grid_size = Vector2i(2, 2)
	spawn_weight = 0.7

func on_player_stand(player: Player, delta: float) -> void:
	# Note: Instructions said push_direction * push_force * delta
	# But velocity is usually not delta-scaled in Godot's move_and_slide if it's an additive force per frame.
	# Actually, if it's called every frame, it IS delta-scaled in the instruction.
	player.velocity.x += push_direction * push_force * delta
