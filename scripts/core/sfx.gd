extends Node

## Sound hook. The game ships silent: every gameplay event still calls
## Sfx.play("name"), so to add sounds just drop files named after the event
## into res://assets/sfx/ (e.g. jump.ogg, shockwave.wav) - they're picked up
## automatically. Event names: jump, double_jump, charge_jump, land, bounce,
## shockwave, break, gravity, throw, hit, speed, vanish, death, count, go,
## chain, win, ui_move, ui_select, ui_back, join, leave.

const DIR := "res://assets/sfx/"
const VOICES := 12

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for file in ResourceLoader.list_directory(DIR):
		var stream := load(DIR + file) as AudioStream
		if stream:
			_streams[file.get_basename()] = stream
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)


func has_sounds() -> bool:
	return not _streams.is_empty()


func play(name: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.04) -> void:
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 50:
		return
	_last_played[name] = now
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter)
	p.play()
