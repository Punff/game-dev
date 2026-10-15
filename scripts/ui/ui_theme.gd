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
		# Hard, offset ink shadow - flat graphic look, no blur.
		s.shadow_color = Palette.INK
		s.shadow_size = 0
		s.shadow_offset = Vector2(shadow, shadow)
		s.expand_margin_bottom = 0
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = bold()
	t.default_font_size = 22
	t.set_color("font_outline_color", "Label", Palette.INK)

	# Buttons: ink slabs; focus = mustard slab with black type.
	var normal := box(Palette.INK_SOFT, Palette.PAPER_DIM, 2, 0, Vector2(18, 10), 4)
	var hover := box(Palette.SMOKE, Palette.PAPER, 2, 0, Vector2(18, 10), 4)
	var focus := box(Palette.MUSTARD, Palette.INK, 3, 0, Vector2(18, 10), 6)
	var pressed := box(Palette.RUST, Palette.INK, 3, 0, Vector2(18, 10), 2)
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
		t.set_font_size("font_size", type, 24)
		t.set_font("font", type, heavy())

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(Color(Palette.INK, 0.94), Palette.PAPER, 3, 0, Vector2(30, 24), 10))
	t.set_stylebox("panel", "Panel", box(Color(Palette.INK, 0.94), Palette.PAPER, 3, 0, Vector2(0, 0), 10))

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
	return t


static func _square(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Palette.INK)
	img.fill_rect(Rect2i(3, 3, size - 6, size - 6), color)
	return ImageTexture.create_from_image(img)


## Convenience: a label with the heavy display font.
static func title(text: String, size := 64, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", title_font())
	l.add_theme_constant_override("outline_size", maxi(6, size / 8))
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


static func button(text: String, min_width := 320.0) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.custom_minimum_size = Vector2(min_width, 54)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): Sfx.play("ui_select"))
	b.focus_entered.connect(func(): Sfx.play("ui_move"))
	return b
