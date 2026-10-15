class_name HelpScreen
extends MenuBase

## "How to play": goal, abilities and a live legend of every block type.

var BLOCKS := [
	[StaticPlatform, "Platform", "Solid ground."],
	[BouncePad, "Bounce Pad", "Launches you sky-high."],
	[SpeedBlock, "Speed Strip", "Shoots you along the arrows."],
	[ConveyorBlock, "Conveyor", "Drags you. Shockwave flips it."],
	[PushZone, "Gust", "Wind that changes direction."],
	[IceBlock, "Ice", "Slippery. Plan your stops."],
	[BreakableBlock, "Concrete", "Jump off, ground-pound, blast or chunk it: shatters into floating debris."],
	[VanishingBlock, "Ghost", "Vanishes after you land. Comes back."],
	[MovingPlatform, "Mover", "Slides side to side."],
	[ReverseBlock, "Scrambler", "Flips left and right for a few seconds."],
]


func _ready() -> void:
	build_overlay(0.8, 1120)
	content.add_child(UiTheme.title("how to play", 40))
	var goal := UiTheme.label("Climb. Wreck the route behind you. The slag never stops rising - last one standing wins. Flying chunks hit hard and smash more concrete: chain it.", 20, Palette.TEXT)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(goal)

	var abilities := GridContainer.new()
	abilities.columns = 2
	abilities.add_theme_constant_override("h_separation", 28)
	abilities.add_theme_constant_override("v_separation", 4)
	for pair in [
		["Double Jump", "Jump again in mid-air. Jumping next to someone shoves them."],
		["Charge Jump", "Hold to charge - start on the ground, keep it running off ledges - release anywhere to launch."],
		["Ground Pound", "Fast-fall onto concrete and it shatters under you (and anyone standing on it)."],
		["Shockwave", "Aimed blast: knocks players back, shatters concrete, flings debris. Aim down to rocket-jump."],
		["Gravity Field", "Hold to hover and grab debris - it stacks under you. Release while aiming to hurl it."],
	]:
		var l := UiTheme.label(pair[0], 20, Palette.ACCENT)
		abilities.add_child(l)
		var d := UiTheme.label(pair[1], 18, Palette.TEXT_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 820
		abilities.add_child(d)
	content.add_child(abilities)
	content.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for entry in BLOCKS:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(96, 40)
		var block: Block = entry[0].new()
		block.set_block_size(Vector2(88, 40))
		block.position = Vector2(46, 20)
		block.sync_to_physics = false   # it's a picture, not a physics body
		block.collision_layer = 0
		block.process_mode = Node.PROCESS_MODE_ALWAYS
		if block is MovingPlatform:
			block.travel = 0.0
		holder.add_child(block)
		h.add_child(holder)
		var texts := VBoxContainer.new()
		texts.add_theme_constant_override("separation", -4)
		texts.add_child(UiTheme.label(entry[1], 19, Palette.TEXT))
		var d := UiTheme.label(entry[2], 15, Palette.TEXT_DIM)
		d.custom_minimum_size.x = 200
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		texts.add_child(d)
		h.add_child(texts)
		grid.add_child(h)

	var back := UiTheme.button("Got it!", 260)
	back.pressed.connect(func(): closed.emit())
	var c := CenterContainer.new()
	c.add_child(back)
	content.add_child(c)
	back.grab_focus.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Sfx.play("ui_back")
		closed.emit()
