extends Node

## Browsers don't tell Godot the display's refresh rate, so the delta
## smoothing that keeps desktop builds at exactly one physics step per frame
## can't work there. Frame times also arrive rounded to whole milliseconds
## (Firefox, without cross-origin isolation) and jitter between 14 and 19 ms
## around a 16.7 ms refresh. With interpolation on, everything is drawn at
## that jittery time - micro-stutter - and some frames run 0 or 2 physics
## steps.
##
## On a ~60 Hz browser we drop interpolation and let the jitter fix lock
## physics to one step per drawn frame, so every frame on screen moves by
## exactly one tick. Measured in Firefox (Zen): frames where on-screen motion
## jumped by more than a tenth of a tick went from 12-50 to 1-4 per ~1200, and
## interpolation's frame of render delay is gone. Faster displays keep
## interpolation, which is what smooths them.

const SAMPLE_FRAMES := 90
const SETTLE_TIME := 1.0           ## skip the first second (loading hitches)

var _deltas := PackedFloat64Array()
var _last := 0


func _ready() -> void:
	if not OS.has_feature("web"):
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	await get_tree().create_timer(SETTLE_TIME, true, false, true).timeout
	_last = Time.get_ticks_usec()
	set_process(true)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_deltas.append(now - _last)
	_last = now
	if _deltas.size() < SAMPLE_FRAMES:
		return
	_deltas.sort()
	var hz := 1000000.0 / _deltas[_deltas.size() / 2]   # median: ignores throttled/hitched frames
	if absf(hz - Engine.physics_ticks_per_second) < 6.0:
		get_tree().physics_interpolation = false
		Engine.physics_jitter_fix = 0.5
	print("Web pacing: display ~%.0f Hz, physics interpolation %s" % [hz, "on" if get_tree().physics_interpolation else "off"])
	queue_free()
