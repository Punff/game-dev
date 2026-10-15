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
	var t := Time.get_ticks_msec() * 0.006
	for p in _icon_positions(110.0):
		for k in 3:
			var pts := PackedVector2Array()
			for i in 8:
				pts.append(p + Vector2((i - 3.5) * 6.0 - d * 6.0, -12.0 + k * 12.0 + sin(t * d + i * 0.8 + k) * 3.0))
			_ink_line(pts, _icon_color(), 3.0)
		var tip := p + Vector2(30.0 * d, 0)
		_ink_line(PackedVector2Array([tip + Vector2(-9 * d, -9), tip, tip + Vector2(-9 * d, 9)]), _icon_color(), 4.0)
