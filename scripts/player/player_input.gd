class_name PlayerInput
extends RefCounted

## One player's controls for the current physics tick, plus the previous tick
## for press/release edges. Local players sample their InputMap actions;
## remote players get numbered frames fed in over the network. Player only
## ever reads from here, never from Input directly.
##
## Online, every tick of controls is a numbered frame. A guest simulates its
## own ball with each frame straight away (prediction) and sends it to the
## host; the host runs exactly one step per frame, in order, and reports the
## last frame it used so the guest can check its prediction (see Player).

## Bit index of each action is its position in Settings.ACTIONS.
var player_id := 1
var is_local := true

## While a menu is open over an online match the game keeps running, so
## local controls read as released instead.
static var suspended := false

var buttons := 0
var move := Vector2.ZERO        ## x: left/right axis, y: up/down axis
var _prev_buttons := 0
## Whether this frame's controls count. Online it travels with the frame, so
## the host and the guest agree exactly when controls switch on at the start.
var allowed := true
var allow_local := true         ## guest: set by the game before each tick
const ALLOWED_BIT := 1 << 24

## Remote frames: the host keeps a short queue and uses one per step.
const MAX_STALL := 12       ## steps to wait for a missing frame before moving on without it
const WINDOW := 60          ## steps over which the host checks whether it keeps more frames waiting than it needs
var seq := 0                ## local: frame number of the current tick; remote: last frame used
var _queue := {}            # frame number -> packed frame
var _stalled := 0
var _window := 0
var _fewest := 1000         # fewest frames waiting at any step in this window
var _catch_up := 0          # extra frames to use up, one per step, to shorten the wait


func _init(id := 1, local := true) -> void:
	player_id = id
	is_local = local


## Advance one tick. Call once at the start of the player's physics step.
func update() -> void:
	if not is_local:
		next_remote()
		return
	_prev_buttons = buttons
	buttons = 0
	move = Vector2.ZERO
	seq += 1
	allowed = allow_local
	if not suspended:
		for i in Settings.ACTIONS.size():
			if Input.is_action_pressed(PlayerManager.action(player_id, Settings.ACTIONS[i])):
				buttons |= 1 << i
		move = Vector2(
			Input.get_axis(PlayerManager.action(player_id, "left"), PlayerManager.action(player_id, "right")),
			Input.get_axis(PlayerManager.action(player_id, "up"), PlayerManager.action(player_id, "down")))


## Remote: how many steps to run this tick. Normally one per frame that has
## arrived; none while the next frame is late (the ball waits a moment, so
## the host's copy of it stays in step with the guest's). Frames that always
## sit waiting are just delay: if some were spare for a whole WINDOW, two are
## used in one step now and then until they're gone. After MAX_STALL the ball
## moves on without input.
func steps_due() -> int:
	if is_local:
		return 1
	if _queue.has(seq + 1):
		_stalled = 0
		_fewest = mini(_fewest, _queue.size())
		_window += 1
		if _window >= WINDOW:
			_catch_up = maxi(_fewest - 1, 0)   # keep one in hand for jitter
			_window = 0
			_fewest = 1000
		if _catch_up > 0 and _queue.size() >= 2:
			_catch_up -= 1
			return 2
		return 1
	if not _queue.is_empty():
		# A frame went missing for good: skip to the next one we have.
		seq = _queue.keys().min() - 1
		Net.stats.skips += 1
		return 1
	_stalled += 1
	Net.stats.stalls += 1
	return 1 if _stalled > MAX_STALL else 0


## Remote: take the next frame (or keep the last controls if there is none).
func next_remote() -> void:
	_prev_buttons = buttons
	if _queue.has(seq + 1):
		seq += 1
		var f: int = _queue[seq]
		_queue.erase(seq)
		_unpack(f)


## Guest replaying its own frames: put frame `f` back (with `prev` before it).
func load_frame(f: int, prev: int) -> void:
	_prev_buttons = prev & 0xFF
	_unpack(f)


func _unpack(f: int) -> void:
	buttons = f & 0xFF
	move = Vector2(((f >> 8) & 0xFF) - 128, ((f >> 16) & 0xFF) - 128) / 64.0
	move = move.limit_length(1.0)
	allowed = f & ALLOWED_BIT != 0


## Remote: frames `last - frames.size() + 1 .. last` from the network. Each
## packet repeats the last few, so a lost packet costs nothing.
func push_frames(last: int, frames: PackedInt32Array) -> void:
	var first := last - frames.size() + 1
	for k in frames.size():
		var n := first + k
		if n > seq and not _queue.has(n):
			_queue[n] = frames[k]


## Packs this tick's controls into one int (8 buttons, two signed axes).
func pack() -> int:
	var mx := clampi(roundi(move.x * 64.0), -64, 64) + 128
	var my := clampi(roundi(move.y * 64.0), -64, 64) + 128
	return (buttons & 0xFF) | (mx << 8) | (my << 16) | (ALLOWED_BIT if allowed else 0)


func clear() -> void:
	buttons = 0
	_prev_buttons = 0
	move = Vector2.ZERO
	seq = 0
	_queue.clear()
	_stalled = 0
	_window = 0
	_fewest = 1000
	_catch_up = 0


func pressed(action: String) -> bool:
	return buttons & _bit(action) != 0

func just_pressed(action: String) -> bool:
	var b := _bit(action)
	return buttons & b != 0 and _prev_buttons & b == 0

func just_released(action: String) -> bool:
	var b := _bit(action)
	return buttons & b == 0 and _prev_buttons & b != 0


static func _bit(action: String) -> int:
	return 1 << Settings.ACTIONS.find(action)
