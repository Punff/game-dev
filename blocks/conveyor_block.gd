class_name ConveyorBlock
extends Block

## Belt that slowly drags you along. A shockwave flips its direction.

const PUSH := 150.0

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
	var col := _icon_color()
	var off := posmod(int(Time.get_ticks_msec() * 0.08 * direction), 30)
	var half := size.x * 0.5 - 18.0
	var x := -half + off
	while x < half - 10.0:
		_ink_line(PackedVector2Array([Vector2(x, -10), Vector2(x + 8 * direction, 0), Vector2(x, 10)]), col, 3.5)
		x += 30.0
	for side in [-1.0, 1.0]:
		draw_circle(Vector2(side * (half + 4), 0), 10.0, Palette.INK)
		draw_circle(Vector2(side * (half + 4), 0), 6.0, col)
