class_name HazardBlock
extends Block

## Red block. Touching it from any side stuns you for a moment and throws
## you off - great for shoving people into. Never wears down.

const STUN := 0.7
const KNOCK := 560.0


func _init() -> void:
	super._init()
	block_id = "hazard_block"
	toughness = 0.0
	animated = true


func on_player_touch(player: Player, normal: Vector2) -> void:
	player.stun(STUN, normal * KNOCK + Vector2(0, -220))


func _draw_icon() -> void:
	# Pulsing black diagonal stripes.
	var face := Rect2(-size * 0.5, size).grow(-OUTLINE)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.008)
	var col := Color(Palette.INK, 0.55 + 0.3 * pulse)
	var h := face.size.y
	var x := face.position.x - h
	while x < face.end.x:
		var t0 := clampf((face.position.x - x) / h, 0.0, 1.0)
		var t1 := clampf((face.end.x - x) / h, 0.0, 1.0)
		var p0 := Vector2(x, face.end.y)
		var p1 := Vector2(x + h, face.position.y)
		draw_line(p0.lerp(p1, t0), p0.lerp(p1, t1), col, 9.0)
		x += 30.0
