extends Node

## Online smoke test. Start a server, then one or more bots:
##   godot --headless --path . -- --server
##   godot --headless --path . res://tests/net_bot.tscn -- --url=ws://127.0.0.1:7777
## Add --host to have the bot host and play instead of joining.
## Rooms (WebRTC): --room=create --code-file=<f> makes a room and writes its
## code to <f>; --room=<f> waits for that file and joins the code in it.
## Point at a local signaling service with --signaling=ws://127.0.0.1:8787.
## --wait-players=N: don't ready up until N players are in (e.g. waiting
## for a person in a browser to join).
## --smash (on the hosting bot) breaks a few blocks one second into the match,
## so the guests can check that debris reaches them.
## Run a bot without --headless and add --shot=<file.png> to save what it
## sees a couple of seconds into the match.
## Each bot joins, readies up, mashes random controls through a whole match
## and checks that snapshots moved its ball, the results arrived and the
## server reopened the lobby. Exit code 0 = pass.

func _ready() -> void:
	# Scene changes free the current scene, so the bot lives beside it.
	var bot := Bot.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--url="):
			bot.url = a.trim_prefix("--url=")
		elif a.begins_with("--name="):
			bot.tag = a.trim_prefix("--name=")
		elif a == "--host":
			bot.hosting = true
		elif a.begins_with("--room="):
			bot.room = a.trim_prefix("--room=")
		elif a.begins_with("--wait-players="):
			bot.wait_players = int(a.trim_prefix("--wait-players="))
		elif a == "--smash":
			bot.smash = true
		elif a.begins_with("--code-file="):
			bot.code_file = a.trim_prefix("--code-file=")
		elif a.begins_with("--shot="):
			bot.shot = a.trim_prefix("--shot=")
	get_tree().root.add_child.call_deferred(bot)


class Bot extends Node:
	const TIMEOUT := 160.0

	var url := Net.DEFAULT_ADDRESS
	var tag := "bot"
	var shot := ""
	var hosting := false
	var room := ""          ## "create", or a file holding the code to join
	var code_file := ""
	var smash := false
	var wait_players := 0
	var _game_time := 0.0
	var _t := 0.0
	var _joined := false
	var _readied := false
	var _start := Vector2.INF
	var _moved := 0.0
	var _last := Vector2.INF
	var _max_frags := 0
	var _max_peers_seen := 0
	var _results := {}
	var _next_mash := 0.0
	var _rng := RandomNumberGenerator.new()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_rng.seed = hash(tag)
		SignalBus.match_ended.connect(func(r): _results = r)

	func _physics_process(delta: float) -> void:
		_t += delta
		if _t > TIMEOUT:
			_finish(false, "timed out (state %s, status '%s')" % [MatchManager.State.keys()[MatchManager.state], Net.status])
			return
		if not _joined and _t > 0.3:
			_joined = true
			MatchManager.state = MatchManager.State.LOBBY   # as if we came through the menu
			if room == "create":
				Net.create_room()
			elif room != "":
				_joined = false   # keep trying until the host has written the code
				if FileAccess.file_exists(room):
					var code := FileAccess.get_file_as_string(room).strip_edges()
					if code != "":
						_joined = true
						Net.join_room(code)
			elif hosting:
				Net.host()
			else:
				Net.join(url)
		if room == "create" and code_file != "" and Net.room_code != "":
			var f := FileAccess.open(code_file, FileAccess.WRITE)
			f.store_string(Net.room_code)
			f.close()
			code_file = ""
		var me := Net.local_info()
		if me and not _readied and MatchManager.state == MatchManager.State.LOBBY 				and PlayerManager.players.size() >= wait_players:
			_readied = true
			_max_peers_seen = maxi(_max_peers_seen, PlayerManager.players.size())
			# Give other bots a moment to join before everyone is ready.
			get_tree().create_timer(4.0 if hosting or room == "create" else 2.0).timeout.connect(func(): Net.ask_ready(true))
		if me:
			_max_peers_seen = maxi(_max_peers_seen, PlayerManager.players.size())
		if Net.game and is_instance_valid(Net.game) and me:
			_play(me, delta)
		if not _results.is_empty() and MatchManager.state == MatchManager.State.LOBBY:
			_finish(_moved > 50.0, "")

	func _play(me: PlayerInfo, _delta: float) -> void:
		var p: Player = Net.game.player_by_id(me.player_id)
		if p == null:
			return
		if _start == Vector2.INF:
			_start = p.global_position
			_last = _start
		_moved += p.global_position.distance_to(_last)
		_last = p.global_position
		_max_frags = maxi(_max_frags, get_tree().get_nodes_in_group("fragments").size())
		_game_time += _delta
		if smash and Net.is_server() and _game_time > 1.0:
			smash = false
			var n := 0
			for b in get_tree().get_nodes_in_group("blocks"):
				if b is BreakableBlock and n < 3:
					b.break_apart(b.global_position, 300.0)
					n += 1
		if shot != "" and _game_time > 5.5:
			get_viewport().get_texture().get_image().save_png(shot)
			shot = ""
		if _t >= _next_mash:
			_next_mash = _t + _rng.randf_range(0.1, 0.4)
			for a in Settings.ACTIONS:
				var act := PlayerManager.action(me.player_id, a)
				if _rng.randf() < (0.6 if a in ["shockwave", "down", "right"] else 0.3):
					Input.action_press(act)
				else:
					Input.action_release(act)

	func _finish(ok: bool, why: String) -> void:
		set_physics_process(false)
		print("[%s] %s  players seen: %d  ball moved: %d px  most chunks: %d  winner: %s  %s" % [
			tag, "PASS" if ok else "FAIL", _max_peers_seen, int(_moved), _max_frags,
			str(_results.get("winner", "?")), why])
		var t0 := Time.get_ticks_msec()
		Net.leave()
		print("[%s] left in %d ms" % [tag, Time.get_ticks_msec() - t0])
		get_tree().quit(0 if ok else 1)
