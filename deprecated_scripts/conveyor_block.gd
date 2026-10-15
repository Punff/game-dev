extends BaseBlock


@export var convey_speed: float = 250.0
var direction: float

func get_block_group() -> String: return "conveyor_blocks"
func get_default_color() -> Color: return Color(0.3, 0.3, 0.35)
func get_default_border_color() -> Color: return Color(0.9, 0.6, 0.05)

func _ready():
	direction = 1.0 if randi() % 2 == 0 else -1.0
	block_color = get_default_color(); border_color = get_default_border_color()
	add_to_group(get_block_group())
	_build_block()

func on_block_built():
	make_arrow()

func make_arrow():
	var body = get_block_body(); if not body: return
	for c in body.get_children():
		if c is Line2D and c.name.begins_with("Arrow"): c.queue_free()
	var _hw = hw(); var _hh = hh(); var asz = min(_hw, _hh) * 0.25; var ax = direction * _hw * 0.35
	var arr = Line2D.new(); arr.name = "Arrow"; arr.width = 2.5; arr.default_color = Color(0.9, 0.6, 0.05); arr.antialiased = true
	arr.points = [Vector2(ax - direction * _hw * 0.3, 0), Vector2(ax, 0), Vector2(ax - direction * 6, -6), Vector2(ax, 0), Vector2(ax - direction * 6, 6)]
	body.add_child(arr)
	var border = body.get_node_or_null("Line2D")
	if border: border.default_color = Color(0.9, 0.6, 0.05)

func get_conveyor_velocity() -> float:
	return convey_speed * direction

func on_shockwave(_dir: Vector2, _origin: Vector2, _range: float):
	direction = -direction; make_arrow()
