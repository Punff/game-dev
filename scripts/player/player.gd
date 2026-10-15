class_name Player extends CharacterBody2D

const VisualEffects = preload("res://scripts/blocks/visual_effects.gd")

@export_group("Player Settings")
var player_data: PlayerData

var jump_action:      String = ""
var left_action:      String = ""
var right_action:     String = ""
var up_action:        String = ""
var down_action:      String = ""
var charge_action:    String = ""
var gravity_action:   String = ""
var shockwave_action: String = ""

@export_group("Movement")
@export var speed:             float = 300.0
@export var acceleration:      float = 18.0
@export var friction:          float = 16.0
@export var jump_height:       float = 600.0
@export var max_jumps:         int   = 2
@export var jump_force_radius:    float = 200.0
@export var jump_force_strength:  float = 500.0
@export var show_force_radius: bool  = true

@export_group("Gravity Field")
@export var gravity_field_radius:             float = 140.0
@export var gravity_field_strength:           float = 350.0
@export var gravity_field_direction_strength: float = 120.0
@export var upward_lift_force:                float = 1200.0
@export var platform_gather_force:            float = 400.0
@export var platform_radius:                  float = 60.0
@export var fragment_push_force:              float = 400.0
@export var push_distance_threshold:          float = 80.0
@export var gravity_field_cooldown:           float = 5.0
@export var gravity_field_max_duration:       float = 1.0
@export var show_gravity_field:               bool  = true

@export_group("Shockwave")
@export var shockwave_range:          float = 450.0
@export var shockwave_force:          float = 1800.0
@export var shockwave_fragment_force: float = 300.0

@export_group("Charged Jump")
@export var max_charge_time: float = 1.5
@export var max_charge_jump: float = 800.0
@export var fast_fall_force: float = 3500.0
@export var max_fall_speed:  float = 4000.0

var gravity: float = 1200.0

var jumps_remaining: int  = 0
var _was_on_floor:   bool = true
var is_dead:         bool = false

var is_charging_jump: bool  = false
var charge_time:      float = 0.0
var charge_visual            = null

var gravity_field_active:         bool  = false
var ability_cooldown_timer:       float = 0.0
var gravity_field_duration_timer: float = 0.0
var gravity_field_visual                = null

var attracted_fragments:          Array = []
var fragment_original_properties: Dictionary = {}
var _grab_time:                   Dictionary = {}

var _movement_lines = null
var _facing_dir: float = 1.0
var _current_blocks: Array = []

signal player_died(player_id: int)

func _ready() -> void:
	add_to_group("player")
	if player_data:
		setup_with_data(player_data)
	_movement_lines = VisualEffects.MovementLines.new()
	add_child(_movement_lines)

func setup_with_data(data: PlayerData) -> void:
	player_data = data
	var prefix := "p%d_" % player_data.player_id
	jump_action      = prefix + "jump"
	left_action      = prefix + "left"
	right_action     = prefix + "right"
	up_action        = prefix + "up"
	down_action      = prefix + "down"
	charge_action    = prefix + "charge"
	gravity_action   = prefix + "gravity"
	shockwave_action = prefix + "shockwave"

	add_to_group("player%d" % player_data.player_id)
	_facing_dir = -1.0 if player_data.player_id == 2 else 1.0

	var rect := get_node_or_null("ColorRect")
	if rect:
		rect.color = player_data.color
	
	_setup_player_visual()

func _setup_player_visual() -> void:
	if not player_data: return
	var rect := $ColorRect
	if not rect: return
	if player_data: rect.color = player_data.color
	else: rect.color = Color.WHITE

	# Noir Player Shader: Thick outline + Visor core
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float outline_width : hint_range(0.01, 0.2) = 0.1;
uniform vec4  outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4  visor_color   : source_color = vec4(1.0, 1.0, 1.0, 0.8);

