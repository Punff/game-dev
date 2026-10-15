class_name ReverseBlock extends Block

@export var reverse_duration: float = 3.0

func _ready() -> void:
	super._ready()
	block_id = "reverse_block"
	block_category = "sabotage"
	spawn_weight = 1.0

func on_player_land(player: Player) -> void:
	player.set_meta("controls_reversed", true)
	# Track how many reverse blocks we are currently touching
	var count = player.get_meta("reverse_touch_count", 0)
	player.set_meta("reverse_touch_count", count + 1)

func on_player_leave(player: Player) -> void:
	if not is_instance_valid(player): return
	
	var count = player.get_meta("reverse_touch_count", 1)
	player.set_meta("reverse_touch_count", count - 1)
	
	# Only start the lingering reverse timer if we aren't touching any other reverse blocks
	if count <= 1:
		player.set_meta("reverse_end_time", Time.get_ticks_msec() + int(reverse_duration * 1000))
		var timer = get_tree().create_timer(reverse_duration)
		timer.timeout.connect(func():
			if is_instance_valid(player):
				var end_time = player.get_meta("reverse_end_time", 0)
				var current_touch = player.get_meta("reverse_touch_count", 0)
				# Only remove if time is up and we aren't currently touching another block
				if Time.get_ticks_msec() >= end_time - 50 and current_touch <= 0:
					player.remove_meta("controls_reversed")
		)
