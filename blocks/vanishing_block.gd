class_name VanishingBlock
extends Block

## Crumbles shortly after someone lands on it, then reappears.

const WARN_TIME := 0.7
const GONE_TIME := 2.6

enum S { SOLID, WARNING, GONE }

var _state := S.SOLID
var _timer := 0.0


func _init() -> void:
	super._init()
	block_id = "vanishing_block"


func on_player_land(_player: Player) -> void:
	if _state == S.SOLID:
		_state = S.WARNING
		_timer = WARN_TIME
		set_process(true)


func _process(delta: float) -> void:
	match _state:
		S.WARNING:
			_timer -= delta
			if _timer <= 0.0:
				_state = S.GONE
				_timer = GONE_TIME
				collision_layer = 0
				Sfx.play("vanish", -4.0)
		S.GONE:
			_timer -= delta
			if _timer <= 0.0:
				_state = S.SOLID
				collision_layer = 1
				set_process(false)
	modulate.a = 0.45 + 0.55 * (_timer / WARN_TIME) if _state == S.WARNING else 1.0
	queue_redraw()


func _draw() -> void:
	match _state:
		S.GONE:
			# Ghost outline so players can see where it will return.
			var r := Rect2(-size * 0.5, size)
			var a := 0.25 + 0.2 * (1.0 - _timer / GONE_TIME)
			# dashed ghost outline
			var x := r.position.x
			while x < r.end.x:
				draw_line(Vector2(x, r.position.y), Vector2(minf(x + 14, r.end.x), r.position.y), Color(colors()[1], a), 3.0)
				draw_line(Vector2(x, r.end.y), Vector2(minf(x + 14, r.end.x), r.end.y), Color(colors()[1], a), 3.0)
				x += 26.0
		S.WARNING:
			var shake := Vector2(randf_range(-2, 2), randf_range(-1, 1)) * (1.0 - _timer / WARN_TIME) * 2.0
			draw_set_transform(shake)
			_draw_body()
			_draw_icon()
			draw_set_transform(Vector2.ZERO)
		_:
			_draw_body()
			_draw_icon()


func _draw_icon() -> void:
	var col := _icon_color(0.9)
	var hx := size.x * 0.5 - 14.0
	var x := -hx
	while x < hx:
		draw_rect(Rect2(x, -4, minf(12.0, hx - x), 8), col)
		x += 22.0
