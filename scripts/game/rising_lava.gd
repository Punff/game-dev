extends Area2D

@export_group("Lava Properties")
@export var base_rise_speed: float = 30.0
@export var max_rise_speed: float = 120.0
@export var lava_width: float = 9000.0
@export var lava_height: float = 4000.0
@export var starting_y_position: float = 600.0

@export_group("Dynamic Balancing")
@export var safety_distance: float = 300.0 # Lava slows down when this close to player
@export var pressure_distance: float = 1000.0 # Lava speeds up when player is further than this

@export_group("Visual Settings")
@export var lava_color: Color = Color(1.0, 0.2, 0.0, 0.85)
@export var bubble_color: Color = Color(1.0, 0.5, 0.0, 0.6)

var current_speed: float = 30.0
var time_passed: float = 0.0
var bubbles: Array = []

func _ready():
	create_lava_visual()
	create_particles()
	setup_collision()
	global_position.y = starting_y_position
	z_index = 5

func _process(delta):
	calculate_dynamic_speed()
	global_position.y -= current_speed * delta
	time_passed += delta
	animate_lava(delta)
	_kill_overlapping_players()

func calculate_dynamic_speed():
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		current_speed = base_rise_speed
		return

	# Find the lowest player (the one closest to the lava)
	var lowest_player_y = -999999.0
	for p in players:
		if is_instance_valid(p) and not p.get("is_dead"):
			lowest_player_y = max(lowest_player_y, p.global_position.y)

	if lowest_player_y == -999999.0: return

	var distance_to_lava = global_position.y - lowest_player_y
	
	# RUBBER BANDING LOGIC:
	if distance_to_lava < safety_distance:
		# Player is in danger! Slow down to 25% of base speed
		current_speed = lerp(current_speed, base_rise_speed * 0.25, 0.05)
	elif distance_to_lava > pressure_distance:
		# Player is too far ahead! Speed up towards max
		current_speed = lerp(current_speed, max_rise_speed, 0.01)
	else:
		# Normal zone
		current_speed = lerp(current_speed, base_rise_speed, 0.02)

func reset_lava_position():
	global_position.y = starting_y_position
	current_speed = base_rise_speed
	# Clear bubbles to prevent lag over long sessions
	for b in bubbles:
		if is_instance_valid(b.node): b.node.queue_free()
	bubbles.clear()

func create_lava_visual():
	# Main Lava Body
	var body = ColorRect.new()
	body.name = "LavaBody"
	body.size = Vector2(lava_width, lava_height)
	body.color = Color(1.0, 0.2, 0.0, 0.9)
	body.position = Vector2(-lava_width/2, 0)
	
	# Add a simple Glow (requires WorldEnvironment with Glow enabled)
	body.modulate = Color(1.5, 1.2, 1.0) # Overdriving colors creates glow
	
	# SHADER: Add a wavy top edge
	var shader_code = """
	shader_type canvas_item;
	void fragment() {
		vec2 uv = UV;
		uv.y += sin(uv.x * 20.0 + TIME * 3.0) * 0.01; // Subtle wave
		COLOR = texture(TEXTURE, uv) * COLOR;
	}
	"""
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = shader_code
	mat.shader = sh
	body.material = mat
	
	add_child(body)
	
	# Animated Edge/Surface
	var edge = ColorRect.new()
	edge.size = Vector2(lava_width, 20)
	edge.color = Color(1, 0.8, 0.2, 1) # Bright yellow-orange edge
	edge.position = Vector2(-lava_width/2, -10)
	add_child(edge)

func setup_collision():
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false

	var shape = CollisionShape2D.new()
	var rect_shape = RectangleShape2D.new()
	rect_shape.size = Vector2(lava_width, lava_height)
	shape.shape = rect_shape
	shape.position = Vector2(0, lava_height/2 - 10)
	add_child(shape)

func animate_lava(delta):
	# Slight bobbing effect
	position.x = sin(time_passed * 2.0) * 10.0
	
	# Spawn random bubbles
	if randf() < 0.1 and bubbles.size() < 50:
		spawn_bubble()
		
	# Update existing bubbles
	for i in range(bubbles.size() - 1, -1, -1):
		var b = bubbles[i]
		if is_instance_valid(b.node):
			b.node.position.y -= b.rise_speed * delta
			if b.node.position.y < -50:
				b.node.queue_free()
				bubbles.remove_at(i)

func spawn_bubble():
	var b_node = ColorRect.new()
	b_node.size = Vector2(randf_range(5, 15), randf_range(5, 15))
	b_node.color = bubble_color
	b_node.position = Vector2(randf_range(-500, 500), lava_height/2)
	add_child(b_node)
	bubbles.append({"node": b_node, "rise_speed": randf_range(50, 150)})

func create_particles():
	var particles = CPUParticles2D.new()
	particles.amount = 100
	particles.lifetime = 4.0
	particles.texture = preload("res://assets/white_square.png") # Or a simple circle
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(4000, 1) # Match lava width
	particles.direction = Vector2(0, -1)
	particles.spread = 20.0
	particles.gravity = Vector2(0, -20) # Slow float up
	particles.initial_velocity_min = 50
	particles.initial_velocity_max = 150
	particles.scale_amount_min = 1.0
	particles.scale_amount_max = 4.0
	particles.color = Color(1, 0.5, 0, 0.6) # Translucent orange
	add_child(particles)

func _kill_overlapping_players():
	for body in get_overlapping_bodies():
		if not is_instance_valid(body): continue
		if body.is_in_group("player") and body.has_method("die") and not body.is_dead:
			body.die()
		
