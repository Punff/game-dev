class_name PushZone
extends Block

## Gusty wind platform: periodically flips the direction it shoves you.

const PUSH := 300.0
const PERIOD := 2.4

var _phase := 0.0


func _init() -> void:
	super._init()
	block_id = "push_zone"
	animated = true


func _ready() -> void:
	super._ready()
	_phase = randf() * PERIOD * 2.0


func direction() -> float:
	var t := Time.get_ticks_msec() / 1000.0 + _phase
	return 1.0 if fmod(t, PERIOD * 2.0) < PERIOD else -1.0


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_push += direction() * PUSH


func _draw_icon() -> void:
	var d := direction()
	var t := Time.get_ticks_msec() * 0.004
	for p in _icon_positions(80.0):
		for k in 2:
			var y := -9.0 + k * 11.0
			var pts := PackedVector2Array()
			for i in 7:
				var x := (i - 3) * 6.0
				pts.append(p + Vector2(x, y + sin(t * d + i * 0.9 + k) * 2.5))
			draw_polyline(pts, _icon_color(0.75), 3.0, true)
		var tip := p + Vector2(22.0 * d, -3)
		draw_polyline(PackedVector2Array([tip + Vector2(-6 * d, -6), tip, tip + Vector2(-6 * d, 6)]), _icon_color(), 3.0, true)
