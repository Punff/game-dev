extends Node

## Scene flow and match state.

enum State { MENU, LOBBY, COUNTDOWN, PLAYING, ENDED }

const MAIN_MENU := "res://scenes/main_menu.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const GAME := "res://scenes/game.tscn"

var state: State = State.MENU
var last_results: Dictionary = {}
var session := 0   ## matches started this run, shown as "SESSION #n"


func goto(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)


func to_menu() -> void:
	state = State.MENU
	goto(MAIN_MENU)


func to_lobby() -> void:
	state = State.LOBBY
	for info in PlayerManager.players.values():
		info.is_ready = false
	goto(LOBBY)


func start_match() -> void:
	session += 1
	PlayerManager.reset_match_stats()
	state = State.COUNTDOWN
	goto(GAME)


func end_match(results: Dictionary) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	last_results = results
	SignalBus.match_ended.emit(results)
