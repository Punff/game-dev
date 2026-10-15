extends Node

## Procedural noir-jazz sound bank: upright-bass plucks (Karplus-Strong),
## finger snaps, rimshots, brass stabs, a revolver-crack shockwave and
## cymbals. Everything is synthesised at startup - one sound per frame so
## there's no hitch - into AudioStreamWAVs. Zero audio assets shipped.

const RATE := 22050
const VOICES := 16

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _last_played: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 1977
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
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 35:
		return
	_last_played[name] = now
	if name == "ui_move" and now - int(_last_played.get("ui_select", -1000)) < 200:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.volume_db = volume_db + BASE_DB
	p.pitch_scale = pitch * (1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter))
	p.play()


## Everything is mixed a bit under the bus so the sliders have headroom.
const BASE_DB := -6.0


# ── Bank ─────────────────────────────────────

const A2 := 110.0
const E3 := 164.81
const G3 := 196.0
const A3 := 220.0
const C4 := 261.63
const D4 := 293.66
const E4 := 329.63
const G4 := 392.0
const B4 := 493.88

func _build_bank() -> void:
	# Kept soft and short on purpose: these fire constantly with 4 players.
	var recipes := {
		"jump": func(): return _pluck(A2 * 2.0, 0.16, 0.16, 0.985),
		"double_jump": func(): return _pluck(E3 * 2.0, 0.14, 0.13, 0.985),
		"charge_jump": func(): return _mix([_pluck(A2, 0.3, 0.2, 0.99), _whoosh(0.22, 0.08)]),
		"land": func(): return _tone(0.06, 90.0, 50.0, 0.18),
		"bounce": func(): return _tone(0.22, 160.0, 380.0, 0.12, true),
		"shockwave": func(): return _mix([_tone(0.25, 110.0, 40.0, 0.35), _noise(0.22, 0.12, 900.0)]),
		"break": func(): return _crumble(),
		"gravity": func(): return _vibes([E4], 0.35, 0.05),
		"throw": func(): return _whoosh(0.2, 0.1),
		"hit": func(): return _mix([_tone(0.08, 160.0, 80.0, 0.25), _noise(0.05, 0.08, 1500.0)]),
		"speed": func(): return _whoosh(0.12, 0.05),
		"vanish": func(): return _noise(0.18, 0.06, 800.0),
		"death": func(): return _mix([_pluck(A2 * 0.5, 0.6, 0.3, 0.995), _noise(0.3, 0.1, 600.0)]),
		"count": func(): return _snap(),
		"go": func(): return _pluck(A3, 0.3, 0.2, 0.99),
		"chain": func(): return _tone(0.15, 200.0, 70.0, 0.25),
		"win": func(): return _seq_samples([_pluck(A3, 0.14, 0.18, 0.99), _pluck(C4, 0.14, 0.18, 0.99), _pluck(E4, 0.5, 0.2, 0.995)]),
		"ui_move": func(): return _hat(0.02, 0.05),
		"ui_select": func(): return _pluck(A3, 0.1, 0.12, 0.98),
		"ui_back": func(): return _pluck(E3, 0.1, 0.12, 0.98),
		"join": func(): return _pluck(E4, 0.18, 0.14, 0.99),
		"leave": func(): return _pluck(A3, 0.18, 0.12, 0.99),
	}
	for key in recipes:
		_streams[key] = _to_wav(recipes[key].call())
		await get_tree().process_frame   # spread the work so startup never hitches


# ── Instruments ──────────────────────────────

## Karplus-Strong plucked string - an upright bass at low pitches.
func _pluck(f: float, dur: float, vol: float, damp := 0.994) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var period := maxi(2, int(RATE / f))
	var ring := PackedFloat32Array()
	ring.resize(period)
	var lp := 0.0
	for i in period:
		lp += 0.5 * (_rng.randf_range(-1.0, 1.0) - lp)   # warmer excitation
		ring[i] = lp
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var idx := i % period
		var nxt := (idx + 1) % period
		var v := ring[idx]
		out[i] = v * vol * 1.6
		ring[idx] = damp * 0.5 * (v + ring[nxt])
	return out


## Pitch sweep with a quick attack and decay (sine or triangle).
func _tone(dur: float, f0: float, f1: float, vol: float, tri := false) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / n
		phase += lerpf(f0, f1, t) / RATE
		var v := sin(phase * TAU) if not tri else 1.0 - 4.0 * absf(fmod(phase, 1.0) - 0.5)
		out[i] = v * minf(t * 60.0, 1.0) * pow(1.0 - t, 1.5) * vol
	return out