void fragment() {
	float dist    = distance(UV, vec2(0.5));
	float fill    = smoothstep(0.5, 0.47, dist);
	float outline = smoothstep(0.5, 0.47, dist - outline_width) - fill;
	
	// Visor / Core effect
	float visor = smoothstep(0.15, 0.05, abs(UV.y - 0.4)) * smoothstep(0.4, 0.35, abs(UV.x - 0.5));
	
	vec4 base = COLOR;
	base = mix(base, visor_color, visor * visor_color.a);
	
	COLOR = mix(vec4(0.0), outline_color, outline);
	COLOR = mix(COLOR, base, fill);
	COLOR.a = max(fill, outline);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("outline_width", 0.1)
	mat.set_shader_parameter("outline_color", Color.BLACK)
	mat.set_shader_parameter("visor_color", Color(1, 1, 1, 0.8))
	rect.material = mat
	
	_add_player_indicator()

func _add_player_indicator() -> void:
	if not player_data or has_node("Indicator"): return
	var label = Label.new()
	label.name = "Indicator"
	label.text = "P%d" % player_data.player_id
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(60, 30)
	label.position = Vector2(-30, -50) # Positioned above the ball
	
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	
	add_child(label)

func _spawn_trail_fragment() -> void:
	# Optimization: only spawn fragments at high speed
	if velocity.length_squared() < 40000: return # Speed > 200
	if Engine.get_frames_drawn() % 4 != 0: return
	
	var trail = ColorRect.new()
	trail.size = $ColorRect.size * 0.8
	trail.position = global_position - trail.size/2
	trail.color = player_data.color
	trail.color.a = 0.4
	trail.top_level = true
	trail.z_index = z_index - 1
	
	# Reuse player shader for trail but simpler
	trail.material = ShaderMaterial.new()
	trail.material.shader = $ColorRect.material.shader
	trail.material.set_shader_parameter("outline_width", 0.05)
	trail.material.set_shader_parameter("visor_color", Color(1, 1, 1, 0))
	
	get_tree().current_scene.add_child(trail)
	
	var tween = create_tween()
	tween.tween_property(trail, "scale", Vector2.ZERO, 0.3)
	tween.parallel().tween_property(trail, "modulate:a", 0.0, 0.3)
	tween.finished.connect(trail.queue_free)

func _physics_process(delta: float) -> void:
	if is_dead or not player_data or not is_inside_tree():
		return

	_spawn_trail_fragment()

	if ability_cooldown_timer > 0.0:
		ability_cooldown_timer -= delta

	if gravity_field_active:
		gravity_field_duration_timer += delta
		if gravity_field_duration_timer >= gravity_field_max_duration:
			deactivate_gravity_field()

	if is_on_floor():
		jumps_remaining = max_jumps
		# Apply a tiny bit of gravity to keep collision active for detection
		velocity.y += gravity * delta * 0.1
	else:
		velocity.y += gravity * delta

	_handle_charged_jump(delta)

	if Input.is_action_just_pressed(jump_action) and jumps_remaining > 0 and not is_charging_jump:
		velocity.y = -jump_height
		jumps_remaining -= 1
		_emit_jump_force()
		if show_force_radius:
			_create_force_wave_effect()

	if Input.is_action_pressed(gravity_action) and _can_activate_gravity_field():
		if not gravity_field_active:
			activate_gravity_field()
	elif Input.is_action_just_released(gravity_action) and gravity_field_active:
		deactivate_gravity_field()

	if gravity_field_active:
		_update_gravity_field(delta)

	if Input.is_action_just_pressed(shockwave_action) and _can_activate_shockwave():
		_fire_shockwave()

	var direction := Input.get_axis(left_action, right_action)
	if has_meta("controls_reversed"):
		direction = -direction

	var target_vx := 0.0
	if direction != 0.0:
		target_vx = direction * speed
		_facing_dir = direction

	var rate := acceleration if direction != 0.0 else friction
	# We move toward the target horizontal velocity, but we allow 
	# additive forces (like conveyors/push zones) to be handled by the blocks themselves.
	velocity.x = move_toward(velocity.x, target_vx, rate * delta * 60.0)

	if not is_on_floor() and Input.is_action_pressed(down_action):
		velocity.y += fast_fall_force * delta
		velocity.y = min(velocity.y, max_fall_speed)

	_apply_squash_and_stretch(delta)

	if _movement_lines:
		_movement_lines.set_velocity(velocity)

	move_and_slide()
	_handle_block_interactions(delta)
	_process_player_collisions()
	_process_fragment_riding()

	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor:
		_spawn_landing_impact()

	_was_on_floor = on_floor_now

func _process_fragment_riding() -> void:
	if not is_on_floor(): return
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		if not col: continue
		var body = col.get_collider()
		if body is RigidBody2D and body.get_meta("rideable", false):
			velocity.y = body.linear_velocity.y
			break

func _process_player_collisions():
	var push_force := 200.0
	var max_sep_speed := 300.0
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		if not col: continue
		var c = col.get_collider()
		if c is CharacterBody2D and c.is_in_group("player"):
			var dir = c.global_position - global_position
			if dir.length_squared() < 0.01:
				dir = Vector2(randf_range(-1, 1), 0).normalized()
			else:
				dir = dir.normalized()
			var rel_vel = c.velocity - velocity
			var rel_along = rel_vel.dot(dir)
			if rel_along < max_sep_speed:
				var impulse = dir * push_force
				c.velocity += impulse
				velocity -= impulse

func _handle_block_interactions(delta: float):
	var new_blocks = []
	
	for i in get_slide_collision_count():
		var col = get_slide_collision(i)
		if not col: continue
		var collider = col.get_collider()
		var block = collider
		while block and not block.is_in_group("blocks") and block != get_tree().current_scene:
			block = block.get_parent()
		if block and block.is_in_group("blocks") and not block in new_blocks:
			new_blocks.append(block)
	
	for block in new_blocks:
		if not block in _current_blocks:
			if block.has_method("on_player_land"):
				block.on_player_land(self)
	
	for block in new_blocks:
		if block.has_method("on_player_stand"):
			block.on_player_stand(self, delta)
		
	for block in _current_blocks:
		if not is_instance_valid(block) or not block in new_blocks:
			if is_instance_valid(block) and block.has_method("on_player_leave"):
				block.on_player_leave(self)
				
	_current_blocks = new_blocks

func _apply_squash_and_stretch(delta: float) -> void:
	var sprite := $ColorRect
	if not sprite: return
	if is_on_floor() and not _was_on_floor:
		sprite.scale = Vector2(1.4, 0.6)
	elif not is_on_floor() and _was_on_floor:
		sprite.scale = Vector2(0.65, 1.4)
	sprite.scale = sprite.scale.lerp(Vector2.ONE, 12.0 * delta)

func die() -> void:
	if is_dead: return
	is_dead = true
	velocity = Vector2.ZERO
	if _movement_lines: _movement_lines.set_velocity(Vector2.ZERO)
	deactivate_gravity_field()
	_stop_charge_visual()

	modulate.a = 0.0
	set_collision_layer(0)
	set_collision_mask(0)
	process_mode = Node.PROCESS_MODE_DISABLED

	if SignalBus.has_signal("player_died"):
		SignalBus.player_died.emit(player_data.player_id)
	player_died.emit(player_data.player_id)

	get_tree().create_timer(2.0).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func take_damage(_amount: int) -> void:
	die()

func reset_player() -> void:
	is_dead                      = false
	visible                      = true
	process_mode                 = Node.PROCESS_MODE_INHERIT
	velocity                     = Vector2.ZERO
	modulate.a                   = 1.0
	set_collision_layer(1)
	set_collision_mask(1)
	jumps_remaining              = max_jumps
	is_charging_jump             = false
	charge_time                  = 0.0
	gravity_field_active         = false
	ability_cooldown_timer       = 0.0
	gravity_field_duration_timer = 0.0

	for fragment in attracted_fragments:
		if is_instance_valid(fragment):
			if fragment.get_meta("controlling_player", null) == self:
				fragment.remove_meta("controlling_player")
			_restore_fragment_properties(fragment)
	attracted_fragments.clear()
	fragment_original_properties.clear()
	_grab_time.clear()
	_stop_charge_visual()
	if gravity_field_visual:
		gravity_field_visual.queue_free()
		gravity_field_visual = null

func _can_activate_gravity_field() -> bool:
	return ability_cooldown_timer <= 0.0

func _can_activate_shockwave() -> bool:
	return ability_cooldown_timer <= 0.0

func activate_gravity_field() -> void:
	gravity_field_active         = true
	gravity_field_duration_timer = 0.0
	_create_gravity_field_visual()
	_update_attracted_fragments(0.0)

func deactivate_gravity_field() -> void:
	if not gravity_field_active: return
	gravity_field_active         = false
	ability_cooldown_timer       = gravity_field_cooldown
	gravity_field_duration_timer = 0.0

	_push_close_fragments()

	for fragment in attracted_fragments:
		if not is_instance_valid(fragment): continue
		if fragment.get_meta("controlling_player", null) == self:
			fragment.remove_meta("controlling_player")
		_restore_fragment_properties(fragment)

	attracted_fragments.clear()
	fragment_original_properties.clear()
	_grab_time.clear()

	if gravity_field_visual:
		gravity_field_visual.queue_free()
		gravity_field_visual = null

func _fire_shockwave() -> void:
	var h = Input.get_axis(left_action, right_action)
	var v = Input.get_axis(up_action, down_action)
	var dir = Vector2(h, v)
	if dir.length_squared() < 0.01: dir = Vector2(_facing_dir, 0)
	else: dir = dir.normalized()

	ability_cooldown_timer = gravity_field_cooldown
	var origin = global_position

	var wave = VisualEffects.ShockwaveEffect.new()
	wave.direction = dir
	wave.max_distance = shockwave_range
	get_tree().current_scene.add_child(wave)
	wave.global_position = origin

	var affected = []
	for g in ["destructible_blocks", "bouncy_blocks", "reverse_blocks", "ice_blocks", "moving_blocks", "regular_blocks", "player", "fragments"]:
		affected.append_array(get_tree().get_nodes_in_group(g))

	for node in affected:
		if node == self: continue
		var to_node = node.global_position - origin
		var dist = to_node.length()
		if dist > shockwave_range or dist < 8.0: continue
		var node_dir = to_node.normalized()
		if node_dir.dot(dir) < 0.25: continue
		var falloff = 1.0 - dist / shockwave_range

		if node.is_in_group("player") and node is CharacterBody2D:
			node.velocity += node_dir * shockwave_force * falloff
			if node.gravity_field_active:
				node.deactivate_gravity_field()
				node.ability_cooldown_timer = node.gravity_field_cooldown
		elif node.is_in_group("fragments") and node is RigidBody2D:
			if node.has_meta("controlling_player"):
				var controller = node.get_meta("controlling_player")
				if is_instance_valid(controller):
					controller.attracted_fragments.erase(node)
				node.remove_meta("controlling_player")
			_restore_fragment_properties(node)
			node.set_meta("shockwave_stun", 0.6)
			node.linear_damp = 0.8
			node.angular_damp = 1.0
			node.apply_central_impulse(node_dir * shockwave_fragment_force * falloff * 2.2)
		elif node.has_method("on_shockwave"):
			node.on_shockwave(node_dir, origin, shockwave_range)

func _update_gravity_field(delta: float) -> void:
	_update_attracted_fragments(delta)
	for fragment in attracted_fragments:
		if is_instance_valid(fragment):
			_apply_gravity_field_to_fragment(fragment, delta)

func _update_attracted_fragments(delta: float) -> void:
	var new_attracted = []
	var all_nodes: Array = get_tree().get_nodes_in_group("fragments")

	for fragment in all_nodes:
		if not is_instance_valid(fragment) or not (fragment is RigidBody2D):
			continue

		if fragment.has_meta("shockwave_stun"):
			var stun_time: float = fragment.get_meta("shockwave_stun")
			stun_time -= delta
			if stun_time <= 0.0:
				fragment.remove_meta("shockwave_stun")
			else:
				fragment.set_meta("shockwave_stun", stun_time)
				continue

		var dist: float = global_position.distance_to(fragment.global_position)
		var in_radius = dist <= gravity_field_radius
		var was_attracted = attracted_fragments.has(fragment) or fragment.has_meta("controlling_player")
		if not (in_radius or (was_attracted and dist <= gravity_field_radius * 1.15)):
			continue

		var can_attract = true

		if fragment.has_meta("controlling_player"):
			var controller = fragment.get_meta("controlling_player")
			if is_instance_valid(controller) and controller != self:
				var dist_to_controller = controller.global_position.distance_to(fragment.global_position)
				if dist < dist_to_controller * 0.85:
					controller.attracted_fragments.erase(fragment)
				else:
					can_attract = false

		if can_attract:
			new_attracted.append(fragment)
			if not attracted_fragments.has(fragment):
				fragment.set_meta("controlling_player", self)
				_grab_time[fragment] = 0.06
				if not fragment_original_properties.has(fragment):
					fragment_original_properties[fragment] = {
						"gravity_scale": fragment.gravity_scale,
						"linear_damp":   fragment.linear_damp,
						"angular_damp":  fragment.angular_damp,
						"lock_rotation": fragment.lock_rotation,
					}

	for fragment in attracted_fragments:
		if is_instance_valid(fragment) and not new_attracted.has(fragment):
			if fragment.get_meta("controlling_player", null) == self:
				fragment.remove_meta("controlling_player")
			_restore_fragment_properties(fragment)
			_grab_time.erase(fragment)

	attracted_fragments = new_attracted

func _restore_fragment_properties(fragment: RigidBody2D) -> void:
	if not is_instance_valid(fragment): return
	if fragment_original_properties.has(fragment):
		var orig: Dictionary = fragment_original_properties[fragment]
		fragment.linear_damp   = orig["linear_damp"]
		fragment.angular_damp  = orig["angular_damp"]
		fragment.gravity_scale = orig["gravity_scale"]
		fragment.lock_rotation = orig["lock_rotation"]
		fragment_original_properties.erase(fragment)

func _apply_gravity_field_to_fragment(fragment: RigidBody2D, delta: float) -> void:
	var raw_dir := Vector2(Input.get_axis(left_action, right_action), Input.get_axis(up_action, down_action))
	var dir = Vector2(raw_dir.x, raw_dir.y * 2.0)

	fragment.gravity_scale = 0.0

	var id = fragment.get_instance_id()
	var angle = (id % 6283) * 0.001
	var radius = 35.0 + (id % 55)
	var orbit = Vector2(cos(angle), sin(angle)) * radius
	var target = global_position + Vector2(0.0, 30.0) + dir * gravity_field_direction_strength + orbit

	var to_target = target - fragment.global_position
	var dist = to_target.length()
	var spd = clamp(dist * 4.0, 0.0, 600.0)
	var target_vel = to_target.normalized() * spd + velocity * 0.3

	fragment.linear_velocity  = fragment.linear_velocity.lerp(target_vel, 4.0 * delta)
	fragment.angular_velocity = lerp(fragment.angular_velocity, 0.0, 20.0 * delta)
	fragment.rotation         = lerp_angle(fragment.rotation, 0.0, 15.0 * delta)

func _push_close_fragments() -> void:
	for fragment in attracted_fragments:
		if not is_instance_valid(fragment): continue
		var dist := global_position.distance_to(fragment.global_position)
		if dist <= push_distance_threshold:
			var dir: Vector2     = (fragment.global_position - global_position).normalized()
			var impulse: Vector2 = dir * fragment_push_force
			impulse.y -= fragment_push_force * 0.4
			fragment.apply_central_impulse(impulse)

func _create_gravity_field_visual() -> void:
	if not show_gravity_field: return
	gravity_field_visual = VisualEffects.GravityFieldEffect.new()
	add_child(gravity_field_visual)

func _emit_jump_force(multiplier: float = 1.0) -> void:
	var affected: Array = (
		get_tree().get_nodes_in_group("destructible_blocks")
		+ get_tree().get_nodes_in_group("bouncy_blocks")
		+ get_tree().get_nodes_in_group("reverse_blocks")
		+ get_tree().get_nodes_in_group("ice_blocks")
		+ get_tree().get_nodes_in_group("player")
	)

	for node in affected:
		if node == self: continue
		if node.is_in_group("destructible_blocks"):
			if _is_player_on_or_near_block(node):
				node.receive_force(global_position, jump_force_strength * multiplier)
		elif node.is_in_group("player"):
			var dist: float = global_position.distance_to(node.global_position)
			if dist <= jump_force_radius:
				var dir: Vector2 = (node.global_position - global_position).normalized()
				node.velocity += dir * jump_force_strength * 0.5 * multiplier
		else:
			var dist := global_position.distance_to(node.global_position)
			if dist <= jump_force_radius:
				var factor := 1.0 - (dist / jump_force_radius)
				node.receive_force(global_position, jump_force_strength * factor * multiplier)

	_apply_force_to_fragments(get_tree().get_nodes_in_group("fragments"))

func _is_player_on_or_near_block(block: Node) -> bool:
	var bp: Vector2 = block.global_position
	var bw: float = 128.0
	var bh: float = 64.0
	
	var collision = block.get_node_or_null("CollisionShape2D")
	if collision and collision.shape is RectangleShape2D:
		bw = collision.shape.size.x
		bh = collision.shape.size.y
	
	var half_w = bw * 0.5
	var half_h = bh * 0.5
	var margin: float = 15.0
	
	if global_position.x < bp.x - half_w - margin or global_position.x > bp.x + half_w + margin:
		return false
		
	var vert: float = global_position.y - (bp.y - half_h)
	return vert >= -40.0 and vert <= 20.0

func _apply_force_to_fragments(frags: Array) -> void:
	for fragment in frags:
		if not is_instance_valid(fragment): continue
		if gravity_field_active and fragment.has_meta("controlling_player"):
			continue
		var dist := global_position.distance_to(fragment.global_position)
		if dist > jump_force_radius: continue
		var factor: float    = 1.0 - (dist / jump_force_radius)
		var dir: Vector2     = (fragment.global_position - global_position).normalized()
		var impulse: Vector2 = dir * jump_force_strength * factor * 0.6
		if impulse.length() < 40.0: impulse = impulse.normalized() * 40.0
		impulse.y -= 25.0
		fragment.angular_velocity += randf_range(-4.0, 4.0)
		fragment.apply_central_impulse(impulse)

func _spawn_landing_impact() -> void:
	var impact = VisualEffects.LandingImpact.new()
	get_parent().add_child(impact)
	impact.global_position = global_position

func _create_force_wave_effect() -> void:
	var wave = VisualEffects.JumpWaveEffect.new()
	get_parent().add_child(wave)
	wave.global_position = global_position

func _handle_charged_jump(delta: float) -> void:
	if Input.is_action_pressed(charge_action) and is_on_floor() and not is_charging_jump:
		is_charging_jump = true
		charge_time = 0.0
		_create_charge_visual()

	if not is_charging_jump: return

	charge_time = min(charge_time + delta, max_charge_time)
	_update_charge_visual()

	if Input.is_action_just_released(charge_action):
		var ratio      := charge_time / max_charge_time
		velocity.y      = -lerp(jump_height, max_charge_jump, ratio)
		jumps_remaining = max_jumps - 1
		_emit_jump_force(1.0 + ratio)
		_create_charged_force_wave(ratio)
		_stop_charge_visual()

func _create_charge_visual() -> void:
	charge_visual = VisualEffects.ChargeEffect.new()
	add_child(charge_visual)

func _update_charge_visual() -> void:
	if charge_visual:
		charge_visual.update_charge(charge_time / max_charge_time)

func _stop_charge_visual() -> void:
	is_charging_jump = false
	charge_time      = 0.0
	if charge_visual:
		charge_visual.queue_free()
		charge_visual = null

func _create_charged_force_wave(charge_ratio: float) -> void:
	var wave = VisualEffects.JumpWaveEffect.new()
	wave.max_radius = 120.0 + charge_ratio * 60.0
	wave.base_color = Color.YELLOW.lerp(Color.ORANGE, charge_ratio) \
		if player_data.player_id == 1 else Color.LIME.lerp(Color.GREEN, charge_ratio)
	get_parent().add_child(wave)
	wave.global_position = global_position

func get_gravity_field_cooldown_progress() -> float:
	if ability_cooldown_timer <= 0.0: return 1.0
	return 1.0 - (ability_cooldown_timer / gravity_field_cooldown)

func get_jump_force_radius() -> float:
	return jump_force_radius

func _draw() -> void:
	if not Engine.is_editor_hint(): return
	if show_force_radius:
		var c := Color.RED if (player_data and player_data.player_id == 1) else Color.GREEN
		draw_circle(Vector2.ZERO, jump_force_radius, Color(c.r, c.g, c.b, 0.1))
		draw_arc(Vector2.ZERO, jump_force_radius, 0.0, TAU, 32, c, 2.0)
	if show_gravity_field:
		var fc := Color.MAGENTA if (player_data and player_data.player_id == 1) else Color.LIME
		draw_circle(Vector2.ZERO, gravity_field_radius, Color(fc.r, fc.g, fc.b, 0.05))
		draw_arc(Vector2.ZERO, gravity_field_radius, 0.0, TAU, 32, fc, 2.0)
		draw_arc(Vector2.ZERO, push_distance_threshold, 0.0, TAU, 32, Color.YELLOW, 1.0)
		var poff := Vector2(0.0, 45.0)
		draw_circle(poff, platform_radius, Color(0.0, 1.0, 1.0, 0.1))
		draw_arc(poff, platform_radius, 0.0, TAU, 32, Color.CYAN, 2.0)
		var d := Vector2(Input.get_axis(left_action, right_action), Input.get_axis(up_action, down_action) * 2.0)
		if d != Vector2.ZERO:
			var aoff := poff + d * gravity_field_direction_strength
			draw_line(poff, aoff, Color(1.0, 0.5, 0.0, 0.6), 2.0)
			draw_circle(aoff, 6.0, Color(1.0, 0.5, 0.0, 0.4))
