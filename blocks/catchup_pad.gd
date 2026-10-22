class_name CatchupPad
extends Block

## A shortcut for whoever is behind. It sits dead, a dull plate like any
## other, until the leader has climbed PAD_ARM above it; from then on it
## glows and launches anyone who lands on it - except the leader - up
## through the platforms above. No callout: you see it light up. (Live
## matches: once someone got 10 m ahead, nobody caught them.)
## Multiplayer only (MapPlanner.catchup_pads).

const PAD_ARM := 300.0             ## px the leader must be above it to arm it
const LAUNCH_VELOCITY := 1150.0    ## ~11 m of rise, plus your double jump

## Whoever has climbed highest; set by the game every tick.
static var leader: Player

var armed := false
var _squash := 0.0


func _init() -> void:
	super._init()
	block_id = "catchup_pad"
	animated = true


func _physics_process(_delta: float) -> void:
	# On physics ticks so it arms on the same tick everywhere (and on a
	# replay). Guests are told by the host.
	if armed or Net.is_client() or not is_instance_valid(leader):
		return
	if leader.spawn_y - leader.max_height_px < get_rect_global().position.y - PAD_ARM:
		_arm()


func _arm() -> void:
	armed = true
	set_physics_process(false)
	_body_art.queue_redraw()
	queue_redraw()
	net_changed()


func on_player_land(player: Player) -> void:
	if not armed or player == leader:
		return
	var behind := (leader.max_height_px - player.max_height_px) / 50.0 if is_instance_valid(leader) else 0.0
	player.launch_through(LAUNCH_VELOCITY)
	Telemetry.ev("catchup", player, {"behind": snappedf(behind, 0.1)})
	_squash = 1.0
	Sfx.play("bounce")


func net_state() -> int:
	return 1 if armed else 0


func apply_net_state(state: int) -> void:
	if state == 1 and not armed:
		_arm()


func colors() -> Array:
	return Palette.BLOCKS["catchup_pad_armed" if armed else "catchup_pad"]


func _process(delta: float) -> void:
	if _squash > 0.0:
		_squash = move_toward(_squash, 0.0, delta * 4.0)
		queue_redraw()
	elif armed:
		redraw_icon()


func _draw_icon() -> void:
	if not armed:
		super._draw_icon()   # rivets: just another plate
		return
	# Lit: a big coiled spring with an arrow, bobbing.
	var col := _icon_color()
	var t := Time.get_ticks_msec() * 0.006
	var lift := -(1.0 - _squash) * 4.0 + sin(t) * 2.5
	for p in _icon_positions(110.0):
		var pts := PackedVector2Array()
		for i in 9:
			pts.append(p + Vector2(-20.0 + i * 5.0, (9.0 if i % 2 == 0 else -9.0) * (1.0 - _squash * 0.5) + lift))
		_ink_line(pts, col, 4.0)
		_ink_line(PackedVector2Array([p + Vector2(-12, -22 + lift), p + Vector2(0, -32 + lift), p + Vector2(12, -22 + lift)]), col, 4.0)
