extends Node

## Persistent user settings: audio, video, gameplay feel and input bindings.
## Stored in user://settings.cfg (IndexedDB on the web build).

const SAVE_PATH := "user://settings.cfg"

const ACTIONS: Array[String] = ["jump", "left", "right", "up", "down", "charge", "gravity", "shockwave"]
const ACTION_LABELS := {
	"jump": "Jump",
	"left": "Move Left",
	"right": "Move Right",
	"up": "Aim Up",
	"down": "Aim Down / Fast Fall",
	"charge": "Charge Jump (hold)",
	"gravity": "Gravity Field (hold)",
	"shockwave": "Shockwave",
}

## Input profiles. Keyboard players use one of the two keyboard halves,
## every gamepad shares the "pad" profile (bound to its own device id).
const PROFILES: Array[String] = ["kb_a", "kb_b", "pad"]
const PROFILE_LABELS := {"kb_a": "Keyboard - Left (WASD)", "kb_b": "Keyboard - Right (Arrows)", "pad": "Gamepad"}
const SLOTS := 2

## Device ids used by PlayerManager for the two keyboard halves.
const DEVICE_KB_A := -1
const DEVICE_KB_B := -2
## An online client's single local player: both keyboard halves and every pad.
const DEVICE_ANY := -3

# Binding dictionaries: {"k": physical_keycode, "loc": KeyLocation} | {"b": button} | {"a": axis, "v": -1/1}
static func _k(code: int, loc: int = KEY_LOCATION_UNSPECIFIED) -> Dictionary: return {"k": code, "loc": loc}
static func _b(button: int) -> Dictionary: return {"b": button}
static func _a(axis: int, v: float) -> Dictionary: return {"a": axis, "v": v}

static func default_bindings() -> Dictionary:
	return {
		"kb_a": {
			"jump": [_k(KEY_W), _k(KEY_SPACE)],
			"left": [_k(KEY_A), {}],
			"right": [_k(KEY_D), {}],
			"up": [_k(KEY_W), {}],
			"down": [_k(KEY_S), {}],
			"charge": [_k(KEY_Q), _k(KEY_SHIFT, KEY_LOCATION_LEFT)],
			"gravity": [_k(KEY_E), {}],
			"shockwave": [_k(KEY_F), {}],
		},
		"kb_b": {
			"jump": [_k(KEY_UP), {}],
			"left": [_k(KEY_LEFT), {}],
			"right": [_k(KEY_RIGHT), {}],
			"up": [_k(KEY_UP), {}],
			"down": [_k(KEY_DOWN), {}],
			"charge": [_k(KEY_SHIFT, KEY_LOCATION_RIGHT), _k(KEY_L)],
			"gravity": [_k(KEY_SLASH), _k(KEY_K)],
			"shockwave": [_k(KEY_PERIOD), _k(KEY_J)],
		},
		"pad": {
			"jump": [_b(JOY_BUTTON_A), {}],
			"left": [_a(JOY_AXIS_LEFT_X, -1.0), _b(JOY_BUTTON_DPAD_LEFT)],
			"right": [_a(JOY_AXIS_LEFT_X, 1.0), _b(JOY_BUTTON_DPAD_RIGHT)],
			"up": [_a(JOY_AXIS_LEFT_Y, -1.0), _b(JOY_BUTTON_DPAD_UP)],
			"down": [_a(JOY_AXIS_LEFT_Y, 1.0), _b(JOY_BUTTON_DPAD_DOWN)],
			"charge": [_a(JOY_AXIS_TRIGGER_RIGHT, 1.0), _b(JOY_BUTTON_RIGHT_SHOULDER)],
			"gravity": [_a(JOY_AXIS_TRIGGER_LEFT, 1.0), _b(JOY_BUTTON_LEFT_SHOULDER)],
			"shockwave": [_b(JOY_BUTTON_B), _b(JOY_BUTTON_X)],
		},
	}

