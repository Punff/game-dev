class_name Sandbox
extends Node2D

## "How to play": a practice level with one station per move, a target dummy
## and every block type, no lava and no way to lose. Concrete rebuilds itself
## and falling off puts you back at the station.
##
## [F3] shows live stats; the event feed (see SandboxLog) is always on and is
## also saved to user://logs/sandbox.log.
##
## It can be driven by a script for testing:
##   godot --path . res://scenes/sandbox.tscn -- --sandbox-script=<file>
## One command per line (# comments):
##   goto <station 1-6>      teleport there, standing still
##   place <x> <y>           teleport to a point (y = feet; the floor is 0)
##   tap <action>            one tick
##   hold <action> <secs>    press, wait, release
##   press / release <action>
##   wait <secs>
##   aim <x> <y>             hold the direction keys for an aim (0 releases)
##   state                   log position, velocity, cooldowns...
##   stats                   toggle the [F3] overlay
##   mark <text>             a note in the log
##   shot <file.png>         screenshot (not in --headless)
##   quit
## Actions are the game's: jump left right up down charge gravity shockwave.

const SCENE := "res://scenes/sandbox.tscn"
const FLOOR_Y := 0.0
const FALL_LIMIT := 700.0
const REBUILD_DELAY := 2.5

var background := Background.new()
var world := Node2D.new()
var camera := GameCamera.new()
var event_log: SandboxLog
var player: Player
var dummy: Player

var _stations: Array = []        # [{name, x}]
var _station := -1
var _concrete: Array = []        # [{pos, size, node, gone_at}]
var _dummy_spot := Vector2.ZERO
var _dummy_off_since := -1.0
var _profile := "kb_a"
var _time := 0.0

var _hud := CanvasLayer.new()
var _stats: Label
var _feed: VBoxContainer
var _station_label: Label


func _ready() -> void:
	MatchManager.state = MatchManager.State.PLAYING
	Player.world_half_width = 100000.0   # no side walls to fall past here
	Block.clock = 0.0
	if not Input.get_connected_joypads().is_empty():
		_profile = "pad"

	add_child(background)
	background.camera = camera
	background.set_half_width(100000.0)
	world.name = "World"
	add_child(world)
	var fx_layer := Node2D.new()
	fx_layer.z_index = 20
	world.add_child(fx_layer)
	Fx.layer = fx_layer
	Fx.reduced = Settings.get_value("reduced_effects")

	_build_level()

	PlayerManager.clear()
	var id := PlayerManager.join(Settings.DEVICE_ANY)   # any keyboard half or pad
	event_log = SandboxLog.new()
	add_child(event_log)
	_spawn_player(id, 0)

	camera.wall_half_width = INF
	add_child(camera)
	camera.targets = [player]
	camera.snap()
	_build_hud()
	event_log.logged.connect(_on_logged)
	event_log.write("START", "sandbox, %d stations" % _stations.size())

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sandbox-script="):
			_run_script.call_deferred(a.trim_prefix("--sandbox-script="))


func _exit_tree() -> void:
	PlayerManager.clear()


# ── Level ────────────────────────────────────

func _k(action: String) -> String:
	return UiTheme.key(_profile, action)


