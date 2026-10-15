class_name ReverseBlock
extends Block

## Scrambles controls (left <-> right) while standing on it and for a while after.

const LINGER := 2.5


func _init() -> void:
	super._init()
	block_id = "reverse_block"
	animated = true


func on_player_land(player: Player) -> void:
	player.reverse_controls(LINGER)


func on_player_stand(player: Player, _delta: float) -> void:
	player.reverse_controls(LINGER)


func _draw_icon() -> void:
	var col := _icon_color()
	var wob := sin(Time.get_ticks_msec() * 0.005) * 2.0
	for p in _icon_positions(80.0):
		var a := p + Vector2(wob, -7)
		var b := p + Vector2(-wob, 3)
		draw_line(a + Vector2(-10, 0), a + Vector2(10, 0), col, 3.0)
		draw_polyline(PackedVector2Array([a + Vector2(5, -5), a + Vector2(10, 0), a + Vector2(5, 5)]), col, 3.0, true)
		draw_line(b + Vector2(-10, 0), b + Vector2(10, 0), col, 3.0)
		draw_polyline(PackedVector2Array([b + Vector2(-5, -5), b + Vector2(-10, 0), b + Vector2(-5, 5)]), col, 3.0, true)