## Section of saw-wave horns through a filter that opens and closes: a stab.
func _brass(freqs: Array, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phases := []
	for f in freqs:
		phases.append([0.0, 0.0])
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.02, 1.0) * exp(-t * 3.0 / dur)
		var vib := 1.0 + 0.006 * sin(t * TAU * 5.5) * minf(t * 4.0, 1.0)
		var s := 0.0
		for k in freqs.size():
			var ph: Array = phases[k]
			ph[0] = fmod(ph[0] + freqs[k] * vib / RATE, 1.0)
			ph[1] = fmod(ph[1] + freqs[k] * 1.007 * vib / RATE, 1.0)
			s += (ph[0] * 2.0 - 1.0) + (ph[1] * 2.0 - 1.0)
		s /= freqs.size() * 2.0
		var cutoff := 300.0 + 3200.0 * env
		y += (1.0 - exp(-TAU * cutoff / RATE)) * (s - y)
		out[i] = y * env * vol * 2.2
	return out


## Vibraphone: sine + bright partial with motor tremolo.
func _vibes(freqs: Array, dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for f in freqs:
		for i in n:
			var t := float(i) / RATE
			var env := minf(t / 0.004, 1.0) * exp(-t * 3.5)
			var trem := 0.8 + 0.2 * sin(t * TAU * 6.0)
			out[i] += (sin(t * TAU * f) + 0.25 * sin(t * TAU * f * 4.0) * exp(-t * 12.0)) * env * trem * vol
	return out


## Revolver crack: sharp transient, low body, long gritty tail.
func _gunshot() -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := _rng.randf_range(-1.0, 1.0)
		var crack := x * exp(-t * 90.0) * 0.9
		lp += (1.0 - exp(-TAU * lerpf(4000.0, 500.0, minf(t * 3.0, 1.0)) / RATE)) * (x - lp)
		var tail := lp * exp(-t * 7.0) * 0.55
		phase += lerpf(160.0, 40.0, minf(t * 8.0, 1.0)) / RATE
		var body := sin(phase * TAU) * exp(-t * 18.0) * 0.6
		out[i] = crack + tail + body
	return out


## Concrete crumbling: a thump and a scatter of low gritty bursts.
func _crumble() -> PackedFloat32Array:
	var out := _tone(0.1, 110.0, 50.0, 0.25)
	out.resize(int(0.35 * RATE))
	for k in 5:
		var at := int(_rng.randf_range(0.0, 0.22) * RATE)
		var burst := _noise(_rng.randf_range(0.03, 0.07), _rng.randf_range(0.05, 0.12), _rng.randf_range(500.0, 1400.0))
		for i in burst.size():
			if at + i < out.size():
				out[at + i] += burst[i]
	return out


## Muted-trumpet "wah" sliding down - the sad horn.
func _wah() -> PackedFloat32Array:
	var dur := 0.8
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(330.0, 140.0, pow(t / dur, 0.7))
		phase = fmod(phase + f / RATE, 1.0)
		var s := phase * 2.0 - 1.0
		var wah := 0.5 + 0.5 * sin(t * TAU * 4.0)
		var cutoff := 250.0 + 1800.0 * wah
		y += (1.0 - exp(-TAU * cutoff / RATE)) * (s - y)
		out[i] = y * minf(t / 0.03, 1.0) * (1.0 - t / dur) * 0.5
	return out


func _noise(dur: float, vol: float, cutoff: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		y += a * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * vol * 2.0 * pow(1.0 - t, 2.0)
	return out


## High-passed noise: hats, snaps, cymbals.
func _hiss(dur: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := _rng.randf_range(-1.0, 1.0)
		y += 0.25 * (x - y)
		out[i] = (x - y) * vol * exp(-t * decay)
	return out


func _hat(dur: float, vol: float) -> PackedFloat32Array:
	return _hiss(dur, vol, 80.0)


func _cymbal(dur: float, vol: float) -> PackedFloat32Array:
	return _hiss(dur, vol, 3.5)


func _snap() -> PackedFloat32Array:
	return _hiss(0.05, 0.18, 70.0)


func _click(vol: float) -> PackedFloat32Array:
	return _hiss(0.015, vol, 300.0)


func _rimshot(vol: float) -> PackedFloat32Array:
	return _mix([_hiss(0.05, vol, 120.0), _tone(0.06, 520.0, 480.0, vol * 0.7)])


func _whoosh(dur: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var y := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := lerpf(300.0, 4000.0, t)
		y += (1.0 - exp(-TAU * cutoff / RATE)) * (_rng.randf_range(-1.0, 1.0) - y)
		out[i] = y * vol * 2.0 * sin(t * PI)
	return out


func _seq_samples(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
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