func _build_level() -> void:
	_block(StaticPlatform, Vector2(4200, FLOOR_Y + 30.0), Vector2(9600, 60))

	# 1. Moving and jumping: steps that need a jump, then a double jump.
	_add_station("Move & jump", 0, [
		"%s %s move     %s jump" % [_k("left"), _k("right"), _k("jump")],
		"Jump again in mid-air for a double jump.",
		"Jumping right next to someone shoves them."])
	_block(StaticPlatform, Vector2(420, -110), Vector2(180, 40))
	_block(StaticPlatform, Vector2(700, -270), Vector2(180, 40))

	# 2. Charge jump: a ledge a double jump can't reach.
	_add_station("Charge jump", 1150, [
		"Hold %s on the ground, let go to launch." % _k("charge"),
		"Charging keeps going if you run off a ledge.",
		"Launch, then double jump at the top to reach the ledge."])
	_block(StaticPlatform, Vector2(1600, -400), Vector2(260, 40))

	# 3. Concrete: jump off it, or fast-fall onto it from the perch.
	_add_station("Concrete", 2300, [
		"Jump off concrete and it shatters behind you.",
		"Hold %s in the air to fast-fall: land hard on concrete to smash it." % _k("down"),
		"Flying chunks hit players and break more concrete."])
	_breakable(Vector2(2560, -120), Vector2(220, 40))
	_block(StaticPlatform, Vector2(2830, -340), Vector2(160, 40))
	_breakable(Vector2(3080, -120), Vector2(260, 40))

	# 4. Gravity field: concrete on the floor to make chunks from.
	_add_station("Gravity field", 3550, [
		"Break concrete, then hold %s near the chunks." % _k("gravity"),
		"With no aim they stack into a floor under you.",
		"Aim (%s %s %s %s) and let go to throw them." % [_k("up"), _k("left"), _k("down"), _k("right")]])
	_breakable(Vector2(3830, -30), Vector2(300, 60))
	_breakable(Vector2(4180, -30), Vector2(300, 60))

	# 5. Shockwave: knock the dummy off its island.
	_add_station("Shockwave", 4750, [
		"%s fires a blast where you aim." % _k("shockwave"),
		"It knocks players back and shatters concrete.",
		"Aim down and blast to rocket-jump. Knock the dummy off!"])
	_dummy_spot = Vector2(5200, -170 - Player.RADIUS - 1)
	_block(StaticPlatform, Vector2(5150, -150), Vector2(380, 40))
	_breakable(Vector2(5550, -300), Vector2(200, 40))

	# 6. Every block type, each on its own plinth with a caption.
	_add_station("Blocks", 6000, ["Every block you'll meet on the way up. Try them all."])
	var x := 6350.0
	for entry in [
		[BouncePad, "Bounce Pad", "Launches you sky-high."],
		[SpeedBlock, "Speed Strip", "Shoots you along the arrows."],
		[ConveyorBlock, "Conveyor", "Drags you. A shockwave flips it."],
		[PushZone, "Gust", "Wind that changes direction."],
		[IceBlock, "Ice", "Slippery. Plan your stops."],
		[VanishingBlock, "Ghost", "Vanishes after you land. Comes back."],
		[MovingPlatform, "Mover", "Slides side to side."],
		[ReverseBlock, "Scrambler", "Flips left and right for a while."],
	]:
		_block(entry[0], Vector2(x, -100), Vector2(220, 40))
		var cap := _panel(Vector2(x - 120, -260), 240)
		var t := UiTheme.label(entry[1], 20, Palette.PAPER)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.get_child(0).add_child(t)
		var d := UiTheme.label(entry[2], 15, Palette.TEXT_DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cap.get_child(0).add_child(d)
		x += 330.0
	var end := _panel(Vector2(x, -330), 340)
	end.get_child(0).add_child(UiTheme.title("that's it", 34, Palette.MUSTARD))
	end.get_child(0).add_child(UiTheme.hint("Ready? [Esc] back to the menu", 18, Palette.TEXT))


func _block(type, pos: Vector2, size: Vector2) -> Block:
	var b: Block = type.new()
	b.set_block_size(size)
	b.position = pos
	world.add_child(b)
	return b


func _breakable(pos: Vector2, size: Vector2) -> void:
	var c := {"pos": pos, "size": size, "node": null, "gone_at": -1.0}
	c.node = _block(BreakableBlock, pos, size)
	_concrete.append(c)


func _add_station(title: String, x: float, lines: Array) -> void:
	_stations.append({"name": title, "x": x})
	var sign := _panel(Vector2(x - 60, -560), 520)
	var col: VBoxContainer = sign.get_child(0)
	col.add_child(UiTheme.title("%d · %s" % [_stations.size(), title], 32, Palette.MUSTARD))
	for line in lines:
		col.add_child(UiTheme.hint(line, 18, Palette.TEXT, false))


## A captioned board standing in the world.
func _panel(pos: Vector2, width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.85), Palette.SMOKE, 2, 0, Vector2(18, 12)))
	p.position = pos
	p.custom_minimum_size.x = width
	p.z_index = -1
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	p.add_child(col)
	world.add_child(p)
	return p


