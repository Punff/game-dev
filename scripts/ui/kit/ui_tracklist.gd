class_name UiTracklist
extends VBoxContainer

## The main menu list, laid out like the back of a record: sides, numbered
## tracks. Moving onto a track previews it; Enter or Right picks it.

signal previewed(id: String)
signal chosen(id: String)

var tracks: Array[UiTrack] = []
var _side := "A"
var _count := 0


func _init() -> void:
	add_theme_constant_override("separation", 6)


func add_side(side: String) -> void:
	_side = side
	_count = 0
	var l := UiTheme.label("SIDE " + side, 15, Palette.MUSTARD)
	l.add_theme_font_override("font", UiTheme.heavy())
	if not tracks.is_empty():
		var gap := Control.new()
		gap.custom_minimum_size.y = 10
		add_child(gap)
	add_child(l)


func add_track(id: String, text: String) -> UiTrack:
	_count += 1
	var t := UiTrack.new(id, "%s%d" % [_side, _count], text)
	t.focus_entered.connect(func(): previewed.emit(id))
	t.pressed.connect(func(): chosen.emit(id))
	t.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_right"):
			t.accept_event()
			Sfx.play("ui_select")
			chosen.emit(id))
	add_child(t)
	tracks.append(t)
	return t


func relink() -> void:
	UiNav.link_vertical(tracks)


func track(id: String) -> UiTrack:
	for t in tracks:
		if t.id == id:
			return t
	return null


func set_current(id: String) -> void:
	for t in tracks:
		t.current = t.id == id
