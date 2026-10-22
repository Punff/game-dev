class_name GameCamera
extends Camera2D

## Keeps every living player in frame. Zooms out as players spread apart,
## and when they're too far apart it favours the leader (the lava will
## sort out stragglers). Also handles screen shake.
##
## With `split_screen` on (couch play), players too far apart for one view
## get views of their own instead: the screen splits along the line between
## them, Voronoi-style. It's seamless - at the moment they stop fitting,
## every view is still this one - and the split line slides into place as
## they drift further. Players close together share a view. SplitScreen
## draws the views; this works out where they look.

const MARGIN_TOP := 300.0
const MARGIN_BOTTOM := 170.0
const MARGIN_SIDE := 220.0
const MIN_ZOOM := 0.5
const MAX_ZOOM := 1.0
## How far past fitting (x the zoomed-out view) until each view has its
## player in the middle of its half of the screen.
const SPLIT_RAMP := 0.6
## Players closer than this (fraction of the zoomed-out view) share a view.
const SHARE := Vector2(0.3, 0.25)

var targets: Array = []
var lava_y := INF
## How far the view may go either side of the centre (INF: no limit).
var wall_half_width := MapPlanner.HALF_WIDTH + 400.0
var split_screen := false
## Views of their own, when split: [{"pos": camera position, "site":
## screen point the view's region forms around}], else empty.
var views: Array = []
## 0..1: how far apart the views look (draws the split line).
var split_amount := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _pane_pos := {}   # player -> smoothed camera position of their view


func _ready() -> void:
	SignalBus.screen_shake_requested.connect(shake)
	tree_exiting.connect(func(): Block.view_rect = Rect2(-1e9, -1e9, 2e9, 2e9))
	position_smoothing_enabled = false
	ignore_rotation = true


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength * float(Settings.get_value("screen_shake")))


func snap() -> void:
	_update(1.0, true)


func is_split() -> bool:
	return not views.is_empty()


## Everything on screen, across every view.
func view_rect() -> Rect2:
	var visible := get_viewport_rect().size / zoom
	var r := Rect2(global_position - visible * 0.5, visible)
	for v in views:
		r = r.merge(Rect2(v.pos - visible * 0.5, visible))
	return r


func _physics_process(delta: float) -> void:
	_update(delta, false)


## The area to show around these players: margins, and not much lava.
func _frame(group: Array) -> Rect2:
	var box := Rect2(group[0].global_position, Vector2.ZERO)
	for t in group:
		box = box.expand(t.global_position)
	var top := box.position.y - MARGIN_TOP
	var bottom := minf(box.end.y + MARGIN_BOTTOM, lava_y + 160.0)
	bottom = maxf(bottom, top + 300.0)
	return Rect2(box.position.x - MARGIN_SIDE, top, box.size.x + MARGIN_SIDE * 2.0, bottom - top)


func _update(delta: float, instant: bool) -> void:
	var vp := get_viewport_rect().size
	var alive := targets.filter(func(t): return is_instance_valid(t) and not t.is_dead)
	if alive.is_empty():
		return
	var frame := _frame(alive)
	var z := clampf(minf(vp.x / frame.size.x, vp.y / frame.size.y), MIN_ZOOM, MAX_ZOOM)
	var visible := vp / z
	var groups := _groups(alive, vp) if split_screen else []
	var target := frame.get_center()
	if groups.size() < 2:
		groups = []
		if frame.size.y > visible.y:
			target.y = frame.position.y + visible.y * 0.5   # favour the leader
		if frame.size.x > visible.x:
			# Too spread: follow whoever is highest horizontally too.
			var lead: Node2D = alive[0]
			for t in alive:
				if t.global_position.y < lead.global_position.y:
					lead = t
			target.x = clampf(lead.global_position.x, frame.position.x + visible.x * 0.5, frame.end.x - visible.x * 0.5)
	target.x = _inside_walls(target.x, visible)
	var k := 1.0 if instant else minf(3.5 * delta, 1.0)
	zoom = zoom.lerp(Vector2(z, z), 1.0 if instant else minf(2.0 * delta, 1.0))
	global_position = global_position.lerp(target, k)
	_update_views(groups, target, z, vp, k)
	Block.view_rect = view_rect().grow(120.0)

	_shake = move_toward(_shake, 0.0, 40.0 * delta)
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake if _shake > 0.1 else Vector2.ZERO


## Don't show much beyond the arena walls.
func _inside_walls(x: float, visible: Vector2) -> float:
	if wall_half_width == INF:
		return x
	if visible.x < wall_half_width * 2.0:
		return clampf(x, -wall_half_width + visible.x * 0.5, wall_half_width - visible.x * 0.5)
	return 0.0


## Players who'd share a view: chains of ones close to each other.
func _groups(alive: Array, vp: Vector2) -> Array:
	var near := vp / MIN_ZOOM * SHARE
	var groups: Array = []
	for t in alive:
		var mine: Array = [t]
		for g in groups.duplicate():
			for o in g:
				var d: Vector2 = (o.global_position - t.global_position).abs()
				if d.x < near.x and d.y < near.y:
					mine.append_array(g)
					groups.erase(g)
					break
		groups.append(mine)
	return groups


## Where each group's view looks. A group's spot on the shared view is
## pulled in toward the middle of the screen once it would be off it - by
## less at first, so the views part gradually - and its view slides over
## to keep the group there.
func _update_views(groups: Array, center: Vector2, z: float, vp: Vector2, k: float) -> void:
	views = []
	split_amount = 0.0
	var visible := vp / z
	var spread := 0.0
	if not groups.is_empty():
		var frame := _frame(targets.filter(func(t): return is_instance_valid(t) and not t.is_dead))
		spread = maxf(frame.size.x * MIN_ZOOM / vp.x, frame.size.y * MIN_ZOOM / vp.y)
	var reach := vp * lerpf(0.5, 0.25, smoothstep(1.0, 1.0 + SPLIT_RAMP, spread))
	var seen := {}
	var furthest := 0.0
	for g in groups:
		var at := _frame(g).get_center()
		# (Scaled, not clamped per axis, so the split stays square to the
		# line between the players.)
		var on_screen := (at - center) * z
		on_screen *= minf(1.0, minf(reach.x / maxf(absf(on_screen.x), 0.001), reach.y / maxf(absf(on_screen.y), 0.001)))
		var want := at - on_screen / z
		want.x = _inside_walls(want.x, visible)
		# A group that just formed carries on from the view of whoever was in it.
		var pos := global_position
		for t in g:
			if _pane_pos.has(t):
				pos = _pane_pos[t]
				break
		pos = pos.lerp(want, k)
		for t in g:
			_pane_pos[t] = pos
			seen[t] = true
		furthest = maxf(furthest, (pos - global_position).length() * z)
		views.append({"pos": pos, "site": vp * 0.5 + (at - pos) * z})
	for t in _pane_pos.keys():
		if not seen.has(t):
			_pane_pos.erase(t)
	if furthest < 0.5:
		views = []   # all the same view, nothing to split
		_pane_pos.clear()
	split_amount = clampf(furthest / 40.0, 0.0, 1.0)
