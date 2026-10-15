extends Node

## Dev helper: renders a scene and saves PNGs.
##   SHOT_SCENE=res://scenes/game.tscn SHOT_OUT=/tmp/x SHOT_PLAYERS=2 godot --path . res://tests/screenshot.tscn

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
	get_tree().root.add_child.call_deferred(scene)
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
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [out, idx])
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
		"climb":
			# Teleport players upward to preview later biomes.
			await get_tree().create_timer(4.0).timeout
			var h := float(OS.get_environment("SHOT_HEIGHT"))
			for p in scene.players:
				p.global_position.y -= h
			scene.lava.surface_y -= h - 500
