extends Node

## Dev helper: renders a scene and saves PNGs.
##   SHOT_SCENE=res://scenes/game.tscn SHOT_OUT=/tmp/x SHOT_PLAYERS=2 godot --path . res://tests/screenshot.tscn

var _svp: SubViewport


func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	var out := OS.get_environment("SHOT_OUT")
	var players := OS.get_environment("SHOT_PLAYERS").to_int()
	var times := OS.get_environment("SHOT_TIMES").split(",", false)
	if times.is_empty():
		times = ["1.5"]
	var devices := [Settings.DEVICE_KB_A, Settings.DEVICE_KB_B, 0, 1]
	for i in players:
		var id := PlayerManager.join(devices[i])
		if OS.get_environment("SHOT_READY") != "":
			PlayerManager.players[id].is_ready = i % 2 == 0
	var login := OS.get_environment("SHOT_LOGIN").split(":")   # user:password, against --signaling
	if login.size() == 2:
		var done := [false]
		Stats.login(login[0], login[1], func(_ok, _e): done[0] = true)
		while not done[0]:
			await get_tree().process_frame
	if OS.get_environment("SHOT_ACTION") == "room":
		# Online lobby as a room host, with a made-up code (it leaves for the
		# menu if it opens offline, so this goes first).
		Net.host()
		Net.room_code = "FKLT8"
	var scene: Node = load(scene_path).instantiate()
	# SHOT_FIXED renders into an offscreen 1280x720 viewport so the output
	# size doesn't depend on the window manager.
	var target: Node = get_tree().root
	if OS.get_environment("SHOT_FIXED") != "":
		_svp = SubViewport.new()
		_svp.size = Vector2i(1280, 720)
		var want := OS.get_environment("SHOT_SIZE").split("x")   # e.g. SHOT_SIZE=1680x720
		if want.size() == 2:
			_svp.size = Vector2i(want[0].to_int(), want[1].to_int())
		_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(_svp)
		_svp.add_child(load("res://scripts/core/grit.gd").new())   # the global overlay lives outside
		target = _svp
	target.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	var action := OS.get_environment("SHOT_ACTION")
	if action != "":
		_do_action(scene, action)
	var elapsed := 0.0
	var idx := 0
	for t in times:
		await get_tree().create_timer(float(t) - elapsed).timeout
		elapsed = float(t)
		await RenderingServer.frame_post_draw
		var vp: Viewport = _svp if _svp else get_viewport()
		vp.get_texture().get_image().save_png("%s_%d.png" % [out, idx])
		idx += 1
	get_tree().quit()