const DEFAULTS := {
	"master_volume": 0.8,
	"sfx_volume": 0.6,
	"fullscreen": false,
	"vsync": true,
	"screen_shake": 0.7,
	"reduced_effects": false,
	"show_fps": false,
	"deadzone": 0.3,
	"rumble": true,
	"best_height": 0,
}

var values: Dictionary = DEFAULTS.duplicate()
var bindings: Dictionary = default_bindings()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Merge into the engine default theme so Controls under CanvasLayers
	# (pause / results overlays) get it too, not just children of the root.
	var theme := UiTheme.build()
	ThemeDB.get_default_theme().merge_with(theme)
	ThemeDB.get_default_theme().default_font = theme.default_font
	ThemeDB.get_default_theme().default_font_size = theme.default_font_size
	ThemeDB.fallback_font = theme.default_font
	get_tree().root.theme = theme
	apply_all()
	_mirror_menu_keys()
	SignalBus.bindings_changed.connect(_mirror_menu_keys)


# Menus move with the left keyboard half's direction keys (WASD by default)
# as well as the arrows, so nobody has to switch hands to get around.
var _menu_key_events: Dictionary = {}   # ui action -> events we added

func _mirror_menu_keys() -> void:
	for ui in _menu_key_events:
		for ev in _menu_key_events[ui]:
			InputMap.action_erase_event(ui, ev)
	_menu_key_events.clear()
	for pair in [["ui_up", "up"], ["ui_down", "down"], ["ui_left", "left"], ["ui_right", "right"]]:
		var added: Array[InputEvent] = []
		for ev in events_for("kb_a", pair[1], -1):
			if not InputMap.action_has_event(pair[0], ev):
				InputMap.action_add_event(pair[0], ev)
				added.append(ev)
		_menu_key_events[pair[0]] = added


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant, save := true) -> void:
	values[key] = value
	apply_all()
	if save:
		save_settings()
	SignalBus.settings_changed.emit()


# ── Persistence ──────────────────────────────

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in DEFAULTS:
		var v: Variant = cfg.get_value("general", key, DEFAULTS[key])
		if typeof(v) == typeof(DEFAULTS[key]) or (typeof(DEFAULTS[key]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
			values[key] = v
	if is_web():
		values.fullscreen = false   # browsers always start windowed
	var defaults := default_bindings()
	for profile in PROFILES:
		for action in ACTIONS:
			var saved: Variant = cfg.get_value("bind_" + profile, action, null)
			if saved is Array and saved.size() == SLOTS:
				bindings[profile][action] = [_sanitize(saved[0]), _sanitize(saved[1])]
			else:
				bindings[profile][action] = defaults[profile][action].duplicate(true)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key in values:
		cfg.set_value("general", key, values[key])
	for profile in PROFILES:
		for action in ACTIONS:
			cfg.set_value("bind_" + profile, action, bindings[profile][action])
	cfg.save(SAVE_PATH)


static func _sanitize(b: Variant) -> Dictionary:
	if not b is Dictionary:
		return {}
	if b.has("k") or b.has("b") or b.has("a"):
		return b
	return {}


# ── Applying ─────────────────────────────────

func apply_all() -> void:
	_set_bus_volume("Master", values.master_volume)
	_set_bus_volume("SFX", values.sfx_volume)
	if not is_web():
		var want_fs: bool = values.fullscreen
		var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
		if want_fs != is_fs:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if want_fs else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)


func toggle_fullscreen() -> void:
	# On the web this has to happen inside an input event (user gesture),
	# so it is applied immediately instead of waiting for apply_all().
	var is_fs := DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if is_fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
	set_value("fullscreen", not is_fs)


func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, linear <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.001)))


static func is_web() -> bool:
	return OS.has_feature("web")


func record_height(meters: int) -> bool:
	if meters > int(values.best_height):
		set_value("best_height", meters)
		return true
	return false


# ── Bindings ─────────────────────────────────

func profile_for_device(device_id: int) -> String:
	match device_id:
		DEVICE_KB_A: return "kb_a"
		DEVICE_KB_B: return "kb_b"
	return "pad"


