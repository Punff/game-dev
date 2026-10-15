class_name ConveyorBlock
extends Block

## Belt that slowly drags you along. A shockwave flips its direction.

const PUSH := 190.0

var direction := 1.0


func _init() -> void:
	super._init()
	block_id = "conveyor_block"
	animated = true


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_push += direction * PUSH


func on_shockwave(_dir: Vector2, _origin: Vector2) -> void:
	direction = -direction


func _draw_icon() -> void:
	var col := _icon_color(0.7)
	var off := fmod(Time.get_ticks_msec() * 0.06 * direction, 24.0)
	var half := size.x * 0.5 - 10.0
	var x := -half + posmod(int(off), 24)
	while x < half:
		draw_line(Vector2(x, -10), Vector2(x + 7, -10), col, 3.0)
		draw_line(Vector2(x, 4), Vector2(x + 7, 4), col, 3.0)
		x += 24.0
	# End rollers
	draw_circle(Vector2(-half + 2, -3), 5.0, Color(colors()[1], 0.8))
	draw_circle(Vector2(half - 2, -3), 5.0, Color(colors()[1], 0.8))
