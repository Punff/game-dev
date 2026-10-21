class_name BouncePad
extends Block

## Launches players high into the air and refills their jumps.

const BOUNCE_VELOCITY := 1000.0

var _squash := 0.0


func _init() -> void:
	super._init()
	block_id = "bounce_pad"
	animated = true


func on_player_land(player: Player) -> void:
	player.launch(BOUNCE_VELOCITY)
	Telemetry.ev("bounce", player)
	_squash = 1.0
	Sfx.play("bounce")


func _process(delta: float) -> void:
	if _squash > 0.0:
		_squash = move_toward(_squash, 0.0, delta * 4.0)
		queue_redraw()   # the boing itself stays smooth
	else:
		redraw_icon()


func _draw_icon() -> void:
	var col := _icon_color()
	var lift := -(1.0 - _squash) * 3.0 + sin(Time.get_ticks_msec() * 0.008) * 2.0
	for p in _icon_positions(110.0):
		# Coiled spring
		var pts := PackedVector2Array()
		for i in 7:
			pts.append(p + Vector2(-16.0 + i * 5.3, (8.0 if i % 2 == 0 else -8.0) * (1.0 - _squash * 0.5) + lift))
		_ink_line(pts, col, 4.0)
		_ink_line(PackedVector2Array([p + Vector2(-20, -16 + lift), p + Vector2(20, -16 + lift)]), col, 4.0)
