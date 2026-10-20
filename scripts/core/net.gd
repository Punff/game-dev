extends Node

## Online play. One process is the server and runs the real simulation;
## everyone else is a client that sends its controls and draws the snapshots
## it gets back. Two ways to connect:
##
## - Rooms (WebRTC, works between browsers anywhere): a player creates a room,
##   their game hosts it, friends join with the room code. The signaling
##   service in signaling/ only introduces them (see RoomLink).
## - Direct (WebSocket): a headless dedicated server
##   (`godot --headless --path . -- --server [--port=7777]`) or a desktop
##   player who picks Host; others join by address. Handy on a LAN.
##
## All RPCs live on this autoload so their node path is the same on every
## peer, whichever scene is loaded.

signal roster_changed
signal status_changed

enum Mode { OFFLINE, SERVER, CLIENT }

const DEFAULT_PORT := 7777
const DEFAULT_ADDRESS := "ws://127.0.0.1:7777"
## Where the room service lives once deployed (see signaling/README.md).
## Override with `-- --signaling=<url>`, or `?signaling=<url>` on the web page.
const SIGNALING_URL := "wss://cakum-pakum-signaling.cakum-pakum-signaling.workers.dev"
const PROTOCOL := 1
const ONLINE_LOBBY := "res://scenes/online_lobby.tscn"
const SNAPSHOT_EVERY := 2          ## physics ticks between snapshots (30 Hz at 60)
const RETURN_TO_LOBBY := 6.0       ## seconds the results stay up before the lobby reopens
const INPUT_KEEPALIVE := 0.5
const ROOM_CONNECT_TIMEOUT := 15.0  ## seconds a guest waits for the direct link to the host
const NO_DIRECT := "Couldn't connect to the host directly. Try another network, or let someone else host."

var mode := Mode.OFFLINE
var dedicated := false
var match_seed := 0
var status := ""                   ## last connection message for the lobby screen
var address := DEFAULT_ADDRESS
var signaling_url := SIGNALING_URL
var room_code := ""                ## set while in a WebRTC room
var game: Node = null              ## the running game scene (game.gd registers itself)

var _peer: MultiplayerPeer
var _room: RoomLink
var _tick := 0
var _next_id := 0
var _sent_input := {}              # player_id -> [buttons, move, time sent]
var _gone_peers: Array[int] = []   # disconnected mid-match, pruned on return to the lobby
var _blocks_broken := 0            # per match, for the server log
var _room_wait := 0.0              # guest: time spent connecting to the host


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _drop(NO_DIRECT if _room else "Couldn't reach the server."))
	multiplayer.server_disconnected.connect(func(): _drop("The host left the room." if _room else "Disconnected from the server."))
	SignalBus.match_ended.connect(_on_match_ended)
	SignalBus.block_broken.connect(func(_p): _blocks_broken += 1)
	SignalBus.screen_shake_requested.connect(_on_shake)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--signaling="):
			signaling_url = a.trim_prefix("--signaling=")
	if Settings.is_web():
		var from_page: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('signaling') || ''")
		if from_page is String and from_page != "":
			signaling_url = from_page
	if "--server" in args:
		var port := DEFAULT_PORT
		for a in args:
			if a.begins_with("--port="):
				port = int(a.trim_prefix("--port="))
		_start_dedicated.call_deferred(port)


func _start_dedicated(port: int) -> void:
	var err := host(port, false)
	print("Server ", "listening on port %d" % port if err == OK else "failed to start: %s" % error_string(err))
	if err == OK:
		MatchManager.state = MatchManager.State.LOBBY
		MatchManager.goto(ONLINE_LOBBY)


# ── Queries ──────────────────────────────────

func is_online() -> bool: return mode != Mode.OFFLINE
func is_server() -> bool: return mode == Mode.SERVER
func is_client() -> bool: return mode == Mode.CLIENT

func my_peer() -> int:
	# While a room is still opening we're online but have no peer yet.
	return multiplayer.get_unique_id() if is_online() and multiplayer.has_multiplayer_peer() else 0


static func can_host() -> bool:
	return not Settings.is_web()   # browsers can't listen for direct connections


func in_room() -> bool:
	return _room != null


# ── Connecting ───────────────────────────────

