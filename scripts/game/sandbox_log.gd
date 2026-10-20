class_name SandboxLog
extends Node

## Watches one player in the sandbox and writes down what it does: jumps,
## landings (impact speed, air time, peak), charge launches, fast-falls,
## gravity fields, shockwaves, hits, concrete breaking. Lines go to the
## on-screen feed, stdout and user://logs/sandbox.log, so a run can be read
## back afterwards - by a person or by a script driving the sandbox.

signal logged(line: String)

const PATH := "user://logs/sandbox.log"

var player: Player
var _file: FileAccess
var _t := 0.0

# Last frame's view of the player, to spot changes.
var _on_floor := true
var _charging := false
var _charge := 0.0
var _field := false
var _shock_cd := 0.0
var _hit_flash := 0.0
var _fast_fall := false
var _coyote := 0.0
var _vy := 0.0
var _jump_held := false
var _jump_pressed_at := -1.0
# Current airtime.
var _air_t := 0.0
var _takeoff_y := 0.0
var _peak_y := 0.0
var _field_held := 0
var _quiet := 0   # ticks to just observe after watch()


func _ready() -> void:
	process_physics_priority = 100   # after the player has moved this tick
	DirAccess.make_dir_recursive_absolute(PATH.get_base_dir())
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	SignalBus.block_broken.connect(func(pos: Vector2): write("BREAK", "concrete at %s" % _v(pos)))
	SignalBus.chain_reaction_occurred.connect(func(n: int, _p): write("CHAIN", "%d breaks in a row" % n))


## Start watching (again) - after a spawn or teleport, so nothing that
## happened before counts as a jump or a landing.
func watch(p: Player) -> void:
	player = p
	_quiet = 2
	_on_floor = true
	_air_t = 0.0
	_charging = false
	_field = false
	_shock_cd = p.shock_cd
	_hit_flash = 0.0


func write(tag: String, text: String) -> void:
	var line := "%7.2fs  %-10s %s" % [_t, tag, text]
	print("[sandbox] " + line)
	if _file:
		_file.store_line(line)
		_file.flush()
	logged.emit(line)


## Everything about the player right now, on one line.
func state() -> String:
	var p := player
	return "pos %s  vel %s  floor %s  jumps %d  charge %.0f%%  field %s (%d held)  shock cd %.1f  field cd %.1f" % [
		_v(p.global_position), _v(p.velocity), p.is_on_floor(), p.jumps_left, p._charge * 100.0,
		p._field_active, p._held.size(), p.shock_cd, p.gravity_cd]


func _physics_process(delta: float) -> void:
	_t += delta
	var p := player
	if p == null or not is_instance_valid(p) or p.is_dead:
		return
	var on_floor := p.is_on_floor()
	var vel := p.velocity
	if _quiet > 0:
		_quiet -= 1
		_on_floor = on_floor
		_shock_cd = p.shock_cd
		_vy = vel.y
		return

	# A jump sets vy to exactly -JUMP_VELOCITY. (jumps_left is no help: it
	# refills at the start of the next tick, so a ground jump reads 1 -> 1.)
	# Bounce pads can land on the same number, so it also needs a fresh press.
	if p._pressed("jump") and not _jump_held:
		_jump_pressed_at = _t
	_jump_held = p._pressed("jump")
	var jumped := absf(vel.y + Player.JUMP_VELOCITY) < 0.5 and absf(_vy + Player.JUMP_VELOCITY) >= 0.5 \
		and _t - _jump_pressed_at <= Player.JUMP_BUFFER + 0.02
	var launched := false
	if p._charging and not _charging:
		write("CHARGE", "started")
	if _charging and not p._charging:
		write("CHARGE", "launch at %.0f%% -> vy %.0f" % [_charge * 100.0, vel.y])
		launched = true
	elif jumped:
		var kind := "ground" if _on_floor or _coyote > 0.0 else "air (double)"
		write("JUMP", "%s  vy %.0f  vx %.0f" % [kind, vel.y, vel.x])
	elif _vy - vel.y > 300.0 and vel.y < -150.0 and p.shock_cd <= _shock_cd + 1.0 and p._hit_flash <= _hit_flash + 0.05:
		write("LAUNCH", "thrown upwards: vy %.0f -> %.0f  at %s" % [_vy, vel.y, _v(p.global_position)])
		launched = true
	if _on_floor and not on_floor and not jumped and not launched and vel.y >= 0.0:
		write("LEDGE", "off the edge at %s without jumping - only the air jump is left" % _v(p.global_position))

	if _on_floor and not on_floor:
		_air_t = 0.0
		_takeoff_y = p.global_position.y
		_peak_y = _takeoff_y
	if not on_floor:
		_air_t += delta
		_peak_y = minf(_peak_y, p.global_position.y)
		var ff := p._pressed("down") and not p._field_active and p._rocket_time <= 0.0
		if ff and not _fast_fall:
			write("FASTFALL", "at %s  vy %.0f" % [_v(p.global_position), vel.y])
		_fast_fall = ff
	if on_floor and not _on_floor:
		var pound := "  (ground-pound speed)" if p.last_impact >= BreakableBlock.POUND_SPEED else ""
		write("LAND", "impact %.0f px/s  air %.2fs  peak +%.0f px  net %+.0f px%s" % [
			p.last_impact, _air_t, _takeoff_y - _peak_y, _takeoff_y - p.global_position.y, pound])
		_fast_fall = false

	if p._field_active and not _field:
		write("FIELD", "on  (%d chunks in range)" % _chunks_near(p))
		_field_held = 0
	if p._field_active:
		_field_held = maxi(_field_held, p._held.size())
	if _field and not p._field_active:
		var thrown := 0
		for f: Fragment in get_tree().get_nodes_in_group("fragments"):
			if f.thrown_by == p and f._thrown_time > 0.0:
				thrown += 1
		write("FIELD", "off  held up to %d  threw %d  aim %s" % [_field_held, thrown, _v(p.aim_vector())])

	if p.shock_cd > _shock_cd + 1.0:
		write("SHOCKWAVE", "aim %s  -> vel %s" % [_v(p.aim_vector()), _v(vel)])
	elif p._hit_flash > _hit_flash + 0.05:
		write("HIT", "knocked to vel %s" % _v(vel))

	_on_floor = on_floor
	_charging = p._charging
	_charge = p._charge
	_field = p._field_active
	_shock_cd = p.shock_cd
	_hit_flash = p._hit_flash
	_coyote = p._coyote
	_vy = vel.y


func _chunks_near(p: Player) -> int:
	var n := 0
	for f: Node2D in get_tree().get_nodes_in_group("fragments"):
		if f.global_position.distance_to(p.global_position) < Player.GRAVITY_RADIUS:
			n += 1
	return n


static func _v(v: Vector2) -> String:
	return "(%.0f, %.0f)" % [v.x, v.y]
