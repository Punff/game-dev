class_name IceBlock extends Block

@export var ice_friction: float = 2.0

func _ready() -> void:
	super._ready()
	block_id = "ice_block"
	block_category = "physics"
	spawn_weight = 1.0

func on_player_stand(player: Player, _delta: float) -> void:
	if not player.has_meta("original_friction"):
		player.set_meta("original_friction", player.friction)
		player.friction = ice_friction

func on_player_leave(player: Player) -> void:
	if player.has_meta("original_friction"):
		player.friction = player.get_meta("original_friction")
		player.remove_meta("original_friction")
