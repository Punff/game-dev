extends Node

## Tiny procedural sound bank. Every sound is synthesised once at startup
## into an AudioStreamWAV, so the game ships with zero audio assets.

const RATE := 22050
const VOICES := 14

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	_build_bank()


## Plays a sound by name. `pitch_jitter` randomises pitch a little so
## repeated sounds don't feel robotic.
func play(name: String, volume_db := 0.0, pitch := 1.0, pitch_jitter := 0.04) -> void:
	var stream: AudioStreamWAV = _streams.get(name)
	if stream == null:
		return
	# Throttle identical sounds fired in the same few milliseconds.
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 35:
		return
	_last_played[name] = now
	if name == "ui_move" and now - int(_last_played.get("ui_select", -1000)) < 200:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))
	p.play()


# ── Synthesis ────────────────────────────────

func _build_bank() -> void:
	_streams["jump"] = _to_wav(_tone(0.11, 330.0, 620.0, "square", 0.22))
	_streams["double_jump"] = _to_wav(_tone(0.10, 520.0, 980.0, "square", 0.18))
	_streams["charge_jump"] = _to_wav(_tone(0.26, 180.0, 900.0, "saw", 0.22))
	_streams["land"] = _to_wav(_noise(0.07, 0.35, 900.0))
	_streams["bounce"] = _to_wav(_tone(0.28, 180.0, 760.0, "sine", 0.45, 18.0))
	_streams["shockwave"] = _to_wav(_mix([_noise(0.32, 0.4, 2400.0), _tone(0.32, 140.0, 40.0, "sine", 0.6)]))
	_streams["break"] = _to_wav(_mix([_noise(0.22, 0.5, 3000.0), _tone(0.12, 220.0, 90.0, "square", 0.15)]))
	_streams["gravity"] = _to_wav(_tone(0.30, 110.0, 160.0, "sine", 0.45, 9.0))
	_streams["death"] = _to_wav(_tone(0.55, 620.0, 70.0, "square", 0.25))
	_streams["count"] = _to_wav(_tone(0.14, 660.0, 660.0, "square", 0.2))
	_streams["go"] = _to_wav(_tone(0.36, 990.0, 990.0, "square", 0.22))
	_streams["ui_move"] = _to_wav(_tone(0.035, 1300.0, 1300.0, "sine", 0.25))
	_streams["ui_select"] = _to_wav(_tone(0.09, 880.0, 1320.0, "square", 0.14))
	_streams["ui_back"] = _to_wav(_tone(0.09, 640.0, 420.0, "square", 0.14))
	_streams["join"] = _to_wav(_seq([[523.25, 0.07], [783.99, 0.12]], "square", 0.18))
	_streams["leave"] = _to_wav(_seq([[587.33, 0.07], [392.0, 0.12]], "square", 0.16))
	_streams["win"] = _to_wav(_seq([[523.25, 0.1], [659.25, 0.1], [783.99, 0.1], [1046.5, 0.32]], "square", 0.2))
	_streams["chain"] = _to_wav(_seq([[783.99, 0.06], [1046.5, 0.06], [1318.5, 0.14]], "square", 0.18))
	_streams["speed"] = _to_wav(_tone(0.12, 400.0, 900.0, "saw", 0.12))
	_streams["vanish"] = _to_wav(_tone(0.18, 900.0, 300.0, "sine", 0.25))


func _osc(kind: String, phase: float) -> float:
	match kind:
		"square": return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw": return fmod(phase, 1.0) * 2.0 - 1.0
	return sin(phase * TAU)


## Pitch sweep with a quick attack and exponential-ish decay.
func _tone(dur: float, f0: float, f1: float, kind: String, vol: float, vibrato := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f0, f1, t)
		if vibrato > 0.0:
			f *= 1.0 + 0.06 * sin(t * dur * vibrato * TAU)
		phase += f / RATE
		var env := minf(t * 40.0, 1.0) * pow(1.0 - t, 1.6)
		out[i] = _osc(kind, phase) * env * vol
	return out


## Low-passed white noise burst.
func _noise(dur: float, vol: float, cutoff: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := clampf(cutoff / RATE * TAU, 0.0, 1.0)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * vol * 2.2 * pow(1.0 - t, 2.0)
	return out


func _seq(notes: Array, kind: String, vol: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		out.append_array(_tone(note[1], note[0], note[0], kind, vol))
	return out


func _mix(parts: Array) -> PackedFloat32Array:
	var n := 0
	for p in parts:
		n = maxi(n, p.size())
	var out := PackedFloat32Array()
	out.resize(n)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav

