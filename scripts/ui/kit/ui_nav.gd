class_name UiNav
extends RefCounted

## Focus wiring for code-built menus: lists and grids that wrap around, so
## keyboard and gamepad never fall off the edge of a page.


## A focus neighbour that means "stay here" (works before entering the tree).
const SELF := NodePath(".")


## Up/down walk the list and wrap; left/right stay put unless `keep_sides`
## (then sliders and cyclers keep their own left/right).
static func link_vertical(controls: Array, keep_sides := false) -> void:
	var list := _visible(controls)
	for i in list.size():
		var c: Control = list[i]
		c.focus_neighbor_top = c.get_path_to(list[(i - 1 + list.size()) % list.size()])
		c.focus_neighbor_bottom = c.get_path_to(list[(i + 1) % list.size()])
		if not keep_sides:
			c.focus_neighbor_left = SELF
			c.focus_neighbor_right = SELF


## Left/right across one row, wrapping.
static func link_horizontal(controls: Array) -> void:
	var list := _visible(controls)
	for i in list.size():
		var c: Control = list[i]
		c.focus_neighbor_left = c.get_path_to(list[(i - 1 + list.size()) % list.size()])
		c.focus_neighbor_right = c.get_path_to(list[(i + 1) % list.size()])


## Rows of controls (rows may differ in length). Up/down keep the column
## where they can, and the whole thing wraps.
static func link_grid(rows: Array) -> void:
	var grid: Array = []
	for r in rows:
		var vis := _visible(r)
		if not vis.is_empty():
			grid.append(vis)
	for r in grid.size():
		link_horizontal(grid[r])
		var above: Array = grid[(r - 1 + grid.size()) % grid.size()]
		var below: Array = grid[(r + 1) % grid.size()]
		for c in grid[r].size():
			var ctl: Control = grid[r][c]
			ctl.focus_neighbor_top = ctl.get_path_to(above[mini(c, above.size() - 1)])
			ctl.focus_neighbor_bottom = ctl.get_path_to(below[mini(c, below.size() - 1)])


## First visible, enabled, focusable control under `root` (or null).
static func first_focusable(root: Node) -> Control:
	for c in root.find_children("*", "Control", true, false):
		var ctl: Control = c
		if ctl.focus_mode == Control.FOCUS_ALL and ctl.is_visible_in_tree() \
				and not (ctl is BaseButton and ctl.disabled):
			return ctl
	return null


static func focus_first(root: Node) -> void:
	var c := first_focusable(root)
	if c:
		c.grab_focus.call_deferred()


static func _visible(controls: Array) -> Array:
	return controls.filter(func(c): return is_instance_valid(c) and c.visible)
