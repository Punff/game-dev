class_name UiFx
extends RefCounted

## Small feedback animations for menus, in the game's printed-comic idiom:
## things get *stamped* (overshoot down to size with a twist), buttons lift
## like a sticker when focused and press flat into their shadow. Everything
## answers something the player did; "Reduced effects" turns it all off.


static func enabled() -> bool:
	return not Settings.get_value("reduced_effects")


## Stamp a control onto the page: starts big and twisted, slams to rest.
static func stamp(c: Control, from_scale := 1.6, twist := -8.0, delay := 0.0) -> void:
	if not enabled() or not is_instance_valid(c):
		return
	_center_pivot(c)
	c.scale = Vector2.ONE * from_scale
	c.rotation_degrees = twist
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.chain().set_parallel()
	tw.tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation_degrees", 0.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.08)


## A quick squash-and-recover, for "this just changed".
static func bump(c: Control, amount := 0.12) -> void:
	if not enabled() or not is_instance_valid(c):
		return
	_center_pivot(c)
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(1.0 + amount, 1.0 - amount * 0.6), 0.05)
	tw.tween_property(c, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Unfold from the left edge after `delay` (staggered lists). Scale and alpha
## only, so it never fights a container's layout.
static func reveal(c: Control, delay := 0.0) -> void:
	if not enabled() or not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	c.scale = Vector2(0.85, 1.0)
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): c.pivot_offset = Vector2(0.0, c.size.y * 0.5))
	tw.tween_property(c, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if c is Button:
		tw.tween_callback(func(): _lift(c, c.has_focus() or c.is_hovered()))   # focus may have arrived meanwhile


## Buttons: lift on focus/hover (sticker peeling up), press flat on click.
static func wire_button(b: Button) -> void:
	b.resized.connect(func(): _pivot_for(b))
	b.focus_entered.connect(func(): _lift(b, true))
	b.focus_exited.connect(func(): _lift(b, b.is_hovered()))
	b.mouse_entered.connect(func(): _lift(b, true))
	b.mouse_exited.connect(func(): _lift(b, b.has_focus()))
	b.button_down.connect(func(): _press(b))


static func _lift(b: Button, up: bool) -> void:
	if not enabled():
		return
	_pivot_for(b)
	var tw := _retween(b)
	tw.tween_property(b, "scale", Vector2.ONE * (1.04 if up else 1.0), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(b, "rotation_degrees", (-1.2 if up else 0.0) * _tilt_sign(b), 0.12)


static func _press(b: Button) -> void:
	if not enabled():
		return
	_pivot_for(b)
	var tw := _retween(b)
	tw.tween_property(b, "scale", Vector2(0.96, 0.92), 0.04)
	tw.tween_property(b, "scale", Vector2.ONE * (1.04 if b.has_focus() or b.is_hovered() else 1.0), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _retween(c: Control) -> Tween:
	var old: Tween = c.get_meta("ui_fx_tween", null)
	if old and old.is_valid():
		old.kill()
	var tw := c.create_tween()
	c.set_meta("ui_fx_tween", tw)
	return tw


## Left-aligned buttons grow to the right; centred ones from the middle.
static func _pivot_for(b: Button) -> void:
	b.pivot_offset = Vector2(0.0, b.size.y * 0.5) if b.alignment == HORIZONTAL_ALIGNMENT_LEFT else b.size * 0.5


static func _tilt_sign(b: Button) -> float:
	return 1.0 if b.alignment == HORIZONTAL_ALIGNMENT_LEFT else 0.0


static func _center_pivot(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	# Containers may lay it out a frame later: re-centre once they do.
	if not c.resized.is_connected(_recenter.bind(c)):
		c.resized.connect(_recenter.bind(c), CONNECT_ONE_SHOT)


static func _recenter(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
