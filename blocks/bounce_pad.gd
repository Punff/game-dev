class_name BouncePad
extends Block

## Launches players high into the air and refills their jumps.

const BOUNCE_VELOCITY := 960.0

var _squash := 0.0


func _init() -> void:
	super._init()
	block_id = "bounce_pad"
	animated = true


func on_player_land(player: Player) -> void:
	player.launch(BOUNCE_VELOCITY)
	_squash = 1.0
	Sfx.play("bounce")


func _process(delta: float) -> void:
	_squash = move_toward(_squash, 0.0, delta * 4.0)
	queue_redraw()


func _draw_icon() -> void:
	var col := _icon_color()
	var lift := -3.0 - (1.0 - _squash) * 2.0 + sin(Time.get_ticks_msec() * 0.006) * 1.5
	for p in _icon_positions(80.0):
		# Double chevron pointing up.
		for k in 2:
			var y := p.y + lift + 6.0 - k * 9.0
			draw_polyline(PackedVector2Array([p + Vector2(-11, y - p.y + 5), p + Vector2(0, y - p.y - 4), p + Vector2(11, y - p.y + 5)]), col, 4.0, true)