## Start a server. With a local player the host plays too (desktop "Host").
func host(port := DEFAULT_PORT, local_player := true) -> Error:
	leave()
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_server(port)
	if err != OK:
		_set_status("Couldn't host on port %d (%s)." % [port, error_string(err)])
		return err
	_become_server(ws, local_player)
	_set_status("Hosting on port %d." % port)
	return OK


func _become_server(peer: MultiplayerPeer, local_player: bool) -> void:
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	mode = Mode.SERVER
	dedicated = not local_player
	PlayerManager.clear()
	if local_player:
		var id := PlayerManager.join(Settings.DEVICE_ANY)
		PlayerManager.players[id].peer_id = 1
	_broadcast_roster()


## Open a WebRTC room and host it from this game (works in the browser).
func create_room() -> void:
	_open_room(true, "")


## Join a friend's room by its code.
func join_room(code: String) -> void:
	_open_room(false, code)


func _open_room(as_host: bool, code: String) -> void:
	leave()
	_room = RoomLink.new()
	_room.failed.connect(_drop)
	_room.opened.connect(_on_room_opened)
	var err := _room.start(signaling_url, as_host, code)
	if err != OK:
		_room = null
		_set_status("Couldn't reach the room service (%s)." % error_string(err))
		return
	# Online from here on, though nobody is connected until the room opens.
	mode = Mode.SERVER if as_host else Mode.CLIENT
	PlayerManager.clear()
	_set_status("Creating a room..." if as_host else "Joining room %s..." % code.strip_edges().to_upper())


func _on_room_opened(code: String) -> void:
	room_code = code
	_room_wait = 0.0
	if _room.is_host:
		_become_server(_room.peer, true)
		_set_status("")
	else:
		_peer = _room.peer
		multiplayer.multiplayer_peer = _peer
		_set_status("Connecting to the host...")


func join(url: String) -> Error:
	leave()
	address = url
	var ws := WebSocketMultiplayerPeer.new()
	var err := ws.create_client(url)
	if err != OK:
		_set_status("Bad address (%s)." % error_string(err))
		return err
	_peer = ws
	multiplayer.multiplayer_peer = _peer
	mode = Mode.CLIENT
	PlayerManager.clear()
	_set_status("Connecting to %s..." % url)
	return OK


func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	if _room:
		_room.close()
	_room = null
	room_code = ""
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	mode = Mode.OFFLINE
	dedicated = false
	_sent_input.clear()
	_gone_peers.clear()
	PlayerManager.clear()   # the online roster means nothing offline
	roster_changed.emit()


func _drop(reason: String) -> void:
	var was_in_game := MatchManager.state != MatchManager.State.LOBBY
	leave()
	_set_status(reason)
	if was_in_game or get_tree().current_scene == null or get_tree().current_scene.scene_file_path != ONLINE_LOBBY:
		MatchManager.state = MatchManager.State.LOBBY
		MatchManager.goto(ONLINE_LOBBY)


func _set_status(text: String) -> void:
	status = text
	status_changed.emit()


func _on_connected() -> void:
	_set_status("Connected. Joining...")
	# Room guests keep their signaling link: it holds their place in the room
	# and tells them at once if the host closes it.
	_hello.rpc_id(1, PROTOCOL)


func _on_peer_connected(_id: int) -> void:
	pass   # the client introduces itself with _hello


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	var info := _info_for_peer(id)
	if info == null:
		return
	if MatchManager.state == MatchManager.State.LOBBY:
		PlayerManager.leave(info.player_id)
		_broadcast_roster()
		_maybe_start()
	else:
		# Mid-match: knock their ball out, tidy up once everyone is back in the lobby.
		_gone_peers.append(id)
		if game:
			var p: Player = game.player_by_id(info.player_id)
			if p:
				p.die()


# ── Lobby (client -> server) ─────────────────

@rpc("any_peer", "reliable")
func _hello(protocol: int) -> void:
	if not is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var reason := ""
	if protocol != PROTOCOL:
		reason = "Version mismatch - update the game."
	elif MatchManager.state != MatchManager.State.LOBBY:
		reason = "A match is in progress. Try again in a minute."
	elif PlayerManager.players.size() >= PlayerManager.MAX_PLAYERS:
		reason = "The server is full."
	if reason != "":
		_refused.rpc_id(id, reason)
		get_tree().create_timer(0.5).timeout.connect(func(): if _peer: _peer.disconnect_peer(id))
		return
	# Each remote player gets an id/colour like a local join; their device is
	# irrelevant here since their controls arrive over the network.
	var pid := PlayerManager.join(-1000 - id)
	PlayerManager.players[pid].peer_id = id
	_broadcast_roster()


