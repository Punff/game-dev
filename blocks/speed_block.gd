class_name SpeedBlock
extends Block

## Treadmill that shoots you along its arrows, and keeps shooting you
## after you leave it: jump off the end for a long jump. (You stand on a
## block for about 0.4 s a landing, so a push that only works underfoot
## barely registered.)

const BOOST := 380.0
## s the boost lasts in the air after you leave it, fading out.
const CARRY_TIME := 0.8

var direction := 1.0


func _init() -> void:
	super._init()
	block_id = "speed_block"
	animated = true


func on_player_land(player: Player) -> void:
	Sfx.play("speed", -6.0)
	# Up to strip speed at once, not after a ramp you'd never finish.
	player.velocity.x = direction * maxf(player.velocity.x * direction, BOOST)


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_push += direction * BOOST


func on_player_leave(player: Player) -> void:
	if not player.is_on_floor():   # (not when you walk onto the next block)
		player.carry(direction * BOOST, CARRY_TIME)


func _draw_icon() -> void:
	var t := fmod(Time.get_ticks_msec() * 0.004, 1.0)
	for p in _icon_positions(90.0):
		for k in 2:
			var x := (k * 16.0 - 8.0 + t * 8.0) * direction
			_ink_line(PackedVector2Array([p + Vector2(x - 9 * direction, -13), p + Vector2(x + 7 * direction, 0), p + Vector2(x - 9 * direction, 13)]), Palette.INK if k == 1 else Palette.RUST, 6.0)
