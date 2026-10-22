class_name UiKeyBind
extends Button

## One remappable slot (profile, action, slot) drawn as a key cap.
## Press it, then press the new key / button / stick. Esc or waiting cancels;
## Backspace clears a keyboard slot. While listening it swallows all input,
## so nothing else in the menu reacts.

signal listening(on: bool)

const GRACE := 0.25
const TIMEOUT := 6.0

## True while any bind cell waits for input (the sleeve ignores Back then).
static var busy := false

var profile: String
var action: String
var slot: int
var _listen := false
var _time := 0.0
var _lit := false


func _init(p := "kb_a", a := "jump", s := 0) -> void:
	profile = p
	action = a
	slot = s
	theme_type_variation = "BareButton"
	custom_minimum_size = Vector2(130, 38)
	focus_mode = Control.FOCUS_ALL
	pressed.connect(_start)
	focus_entered.connect(func():
		Sfx.play("ui_move")
		queue_redraw())
	focus_exited.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	set_process(false)


func _exit_tree() -> void:
	if _listen:
		busy = false


func set_lit(v: bool) -> void:
	_lit = v
	queue_redraw()


func _start() -> void:
	_listen = true
	busy = true
	_time = 0.0
	set_process(true)
	listening.emit(true)
	UiFx.bump(self, 0.08)
	queue_redraw()


func _stop() -> void:
	_listen = false
	busy = false
	set_process(false)
	listening.emit(false)
	queue_redraw()
	grab_focus()


func _process(delta: float) -> void:
	_time += delta
	if _time > TIMEOUT:
		_stop()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not _listen:
		return
	get_viewport().set_input_as_handled()
	if _time < GRACE:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			Sfx.play("ui_back")
			_stop()
			return
		if event.physical_keycode in [KEY_BACKSPACE, KEY_DELETE] and profile != "pad":
			Settings.set_binding(profile, action, slot, {})
			_stop()
			return
	var binding := Settings.event_to_binding(event, profile == "pad")
	if binding.is_empty():
		return
	Settings.set_binding(profile, action, slot, binding)
	Sfx.play("ui_select")
	_stop()


func _draw() -> void:
	var focused := has_focus()
	var bg := Palette.INK_SOFT
	var fg := Palette.PAPER
	var edge := Palette.SMOKE
	if _listen:
		var blink := 0.5 + 0.5 * sin(_time * 10.0)
		bg = Palette.MUSTARD.lerp(Palette.PAPER, blink * 0.4)
		fg = Palette.INK
		edge = Palette.INK
	elif focused:
		bg = Palette.MUSTARD
		fg = Palette.INK
		edge = Palette.INK
	elif _lit:
		bg = Palette.INK
		edge = Palette.INK
	elif is_hovered():
		edge = Palette.PAPER_DIM
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(r.position + Vector2(3, 3), r.size), Palette.INK)
	draw_rect(r, bg)
	draw_rect(r, edge, false, 2.0)
	var text := "PRESS... %d" % ceili(TIMEOUT - _time) if _listen \
		else Settings.binding_label(Settings.bindings[profile][action][slot])
	var font := UiTheme.heavy()
	var fs := 18
	var w := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, size.x - 12)
	draw_string(font, Vector2((size.x - w) * 0.5, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, fs, fg)
