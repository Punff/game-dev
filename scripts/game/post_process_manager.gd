extends CanvasLayer

var _mat: ShaderMaterial

var _jazz_overlay: Control

func _ready():
	layer = 10 # Above everything
	var rect = ColorRect.new()
	rect.color = Color(1, 1, 1, 0) # Transparent by default
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/post_process_glitch.gdshader")
	_mat.set_shader_parameter("aberration_amount", 0.0)
	_mat.set_shader_parameter("glitch_intensity", 0.0)
	rect.material = _mat
	add_child(rect)
	
	_jazz_overlay = Control.new()
	_jazz_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_jazz_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_jazz_overlay)
	
	SignalBus.chain_reaction_occurred.connect(_on_chain_reaction)

func _on_chain_reaction(count: int) -> void:
	# Jazz Sequence / Freeze Frame
	Engine.time_scale = 0.05
	_flash_jazz_bars()
	
	await get_tree().create_timer(0.15, true, false, true).timeout
	Engine.time_scale = 1.0

func _flash_jazz_bars() -> void:
	# Create multi-layered color bars (Cowboy Bebop title card style)
	var colors = [
		Color(1.0, 1.0, 0.0), # Neon Yellow
		Color(1.0, 0.27, 0.0), # Ember Orange
		Color(0.5, 0.1, 0.1), # Burgundy
		Color(0.0, 0.0, 0.0)  # Black
	]
	
	for i in range(8):
		var bar = ColorRect.new()
		bar.color = colors[i % colors.size()]
		bar.custom_minimum_size.y = 80
		bar.size.x = 2000
		bar.rotation = deg_to_rad(-15)
		bar.position = Vector2(-200, i * 120 - 100)
		_jazz_overlay.add_child(bar)
		
		var tween = create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tween.tween_property(bar, "position:x", 2000, 0.3)
		tween.finished.connect(bar.queue_free)

func _process(_delta):
	# Optimization: Skip expensive calculations every frame
	if Engine.get_frames_drawn() % 2 != 0: return
	
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty(): return
	
	var max_speed = 0.0
	for p in players:
		if is_instance_valid(p):
			var s_sq = p.velocity.length_squared()
			if s_sq > max_speed: max_speed = s_sq
	
	var speed_factor = clamp(sqrt(max_speed) / 1500.0, 0.0, 1.0)
	_mat.set_shader_parameter("aberration_amount", speed_factor * 3.0)
	
	# Only update glitch occasionally
	if speed_factor > 0.85:
		_mat.set_shader_parameter("glitch_intensity", 0.1)
	else:
		_mat.set_shader_parameter("glitch_intensity", 0.0)
