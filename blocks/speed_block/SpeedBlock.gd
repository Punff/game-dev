class_name SpeedBlock extends Block

@export var boost_direction: float = 1.0   # 1.0 right, -1.0 left
@export var boost_force: float = 200.0

func _ready() -> void:
	super._ready()
	block_id = "speed_block"
	block_category = "trigger"
	spawn_weight = 1.0

func on_player_stand(player: Player, delta: float) -> void:
	player.velocity.x += boost_direction * boost_force * delta * 8.0
