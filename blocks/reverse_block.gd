class_name ReverseBlock
extends Block

## Scrambles controls (left <-> right) while standing on it and for a while after.

const LINGER := 2.5


func _init() -> void:
	super._init()
	block_id = "reverse_block"
	animated = true


func on_player_land(player: Player) -> void:
	if not player.is_reversed():
		Telemetry.ev("reversed", player)
	player.reverse_controls(LINGER)


func on_player_stand(player: Player, _delta: float) -> void:
	player.reverse_controls(LINGER)


func _draw_icon() -> void:
	var col := _icon_color()
	var wob := sin(Time.get_ticks_msec() * 0.006) * 3.0
	for p in _icon_positions(110.0):
		var a := p + Vector2(wob, -9)
		var b := p + Vector2(-wob, 9)
		_ink_line(PackedVector2Array([a + Vector2(-16, 0), a + Vector2(16, 0), a + Vector2(8, -7)]), col, 4.0)
		_ink_line(PackedVector2Array([b + Vector2(16, 0), b + Vector2(-16, 0), b + Vector2(-8, 7)]), col, 4.0)
