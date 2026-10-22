class_name UiSleeve
extends Control

## The record sleeve: a card that holds a stack of UiPages. Its title is
## stamped over the top edge; a breadcrumb shows how deep you are.
## push() / pop() move through pages and hand focus back where it was.
## Back on the bottom page emits backed_out (the main menu returns to the
## tracklist; a floating sleeve closes).
##
## On the main menu the sleeve can also just preview a track: title and
## liner notes, nothing to focus.

signal backed_out
signal changed

## Only reads Back / tab keys while it has the player's attention.
var active := false
const TITLE_SIZE := 64
## The vinyl stage on the main menu (pages preview cosmetics on it).
var stage: VinylStage

var _stack: Array[UiPage] = []
var _focus_memory: Array[Control] = []
var _panel := Panel.new()
var _title: Label
var _crumb: Label
var _holder := MarginContainer.new()
var _preview := VBoxContainer.new()
var _preview_text: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.theme_type_variation = "SleevePanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_holder.clip_contents = true
	for side in ["left", "right"]:
		_holder.add_theme_constant_override("margin_" + side, 34)
	_holder.add_theme_constant_override("margin_top", 58)
	_holder.add_theme_constant_override("margin_bottom", 26)
	add_child(_holder)

	_preview.add_theme_constant_override("separation", 16)
	_preview.visible = false
	_preview_text = UiPage.notes("", Palette.TEXT, 22)
	_preview_text.custom_minimum_size.x = 250
	_preview_text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_preview.add_child(_preview_text)
	_holder.add_child(_preview)

	# Stamped across the top edge, leaning out of the card.
	_title = UiTheme.title("", TITLE_SIZE, Palette.PAPER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.position = Vector2(-22, -50)
	_title.rotation_degrees = -2.5
	_title.add_theme_constant_override("outline_size", 10)
	add_child(_title)
	_crumb = UiTheme.label("", 15, Palette.MUSTARD)
	_crumb.add_theme_font_override("font", UiTheme.heavy())
	_crumb.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_crumb.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_crumb.offset_left = -400
	_crumb.offset_right = -24
	_crumb.offset_top = 16
	add_child(_crumb)
	resized.connect(_fit_title)


func top() -> UiPage:
	return _stack[-1] if not _stack.is_empty() else null


func depth() -> int:
	return _stack.size()


## Replace everything with this page.
func open(page: UiPage) -> void:
	clear()
	push(page, false)


func push(page: UiPage, remember := true) -> void:
	var owner_now := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_focus_memory.append(owner_now if remember else null)
	var below := top()
	if below:
		below.left()
		below.visible = false
	_preview.visible = false
	page.sleeve = self
	_stack.append(page)
	_holder.add_child(page)
	page._ensure_built()
	if page.tabs and not page.tabs.switched.is_connected(_on_tab):
		page.tabs.switched.connect(_on_tab)
	_show_top(true)


func pop() -> void:
	if _stack.is_empty():
		return
	var page: UiPage = _stack.pop_back()
	var restore: Control = _focus_memory.pop_back()
	page.left()
	page.queue_free()
	if _stack.is_empty():
		changed.emit()
		return
	_show_top(false)
	if is_instance_valid(restore) and restore.is_visible_in_tree():
		restore.grab_focus.call_deferred()


func clear() -> void:
	while not _stack.is_empty():
		var page: UiPage = _stack.pop_back()
		page.left()
		page.queue_free()
	_focus_memory.clear()


## Title and liner notes only (main menu, while browsing the tracklist).
func preview(title_text: String, notes_text: String) -> void:
	clear()
	_preview.visible = true
	_preview_text.text = notes_text
	_set_title(title_text, false)
	_crumb.text = ""
	changed.emit()


## Back, as if the player pressed it.
func back() -> void:
	var page := top()
	if page and page.handle_back():
		return
	Sfx.play("ui_back")
	if _stack.size() > 1:
		pop()
	else:
		backed_out.emit()


func _show_top(fresh: bool) -> void:
	var page := top()
	page.visible = true
	_set_title(page.title, fresh)
	var names: Array[String] = []
	for p in _stack:
		names.append(p.title.to_upper())
	_crumb.text = " / ".join(names) if _stack.size() > 1 else ""
	page.entered()
	if fresh:
		UiFx.reveal(page, 0.04)
		page.focus_first()
	changed.emit()


## The stamped title shrinks until it fits across the card.
func _fit_title() -> void:
	var room := size.x - 4.0
	var fs := TITLE_SIZE
	var font := UiTheme.title_font()
	while fs > 32 and font.get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
		fs -= 4
	_title.add_theme_font_size_override("font_size", fs)
	_title.position.y = -50.0 + (TITLE_SIZE - fs) * 0.75
	_title.size = Vector2.ZERO


func _on_tab(_i: int) -> void:
	changed.emit()   # hints can differ per tab


func _set_title(text: String, stamp: bool) -> void:
	var was := _title.text
	_title.text = text.to_upper()
	_fit_title()
	if stamp or was != _title.text:
		UiFx.stamp(_title, 1.25, -6.0)


func _unhandled_input(event: InputEvent) -> void:
	if not active or _stack.is_empty() or UiKeyBind.busy:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		back()
	elif top().tabs and (event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev")):
		get_viewport().set_input_as_handled()
		top().tabs.step(1 if event.is_action_pressed("ui_tab_next") else -1)


## A sleeve on its own over a dimmed screen, for in-game menus (Settings from
## Pause). Emits `closed` when backed out of; the caller frees it.
static func floating(page: UiPage) -> Floating:
	var f := Floating.new()
	f.page = page
	return f


class Floating extends Control:
	signal closed
	var sleeve := UiSleeve.new()
	var page: UiPage
	var hints := UiHintBar.new()

	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_ALWAYS
		var dim := ColorRect.new()
		dim.color = Color(Palette.BG_DEEP, 0.75)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
		add_child(sleeve)
		add_child(hints)
		sleeve.active = true
		sleeve.backed_out.connect(func(): closed.emit())
		sleeve.changed.connect(func():
			if sleeve.top():
				hints.set_hints(sleeve.top().hints()))
		resized.connect(_layout)

	func _ready() -> void:
		_layout()
		sleeve.open(page)
		UiFx.stamp(sleeve, 1.05, -1.5)

	func _layout() -> void:
		var s := Vector2(minf(860.0, size.x - 80.0), minf(580.0, size.y - 140.0))
		sleeve.size = s
		sleeve.position = ((size - s) * 0.5 + Vector2(0, 10)).floor()
		hints.position = sleeve.position + Vector2(0, s.y + 18)
