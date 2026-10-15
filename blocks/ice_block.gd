class_name IceBlock
extends Block

## Slippery: you keep sliding and turn slowly.


func _init() -> void:
	super._init()
	block_id = "ice_block"


func on_player_stand(player: Player, _delta: float) -> void:
	player.surface_ice = true


func _draw_icon() -> void:
	var col := Color(1, 1, 1, 0.75)
	for p in _icon_positions(70.0):
		draw_line(p + Vector2(-12, 6), p + Vector2(-2, -8), col, 3.0, true)
		draw_line(p + Vector2(2, 6), p + Vector2(8, -2), col, 3.0, true)
