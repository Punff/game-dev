extends Node

## Talks to the stats side of the room server (signaling/, the /v1 routes):
## uploads each finished match record (Telemetry) and fetches the
## leaderboards and this player's stats. Uploads that fail wait in
## user://logs/pending.jsonl and go out on the next start.
## Nothing is sent with Settings "share_stats" off.

signal match_submitted(reply: Dictionary)   ## the server's answer, e.g. {"rank": 12}

const PENDING := "user://logs/pending.jsonl"
const MAX_PENDING := 20
const TIMEOUT := 15.0


func _ready() -> void:
	_flush_pending.call_deferred()


## https:// address of the server, from the signaling one (same Worker).
func base_url() -> String:
	return Net.signaling_url.replace("wss://", "https://").replace("ws://", "http://").trim_suffix("/")


func enabled() -> bool:
	return Settings.get_value("share_stats") and not OS.has_environment("NO_STATS")


func submit_match(rec: Dictionary) -> void:
	if not enabled():
		return
	var body := JSON.stringify(rec)
	_request("/v1/matches", HTTPClient.METHOD_POST, body, func(ok: bool, reply: Dictionary):
		if ok:
			match_submitted.emit(reply)
		elif reply.get("retry", true):
			_keep(body))


## board: "height" (best solo climb) or "wins" (online wins).
## done(ok, {"rows": [{"name", "value", "client"}...], "me": {...}})
func leaderboard(board: String, done: Callable) -> void:
	_request("/v1/leaderboard?board=%s&limit=15&me=%s" % [board, Settings.client_id()], HTTPClient.METHOD_GET, "", done)


## done(ok, {"player": {...} or null})
func my_stats(done: Callable) -> void:
	_request("/v1/players/" + Settings.client_id(), HTTPClient.METHOD_GET, "", done)


func _request(path: String, method: int, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, raw: PackedByteArray):
		http.queue_free()
		var reply: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if not reply is Dictionary:
			reply = {}
		# A 4xx means the server looked and said no; retrying won't help
		# (except "slow down").
		if code >= 400 and code < 500 and code != 429:
			reply["retry"] = false
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, reply))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if http.request(base_url() + path, headers, method, body) != OK:
		http.queue_free()
		done.call(false, {})


func _keep(body: String) -> void:
	var lines := _read_pending()
	lines.append(body)
	_write_pending(lines.slice(-MAX_PENDING))


## One at a time, so a long-offline queue doesn't burst the server.
func _flush_pending() -> void:
	if not enabled():
		return
	var lines := _read_pending()
	if lines.is_empty():
		return
	_write_pending(lines.slice(1))
	_request("/v1/matches", HTTPClient.METHOD_POST, lines[0], func(ok: bool, reply: Dictionary):
		if ok or not reply.get("retry", true):
			_flush_pending()
		else:
			_keep(lines[0]))


func _read_pending() -> Array:
	var f := FileAccess.open(PENDING, FileAccess.READ)
	if f == null:
		return []
	var out := []
	while not f.eof_reached():
		var l := f.get_line()
		if l != "":
			out.append(l)
	return out


func _write_pending(lines: Array) -> void:
	DirAccess.make_dir_recursive_absolute(PENDING.get_base_dir())
	var f := FileAccess.open(PENDING, FileAccess.WRITE)
	if f:
		for l in lines:
			f.store_line(l)
