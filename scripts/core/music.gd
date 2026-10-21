extends Node

## Menu music. Plays on the title and lobby screens (carrying on between
## them), fades out when a match or the sandbox starts and comes back from
## the top on the next menu.

const TRACK := preload("res://assets/music/home_again.mp3")
const MENU_SCENES: Array[String] = ["res://scenes/main_menu.tscn", "res://scenes/lobby.tscn", "res://scenes/online_lobby.tscn"]
const FADE_IN := 1.5
const FADE_OUT := 0.8
const VOLUME_DB := -3.0          ## the track sits a little under full level

var _player := AudioStreamPlayer.new()
var _tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.stream = TRACK
	_player.bus = &"Music"
	add_child(_player)
	get_tree().scene_changed.connect(_on_scene_changed)
	_on_scene_changed.call_deferred()


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var wanted := scene != null and scene.scene_file_path in MENU_SCENES
	if wanted and not _player.playing:
		_fade(VOLUME_DB, FADE_IN, true)
	elif not wanted and _player.playing:
		_fade(-60.0, FADE_OUT, false)


func _fade(to_db: float, time: float, start: bool) -> void:
	if _tween:
		_tween.kill()
	if start:
		_player.volume_db = -60.0
		_player.play()
	_tween = create_tween()
	_tween.tween_property(_player, "volume_db", to_db, time).set_trans(Tween.TRANS_SINE)
	if not start:
		_tween.tween_callback(_player.stop)
