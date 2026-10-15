class_name SpeedBlock
extends Block

## Treadmill that boosts you along its arrows.

const BOOST := 520.0

var direction := 1.0


func _init() -> void:
	super._init()
	block_id = "speed_block"
	animated = true


func on_player_land(_player: Player) -> void:
	Sfx.play("speed", -6.0)


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_push += direction * BOOST


func _draw_icon() -> void:
	var t := fmod(Time.get_ticks_msec() * 0.004, 1.0)
	for p in _icon_positions(90.0):
		for k in 2:
			var x := (k * 16.0 - 8.0 + t * 8.0) * direction
			_ink_line(PackedVector2Array([p + Vector2(x - 9 * direction, -13), p + Vector2(x + 7 * direction, 0), p + Vector2(x - 9 * direction, 13)]), Palette.INK if k == 1 else Palette.RUST, 6.0)
