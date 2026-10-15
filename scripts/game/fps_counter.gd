extends Label

# ─────────────────────────────────────────────
#  FPS COUNTER
#  Add as a CanvasLayer child so it stays on
#  screen regardless of camera movement.
# ─────────────────────────────────────────────

@export var update_interval: float = 0.15   # seconds between label refreshes

var _timer: float = 0.0

func _ready() -> void:
	# Default positioning — top-right, monospace feel
	anchor_left      = 1.0
	anchor_right     = 1.0
	anchor_top       = 0.0
	anchor_bottom    = 0.0
	offset_left      = -90.0
	offset_top       =  8.0
	offset_right     = -8.0
	offset_bottom    =  30.0

	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_color",        Color(1.0, 1.0, 1.0, 0.85))
	add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	add_theme_constant_override("shadow_offset_x", 1)
	add_theme_constant_override("shadow_offset_y", 1)

func _process(delta: float) -> void:
	_timer += delta
	if _timer >= update_interval:
		_timer = 0.0
		text = "%d fps" % Engine.get_frames_per_second()
