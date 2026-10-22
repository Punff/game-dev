class_name UiTheme
extends RefCounted

## Builds the global UI theme in code so every menu shares one look,
## including a strong focus style for controller navigation.

const FONT_BODY := preload("res://assets/fonts/OpenSans-CondensedBold.ttf")
const FONT_HEAVY := preload("res://assets/fonts/OpenSans-CondensedExtraBold.ttf")
const FONT_TITLE := preload("res://assets/fonts/OpenSans-CondensedExtraBoldItalic.ttf")


static func bold() -> Font:
	return FONT_BODY


static func heavy() -> Font:
	return FONT_HEAVY


static func title_font() -> Font:
	return FONT_TITLE


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 0, pad := Vector2(18, 10), shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = radius > 0
	if shadow > 0:
		# Hard, offset ink shadow - a comic panel sitting on the page.
		# (StyleBoxFlat only draws a shadow with size >= 1; 1 px is as hard as it gets.)
		s.shadow_color = Palette.INK
		s.shadow_size = 1
		s.shadow_offset = Vector2(shadow, shadow)
	return s


## Same box, but its shadow in another colour.
static func shadowed(bg: Color, border: Color, shadow_color: Color, offset := 5) -> StyleBoxFlat:
	var s := box(bg, border, 2, 0, Vector2(18, 10), offset)
	s.shadow_color = shadow_color
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = bold()
	t.default_font_size = 22
	t.set_color("font_outline_color", "Label", Palette.INK)

	# Buttons are comic panels on a hard ink shadow. Focus peels one up into
	# a paper sticker on a mustard shadow; pressing stamps it flat into the
	# page (no shadow, nudged into where the shadow was).
	var normal := box(Palette.INK_SOFT, Palette.SMOKE, 2, 0, Vector2(18, 10), 4)
	var hover := box(Palette.SMOKE, Palette.PAPER_DIM, 2, 0, Vector2(18, 10), 4)
	var focus := shadowed(Palette.PAPER, Palette.INK, Palette.MUSTARD, 6)
	var pressed := box(Palette.MUSTARD, Palette.INK, 2, 0, Vector2(18, 10))
	pressed.expand_margin_left = -3.0
	pressed.expand_margin_right = 3.0
	pressed.expand_margin_top = -3.0
	pressed.expand_margin_bottom = 3.0
	var disabled := box(Palette.INK, Palette.SMOKE, 2)
	for type in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, Palette.PAPER)
		t.set_color("font_hover_color", type, Palette.PAPER)
		t.set_color("font_focus_color", type, Palette.INK)
		t.set_color("font_pressed_color", type, Palette.INK)
		t.set_color("font_hover_pressed_color", type, Palette.INK)
		t.set_color("font_disabled_color", type, Palette.SMOKE)
		t.set_font_size("font_size", type, 22)
		t.set_font("font", type, heavy())

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(Color(Palette.INK, 0.94), Palette.SMOKE, 2, 0, Vector2(30, 24)))
	t.set_stylebox("panel", "Panel", box(Color(Palette.INK, 0.94), Palette.SMOKE, 2, 0, Vector2(0, 0)))

	# Labels
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("font_outline_color", "Label", Palette.BG_DEEP)

	# Sliders
	var track := box(Palette.INK, Palette.PAPER_DIM, 2, 0, Vector2(0, 4))
	var fill := box(Palette.PAPER_DIM, Color.TRANSPARENT, 0, 0, Vector2(0, 4))
	var fill_focus := box(Palette.MUSTARD, Color.TRANSPARENT, 0, 0, Vector2(0, 4))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_focus)
	t.set_stylebox("focus", "HSlider", box(Color.TRANSPARENT, Palette.MUSTARD, 2, 0, Vector2(4, 4)))
	t.set_icon("grabber", "HSlider", _square(18, Palette.PAPER))
	t.set_icon("grabber_highlight", "HSlider", _square(22, Palette.MUSTARD))

	# Separators / scroll
	var sep := StyleBoxLine.new()
	sep.color = Palette.LINE
	sep.thickness = 2
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	t.set_stylebox("scroll", "VScrollBar", box(Palette.BG_DEEP, Color.TRANSPARENT, 0, 4, Vector2(4, 4)))
	t.set_stylebox("grabber", "VScrollBar", box(Palette.LINE, Color.TRANSPARENT, 0, 4, Vector2(4, 4)))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(Palette.TEXT_DIM, Color.TRANSPARENT, 0, 4, Vector2(4, 4)))

	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", box(Palette.BG_DEEP, Palette.LINE, 2, 8, Vector2(10, 6)))

	# Text fields: ink slips that get a mustard edge while you type.
	t.set_stylebox("normal", "LineEdit", box(Palette.INK, Palette.SMOKE, 2, 0, Vector2(14, 8), 4))
	t.set_stylebox("focus", "LineEdit", shadowed(Palette.INK, Palette.MUSTARD, Palette.MUSTARD, 5))
	t.set_stylebox("read_only", "LineEdit", box(Palette.INK, Palette.SMOKE, 2, 0, Vector2(14, 8)))
	t.set_color("font_color", "LineEdit", Palette.PAPER)
	t.set_color("font_placeholder_color", "LineEdit", Color(Palette.PAPER_DIM, 0.45))
	t.set_color("caret_color", "LineEdit", Palette.MUSTARD)
	t.set_color("selection_color", "LineEdit", Color(Palette.MUSTARD, 0.35))
	t.set_font("font", "LineEdit", heavy())
	t.set_font_size("font_size", "LineEdit", 22)

	_build_kit(t)
	return t


