class_name ProfilePage
extends UiPage

## Who you are: the account and your totals (Card), and how your ball looks
## (Customise). Colour changes show on the record straight away; the locked
## slots are where skins, trails and name tags will go.

const STATS := [
	["solo_runs", "solo runs", ""], ["best_solo", "best climb", " m"], ["total_climb", "climbed in all", " m"],
	["online_matches", "online played", ""], ["online_wins", "online wins", ""], ["kos", "knock-outs", ""],
]


func _init() -> void:
	title = "Profile"


func build() -> void:
	tabs = UiTabs.new()
	tabs.add_tab("Card", _build_card)
	tabs.add_tab("Customise", _build_customise)
	add_child(tabs)
	tabs.show_tab(0, false)
	Stats.account_changed.connect(_on_account_changed)


func entered() -> void:
	if tabs.index == 0:
		tabs.show_tab(0)   # back from signing in: show the new account


func _on_account_changed() -> void:
	if is_inside_tree() and visible and tabs.index == 0:
		tabs.show_tab(0)


# ── Card ─────────────────────────────────────

func _build_card(body: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var name_label := UiTheme.title(Settings.player_name() if Settings.logged_in() else "Guest", 44, Palette.PAPER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(name_label)
	head.add_child(UiChip.new("ranked" if Settings.logged_in() else "not ranked", Palette.GOOD if Settings.logged_in() else Palette.SMOKE))
	body.add_child(head)
	body.add_child(UiPage.notes(
		"Your solo climbs and online wins count for this account on any computer you log in on." if Settings.logged_in()
		else "Guests aren't on the leaderboards. An account takes ten seconds: a name and a password."))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var tiles := {}
	for s in STATS:
		var tile := UiStat.new(s[1])
		grid.add_child(tile)
		tiles[s[0]] = tile
	if Stats.enabled():
		Stats.my_stats(func(ok: bool, reply: Dictionary):
			var p: Variant = reply.get("player")
			if not ok or not p is Dictionary:
				return
			for s in STATS:
				var tile: Variant = tiles[s[0]]   # untyped: the page may be gone by now
				if is_instance_valid(tile):
					tile.set_value("%d%s" % [int(p.get(s[0], 0)), s[2]]))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var customise := UiTheme.button("Customise ball", 0)
	customise.pressed.connect(func(): tabs.step(1))
	var b: Button
	if Settings.logged_in():
		b = UiTheme.button("Log out", 0)
		b.pressed.connect(func(): Stats.logout())
	else:
		b = UiTheme.button("Log in / Create account", 0)
		b.pressed.connect(func(): push(SignInPage.new()))
	for x in [customise, b]:
		x.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(x)
	# Customise first, so a stray Enter never logs anyone out.
	UiNav.link_horizontal([customise, b])
	for x in [customise, b]:
		x.focus_neighbor_top = UiNav.SELF
		x.focus_neighbor_bottom = UiNav.SELF


# ── Customise ────────────────────────────────

func _build_customise(body: VBoxContainer) -> void:
	var idx := int(Settings.get_value("ball_color"))
	var row := UiRow.cycler("Ball colour", Palette.PLAYER_COLOR_NAMES, idx, func(i: int):
		Settings.set_value("ball_color", i)
		if stage():
			stage().set_look(BallPortrait.my_look()), Palette.PLAYER_COLORS)
	body.add_child(row)
	body.add_child(UiPage.notes("Your colour in the lobby when it's free. Someone else might have it first."))

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	body.add_child(spacer)
	body.add_child(UiPage.heading("Coming soon"))
	var cards_row := HBoxContainer.new()
	cards_row.add_theme_constant_override("separation", 12)
	body.add_child(cards_row)
	var cards: Array = []
	for slot in [["Skin", "Patterns and prints for your ball."], ["Trail", "What you leave behind on a jump."], ["Name tag", "How your name shows in a match."]]:
		var art := BallPortrait.new()
		art.radius = 22.0
		art.looks = [BallPortrait.look_for_color(Palette.SMOKE)]
		var card := UiCard.new(slot[0], slot[1], art, Vector2(140, 190))
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.set_locked()
		cards_row.add_child(card)
		cards.append(card)
	UiNav.link_grid([[row.control], cards])
