class_name EndScreen
extends CanvasLayer

## Results, laid out like the main menu: the match in a sleeve on the left
## (ResultsPage), and where you now stand on the leaderboard in a second one
## on the right - Highest Climb after a solo run, today's climb among your
## friends after a daily one, Online Wins after an online match. Couch
## matches aren't ranked, so they get the result alone.

const BOARD_ROWS := 7
const SUBMIT_WAIT := 6.0   ## solo: show the board anyway if the upload never answers
const ONLINE_WAIT := 2.5   ## online: give the host's upload a moment to land

var page: ResultsPage
# Built when results come in (most screens are freed without ever showing).
var _root: Control
var _sleeve: UiSleeve
var _board_sleeve: UiSleeve
var _board: UiBoard
var _hints: UiHintBar


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	SignalBus.match_ended.connect(_show)


func _show(results: Dictionary) -> void:
	var game := get_parent()
	if game and game.get("pause_menu"):
		game.pause_menu.close()   # online guests get results while a pause menu may be up
	_root = Control.new()
	_sleeve = UiSleeve.new()
	_hints = UiHintBar.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(Palette.BG_DEEP, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var board_id := "daily" if results.has("daily") else "height" if results.solo else ("wins" if Net.is_online() else "")
	if board_id != "":
		_board_sleeve = UiSleeve.new()
		_root.add_child(_board_sleeve)
		var board_page := UiPage.new()
		board_page.title = {"height": "Highest climb", "daily": "Today's climb", "wins": "Online wins"}[board_id]
		_board = UiBoard.new(board_id, true, BOARD_ROWS)
		board_page.add_child(_board)
		_board_sleeve.open(board_page)
		_board.show_message("Waiting for the server...")
	page = ResultsPage.new(results)
	_root.add_child(_sleeve)
	_sleeve.open(page)
	_sleeve.active = true
	_root.add_child(_hints)
	_hints.set_hints(page.hints())
	_root.resized.connect(_layout)
	_layout()

	visible = true
	get_tree().paused = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	if _board_sleeve:
		UiFx.reveal(_board_sleeve, 0.35)
	_load_board(results)

	# Players are usually still mashing jump (= Space / A = accept) when the
	# match ends: hold the buttons a moment so nobody skips the results.
	for b: Button in page.buttons:
		b.disabled = true
	await get_tree().create_timer(0.6).timeout
	for b: Button in page.buttons:
		b.disabled = false
	page.focus_first()


func _load_board(results: Dictionary) -> void:
	if not Stats.enabled():
		if _board:
			_board.refresh()   # says how to turn it on
		return
	if results.has("daily"):
		# The run went up as the match ended; the board is fresh once it's in.
		var waited := 0.0
		while Stats.daily_pending and waited < SUBMIT_WAIT:
			await get_tree().create_timer(0.2).timeout
			waited += 0.2
		if is_instance_valid(page):
			page.show_daily(Stats.daily_reply)
			_board.refresh()
	elif results.solo:
		# The run is on its way up (Telemetry); the board is fresh once it lands.
		var answered := [false]
		Stats.match_submitted.connect(func(reply: Dictionary):
			answered[0] = true
			if is_instance_valid(page):
				page.show_rank(reply)
				_board.refresh(), CONNECT_ONE_SHOT)
		await get_tree().create_timer(SUBMIT_WAIT).timeout
		if not answered[0] and is_instance_valid(_board):
			_board.refresh()
	elif _board:
		await get_tree().create_timer(ONLINE_WAIT).timeout
		if is_instance_valid(_board):
			_board.refresh()


func _layout() -> void:
	var s := _root.size
	var top := 130.0
	var h := s.y - top - 90.0
	var w := minf(560.0, s.x - 120.0)
	if _board_sleeve:
		var bw := minf(520.0, s.x - w - 160.0)
		var x := (s.x - w - 40.0 - bw) * 0.5
		_sleeve.position = Vector2(x, top)
		_board_sleeve.position = Vector2(x + w + 40.0, top + 30.0)
		_board_sleeve.size = Vector2(bw, h - 30.0)
	else:
		_sleeve.position = Vector2((s.x - w) * 0.5, top)
	_sleeve.size = Vector2(w, h)
	_hints.position = Vector2(_sleeve.position.x, s.y - 50.0)