## Styles for the menu kit (scripts/ui/kit). Widgets read these by type name,
## so the whole kit restyles from here.
static func _build_kit(t: Theme) -> void:
	# Tracklist entries: bare type until focused, then the paper sticker.
	t.set_type_variation("TrackButton", "Button")
	var track_pad := Vector2(18, 4)
	var track_normal := box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, track_pad)
	track_normal.content_margin_left = 62
	var track_hover := box(Color(Palette.INK_SOFT, 0.85), Color.TRANSPARENT, 0, 0, track_pad)
	track_hover.content_margin_left = 62
	var track_focus := shadowed(Palette.PAPER, Palette.INK, Palette.MUSTARD, 6)
	track_focus.content_margin_left = 62
	var track_pressed := box(Palette.MUSTARD, Palette.INK, 2, 0, track_pad)
	track_pressed.content_margin_left = 62
	for s in ["normal", "disabled"]:
		t.set_stylebox(s, "TrackButton", track_normal)
	t.set_stylebox("hover", "TrackButton", track_hover)
	t.set_stylebox("focus", "TrackButton", track_focus)
	t.set_stylebox("pressed", "TrackButton", track_pressed)
	t.set_stylebox("hover_pressed", "TrackButton", track_pressed)
	t.set_font_size("font_size", "TrackButton", 30)
	t.set_color("font_hover_color", "TrackButton", Palette.MUSTARD)

	# The sleeve: a heavy ink card thrown on the table.
	t.set_type_variation("SleevePanel", "Panel")
	var sleeve := box(Color(Palette.INK, 0.97), Palette.PAPER, 2, 0, Vector2(34, 26), 12)
	t.set_stylebox("panel", "SleevePanel", sleeve)

	# Setting rows: a hairline underneath, a paper sticker while in use.
	var row := box(Color.TRANSPARENT, Palette.LINE, 0, 0, Vector2(14, 6))
	row.border_width_bottom = 2
	t.set_type_variation("UiRow", "PanelContainer")
	t.set_stylebox("normal", "UiRow", row)
	t.set_stylebox("panel", "UiRow", row)
	var lit := shadowed(Palette.PAPER, Palette.INK, Palette.MUSTARD, 5)
	lit.content_margin_left = 14
	lit.content_margin_right = 14
	lit.content_margin_top = 6
	lit.content_margin_bottom = 6
	t.set_stylebox("lit", "UiRow", lit)
	t.set_color("font_color", "UiRow", Palette.TEXT)
	t.set_color("font_lit_color", "UiRow", Palette.INK)

	# Sliders on a row: the row is the focus highlight.
	t.set_type_variation("RowSlider", "HSlider")
	t.set_stylebox("focus", "RowSlider", StyleBoxEmpty.new())

	# Big tiles (game modes, cosmetics).
	t.set_type_variation("CardButton", "Button")
	var card := box(Palette.INK_SOFT, Palette.SMOKE, 2, 0, Vector2(14, 14), 6)
	var card_hover := box(Palette.SMOKE, Palette.PAPER_DIM, 2, 0, Vector2(14, 14), 6)
	var card_focus := shadowed(Palette.PAPER, Palette.INK, Palette.MUSTARD, 9)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		card_focus.set_content_margin(side, 14)
	var card_pressed := box(Palette.MUSTARD, Palette.INK, 2, 0, Vector2(14, 14))
	t.set_stylebox("normal", "CardButton", card)
	t.set_stylebox("disabled", "CardButton", card)
	t.set_stylebox("hover", "CardButton", card_hover)
	t.set_stylebox("focus", "CardButton", card_focus)
	t.set_stylebox("pressed", "CardButton", card_pressed)
	t.set_stylebox("hover_pressed", "CardButton", card_pressed)

	# Widgets that draw themselves (toggle, cycler, key binds) on a row.
	t.set_type_variation("BareButton", "Button")
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(s, "BareButton", StyleBoxEmpty.new())

	# Chips: little stamped tags (rank, NEW, SOON).
	t.set_type_variation("Chip", "PanelContainer")
	t.set_stylebox("panel", "Chip", box(Palette.MUSTARD, Palette.INK, 2, 0, Vector2(8, 0), 3))

	# Tab strip under a page title.
	t.set_type_variation("TabButton", "Button")
	var tab := box(Color.TRANSPARENT, Palette.SMOKE, 0, 0, Vector2(14, 4))
	tab.border_width_bottom = 3
	var tab_on := box(Palette.MUSTARD, Palette.INK, 2, 0, Vector2(14, 4), 4)
	for s in ["normal", "disabled", "focus"]:
		t.set_stylebox(s, "TabButton", tab)
	t.set_stylebox("hover", "TabButton", box(Color(Palette.INK_SOFT, 0.9), Palette.PAPER_DIM, 0, 0, Vector2(14, 4)))
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_font_size("font_size", "TabButton", 19)
	t.set_color("font_color", "TabButton", Palette.PAPER_DIM)
	t.set_color("font_pressed_color", "TabButton", Palette.INK)
	t.set_color("font_hover_pressed_color", "TabButton", Palette.INK)
	t.set_color("font_focus_color", "TabButton", Palette.PAPER_DIM)


