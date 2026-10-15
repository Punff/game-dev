extends ColorRect

@export_group("Height Settings")
@export var start_height: float = 0.0          # Starting Y (Floor)
@export var target_height: float = 10000.0     # Maximum height for color change
@export var height_gradient: Gradient          # Create this in the Inspector!

var player_ref: Node2D = null
var initial_y: float = 0.0

func _ready():
	# Find Player 1 to track height
	player_ref = get_tree().get_first_node_in_group("player")
	if player_ref:
		initial_y = player_ref.global_position.y

func _process(_delta: float) -> void:
	if not player_ref: 
		player_ref = get_tree().get_first_node_in_group("player")
		return
	
	# 1. Calculate how high the player has gone (consistent with your UI script)
	var current_height = initial_y - player_ref.global_position.y
	
	# 2. Map height to a 0.0 - 1.0 range
	var progress = remap(current_height, start_height, target_height, 0.0, 1.0)
	progress = clamp(progress, 0.0, 1.0)
	
	# 3. Apply color from Gradient
	if height_gradient:
		# We use 'self.modulate' to change the color of the fog texture
		self.modulate = height_gradient.sample(progress)