@rpc("authority", "reliable")
func _refused(reason: String) -> void:
	_drop(reason)


func ask_ready(value: bool) -> void:
	if is_server():
		_apply_ready(my_peer(), value)
	else:
		_set_ready.rpc_id(1, value)


func ask_color(step: int) -> void:
	if is_server():
		_apply_color(my_peer(), step)
	else:
		_cycle_color.rpc_id(1, step)


@rpc("any_peer", "reliable")
func _set_ready(value: bool) -> void:
	if is_server():
		_apply_ready(multiplayer.get_remote_sender_id(), value)


@rpc("any_peer", "reliable")
func _cycle_color(step: int) -> void:
	if is_server():
		_apply_color(multiplayer.get_remote_sender_id(), step)


func _apply_ready(peer: int, value: bool) -> void:
	var info := _info_for_peer(peer)
	if info and MatchManager.state == MatchManager.State.LOBBY:
		info.is_ready = value
		_broadcast_roster()
		_maybe_start()


func _apply_color(peer: int, step: int) -> void:
	var info := _info_for_peer(peer)
	if info and not info.is_ready:
		PlayerManager.cycle_color(info.player_id, signi(step))
		_broadcast_roster()


func _maybe_start() -> void:
	var infos := PlayerManager.players.values()
	if infos.is_empty() or MatchManager.state != MatchManager.State.LOBBY:
		return
	for info in infos:
		if not info.is_ready:
			return
	var match_seed_value := (randi() % 2000000000) + 1
	_start_match.rpc(match_seed_value)
	_start_match(match_seed_value)


# ── Roster (server -> clients) ───────────────

func _broadcast_roster() -> void:
	roster_changed.emit()
	if not is_server():
		return
	var list := []
	for info in PlayerManager.sorted_players():
		list.append([info.player_id, info.peer_id, info.color_index, info.is_ready])
	_roster.rpc(list)


@rpc("authority", "reliable")
func _roster(list: Array) -> void:
	var infos: Array[PlayerInfo] = []
	for row in list:
		var info := PlayerInfo.new()
		info.player_id = row[0]
		info.peer_id = row[1]
		info.color_index = row[2]
		info.is_ready = row[3]
		info.device_id = Settings.DEVICE_ANY if info.peer_id == my_peer() else -1000 - info.peer_id
		infos.append(info)
	PlayerManager.replace_all(infos)
	if status.begins_with("Connect"):
		_set_status("")
	roster_changed.emit()


func local_info() -> PlayerInfo:
	return _info_for_peer(my_peer())


func _info_for_peer(peer: int) -> PlayerInfo:
	for info in PlayerManager.players.values():
		if info.peer_id == peer:
			return info
	return null


# ── Match flow (server -> clients) ───────────

@rpc("authority", "reliable")
func _start_match(seed_value: int) -> void:
	match_seed = seed_value
	_blocks_broken = 0
	_tick = 0
	_next_id = 0
	MatchManager.start_match()


func _on_match_ended(results: Dictionary) -> void:
	if not is_server():
		return
	if dedicated:
		print("Match over: winner %s, %d players, %d s, %d blocks broken" % [
			"P%d" % results.winner if results.winner > 0 else "none", results.standings.size(), int(results.time), _blocks_broken])
	var standings := []
	for info: PlayerInfo in results.standings:
		standings.append([info.player_id, info.max_height, info.death_order])
	_match_ended.rpc({
		"winner": results.winner, "solo": results.solo, "time": results.time,
		"best_height": results.best_height, "standings": standings,
	})
	get_tree().create_timer(RETURN_TO_LOBBY).timeout.connect(return_to_lobby)


@rpc("authority", "reliable")
func _match_ended(data: Dictionary) -> void:
	var standings: Array = []
	for row in data.standings:
		var info: PlayerInfo = PlayerManager.players.get(row[0])
		if info:
			info.max_height = row[1]
			info.death_order = row[2]
			standings.append(info)
	data.standings = standings
	data.new_record = false
	MatchManager.end_match(data)


