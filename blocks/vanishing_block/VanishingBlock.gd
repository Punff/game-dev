class_name VanishingBlock extends Block

@export var visible_time: float = 0.8    # seconds before disappearing after step
@export var respawn_time: float = 3.0
var _timer: float = 0.0
var _state: String = "solid"   # "solid" | "fading" | "gone"

func _ready() -> void:
	super._ready()
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
				set_collision_layer_value(1, false) # Disable collision (layer 1)
				modulate.a = 0.15
		"gone":
			_timer -= delta
			if _timer <= 0.0:
				_state = "solid"
				set_collision_layer_value(1, true) # Enable collision (layer 1)
				modulate.a = 1.0
