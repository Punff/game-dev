class_name Crown
extends Control

## A three-point paper crown in ink and mustard, for the results screen.

var bob := true


func _init(width := 56.0) -> void:
	custom_minimum_size = Vector2(width, width * 0.75)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if bob:
		queue_redraw()


func _draw() -> void:
	var s := size.x / 24.0
	var t := Time.get_ticks_msec() * 0.001
	var lift := sin(t * 3.0) * s * 0.6 if bob and UiFx.enabled() else 0.0
	draw_set_transform(size * 0.5 + Vector2(0, lift), 0.0, Vector2(s, s))
	var pts := PackedVector2Array([Vector2(-10, 6), Vector2(-11, -6), Vector2(-5, -1), Vector2(0, -9),
		Vector2(5, -1), Vector2(11, -6), Vector2(10, 6)])
	draw_colored_polygon(Block._shifted(pts, Vector2(1.5, 1.5)), Palette.INK)
	draw_colored_polygon(pts, Palette.MUSTARD)
	pts.append(pts[0])
	draw_polyline(pts, Palette.INK, 1.6)
	for p in [Vector2(-11, -6), Vector2(0, -9), Vector2(11, -6)]:
		draw_circle(p, 1.8, Palette.PAPER)
	draw_line(Vector2(-9.5, 3), Vector2(9.5, 3), Color(Palette.INK, 0.45), 1.2)
	draw_set_transform(Vector2.ZERO)
