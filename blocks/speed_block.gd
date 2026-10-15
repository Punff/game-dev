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
	var t := fmod(Time.get_ticks_msec() * 0.003, 1.0)
	for p in _icon_positions(70.0):
		for k in 2:
			var x := (k * 12.0 - 6.0 + t * 6.0) * direction
			var a := 0.5 + 0.4 * float(k)
			var col := _icon_color(a)
			draw_polyline(PackedVector2Array([p + Vector2(x - 6 * direction, -9), p + Vector2(x + 5 * direction, 0), p + Vector2(x - 6 * direction, 9)]), col, 4.0, true)