func _spawn_player(id: int, station: int) -> void:
	if player:
		player.queue_free()
	player = Player.new()
	player.setup(PlayerManager.players[id])
	player.position = _spawn_point(station)
	player.controls_enabled = true
	world.add_child(player)
	camera.targets = [player]
	event_log.watch(player)
	if dummy == null:
		_spawn_dummy()


func _spawn_point(station: int) -> Vector2:
	return Vector2(_stations[station].x, FLOOR_Y - Player.RADIUS - 1.0)


func _spawn_dummy() -> void:
	if dummy:
		dummy.queue_free()
	var info := PlayerInfo.new()
	info.player_id = 99
	info.color_index = 3
	dummy = Player.new()
	dummy.setup(info)
	dummy.input = PlayerInput.new(99, false)   # nobody drives it
	dummy.name_tag = "DUMMY"
	dummy.position = _dummy_spot
	dummy.facing = -1.0
	world.add_child(dummy)
	_dummy_off_since = -1.0


# ── Running ──────────────────────────────────

func _physics_process(delta: float) -> void:
	_time += delta
	Block.clock += delta

	if player.is_dead or player.global_position.y > FALL_LIMIT:
		event_log.write("RESPAWN", "fell at %s" % SandboxLog._v(player.global_position))
		_teleport(maxi(_station, 0))

	var s := 0
	for i in _stations.size():
		if player.global_position.x >= _stations[i].x - 150.0:
			s = i
	if s != _station:
		_station = s
		_station_label.text = "%d / %d   %s" % [s + 1, _stations.size(), _stations[s].name]
		event_log.write("STATION", "%d %s" % [s + 1, _stations[s].name])

	# The dummy counts as knocked off once it leaves its island.
	var off := dummy.is_dead or dummy.global_position.y > _dummy_spot.y + 40.0 \
		or absf(dummy.global_position.x - 5150.0) > 230.0
	if off and _dummy_off_since < 0.0:
		_dummy_off_since = _time
		event_log.write("DUMMY", "knocked off, flying at %s" % SandboxLog._v(dummy.velocity))
	if _dummy_off_since >= 0.0 and _time - _dummy_off_since > 2.0:
		_spawn_dummy()

	for c in _concrete:
		if is_instance_valid(c.node) and not c.node.is_queued_for_deletion():
			continue
		if c.gone_at < 0.0:
			c.gone_at = _time
		elif _time - c.gone_at > REBUILD_DELAY and not Rect2(c.pos - c.size * 0.5, c.size).grow(60).has_point(player.global_position):
			c.node = _block(BreakableBlock, c.pos, c.size)
			c.gone_at = -1.0

	if _stats.visible:
		_stats.text = _stats_text()


func _teleport(station: int) -> void:
	var id := player.player_id
	_spawn_player(id, station)
	camera.snap()


func _stats_text() -> String:
	var p := player
	return "\n".join([
		"pos      %.0f, %.0f" % [p.global_position.x, p.global_position.y],
		"vel      %.0f, %.0f" % [p.velocity.x, p.velocity.y],
		"floor    %s   jumps %d   coyote %.2f" % [p.is_on_floor(), p.jumps_left, maxf(p._coyote, 0.0)],
		"charge   %.0f%%%s" % [p._charge * 100.0, "  charging" if p._charging else ""],
		"field    %s   held %d   cd %.1f" % [p._field_active, p._held.size(), p.gravity_cd],
		"shock    cd %.1f" % p.shock_cd,
		"impact   %.0f (pound at %.0f)" % [p.last_impact, BreakableBlock.POUND_SPEED],
		"chunks   %d" % get_tree().get_nodes_in_group("fragments").size(),
		"fps      %d" % Engine.get_frames_per_second(),
	])


# ── HUD ──────────────────────────────────────

