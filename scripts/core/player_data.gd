extends Resource
class_name PlayerData

@export var player_id: int = 1
@export var device_id: int = -1 # -1 for keyboard, 0+ for gamepads
@export var color: Color = Color.WHITE
@export var name: String = "Player"

# Stats/State for the current match
var score: int = 0
var is_ready: bool = false
var is_dead: bool = false
