class_name UiPage
extends VBoxContainer

## One page in a UiSleeve. Subclasses set `title` (and `teaser`, the line
## shown while it's only previewed), build their controls in build(), and
## wire their own focus. Back pops the page unless handle_back() says no;
## LB/RB step `tabs` if the page has them.

var title := ""
var teaser := ""
var sleeve: UiSleeve
## Set when the page uses tabs, so the sleeve can step them.
var tabs: UiTabs
## Colour of the stamped title (e.g. the winner's colour on Results).
var title_color := Palette.PAPER
## Size of a floating sleeve (in-game) while this page is on top.
var float_size := Vector2(860, 580)
var _built := false


## Fill the page. Called once, the first time it's shown.
func build() -> void:
	pass


## Became the top page (first time, or after the page above it closed).
func entered() -> void:
	pass


## Stopped being the top page (popped, or covered by another page).
func left() -> void:
	pass


## Key hints for the footer while this page has the input.
func hints() -> String:
	var t := "%s select     %s back" % [UiHintBar.accept_key(), UiHintBar.back_key()]
	if tabs:
		t = "%s tabs     " % UiHintBar.tab_keys() + t
	return t


## Return true to swallow Back (e.g. a sign-in screen that has to be answered).
func handle_back() -> bool:
	return false


func focus_first() -> void:
	UiNav.focus_first(self)


## The record on the main menu, if this page is in one (null in-game).
func stage() -> VinylStage:
	return sleeve.stage if sleeve else null


func push(page: UiPage) -> void:
	sleeve.push(page)


func pop() -> void:
	sleeve.pop()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	build()


## A heading inside a page (smaller than the sleeve title).
static func heading(text: String) -> Label:
	var l := UiTheme.title(text, 24, Palette.MUSTARD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


## Liner-notes copy: small, wrapping.
static func notes(text: String, color := Palette.TEXT_DIM, font_size := 18) -> Label:
	var l := UiTheme.label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## A label for status / errors that bumps when it changes.
static func say(l: Label, text: String, color := Palette.TEXT_DIM) -> void:
	l.text = text
	l.add_theme_color_override("font_color", color)
	UiFx.bump(l, 0.08)
