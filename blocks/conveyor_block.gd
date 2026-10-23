class_name ConveyorBlock
extends Block

## Belt that slowly drags you along. A shockwave flips its direction, and
## the jolt throws whoever's on it (but the blaster) off the new way: the
## belt is a trap to spring on someone, from anywhere in reach of it.

const PUSH := 150.0
## The jolt, as a blast (it merges with the shockwave itself if that hit
## them too): sideways along the new direction, and up off the belt.
const FLIP_KICK := Vector2(700.0, -360.0)

var direction := 1.0


func _init() -> void:
	super._init()
	block_id = "conveyor_block"
	animated = true


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_push += direction * PUSH


func on_shockwave(_dir: Vector2, _origin: Vector2, by: Player = null) -> void:
	direction = -direction
	var kicked := 0
	for p: Player in get_tree().get_nodes_in_group("player"):
		if p != by and not p.is_dead and self in p._floor_blocks:
			p.hit_by_shockwave(Vector2(direction * FLIP_KICK.x, FLIP_KICK.y), by)
			kicked += 1
	if kicked > 0:
		Fx.speed_lines(global_position, Vector2(direction, 0), Palette.BLOCKS[block_id][1])
		Sfx.play("hit", -2.0)
	Telemetry.ev("conveyor_flip", by, {"kicked": kicked})
	net_changed()


func net_state() -> int:
	return 1 if direction < 0.0 else 0


func apply_net_state(state: int) -> void:
	direction = -1.0 if state == 1 else 1.0


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
