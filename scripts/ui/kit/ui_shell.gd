class_name UiShell
extends Control

## The main menu, laid out like a record on the table: the tracklist on the
## left, the player's ball spinning on a record in the middle, and the sleeve
## on the right holding whichever page is open. Browsing the tracklist only
## previews a page in a narrow sleeve resting at the side; opening one slides
## the sleeve in over the record. Back from the sleeve's first page returns
## to the tracklist.
##
## First launch (no account, never chose to play as a guest): only the record
## and a sign-in page, until the player answers it.

const TRACKS := [
	{"id": "play", "side": "A", "text": "Play", "biome": 0,
		"notes": "Climb alone, with friends on one screen, or online with a room code."},
	{"id": "profile", "side": "A", "text": "Profile", "biome": 2,
		"notes": "Your ball, your account and your numbers. Cosmetics are coming here."},
	{"id": "leaderboard", "side": "A", "text": "Leaderboard", "biome": 1,
		"notes": "The highest solo climbs and the most online wins."},
	{"id": "howto", "side": "B", "text": "How to play",
		"notes": "A practice level with every move explained. Nothing can hurt you there."},
	{"id": "settings", "side": "B", "text": "Settings", "biome": 3,
		"notes": "Sound, screen, controls and key bindings."},
	{"id": "quit", "side": "B", "text": "Quit",
		"notes": "Lift the needle. See you on the next climb."},
]
const MARGIN := 56.0
const LIST_W := 300.0
const REST_W := 340.0    ## width of the resting sleeve (previews only)

## Page to come back to after leaving a screen, e.g. "online" when the online
## lobby gives up on a connection. Read once by the next shell.
static var resume := ""

var tracklist := UiTracklist.new()
var stage := VinylStage.new()
var sleeve := UiSleeve.new()
var hint_bar := UiHintBar.new()
var _bg := Background.new()
var _title: Label
var _tagline: Label
var _version: Label
var _list_box := Control.new()
var _open := false
var _open_t := 0.0       # 0 = sleeve resting, 1 = sleeve in front
var _intro := 0.0        # 0 -> 1 as the screen first comes in
var _sky := 0.0
var _previewing := ""
var _gate: SignInPage


func _ready() -> void:
	MatchManager.state = MatchManager.State.MENU
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.auto_scroll = 30.0
	add_child(_bg)

	stage.player_name = ""
	add_child(stage)
	sleeve.stage = stage
	add_child(sleeve)

	_title = UiTheme.title("ultimate cakum pakum", 54, Palette.PAPER)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.position = Vector2(MARGIN, 26)
	add_child(_title)
	_tagline = UiTheme.label("Climb. Wreck the route behind you. Outlast the slag.", 20, Palette.MUSTARD)
	_tagline.position = Vector2(MARGIN + 4, 98)
	add_child(_tagline)

	_list_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list_box)
	tracklist.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tracklist.alignment = BoxContainer.ALIGNMENT_CENTER
	_list_box.add_child(tracklist)
	var side := ""
	for t in TRACKS:
		if t.side != side:
			side = t.side
			tracklist.add_side(side)
		var track := tracklist.add_track(t.id, t.text)
		if t.id == "quit" and Settings.is_web():
			track.visible = false
	tracklist.relink()
	tracklist.previewed.connect(_on_previewed)
	tracklist.chosen.connect(choose)

	add_child(hint_bar)
	_version = UiTheme.label("v%s" % ProjectSettings.get_setting("application/config/version"), 15, Palette.PAPER_DIM)
	add_child(_version)

	sleeve.backed_out.connect(_back_to_list)
	sleeve.changed.connect(_update_hints)
	sleeve.gui_input.connect(_on_sleeve_click)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	Stats.account_changed.connect(_refresh_player)
	resized.connect(_layout)
	_refresh_player()

	if Settings.logged_in() or Settings.get_value("onboarded"):
		_enter_menu()
	else:
		_show_gate()
	_play_intro()


