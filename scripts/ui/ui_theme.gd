class_name UiTheme
extends RefCounted

## Builds the global UI theme in code so every menu shares one look,
## including a strong focus style for controller navigation.

const FONT_BODY := preload("res://assets/fonts/Nunito-Regular.ttf")
const FONT_HEAVY := preload("res://assets/fonts/Nunito-Black.ttf")

static var _bold: FontVariation


static func bold() -> Font:
	if _bold == null:
		_bold = FontVariation.new()
		_bold.base_font = FONT_BODY
		_bold.variation_embolden = 0.9
	return _bold


static func heavy() -> Font:
	return FONT_HEAVY


static func box(bg: Color, border: Color = Color.TRANSPARENT, border_w := 0, radius := 12, pad := Vector2(18, 10)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = bold()
	t.default_font_size = 22

	# Buttons
	var normal := box(Palette.PANEL_HI, Palette.LINE, 2)
	var hover := box(Palette.PANEL_HI.lightened(0.08), Palette.TEXT_DIM, 2)
	var focus := box(Palette.PANEL_HI.lightened(0.1), Palette.ACCENT, 3)
	var pressed := box(Palette.ACCENT.darkened(0.25), Palette.ACCENT, 3)
	var disabled := box(Palette.PANEL.darkened(0.1), Palette.PANEL_HI, 2)
	for type in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, focus)
		t.set_color("font_color", type, Palette.TEXT)
		t.set_color("font_hover_color", type, Palette.TEXT)
		t.set_color("font_focus_color", type, Palette.ACCENT)
		t.set_color("font_pressed_color", type, Palette.BG_DEEP)
		t.set_color("font_hover_pressed_color", type, Palette.BG_DEEP)
		t.set_color("font_disabled_color", type, Palette.TEXT_DIM.darkened(0.3))
		t.set_font_size("font_size", type, 22)

	# Panels
	t.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, Palette.LINE, 2, 18, Vector2(28, 24)))
	t.set_stylebox("panel", "Panel", box(Palette.PANEL, Palette.LINE, 2, 18))

	# Labels
	t.set_color("font_color", "Label", Palette.TEXT)
	t.set_color("font_outline_color", "Label", Palette.BG_DEEP)

	# Sliders
	var track := box(Palette.BG_DEEP, Palette.LINE, 2, 6, Vector2(0, 4))
	var fill := box(Palette.ACCENT.darkened(0.15), Color.TRANSPARENT, 0, 6, Vector2(0, 4))
	var fill_focus := box(Palette.ACCENT, Color.TRANSPARENT, 0, 6, Vector2(0, 4))
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_focus)
	t.set_stylebox("focus", "HSlider", box(Color.TRANSPARENT, Palette.ACCENT, 2, 8, Vector2(4, 4)))
	t.set_icon("grabber", "HSlider", _dot(22, Palette.TEXT))
	t.set_icon("grabber_highlight", "HSlider", _dot(24, Palette.ACCENT))

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


static func _dot(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			var a := clampf(c - d + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(color, a))
	return ImageTexture.create_from_image(img)


## Convenience: a label with the heavy display font.
static func title(text: String, size := 64, color := Palette.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", heavy())
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
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 56)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): Sfx.play("ui_select"))
	b.focus_entered.connect(func(): Sfx.play("ui_move"))
	return b