static func _square(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Palette.INK)
	img.fill_rect(Rect2i(3, 3, size - 6, size - 6), color)
	return ImageTexture.create_from_image(img)


## Convenience: a label with the heavy display font. Big ones (headlines)
## use the italic cut, leaning forward like a comic sound effect.
static func title(text: String, size := 64, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", title_font() if size >= 48 else heavy())
	l.add_theme_constant_override("outline_size", maxi(4, size / 12))
	l.add_theme_color_override("font_outline_color", Palette.INK)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func label(text: String, size := 20, color := Palette.TEXT_DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A key drawn as a little paper cap, e.g. keycap("W").
static func keycap(key: String, size := 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(Palette.PAPER, Palette.INK, 2, 3, Vector2(7, 1)))
	var l := label(key, size, Palette.INK)
	l.add_theme_font_override("font", heavy())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size.x = size * 0.7
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## A row of text with [Key] tokens drawn as key caps:
## hint("[W] jump   [A] [D] move").
static func hint(text: String, size := 18, color := Palette.TEXT_DIM, center := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if center:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
	var re := RegEx.create_from_string("\\[([^\\]]+)\\]")
	var at := 0
	for m in re.search_all(text):
		_hint_text(row, text.substr(at, m.get_start() - at), size, color)
		row.add_child(keycap(m.get_string(1), size - 2))
		at = m.get_end()
	_hint_text(row, text.substr(at), size, color)
	return row


# Plain text between key caps; a run of 2+ spaces becomes a wider gap.
static func _hint_text(row: HBoxContainer, s: String, size: int, color: Color) -> void:
	var gap := func():
		var g := Control.new()
		g.custom_minimum_size.x = size * 0.9
		row.add_child(g)
	if s.begins_with("  ") and row.get_child_count() > 0:
		gap.call()
	if s.strip_edges() != "":
		row.add_child(label(s.strip_edges(), size, color))
	if s.ends_with("  ") and s.strip_edges() != "":
		gap.call()


## "[W]" for a profile's first binding of an action, ready for hint().
static func key(profile: String, action: String) -> String:
	return "[%s]" % Settings.action_hint(profile, action).replace("L-Stick ", "").replace("D-Pad ", "")


static func button(text: String, min_width := 320.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 50)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): Sfx.play("ui_select"))
	b.focus_entered.connect(func(): Sfx.play("ui_move"))
	UiFx.wire_button(b)
	return b
