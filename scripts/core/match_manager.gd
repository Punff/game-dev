extends Node

## Scene flow and match state.

enum State { MENU, LOBBY, COUNTDOWN, PLAYING, ENDED }

const MAIN_MENU := "res://scenes/main_menu.tscn"
const LOBBY := "res://scenes/lobby.tscn"
const GAME := "res://scenes/game.tscn"

var state: State = State.MENU
var last_results: Dictionary = {}
## Offline: the next match uses this map seed (bot runs, so before-and-after
## comparisons play the same maps). Used once, then back to random.
var next_map_seed := 0

# Each new screen comes up out of ink. It never delays the change itself.
var _curtain_layer := CanvasLayer.new()
var _curtain := ColorRect.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_curtain_layer.layer = 90
	_curtain.color = Palette.INK
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_curtain.visible = false
	_curtain_layer.add_child(_curtain)
	add_child(_curtain_layer)


func goto(path: String) -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)
	if not UiFx.enabled():
		return
	_curtain.visible = true
	_curtain.modulate.a = 1.0
	var tw := _curtain.create_tween()
	tw.tween_property(_curtain, "modulate:a", 0.0, 0.25).set_ease(Tween.EASE_IN).set_delay(0.05)
	tw.tween_callback(func(): _curtain.visible = false)


func to_menu() -> void:
	Net.leave()
	state = State.MENU
	goto(MAIN_MENU)


func to_lobby() -> void:
	Net.leave()
	state = State.LOBBY
	for info in PlayerManager.players.values():
		info.is_ready = false
	goto(LOBBY)


func start_match() -> void:
	PlayerManager.reset_match_stats()
	state = State.COUNTDOWN
	goto(GAME)


func end_match(results: Dictionary) -> void:
	if state == State.ENDED:
		return
	state = State.ENDED
	last_results = results
	SignalBus.match_ended.emit(results)
