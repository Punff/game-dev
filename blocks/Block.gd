class_name Block extends AnimatableBody2D

@export var block_id: String
@export var block_category: String   # "static" | "physics" | "trigger" | "sabotage"
@export var grid_size: Vector2i = Vector2i(2, 1)
@export var spawn_weight: float = 1.0
@export var min_spacing: int = 0
@export var can_stack: bool = true
@export var texture: Texture2D
@export var tint: Color = Color.WHITE

func _ready() -> void:
	add_to_group("blocks")
	_setup_visuals()

func _setup_visuals() -> void:
	# Add BlockVisuals child if it doesn't exist
	if not has_node("BlockVisuals"):
		var visuals_script = load("res://blocks/BlockVisuals.gd")
		var visuals = Node2D.new()
		visuals.name = "BlockVisuals"
		visuals.set_script(visuals_script)
		add_child(visuals)

func on_player_land(_player: Player) -> void: pass
func on_player_stand(_player: Player, _delta: float) -> void: pass
func on_player_leave(_player: Player) -> void: pass
func on_activate(_source: Player, _target: Player) -> void: pass
func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float) -> void: pass
func receive_shockwave() -> void: pass

func set_block_size(new_size: Vector2) -> void:
	# Update collision shape
	var collision = get_node_or_null("CollisionShape2D")
	if collision and collision.shape is RectangleShape2D:
		collision.shape = collision.shape.duplicate()
		collision.shape.size = new_size
	
	# Update sprite
	var sprite = get_node_or_null("Sprite2D")
	if sprite:
		if sprite.region_enabled:
			sprite.region_rect = Rect2(Vector2.ZERO, new_size)
		else:
			# If we have a texture, scale based on its size
			if sprite.texture:
				sprite.scale = new_size / sprite.texture.get_size()
			else:
				# Fallback if no texture is set yet
				sprite.scale = new_size / Vector2(128, 64) # Default size assumption
	
	# Update visuals
	var visuals = get_node_or_null("BlockVisuals")
	if visuals and visuals.has_method("_update_rect_size"):
		visuals._update_rect_size()
		visuals.queue_redraw()
