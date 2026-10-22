extends Node

## Designer tool: draws a seed's whole layout to a PNG, without playing it.
##   MAP_SEED=230 MAP_TO=600 MAP_OUT=/tmp/map.png godot --headless --path . res://tests/map_preview.tscn
## MAP_FROM / MAP_TO (m) pick the stretch (default 0-400), MAP_SCALE the
## size (default 0.25 px per world px). Bottom of the image is the start.
## Platforms are in their block colours; a moving one shows its lane. The
## background is banded by biome, a mustard tick marks a charge-jump row,
## a rust one a row with no guaranteed way up (there shouldn't be any).
## Thin lines every 10 m, thick every 50 m. Prints a summary per biome.

const BIOME_TINT := {"Rubble": Color("1b1f2b"), "Inferno": Color("2b1514"), "Void": Color("112022"), "Storm": Color("1d1d22")}
const TYPE_KEY := {"static": "static_platform", "floor": "static_platform", "breakable": "breakable_block",
	"bouncy": "bounce_pad", "speed": "speed_block", "conveyor": "conveyor_block", "push": "push_zone",
	"vanishing": "vanishing_block", "ice": "ice_block", "moving": "moving_platform", "reverse": "reverse_block"}


func _ready() -> void:
	var seed_value := int(OS.get_environment("MAP_SEED")) if OS.has_environment("MAP_SEED") else 1
	var from_m := float(OS.get_environment("MAP_FROM")) if OS.has_environment("MAP_FROM") else 0.0
	var to_m := float(OS.get_environment("MAP_TO")) if OS.has_environment("MAP_TO") else 400.0
	var k := float(OS.get_environment("MAP_SCALE")) if OS.has_environment("MAP_SCALE") else 0.25
	var out := OS.get_environment("MAP_OUT") if OS.has_environment("MAP_OUT") else "user://map_preview.png"

	var planner := MapPlanner.new(seed_value)
	planner.start(0.0)
	planner.generate_until(-to_m * 50.0 - 400.0)

	var half := MapPlanner.HALF_WIDTH
	var top_y := -to_m * 50.0
	var bot_y := -from_m * 50.0 + 80.0
	var w := int(half * 2.0 * k) + 40
	var h := int((bot_y - top_y) * k)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var px := func(x: float) -> int: return int((x + half) * k) + 20
	var py := func(y: float) -> int: return int((y - top_y) * k)

	# Biome bands, height lines.
	for y in range(h):
		var world_y := top_y + y / k
		var biome: Dictionary = planner.biome_at(-world_y)
		img.fill_rect(Rect2i(0, y, w, 1), BIOME_TINT.get(biome.name, Color.BLACK))
	var m := ceili(from_m / 10.0) * 10
	while m <= to_m:
		var y: int = py.call(-m * 50.0)
		img.fill_rect(Rect2i(0, y, w, 2 if m % 50 == 0 else 1), Color(1, 1, 1, 1) * (0.35 if m % 50 == 0 else 0.18))
		m += 10

	var summary := {}
	for row in planner.rows:
		if row.y < top_y - 200.0 or row.y > bot_y:
			continue
		var b: String = row.biome
		if not summary.has(b):
			summary[b] = {"rows": 0, "charged": 0, "unreachable": 0, "types": {}}
		var s: Dictionary = summary[b]
		s.rows += 1
		var ry: int = py.call(row.y)
		if row.get("charged", false):
			s.charged += 1
			img.fill_rect(Rect2i(0, ry - 2, 12, 4), Palette.MUSTARD)
		if not row.platforms.any(func(p): return p.reachable and p.anchor_ok):
			s.unreachable += 1
			img.fill_rect(Rect2i(w - 12, ry - 3, 12, 6), Palette.RUST)
		for p in row.platforms:
			s.types[p.type] = s.types.get(p.type, 0) + 1
			var col: Color = Palette.BLOCKS.get(TYPE_KEY.get(p.type, "static_platform"), Palette.BLOCKS["static_platform"])[0]
			var x0: int = px.call(p.x0)
			var x1: int = px.call(p.x1)
			var y0: int = py.call(p.y - p.h * 0.5)
			var y1: int = py.call(p.y + p.h * 0.5)
			if p.travel > 0.0:   # a moving platform's lane
				img.fill_rect(Rect2i(px.call(p.x0 - p.travel), y0 + 2, int((p.x1 - p.x0 + p.travel * 2.0) * k), maxi(y1 - y0 - 4, 1)), col.darkened(0.6))
			img.fill_rect(Rect2i(x0 - 1, y0 - 1, x1 - x0 + 2, y1 - y0 + 2), Palette.INK)
			img.fill_rect(Rect2i(x0, y0, maxi(x1 - x0, 1), maxi(y1 - y0, 1)), col)

	img.save_png(out)
	print("Map preview: seed %d, %d-%d m -> %s (%dx%d)" % [seed_value, from_m, to_m, ProjectSettings.globalize_path(out), w, h])
	for b in summary:
		var s: Dictionary = summary[b]
		var types: Array = s.types.keys()
		types.sort_custom(func(x, y): return s.types[x] > s.types[y])
		print("  %-8s %3d rows, %2d charge rows, %d unreachable; %s" % [b, s.rows, s.charged, s.unreachable,
			", ".join(types.map(func(t): return "%s %d" % [t, s.types[t]]))])
	get_tree().quit()