func _play_intro() -> void:
	UiFx.stamp(_title, 1.25, -4.0)
	if not UiFx.enabled():
		_intro = 1.0
		_layout()
		return
	var tw := create_tween()
	tw.tween_method(func(k: float):
		_intro = k
		_layout(), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enter_menu() -> void:
	tracklist.visible = true
	var i := 0
	for t in tracklist.tracks:
		UiFx.reveal(t, 0.12 + i * 0.05)
		i += 1
	if resume == "online":
		resume = ""
		choose("play")
		(sleeve.top() as PlayPage).open_online()
	else:
		_back_to_list(false)


# ── Gate ─────────────────────────────────────

func _show_gate() -> void:
	tracklist.visible = false
	_gate = SignInPage.new()
	_gate.gate = true
	_gate.done.connect(_finish_gate)
	sleeve.open(_gate)
	_set_open(true)


func _finish_gate() -> void:
	_gate = null
	stage.hop()
	_enter_menu()


# ── Tracks ───────────────────────────────────

func _on_previewed(id: String) -> void:
	_previewing = id
	var t := _track_info(id)
	if _open:
		_set_open(false)
	sleeve.preview(t.text, t.notes)
	_tint(t)
	_update_hints()


## Open a track: a page in the sleeve, or an action (How to play, Quit).
func choose(id: String) -> void:
	var t := _track_info(id)
	_tint(t)
	match id:
		"howto":
			MatchManager.goto(Sandbox.SCENE)
			return
		"quit":
			get_tree().quit()
			return
	stage.hop()
	tracklist.set_current(id)
	sleeve.open(_make_page(id))
	_set_open(true)


func _make_page(id: String) -> UiPage:
	match id:
		"play": return PlayPage.new()
		"profile": return ProfilePage.new()
		"leaderboard": return LeaderboardPage.new()
		"settings": return SettingsPage.new()
	return UiPage.new()


func _back_to_list(wobble := true) -> void:
	if wobble:
		stage.wobble()
	var id := tracklist.tracks[0].id
	for t in tracklist.tracks:
		if t.current:
			id = t.id
	tracklist.set_current("")
	_set_open(false)
	var track := tracklist.track(id)
	track.grab_focus.call_deferred()
	_on_previewed(id)


func _track_info(id: String) -> Dictionary:
	for t in TRACKS:
		if t.id == id:
			return t
	return TRACKS[0]


# ── State and layout ─────────────────────────

func _set_open(on: bool) -> void:
	_open = on
	sleeve.active = on
	_update_hints()
	var target := 1.0 if on else 0.0
	if not UiFx.enabled() or not is_inside_tree():
		_open_t = target
		_layout()
		return
	var tw := create_tween()
	tw.tween_method(func(k: float):
		_open_t = k
		_layout(), _open_t, target, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _layout() -> void:
	var s := size
	if s.x <= 0.0:
		return
	var t := _open_t
	var top := 140.0
	var sw := clampf(s.x * 0.46, 570.0, 780.0)
	var open_x := s.x - MARGIN - sw
	var home_x := s.x - MARGIN - REST_W
	var x := lerpf(home_x, open_x, t) + (1.0 - _intro) * 420.0
	sleeve.position = Vector2(x, top)
	sleeve.size = Vector2(lerpf(REST_W, sw, t), s.y - top - 86.0)
	sleeve.pivot_offset = Vector2.ZERO
	sleeve.rotation_degrees = lerpf(2.5, 0.0, t)

	# The record fills the gap at rest, and slides under the sleeve when open.
	var left := MARGIN + LIST_W + 30.0
	var cy := s.y * 0.48
	var r_home := clampf(minf((home_x - left) * 0.5 - 30.0, (s.y - 280.0) * 0.5), 110.0, 240.0)
	var c_home := Vector2((left + home_x) * 0.5, cy)
	var r_open := clampf(minf((open_x - left) / 1.5, s.y * 0.24), 90.0, 200.0)
	var c_open := Vector2(maxf(left + r_open, open_x - r_open * 0.5), cy)
	stage.radius = lerpf(r_home, r_open, t) * lerpf(0.6, 1.0, _intro)
	stage.center = c_home.lerp(c_open, t)

	_list_box.position = Vector2(MARGIN, 150.0)
	_list_box.size = Vector2(LIST_W + 40.0, s.y - 150.0 - 80.0)
	hint_bar.position = Vector2(MARGIN, s.y - 50.0)
	_version.position = Vector2(s.x - MARGIN - 60.0, s.y - 46.0)


# ── Input and focus ──────────────────────────

func _on_focus_changed(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	if sleeve.is_ancestor_of(c) and not _open:
		_set_open(true)   # the mouse went straight into the sleeve


func _on_sleeve_click(ev: InputEvent) -> void:
	if not _open and _previewing != "" and ev is InputEventMouseButton and ev.pressed \
			and ev.button_index == MOUSE_BUTTON_LEFT:
		choose(_previewing)


func _update_hints() -> void:
	if _open and sleeve.top():
		hint_bar.set_hints(sleeve.top().hints())
	else:
		var nav := "[D-Pad]" if UiHintBar.pad_active() else "%s %s" % [UiTheme.key("kb_a", "up"), UiTheme.key("kb_a", "down")]
		hint_bar.set_hints("%s choose     %s open" % [nav, UiHintBar.accept_key()])


func _tint(t: Dictionary) -> void:
	if not t.has("biome"):
		return
	var to: float = MapPlanner.BIOMES[t.biome].from + 1.0
	var tw := create_tween()
	tw.tween_method(func(h: float):
		_sky = h
		_bg.set_height(h), _sky, to, 0.9).set_trans(Tween.TRANS_SINE)


func _refresh_player() -> void:
	stage.look = BallPortrait.my_look()
	stage.player_name = Settings.player_name().to_upper() if Settings.logged_in() else "GUEST"
	stage.rank_text = ""
	if not Settings.logged_in() or not Stats.enabled():
		return
	Stats.leaderboard("height", func(ok: bool, reply: Dictionary):
		var me: Variant = reply.get("me")
		if ok and is_inside_tree() and me is Dictionary and me.has("rank"):
			stage.rank_text = "#%d" % int(me.rank))
