class_name PlayerInfo
extends RefCounted

## Lobby/match data for one joined player.

var player_id := 1
var device_id := -1          ## Settings.DEVICE_KB_A / DEVICE_KB_B, or a joypad id
var color_index := 0
var is_ready := false
var peer_id := 0             ## online: the peer that controls this player (0 offline)

# Per-match results
var max_height := 0
var death_order := 0         ## 0 = still alive / winner


var color: Color:
	get: return Palette.PLAYER_COLORS[color_index]


var display_name: String:
	get: return "P%d" % player_id


func is_keyboard() -> bool:
	return device_id < 0


## Controlled from this machine (always true offline).
func is_local() -> bool:
	return peer_id == 0 or peer_id == Net.my_peer()


func device_label() -> String:
	if not is_local():
		return "Online"
	match device_id:
		Settings.DEVICE_ANY: return "This computer"
		Settings.DEVICE_KB_A: return "Keyboard Left"
		Settings.DEVICE_KB_B: return "Keyboard Right"
	var n := Input.get_joy_name(device_id)
	return n if n != "" else "Gamepad %d" % (device_id + 1)
