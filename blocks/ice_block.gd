class_name IceBlock
extends Block

## Slippery: you keep sliding and turn slowly.


func _init() -> void:
	super._init()
	block_id = "ice_block"


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_ice = true


func _draw_icon() -> void:
	var col := Color(1, 1, 1, 0.9)
	for p in _icon_positions(90.0):
		draw_line(p + Vector2(-18, 10), p + Vector2(-4, -12), col, 4.0)
		draw_line(p + Vector2(2, 10), p + Vector2(10, -2), col, 4.0)
	# frost rim
	draw_rect(Rect2(-size.x * 0.5 + OUTLINE, -size.y * 0.5 + OUTLINE, size.x - OUTLINE * 2, 6), Color(1, 1, 1, 0.6))
