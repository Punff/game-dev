class_name LeaderboardPage
extends UiPage

## Best solo climbs or online wins, and your place. Everything comes from
## Stats (the server). Only accounts are ranked.

const BOARDS := [["height", "Highest Climb"], ["wins", "Online Wins"]]


func _init() -> void:
	title = "Leaderboard"


func build() -> void:
	tabs = UiTabs.new()
	for i in BOARDS.size():
		tabs.add_tab(BOARDS[i][1], _build_board.bind(i))
	add_child(tabs)
	tabs.show_tab(0, false)


func _build_board(body: VBoxContainer, board: int) -> void:
	var list := UiBoard.new(BOARDS[board][0])
	body.add_child(list)
	var b: Button
	if Settings.logged_in():
		b = UiTheme.button("Refresh", 200)
		b.pressed.connect(list.refresh)
	else:
		b = UiTheme.button("Log in to get ranked", 0)
		b.pressed.connect(func(): push(SignInPage.new()))
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	body.add_child(b)
	UiNav.link_vertical([b])
	list.refresh()
