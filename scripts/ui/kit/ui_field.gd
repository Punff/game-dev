class_name UiField
extends VBoxContainer

## A captioned text field. `edit` is the LineEdit (focus goes there).

var edit := LineEdit.new()


func _init(caption := "", placeholder := "", max_len := 64, secret := false) -> void:
	add_theme_constant_override("separation", 4)
	if caption != "":
		var l := UiTheme.label(caption.to_upper(), 15, Palette.PAPER_DIM)
		l.add_theme_font_override("font", UiTheme.heavy())
		add_child(l)
	edit.placeholder_text = placeholder
	edit.max_length = max_len
	edit.secret = secret
	edit.custom_minimum_size = Vector2(0, 48)
	edit.focus_entered.connect(func(): Sfx.play("ui_move"))
	add_child(edit)


var text: String:
	get: return edit.text
	set(v): edit.text = v
