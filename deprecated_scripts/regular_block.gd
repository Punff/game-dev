extends BaseBlock
class_name RegularBlock

func get_block_group() -> String: return "regular_blocks"
func get_default_color() -> Color: return Color(0.6, 0.62, 0.65)

func on_block_built():
	var body = get_block_body(); var _hw = hw(); var _hh = hh()
	add_line(body, [Vector2(-_hw * 0.35, -_hh * 0.15), Vector2(_hw * 0.35, -_hh * 0.15)], Color(1,1,1,0.15), 1.0)
	add_line(body, [Vector2(-_hw * 0.35, _hh * 0.15), Vector2(_hw * 0.35, _hh * 0.15)], Color(0,0,0,0.15), 1.0)

func receive_force(_o: Vector2, _s: float):
	if _s >= 50.0: play_impact()