func set_binding(profile: String, action: String, slot: int, binding: Dictionary) -> void:
	bindings[profile][action][slot] = binding
	save_settings()
	SignalBus.bindings_changed.emit()


func reset_bindings(profile: String) -> void:
	bindings[profile] = default_bindings()[profile]
	save_settings()
	SignalBus.bindings_changed.emit()


## Builds InputEvents for a profile/action, bound to a specific device.
func events_for(profile: String, action: String, device_id: int) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	if device_id == DEVICE_ANY:
		for p in PROFILES:
			out.append_array(events_for(p, action, -1))
		return out
	for b in bindings[profile][action]:
		var ev := binding_to_event(b, device_id)
		if ev:
			out.append(ev)
	return out


static func binding_to_event(b: Dictionary, device_id: int = -1) -> InputEvent:
	if b.has("k"):
		var ev := InputEventKey.new()
		ev.physical_keycode = int(b.k)
		ev.location = int(b.get("loc", KEY_LOCATION_UNSPECIFIED))
		ev.device = -1
		return ev
	if b.has("b"):
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(b.b)
		ev.device = device_id
		return ev
	if b.has("a"):
		var ev := InputEventJoypadMotion.new()
		ev.axis = int(b.a)
		ev.axis_value = signf(b.v)
		ev.device = device_id
		return ev
	return null


## Converts a raw input event into a binding dictionary, or {} if unusable.
static func event_to_binding(ev: InputEvent, want_pad: bool) -> Dictionary:
	if want_pad:
		if ev is InputEventJoypadButton and ev.pressed:
			return _b(ev.button_index)
		if ev is InputEventJoypadMotion and absf(ev.axis_value) > 0.6:
			return _a(ev.axis, signf(ev.axis_value))
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		if code == 0:
			return {}
		var loc: int = ev.location if code in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META] else KEY_LOCATION_UNSPECIFIED
		return _k(code, loc)
	return {}


const PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_GUIDE: "Home", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

const PRETTY_KEYS := {"Period": ".", "Comma": ",", "Slash": "/", "Minus": "-", "Semicolon": ";",
	"Apostrophe": "'", "BracketLeft": "[", "BracketRight": "]", "Backslash": "\\", "Equal": "=", "QuoteLeft": "`"}

static func binding_label(b: Dictionary) -> String:
	if b.is_empty():
		return "-"
	if b.has("k"):
		var code := int(b.k)
		var name := OS.get_keycode_string(code)
		if not is_web() and DisplayServer.get_name() != "headless":
			var mapped := DisplayServer.keyboard_get_keycode_from_physical(code)
			if mapped != KEY_NONE:
				name = OS.get_keycode_string(mapped)
		name = PRETTY_KEYS.get(name, name)
		match int(b.get("loc", 0)):
			KEY_LOCATION_LEFT: name = "L-" + name
			KEY_LOCATION_RIGHT: name = "R-" + name
		return name if name != "" else "Key %d" % code
	if b.has("b"):
		return PAD_BUTTON_NAMES.get(int(b.b), "Button %d" % int(b.b))
	if b.has("a"):
		var v := signf(b.v)
		match int(b.a):
			JOY_AXIS_LEFT_X: return "L-Stick Left" if v < 0 else "L-Stick Right"
			JOY_AXIS_LEFT_Y: return "L-Stick Up" if v < 0 else "L-Stick Down"
			JOY_AXIS_RIGHT_X: return "R-Stick Left" if v < 0 else "R-Stick Right"
			JOY_AXIS_RIGHT_Y: return "R-Stick Up" if v < 0 else "R-Stick Down"
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Axis %d" % int(b.a)
	return "-"


## Short "primary key" label for an action, used in on-screen hints.
func action_hint(profile: String, action: String) -> String:
	for b in bindings[profile][action]:
		if not b.is_empty():
			return binding_label(b)
	return "-"
