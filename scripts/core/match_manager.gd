extends Node

enum GameState {
	MENU,
	LOBBY,
	STARTING,
	PLAYING,
	PAUSED,
	ENDED
}

var current_state: GameState = GameState.MENU
var current_mode: String = "survival"
var selected_biome: String = "default"

func _ready() -> void:
	SignalBus.match_start_requested.connect(_on_match_start_requested)
	SignalBus.game_paused.connect(_on_game_paused)

func _on_match_start_requested(mode_id: String) -> void:
	current_mode = mode_id
	current_state = GameState.STARTING

	SignalBus.match_started.emit()
	current_state = GameState.PLAYING

func _on_game_paused(is_paused: bool) -> void:
	if is_paused:
		current_state = GameState.PAUSED
	else:
		current_state = GameState.PLAYING

func end_match(results: Dictionary) -> void:
	current_state = GameState.ENDED
	SignalBus.match_ended.emit(results)

func reset_to_menu() -> void:
	current_state = GameState.MENU
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
