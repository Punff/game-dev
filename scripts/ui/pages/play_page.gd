class_name PlayPage
extends UiPage

## Game modes as cards, and the daily climb as a strip under them. A new
## mode is a new entry in MODES and a case in _go().

const MODES := [
	{"id": "solo", "title": "Solo", "sub": "Straight in: you and the rising slag. Climbs count for the board.", "balls": 1},
	{"id": "local", "title": "Local", "sub": "2-4 players on one screen: keyboard halves and pads.", "balls": 3},
	{"id": "online", "title": "Online", "sub": "Make a room, share the code, play anywhere.", "balls": 2},
]

var _last_device := Settings.DEVICE_KB_A   # whoever picked Solo plays it


func _init() -> void:
	title = "Play"


func build() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(row)
	var cards: Array = []
	for m in MODES:
		var art := BallPortrait.new()
		art.radius = 30.0 if m.balls < 3 else 22.0
		art.waves = m.id == "online"
		var looks: Array = [BallPortrait.my_look()]
		for i in m.balls - 1:
			looks.append(BallPortrait.look_for_color(Palette.PLAYER_COLORS[(i + 1) * 3 % Palette.PLAYER_COLORS.size()]))
		art.looks = looks
		var card := UiCard.new(m.title, m.sub, art, Vector2(150, 230))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_go.bind(m.id))
		row.add_child(card)
		cards.append(card)
	UiNav.link_horizontal(cards)

	var today := int(Daily.local_best(Daily.today()).get("height", 0))
	var art := BallPortrait.new()
	art.radius = 22.0
	art.looks = [BallPortrait.my_look()]
	var sub := "Today's map, the same for everyone. Race your friends' ghosts."
	if today > 0:
		sub = "Your best today: %d m. Beat it, or your friends' ghosts." % today
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var date := "%s %d" % [months[int(Daily.today().substr(5, 2)) - 1], int(Daily.today().substr(8, 2))]
	var daily := UiCard.new("Daily climb  ·  %s" % date, sub, art, Vector2(0, 92), true)
	daily.pressed.connect(_go.bind("daily"))
	add_child(daily)
	for c in cards:
		c.focus_neighbor_top = UiNav.SELF
		c.focus_neighbor_bottom = c.get_path_to(daily)
	daily.focus_neighbor_top = daily.get_path_to(cards[0])
	daily.focus_neighbor_bottom = UiNav.SELF
	daily.focus_neighbor_left = UiNav.SELF
	daily.focus_neighbor_right = UiNav.SELF

	var best := int(Settings.get_value("best_height"))
	if best > 0:
		var foot := HBoxContainer.new()
		foot.add_theme_constant_override("separation", 10)
		foot.add_child(UiChip.new("best %d m" % best))
		foot.add_child(UiPage.notes("on this computer. Beat it."))
		add_child(foot)


func open_online() -> void:
	push(OnlinePage.new())


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_last_device = event.device
	elif event is InputEventKey and event.pressed:
		_last_device = Settings.DEVICE_KB_A


func _go(id: String) -> void:
	match id:
		"solo", "daily":
			# Straight into a run: there's nobody to wait for.
			PlayerManager.clear()
			PlayerManager.join(_last_device)
			MatchManager.daily = Daily.today() if id == "daily" else ""
			MatchManager.start_match()
		"local":
			MatchManager.to_lobby()
		"online":
			open_online()
