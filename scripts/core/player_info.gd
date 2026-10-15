class_name PlayerInfo
extends RefCounted

## Lobby/match data for one joined player.

var player_id := 1
var device_id := -1          ## Settings.DEVICE_KB_A / DEVICE_KB_B, or a joypad id
var color_index := 0
var is_ready := false

# Per-match results
var max_height := 0
var death_order := 0         ## 0 = still alive / winner


var color: Color:
	get: return Palette.PLAYER_COLORS[color_index]


var display_name: String:
	get: return "P%d" % player_id


func is_keyboard() -> bool:
	return device_id < 0


func device_label() -> String:
	match device_id:
		Settings.DEVICE_KB_A: return "Keyboard Left"
		Settings.DEVICE_KB_B: return "Keyboard Right"
	var n := Input.get_joy_name(device_id)
	return n if n != "" else "Gamepad %d" % (device_id + 1)
