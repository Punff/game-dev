class_name UiCycler
extends Button

## "◀ value ▶" picker: left/right step through options, Enter steps forward,
## clicking either end steps that way. Optional colour swatches per option.

signal changed(index: int)

var options: Array = []
var index := 0
var swatches: Array = [] :
	set(v):
		swatches = v
		queue_redraw()
var _lit := false
var _nudge := 0.0   # arrow kick after a step, signed


func _init(opts: Array = [], start := 0) -> void:
	options = opts
	index = clampi(start, 0, maxi(0, opts.size() - 1))
	theme_type_variation = "BareButton"
	custom_minimum_size = Vector2(300, 36)
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(func(): Sfx.play("ui_move"))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func set_options(opts: Array, start := -1) -> void:
	options = opts
	if start >= 0:
		index = start
	index = clampi(index, 0, maxi(0, options.size() - 1))
	queue_redraw()


func step(dir: int) -> void:
	if options.size() < 2:
		return
	index = posmod(index + dir, options.size())
	Sfx.play("ui_move")
	_nudge = float(dir)
	if UiFx.enabled():
		create_tween().tween_method(_set_nudge, float(dir), 0.0, 0.2)
	else:
		_nudge = 0.0
	queue_redraw()
	changed.emit(index)


func _set_nudge(k: float) -> void:
	_nudge = k
	queue_redraw()


func set_lit(v: bool) -> void:
	_lit = v
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_accept"):
		step(1)
		accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		step(-1 if event.position.x < size.x * 0.5 else 1)
		grab_focus()
		accept_event()


func _draw() -> void:
	var ink := Palette.INK if _lit else Palette.PAPER
	var accent := Palette.INK if _lit else (Palette.MUSTARD if is_hovered() else Palette.PAPER_DIM)
	var mid := size.y * 0.5
	var a := 9.0
	var lx := 8.0 + minf(_nudge, 0.0) * 6.0
	var rx := size.x - 8.0 + maxf(_nudge, 0.0) * 6.0
	draw_colored_polygon(PackedVector2Array([Vector2(lx, mid), Vector2(lx + a * 1.3, mid - a), Vector2(lx + a * 1.3, mid + a)]), accent)
	draw_colored_polygon(PackedVector2Array([Vector2(rx, mid), Vector2(rx - a * 1.3, mid - a), Vector2(rx - a * 1.3, mid + a)]), accent)
	if options.is_empty():
		return
	var font := UiTheme.heavy()
	var fs := 20
	var text := str(options[index]).to_upper()
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := (size.x - w) * 0.5
	if index < swatches.size():
		var sw := 18.0
		x += (sw + 10) * 0.5
		var box := Rect2(Vector2(x - sw - 10, mid - sw * 0.5), Vector2(sw, sw))
		draw_rect(box, swatches[index])
		draw_rect(box, Palette.INK, false, 2.0)
	draw_string(font, Vector2(x, mid + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
