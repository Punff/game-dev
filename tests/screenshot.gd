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
	var scene: Node = load(scene_path).instantiate()
	# SHOT_FIXED renders into an offscreen 1280x720 viewport so the output
	# size doesn't depend on the window manager.
	var target: Node = get_tree().root
	if OS.get_environment("SHOT_FIXED") != "":
		_svp = SubViewport.new()
		_svp.size = Vector2i(1280, 720)
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
		"settings": scene.open_settings()
		"help": scene._on_help()
		"controls":
			scene.open_settings()
			await get_tree().process_frame
			scene.get_child(-1)._set_tab(1)
		"pause":
			await get_tree().create_timer(4.5).timeout
			scene.pause_menu.open()
		"end":
			await get_tree().create_timer(4.5).timeout
			for p in scene.players.slice(1):
				p.die()
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
		"bricks":
			# Brick walls taking local damage: P1 ground-pounds one, P2 pries
			# bricks out of another with the gravity field, then P1 blasts it.
			await get_tree().create_timer(4.0).timeout
			var walls := []
			for b in get_tree().get_nodes_in_group("blocks"):
				if b is BreakableBlock and b.size.x > 150 and b.global_position.y < -150 and b.global_position.y > -2000:
					walls.append(b)
			walls.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
			if walls.size() < 2:
				return
			var a: Block = walls[0]
			var w: Block = walls[1]
			var ps: Array = scene.players
			var top := a.global_position.y - a.size.y * 0.5 - Player.RADIUS - 1
			ps[0].global_position = Vector2(a.global_position.x - a.size.x * 0.2, top - 140)
			ps[0].velocity = Vector2(0, 1500)
			ps[1].global_position = Vector2(w.global_position.x + w.size.x * 0.5 + 60, w.global_position.y)
			scene.lava.surface_y = top + 600
			scene.camera.snap()
			Input.action_press(PlayerManager.action(2, "gravity"))
			await get_tree().create_timer(1.2).timeout
			Input.action_release(PlayerManager.action(2, "gravity"))
			ps[0].global_position = Vector2(w.global_position.x - w.size.x * 0.5 - 120, w.global_position.y)
			ps[0].velocity = Vector2.ZERO
			ps[0].facing = 1.0
			ps[0]._fire_shockwave()
		"climb":
			# Teleport players upward to preview later biomes.
			await get_tree().create_timer(4.0).timeout
			var h := float(OS.get_environment("SHOT_HEIGHT"))
			for p in scene.players:
				p.global_position.y -= h
			scene.lava.surface_y -= h - 500
