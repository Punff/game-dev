class_name BouncePad extends Block

@export var bounce_force: float = 900.0

func _ready() -> void:
	super._ready()
	block_id = "bounce_pad"
	block_category = "physics"
	spawn_weight = 1.2

func on_player_land(player: Player) -> void:
	player.velocity.y = -bounce_force
	# Optional: feedback like animation or sound can be added here
