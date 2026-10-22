class_name UiHintBar
extends HBoxContainer

## Footer of key hints for whatever has the input right now, e.g.
## set_hints("[Enter] select   [Esc] back"). Tokens are drawn as keycaps.

var _text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)


func set_hints(text: String) -> void:
	if text == _text:
		return
	_text = text
	for c in get_children():
		c.queue_free()
	add_child(UiTheme.hint(text, 16, Palette.PAPER_DIM, false))


## Accept / back caps for whatever the player is using right now.
static func accept_key() -> String:
	return "[A]" if UiHintBar.pad_active() else "[Enter]"


static func back_key() -> String:
	return "[B]" if UiHintBar.pad_active() else "[Esc]"


static func tab_keys() -> String:
	return "[LB] [RB]" if UiHintBar.pad_active() else "[Q] [E]"


static func pad_active() -> bool:
	return not Input.get_connected_joypads().is_empty()
