class_name RoomLink
extends RefCounted

## Online rooms over WebRTC. Talks to the signaling service (signaling/) to
## get a room code and swap connection offers, then hands Godot a
## WebRTCMultiplayerPeer whose connections go straight between the players.
## The host is peer 1 and runs the match; guests connect only to the host.
## Call poll() every frame.

signal opened(code: String)          ## the room exists (host) / we're in it (guest)
signal failed(reason: String)

var peer := WebRTCMultiplayerPeer.new()
var code := ""
var is_host := false

## Print signaling traffic and connection changes (`-- --net-debug`).
static var debug := "--net-debug" in OS.get_cmdline_user_args()

var _ws := WebSocketPeer.new()
var _ice: Array = []
var _was_open := false
var _done := false


func start(signaling_url: String, host: bool, join_code := "") -> Error:
	is_host = host
	var path := "/create" if host else "/join/" + join_code.strip_edges().to_upper()
	return _ws.connect_to_url(signaling_url.trim_suffix("/") + path)


func poll() -> void:
	if _done:
		return
	_ws.poll()
	while _ws.get_available_packet_count() > 0 and not _done:
		_handle(_ws.get_packet().get_string_from_utf8())
	if _done:
		return   # an error message already said why
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_was_open = true
		WebSocketPeer.STATE_CLOSED:
			_done = true
			if code == "":
				failed.emit("Couldn't reach the room service." if not _was_open else "The room service hung up.")
			# Once in a room, losing signaling only stops new players joining.


func close_signaling() -> void:
	_done = true
	_ws.close()


func close() -> void:
	close_signaling()
	peer.close()


func _handle(text: String) -> void:
	var msg: Variant = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	if debug:
		print("[room] <- %s from %s (%d ms)" % [msg.get("type"), msg.get("from", msg.get("id", "-")), Time.get_ticks_msec()])
	match msg.get("type", ""):
		"welcome":
			code = str(msg.code)
			_ice = msg.get("ice", [])
			var id := int(msg.id)
			var err := peer.create_server() if is_host else peer.create_client(id)
			if err != OK:
				failed.emit("Couldn't start online play (%s)." % error_string(err))
				return
			if not is_host and not _connect_to(1):
				return
			opened.emit(code)
		"peer_joined":
			var id := int(msg.id)
			if not peer.has_peer(id) and _connect_to(id):
				_connection(id).create_offer()
		"peer_left":
			# Only a guest who never finished connecting; connected guests drop
			# their signaling on purpose and stay in the game.
			var id := int(msg.id)
			if peer.has_peer(id) and not peer.get_peer(id).connected:
				peer.remove_peer(id)
		"offer", "answer":
			var conn := _connection(int(msg.get("from", 0)))
			if conn:
				conn.set_remote_description(msg.type, str(msg.sdp))
		"candidate":
			var conn := _connection(int(msg.get("from", 0)))
			if conn:
				conn.add_ice_candidate(str(msg.mid), int(msg.index), str(msg.sdp))
		"error":
			failed.emit(str(msg.get("reason", "The room service refused.")))
			close_signaling()


func _connect_to(id: int) -> bool:
	var conn := WebRTCPeerConnection.new()
	if conn.initialize({"iceServers": _ice}) != OK:
		failed.emit("This build can't do online rooms (WebRTC is missing).")
		return false
	# Offers/answers we create go to the other side through signaling.
	# (Method callables, not lambdas: a lambda capturing the connection would
	# keep it alive forever, and the WebRTC add-on then hangs on quit.)
	conn.session_description_created.connect(_on_description.bind(id))
	conn.ice_candidate_created.connect(_on_candidate.bind(id))
	peer.add_peer(conn, id)
	return true


func _on_description(type: String, sdp: String, id: int) -> void:
	var conn := _connection(id)
	if conn:
		conn.set_local_description(type, sdp)
		_send({"type": type, "to": id, "sdp": sdp})


func _on_candidate(mid: String, index: int, sdp: String, id: int) -> void:
	_send({"type": "candidate", "to": id, "mid": mid, "index": index, "sdp": sdp})


func _connection(id: int) -> WebRTCPeerConnection:
	if not peer.has_peer(id):
		return null
	return peer.get_peer(id).connection


func _send(msg: Dictionary) -> void:
	if debug:
		print("[room] -> %s to %s (%d ms)" % [msg.type, msg.to, Time.get_ticks_msec()])
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(JSON.stringify(msg))
