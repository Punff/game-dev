class_name PlayerInput
extends RefCounted

## One player's controls for the current physics tick, plus the previous tick
## for press/release edges. Local players sample their InputMap actions;
## remote players get frames fed in over the network. Player only ever reads
## from here, never from Input directly.

## Bit index of each action is its position in Settings.ACTIONS.
var player_id := 1
var is_local := true

## While a menu is open over an online match the game keeps running, so
## local controls read as released instead.
static var suspended := false

var buttons := 0
var move := Vector2.ZERO        ## x: left/right axis, y: up/down axis
var _prev_buttons := 0

# Latest frame received for a remote player, applied on the next tick.
# Presses that start and end between two ticks are latched so taps survive.
var _remote_buttons := 0
var _remote_latched := 0
var _remote_move := Vector2.ZERO


func _init(id := 1, local := true) -> void:
	player_id = id
	is_local = local


## Advance one tick. Call once at the start of the player's physics step.
func update() -> void:
	_prev_buttons = buttons
	if is_local:
		buttons = 0
		move = Vector2.ZERO
		if suspended:
			return
		for i in Settings.ACTIONS.size():
			if Input.is_action_pressed(PlayerManager.action(player_id, Settings.ACTIONS[i])):
				buttons |= 1 << i
		move = Vector2(
			Input.get_axis(PlayerManager.action(player_id, "left"), PlayerManager.action(player_id, "right")),
			Input.get_axis(PlayerManager.action(player_id, "up"), PlayerManager.action(player_id, "down")))
	else:
		buttons = _remote_buttons | _remote_latched
		_remote_latched = 0
		move = _remote_move


## Feed a frame received from the network (remote players only).
func push_remote(new_buttons: int, new_move: Vector2) -> void:
	_remote_latched |= new_buttons & ~_remote_buttons
	_remote_buttons = new_buttons
	_remote_move = new_move.limit_length(1.0)


func clear() -> void:
	buttons = 0
	_prev_buttons = 0
	move = Vector2.ZERO
	_remote_buttons = 0
	_remote_latched = 0
	_remote_move = Vector2.ZERO


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
