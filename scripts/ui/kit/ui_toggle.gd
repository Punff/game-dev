class_name UiToggle
extends Button

## OFF | ON switch with a sticker that slides to the chosen side.
## Enter flips it; left/right pick a side.

signal changed(on: bool)

var on := false
var _k := 0.0     # sticker position, 0 = off, 1 = on
var _lit := false


func _init(start := false) -> void:
	on = start
	_k = 1.0 if on else 0.0
	theme_type_variation = "BareButton"
	custom_minimum_size = Vector2(150, 36)
	focus_mode = Control.FOCUS_ALL
	pressed.connect(func(): set_on(not on))
	focus_entered.connect(func(): Sfx.play("ui_move"))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_on(v: bool) -> void:
	if v == on:
		return
	on = v
	Sfx.play("ui_select")
	changed.emit(on)
	if not UiFx.enabled():
		_k = 1.0 if on else 0.0
		queue_redraw()
		return
	var tw := create_tween()
	tw.tween_method(_set_k, _k, 1.0 if on else 0.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_k(k: float) -> void:
	_k = k
	queue_redraw()


func set_lit(v: bool) -> void:
	_lit = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		set_on(false)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		set_on(true)
		accept_event()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var half := size.x * 0.5
	draw_rect(Rect2(r.position + Vector2(4, 4), r.size), Palette.INK)
	draw_rect(r, Palette.INK if _lit else Palette.INK_SOFT)
	var knob := Rect2(Vector2(_k * half, 0), Vector2(half, size.y)).grow(-3)
	draw_rect(knob, Palette.GOOD.lerp(Palette.SMOKE, 1.0 - _k))
	draw_rect(r, Palette.PAPER if _lit or is_hovered() else Palette.SMOKE, false, 2.0)
	var font := UiTheme.heavy()
	var fs := 18
	for i in 2:
		var text := "ON" if i == 1 else "OFF"
		var active := (i == 1) == on
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(half * i + (half - w) * 0.5, size.y * 0.5 + fs * 0.36)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.INK if active else Palette.PAPER_DIM)