func _do_action(scene: Node, action: String) -> void:
	match action:
		# Main menu (UiShell): open a track, or a page inside one.
		"play", "settings", "leaderboard", "profile", "friends": scene.choose(action)
		"online":
			scene.choose("play")
			scene.sleeve.top().open_online()
		"customise":
			scene.choose("profile")
			scene.sleeve.top().tabs.show_tab(1)
		"signin":
			scene.choose("profile")
			scene.sleeve.top().push(SignInPage.new())
		"gate": scene._show_gate()
		"browse": scene.tracklist.track("leaderboard").grab_focus.call_deferred()
		"room":
			scene._refresh()
		"controls":
			scene.choose("settings")
			scene.sleeve.top().tabs.show_tab(3)
		"pause_settings":
			await get_tree().create_timer(4.5).timeout
			scene.pause_menu.open()
			scene.pause_menu.page.push(SettingsPage.new())
		"pause":
			await get_tree().create_timer(4.5).timeout
			scene.pause_menu.open()
		"end":
			await get_tree().create_timer(4.5).timeout
			for p in scene.players.slice(1):
				p.die()
		"solo_end":
			await get_tree().create_timer(4.5).timeout
			scene.players[0].die()
		"lava":
			# Lava right under the players, then one falls in and one is knocked off.
			await get_tree().create_timer(4.5).timeout
			scene.lava.surface_y = scene.players[0].global_position.y + 70.0
			await get_tree().create_timer(1.0).timeout
			scene.players[1].global_position.y = scene.lava.surface_y + 2.0
			scene.players[2].global_position.x = 2000.0
		"crown":
			# Four players; P2 climbs above the rest, then two fall in the lava.
			await get_tree().create_timer(4.5).timeout
			scene.lava.surface_y = scene.players[0].global_position.y + 90.0
			scene.players[1].velocity.y = -700.0
			await get_tree().create_timer(1.2).timeout
			scene.players[2].global_position.y = scene.lava.surface_y + 2.0
			scene.players[3].global_position.y = scene.lava.surface_y + 2.0
		"split":
			# Couch split screen: P2 floats away up and to the side, the view splits, then they come back.
			await get_tree().create_timer(4.0).timeout
			var ps: Array = scene.players
			for p in ps:
				p.set_physics_process(false)
			var from: Vector2 = ps[1].global_position
			var t := 0.0
			while t < 6.0:
				await get_tree().physics_frame
				t += get_physics_process_delta_time()
				var k := t / 3.0 if t < 3.0 else (6.0 - t) / 3.0
				ps[1].global_position = from + Vector2(700, -2600) * k
				if ps.size() > 2:
					ps[2].global_position = from + Vector2(-700, -1300) * k
				scene.lava.surface_y = 650.0
		"catchup":
			# The first catch-up pad, dead, then lit once P1 climbs past it.
			await get_tree().create_timer(4.0).timeout
			var pads := get_tree().get_nodes_in_group("blocks").filter(func(b): return b is CatchupPad)
			if pads.is_empty():
				return
			pads.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
			var pad: CatchupPad = pads[0]
			var ps: Array = scene.players
			for p in ps:
				p.set_physics_process(false)
			ps[1].global_position = pad.global_position + Vector2(-40, -Block.HEIGHT * 0.5 - Player.RADIUS - 1)
			ps[0].global_position = pad.global_position + Vector2(260, -120)
			scene.lava.surface_y = pad.global_position.y + 900.0
			scene.camera.snap()
			await get_tree().create_timer(1.0).timeout
			ps[0].global_position.y = pad.global_position.y - CatchupPad.PAD_ARM - 60.0
			ps[0].max_height_px = ps[0].spawn_y - ps[0].global_position.y
		"blast":
			# Shatter nearby concrete and fire a shockwave to preview debris.
			await get_tree().create_timer(4.2).timeout
			var c: Vector2 = scene.camera.get_screen_center_position()
			for b in get_tree().get_nodes_in_group("destructible") + get_tree().get_nodes_in_group("blocks"):
				if b is BreakableBlock and b.global_position.distance_to(c) < 700:
					b.break_apart(c + Vector2(0, 300), 300.0)
			scene.players[0]._fire_shockwave()
			scene.players[1]._field_active = true
		"brawl":
			# Staged mid-climb scrap for store-page shots, driven by real inputs.
			await get_tree().create_timer(4.0).timeout
			var cands := []
			for b in get_tree().get_nodes_in_group("blocks"):
				if b.size.x > 200 and b.global_position.y < -380 and b.global_position.y > -1000 and not b is BreakableBlock:
					cands.append(b)
			cands.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
			var base: Block = cands[0] if not cands.is_empty() else null
			if base:
				var top := base.global_position.y - base.size.y * 0.5 - Player.RADIUS - 1
				var ps: Array = scene.players
				ps[0].global_position = Vector2(base.global_position.x - base.size.x * 0.3, top)
				ps[1].global_position = Vector2(base.global_position.x + base.size.x * 0.15, top)
				if ps.size() > 2:
					ps[2].global_position = Vector2(base.global_position.x + 260, top - 170)
				scene.lava.surface_y = top + 520
				scene.camera.snap()
				for b in get_tree().get_nodes_in_group("blocks"):
					if b is BreakableBlock and b.global_position.distance_to(base.global_position) < 650:
						b.break_apart(b.global_position + Vector2(0, 80), 160.0)
			await get_tree().create_timer(0.5).timeout
			Input.action_press(PlayerManager.action(2, "gravity"))
			Input.action_press(PlayerManager.action(1, "right"))
			await get_tree().create_timer(0.45).timeout
			Input.action_release(PlayerManager.action(1, "right"))
			Input.action_press(PlayerManager.action(1, "shockwave"))
			await get_tree().create_timer(0.05).timeout
			Input.action_release(PlayerManager.action(1, "shockwave"))
			if scene.players.size() > 2:
				Input.action_press(PlayerManager.action(3, "jump"))
		"field":
			# P1 jumps off a concrete block and holds the gravity field: the
			# shards should pack into a floor under them.
			await get_tree().create_timer(4.0).timeout
			var cands := []
			for b in get_tree().get_nodes_in_group("blocks"):
				if b is BreakableBlock and b.size.x > 220 and b.global_position.y < -150:
					cands.append(b)
			cands.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
			if cands.is_empty():
				return
			var blk: Block = cands[0]
			var p: Player = scene.players[0]
			p.global_position = blk.global_position - Vector2(0, blk.size.y * 0.5 + Player.RADIUS + 1)
			scene.lava.surface_y = blk.global_position.y + 700
			scene.camera.snap()
			await get_tree().physics_frame
			await get_tree().physics_frame
			Input.action_press(PlayerManager.action(1, "jump"))
			for i in 4:
				await get_tree().physics_frame
			Input.action_release(PlayerManager.action(1, "jump"))
			Input.action_press(PlayerManager.action(1, "gravity"))
		"climb":
			# Teleport players upward to preview later biomes.
			await get_tree().create_timer(4.0).timeout
			var h := float(OS.get_environment("SHOT_HEIGHT"))
			for p in scene.players:
				p.global_position.y -= h
			scene.lava.surface_y -= h - 500