func _build_hud() -> void:
	add_child(_hud)
	var top := VBoxContainer.new()
	top.position = Vector2(24, 18)
	top.add_theme_constant_override("separation", 4)
	_hud.add_child(top)
	top.add_child(UiTheme.title("sandbox", 30, Palette.PAPER))
	_station_label = UiTheme.label("", 20, Palette.MUSTARD)
	top.add_child(_station_label)
	top.add_child(UiTheme.hint("[Esc] menu   [R] respawn   [1]-[%d] stations   [F3] stats" % _stations.size(), 16, Palette.PAPER_DIM, false))

	_stats = UiTheme.label("", 15, Palette.PAPER)
	_stats.add_theme_font_override("font", UiTheme.bold())
	_stats.visible = false
	var stats_bg := PanelContainer.new()
	stats_bg.add_theme_stylebox_override("panel", UiTheme.box(Color(Palette.INK, 0.8), Palette.SMOKE, 2, 0, Vector2(12, 8)))
	stats_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	stats_bg.offset_left = -320
	stats_bg.offset_top = 18
	stats_bg.offset_right = -20
	stats_bg.add_child(_stats)
	_hud.add_child(stats_bg)
	_stats.visibility_changed.connect(func(): stats_bg.visible = _stats.visible)
	stats_bg.visible = false

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.offset_left = 24
	_feed.offset_bottom = -18
	_feed.add_theme_constant_override("separation", 0)
	_hud.add_child(_feed)


func _on_logged(line: String) -> void:
	var l := UiTheme.label(line.strip_edges(), 15, Palette.PAPER_DIM)
	_feed.add_child(l)
	while _feed.get_child_count() > 7:
		_feed.get_child(0).free()
	for i in _feed.get_child_count():
		_feed.get_child(i).modulate.a = 0.35 + 0.65 * float(i + 1) / _feed.get_child_count()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		MatchManager.to_menu()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_R:
			_teleport(maxi(_station, 0))
		KEY_F3:
			_stats.visible = not _stats.visible
		_:
			var n: int = event.physical_keycode - KEY_1
			if n >= 0 and n < _stations.size():
				_teleport(n)


# ── Scripted runs ────────────────────────────

func _run_script(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		event_log.write("SCRIPT", "can't open %s" % path)
		get_tree().quit(1)
		return
	event_log.write("SCRIPT", path)
	for raw in f.get_as_text().split("\n"):
		var line := raw.split("#")[0].strip_edges()
		if line == "":
			continue
		var w := line.split(" ", false)
		var act := func(name: String) -> StringName: return PlayerManager.action(player.player_id, name)
		match w[0]:
			"goto":
				_teleport(int(w[1]) - 1)
				await _settle()
			"place":
				_teleport(maxi(_station, 0))
				player.global_position = Vector2(float(w[1]), float(w[2]) - Player.RADIUS - 1.0)
				event_log.watch(player)
				await _settle()
			"tap":
				Input.action_press(act.call(w[1]))
				await _ticks(1)
				Input.action_release(act.call(w[1]))
			"hold":
				Input.action_press(act.call(w[1]))
				await _ticks(roundi(float(w[2]) * 60.0))
				Input.action_release(act.call(w[1]))
			"press":
				Input.action_press(act.call(w[1]))
			"release":
				Input.action_release(act.call(w[1]))
			"wait":
				await _ticks(roundi(float(w[1]) * 60.0))
			"aim":
				var v := Vector2(float(w[1]), float(w[2]))
				for pair in [["left", v.x < 0], ["right", v.x > 0], ["up", v.y < 0], ["down", v.y > 0]]:
					if pair[1]:
						Input.action_press(act.call(pair[0]))
					else:
						Input.action_release(act.call(pair[0]))
			"stats":
				_stats.visible = not _stats.visible
			"state":
				event_log.write("STATE", event_log.state())
			"mark":
				event_log.write("MARK", line.substr(5))
			"shot":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(w[1])
				event_log.write("SHOT", w[1])
			"quit":
				break
			_:
				event_log.write("SCRIPT", "unknown command: %s" % line)
	event_log.write("SCRIPT", "done")
	get_tree().quit()


## Wait until the player stands on something (a fresh spawn is 1 px up and
## only has its air jump until it lands).
func _settle() -> void:
	for i in 30:
		await get_tree().physics_frame
		if player.is_on_floor():
			return


func _ticks(n: int) -> void:
	for i in maxi(n, 1):
		await get_tree().physics_frame