func return_to_lobby() -> void:
	if not is_server() or MatchManager.state != MatchManager.State.ENDED:
		return
	for id in _gone_peers:
		var info := _info_for_peer(id)
		if info:
			PlayerManager.leave(info.player_id)
	_gone_peers.clear()
	_to_lobby.rpc()
	_to_lobby()
	_broadcast_roster()


@rpc("authority", "reliable")
func _to_lobby() -> void:
	for info in PlayerManager.players.values():
		info.is_ready = false
	MatchManager.state = MatchManager.State.LOBBY
	MatchManager.goto(ONLINE_LOBBY)


# ── In-match traffic ─────────────────────────

func next_id() -> int:
	_next_id += 1
	return _next_id


## Client: forward one local player's controls when they change.
func send_input(player_id: int, buttons: int, move: Vector2) -> void:
	move = (move * 64.0).round() / 64.0
	var now := Time.get_ticks_msec() / 1000.0
	var last: Array = _sent_input.get(player_id, [-1, Vector2.INF, 0.0])
	if last[0] == buttons and last[1] == move and now - last[2] < INPUT_KEEPALIVE:
		return
	_sent_input[player_id] = [buttons, move, now]
	_recv_input.rpc_id(1, player_id, buttons, move)


# Reliable: controls are only sent when they change, so none may go missing.
@rpc("any_peer", "reliable")
func _recv_input(player_id: int, buttons: int, move: Vector2) -> void:
	if not is_server() or game == null:
		return
	var info: PlayerInfo = PlayerManager.players.get(player_id)
	if info == null or info.peer_id != multiplayer.get_remote_sender_id():
		return   # not theirs to drive
	var p: Player = game.player_by_id(player_id)
	if p:
		p.input.push_remote(buttons, move)


func _process(delta: float) -> void:
	if _room:
		_room.poll()
	# Without a TURN relay some networks can't link up directly; say so
	# instead of spinning forever.
	if _room and is_client() and room_code != "" and local_info() == null:
		_room_wait += delta
		if _room_wait > ROOM_CONNECT_TIMEOUT:
			_drop(NO_DIRECT)


func _physics_process(_delta: float) -> void:
	if not is_server() or game == null or not is_instance_valid(game):
		return
	if MatchManager.state == MatchManager.State.LOBBY:
		return
	_tick += 1
	if _tick % SNAPSHOT_EVERY == 0:
		var snap: Array = game.build_snapshot()
		# Things that happen once (chunks appearing / vanishing, blocks
		# breaking) must arrive; positions are fine to drop, the next
		# snapshot replaces them.
		if not (snap[3].is_empty() and snap[4].is_empty() and snap[5].is_empty()):
			_events.rpc(snap[3], snap[4], snap[5])
		_snapshot.rpc(snap[0], snap[1], snap[2])


@rpc("authority", "reliable")
func _events(spawns: Array, gone: PackedInt32Array, blocks: PackedInt32Array) -> void:
	if game and is_instance_valid(game):
		game.apply_events(spawns, gone, blocks)


@rpc("authority", "unreliable_ordered")
func _snapshot(header: PackedFloat32Array, players: PackedFloat32Array, frags: PackedFloat32Array) -> void:
	if game and is_instance_valid(game):
		game.apply_state(header, players, frags)


static func snapshot_interval() -> float:
	return float(SNAPSHOT_EVERY) / Engine.physics_ticks_per_second


## Server: replay a visual effect on every client (see Fx).
func relay_fx(kind: StringName, args: Array) -> void:
	if game:
		_fx.rpc(kind, args)


@rpc("authority", "unreliable_ordered")
func _fx(kind: StringName, a: Array) -> void:
	match kind:
		&"ring": Fx.ring(a[0], a[1], a[2], a[3], a[4])
		&"burst": Fx.burst(a[0], a[1], a[2], a[3], a[4])
		&"dust": Fx.dust(a[0], a[1], a[2])
		&"cone": Fx.cone(a[0], a[1], a[2], a[3])
		&"speed_lines": Fx.speed_lines(a[0], a[1], a[2])
		&"popup": Fx.popup(a[0], a[1], a[2], a[3])
		&"splash": Fx.splash(a[0], a[1])


func _on_shake(strength: float) -> void:
	if is_server() and game:
		_shake.rpc(strength)


@rpc("authority", "unreliable_ordered")
func _shake(strength: float) -> void:
	SignalBus.screen_shake_requested.emit(strength)
