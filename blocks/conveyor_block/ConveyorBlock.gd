class_name ConveyorBlock extends Block

@export var direction: float = 1.0
@export var speed: float = 220.0
var _base_direction: float

func _ready() -> void:
	super._ready()
	block_id = "conveyor_block"
	block_category = "sabotage"
	grid_size = Vector2i(3, 1)
	spawn_weight = 0.8
	
	# Randomize initial direction
	if randf() > 0.5:
		direction *= -1.0
	
	_base_direction = direction

func on_player_stand(player: Player, delta: float) -> void:
	# Additive push instead of hard override, allowing player movement
	player.velocity.x += direction * speed * delta * 5.0

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float) -> void:
	receive_shockwave()

func receive_shockwave() -> void:
	direction *= -1.0
	_play_reverse_anim()

func _play_reverse_anim() -> void:
	# Optional: flip belt UV scroll direction or flip sprite
	pass
