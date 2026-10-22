extends Node

## Talks to the stats side of the room server (signaling/, the /v1 routes):
## uploads each finished match record (Telemetry), fetches the leaderboards
## and this player's stats, and logs in to an account. Uploads that fail wait
## in user://logs/pending.jsonl and go out on the next start.
## Nothing is sent with Settings "share_stats" off.
##
## Logged in, requests carry the session token (Settings "auth_token"); the
## password itself is only ever sent to log in and never stored.

signal match_submitted(reply: Dictionary)   ## the server's answer, e.g. {"rank": 12}
signal account_changed()

const PENDING := "user://logs/pending.jsonl"
const MAX_PENDING := 20
const TIMEOUT := 15.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # the results screen pauses the game while it waits for us
	_flush_pending.call_deferred()
	_check_session.call_deferred()


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
## around: `limit` rows centred on this player's place instead of the top.
## done(ok, {"rows": [{"rank", "name", "value", "you"}...], "me": {"rank", "value"} or null})
func leaderboard(board: String, done: Callable, around := false, limit := 15) -> void:
	var q := "/v1/leaderboard?board=%s&limit=%d&me=%s" % [board, limit, Settings.client_id()]
	if around:
		q += "&around=me"
	_request(q, HTTPClient.METHOD_GET, "", done)


## done(ok, {"player": {...} or null})
func my_stats(done: Callable) -> void:
	_request("/v1/players/" + Settings.client_id(), HTTPClient.METHOD_GET, "", done)


# ── Friends ──────────────────────────────────

const PRESENCE_EVERY := 60.0   ## heartbeat while logged in (friends see you online)
var _presence_sent := ""      # status|room last sent
var _presence_clock := PRESENCE_EVERY
var _presence_check := 0.0


## done(ok, {"friends": [{name, online, status, room}], "incoming": [name],
## "outgoing": [name], "invites": [{from, room}]})
func friends(done: Callable) -> void:
	_request("/v1/friends", HTTPClient.METHOD_GET, "", done)


## kind: "request", "accept", "remove" or "invite" (with `room`).
## done(ok, {"status"?, "error"?})
func friend_action(kind: String, username: String, done: Callable, room := "") -> void:
	var body := {"username": username.strip_edges()}
	if room != "":
		body["room"] = room
	_request("/v1/friends/" + kind, HTTPClient.METHOD_POST, JSON.stringify(body), done)


## Where this game is, for friends: "menu", "room" (with its code) or "match".
func presence_now() -> Array:
	if Net.is_online() and MatchManager.state in [MatchManager.State.COUNTDOWN, MatchManager.State.PLAYING]:
		return ["match", ""]
	if Net.is_online() and Net.room_code != "":
		return ["room", Net.room_code]
	return ["menu", ""]


## Heartbeat: once a minute, and at once when the status changes (opening a
## room, starting a match), checked every second.
func _process(delta: float) -> void:
	if not Settings.logged_in() or not enabled():
		return
	_presence_clock += delta
	_presence_check += delta
	if _presence_check < 1.0:
		return
	_presence_check = 0.0
	var now := presence_now()
	var key := "%s|%s" % now
	if key != _presence_sent or _presence_clock >= PRESENCE_EVERY:
		_presence_sent = key
		_presence_clock = 0.0
		_request("/v1/presence", HTTPClient.METHOD_POST, JSON.stringify({"status": now[0], "room": now[1]}), func(_ok, _r): pass)


# ── Account ──────────────────────────────────

## done(ok, error message). On success Settings holds the new session.
func register(username: String, password: String, done: Callable) -> void:
	_auth("/v1/auth/register", username, password, done)


func login(username: String, password: String, done: Callable) -> void:
	_auth("/v1/auth/login", username, password, done)


func logout() -> void:
	if Settings.logged_in():
		_request("/v1/auth/logout", HTTPClient.METHOD_POST, JSON.stringify({"client": Settings.client_id()}), func(_ok, _r): pass)
	_set_session("", "")


func _auth(path: String, username: String, password: String, done: Callable) -> void:
	var body := JSON.stringify({"username": username.strip_edges(), "password": password, "client": Settings.client_id()})
	_request(path, HTTPClient.METHOD_POST, body, func(ok: bool, reply: Dictionary):
		if ok and reply.has("token"):
			_set_session(reply.token, reply.username)
			done.call(true, "")
		else:
			done.call(false, str(reply.get("error", "Couldn't reach the server. Try again later."))))


## A session can expire or be logged out elsewhere; only a clear "no" from the
## server logs us out here (being offline doesn't).
func _check_session() -> void:
	if not Settings.logged_in() or not enabled():
		return
	var asked_with: String = Settings.get_value("auth_token")
	_request("/v1/auth/me", HTTPClient.METHOD_GET, "", func(ok: bool, reply: Dictionary):
		if Settings.get_value("auth_token") != asked_with:
			return   # logged in or out meanwhile: this answer is about the old session
		if ok and reply.has("username") and reply.username != Settings.get_value("account_name"):
			_set_session(Settings.get_value("auth_token"), reply.username)
		elif not ok and reply.get("unauthorized", false):
			Settings.set_value("onboarded", false, false)   # ask again on the main menu
			_set_session("", ""))


func _set_session(token: String, username: String) -> void:
	Settings.set_value("auth_token", token, false)
	Settings.set_value("account_name", username)
	account_changed.emit()


func _request(path: String, method: int, body: String, done: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers, raw: PackedByteArray):
		http.queue_free()
		# Parsed quietly: offline or timed out, there's no body at all.
		var json := JSON.new()
		var reply: Variant = json.data if json.parse(raw.get_string_from_utf8()) == OK else {}
		if not reply is Dictionary:
			reply = {}
		# A 4xx means the server looked and said no; retrying won't help
		# (except "slow down").
		if code >= 400 and code < 500 and code != 429:
			reply["retry"] = false
		if code == 401:
			reply["unauthorized"] = true
		if not done.is_valid():
			return   # whoever asked (a menu page) is gone
		done.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, reply))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if Settings.logged_in():
		headers.append("Authorization: Bearer " + str(Settings.get_value("auth_token")))
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
