extends Node2D

## Match orchestration: builds the world, runs the countdown, tracks deaths,
## and decides the winner.
##
## Online, the server runs all of that and streams snapshots; clients build
## the same map from the shared seed and only display what they're sent.

const FLOOR_Y := 0.0
const COUNTDOWN := 3
const LAVA_START_BELOW := 650.0
const LAVA_GRACE := 3.5
const END_DELAY := 1.4

var background := Background.new()
var world := Node2D.new()
var map_gen: Node2D
var lava := Lava.new()
var camera := GameCamera.new()
var hud: Hud
var pause_menu: PauseMenu
var end_screen: EndScreen

var players: Array[Player] = []
var _deaths := 0
var _match_time := 0.0
var _countdown := 0.0
var _ending := false

# Online bookkeeping (server: what to send next; client: puppets by id).
var _block_states := {}            # net_id -> state, changed since the last snapshot
var _gone_fragments := PackedInt32Array()
var _puppet_fragments := {}        # net_id -> Fragment
var _snapshots_built := 0


func _ready() -> void:
	add_child(background)
	world.name = "World"
	add_child(world)

	map_gen = preload("res://scripts/game/map_generation.gd").new()
	map_gen.name = "Map"
	if Net.is_online():
		map_gen.map_seed = Net.match_seed
		Net.game = self
	world.add_child(map_gen)
	map_gen.generate(FLOOR_Y)

	var fx_layer := Node2D.new()
	fx_layer.name = "Fx"
	fx_layer.z_index = 20
	world.add_child(fx_layer)
	Fx.layer = fx_layer
	Fx.reduced = Settings.get_value("reduced_effects")

	world.add_child(lava)
	lava.surface_y = FLOOR_Y + LAVA_START_BELOW
	add_child(camera)
	background.camera = camera
	background.set_half_width(MapPlanner.HALF_WIDTH + 20.0)

	if PlayerManager.players.is_empty() and not Net.is_online():
		PlayerManager.join(Settings.DEVICE_KB_A)   # launched directly (editor / tests)
	_spawn_players()

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	end_screen = EndScreen.new()
	add_child(end_screen)

	SignalBus.player_died.connect(_on_player_died)
	SignalBus.chain_reaction_occurred.connect(_on_chain)
	SignalBus.settings_changed.connect(func(): Fx.reduced = Settings.get_value("reduced_effects"))
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	camera.targets = players
	camera.lava_y = lava.surface_y
	camera.snap()
	_countdown = COUNTDOWN + 0.6
	MatchManager.state = MatchManager.State.COUNTDOWN


func _spawn_players() -> void:
	var infos := PlayerManager.sorted_players()
	var n := infos.size()
	var spacing := minf(200.0, 800.0 / maxf(n, 1))
	for i in n:
		var p := Player.new()
		p.setup(infos[i])
		p.position = Vector2((i - (n - 1) * 0.5) * spacing, FLOOR_Y - Player.RADIUS - 1.0)
		p.facing = -1.0 if p.position.x > 0 else 1.0
		if Net.is_client():
			p.puppet = true
			p.collision_layer = 0
			p.collision_mask = 0
		world.add_child(p)
		players.append(p)


func _exit_tree() -> void:
	if Net.game == self:
		Net.game = null
	PlayerInput.suspended = false
	Player.lava_y = INF


func player_by_id(id: int) -> Player:
	for p in players:
		if p.player_id == id:
			return p
	return null


func _physics_process(delta: float) -> void:
	PlayerInput.suspended = Net.is_online() and pause_menu.visible
	if Net.is_client():
		_client_tick(delta)
		return
	var alive := players.filter(func(p): return not p.is_dead)
	if MatchManager.state == MatchManager.State.COUNTDOWN:
		var before := ceili(_countdown - 0.6)
		_countdown -= delta
		var after := ceili(_countdown - 0.6)
		if after != before and after > 0:
			Sfx.play("count")
		if _countdown <= 0.6:
			_start_match()
	elif MatchManager.state == MatchManager.State.PLAYING:
		_match_time += delta
		lava.active = _match_time > LAVA_GRACE

	var highest := INF
	var lowest := -INF
	for p in alive:
		highest = minf(highest, p.global_position.y)
		lowest = maxf(lowest, p.global_position.y)
		if p.global_position.y > lava.surface_y - 4.0:
			p.die()
		p.info.max_height = p.height_meters()
	if alive.is_empty():
		highest = camera.global_position.y
		lowest = highest

	lava.update_lava(delta, lowest, camera)
	camera.lava_y = lava.surface_y
	Player.lava_y = lava.surface_y
	map_gen.update_stream(highest, lava.surface_y)
	background.set_height(map_gen.height_of(camera.global_position.y))


func _start_match() -> void:
	MatchManager.state = MatchManager.State.PLAYING
	for p in players:
		p.controls_enabled = true
	Sfx.play("go")
	SignalBus.match_started.emit()


func countdown_value() -> int:
	return ceili(_countdown - 0.6) if MatchManager.state == MatchManager.State.COUNTDOWN else 0


func show_go() -> bool:
	return false


func leader() -> Player:
	var best: Player = null
	for p in players:
		if not p.is_dead and (best == null or p.max_height_px > best.max_height_px):
			best = p
	return best


func _on_player_died(player_id: int) -> void:
	if Net.is_client():
		return   # the server decides who's out and who won
	_deaths += 1
	var info: PlayerInfo = PlayerManager.players.get(player_id)
	if info:
		info.death_order = _deaths
	var alive := players.filter(func(p): return not p.is_dead)
	var solo := players.size() == 1
	if solo and alive.is_empty() or not solo and alive.size() <= 1:
		_finish(alive[0] if alive.size() == 1 else null)


func _finish(winner: Player) -> void:
	if _ending:
		return
	_ending = true
	if winner:
		winner.controls_enabled = false
	var standings := PlayerManager.sorted_players()
	standings.sort_custom(func(a, b):
		# Survivors first, then whoever died last.
		var ka: int = 1000 if a.death_order == 0 else a.death_order
		var kb: int = 1000 if b.death_order == 0 else b.death_order
		return ka > kb)
	var best_height := 0
	for info in standings:
		best_height = maxi(best_height, info.max_height)
	var new_record := Settings.record_height(best_height)
	var results := {
		"winner": winner.player_id if winner else -1,
		"solo": players.size() == 1,
		"standings": standings,
		"time": _match_time,
		"best_height": best_height,
		"new_record": new_record,
	}
	await get_tree().create_timer(END_DELAY).timeout
	lava.active = false
	if winner:
		Sfx.play("win")
	MatchManager.end_match(results)


func _on_chain(count: int, _pos: Vector2) -> void:
	if count == 3:
		Sfx.play("chain")
		_hit_stop(0.12)
	Fx.popup(camera.get_screen_center_position() + Vector2(0, -120), "x%d" % count, Palette.PAPER, 26 + count * 2)
	SignalBus.screen_shake_requested.emit(4.0 + count)


## Freeze-frame for impact. Uses a real-time timer so it ends on time.
func _hit_stop(duration: float) -> void:
	if Net.is_online():
		return   # would only freeze the server's copy of the world
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## A controller dropping out mid-match pauses the game so nobody dies to it.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and PlayerManager.find_by_device(device) and MatchManager.state != MatchManager.State.ENDED and not Net.is_online():
		pause_menu.open("Controller %d disconnected" % (device + 1))


## Browsers throttle hidden tabs; pause instead of letting the lava run.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.is_web() and MatchManager.state == MatchManager.State.PLAYING and not Net.is_online():
		pause_menu.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and MatchManager.state != MatchManager.State.ENDED:
		get_viewport().set_input_as_handled()
		pause_menu.open()


# ── Online ───────────────────────────────────

## Server: a block's gameplay state changed (see Block.net_changed).
func queue_block_state(b: Block) -> void:
	_block_states[b.net_id] = b.net_state()


func fragment_gone(id: int) -> void:
	_gone_fragments.append(id)


## Server: everything a client needs to draw this tick.
## [header, players, fragments, new fragments, gone fragments, block states]
func build_snapshot() -> Array:
	var header := PackedFloat32Array([MatchManager.state, _countdown, Block.clock, lava.surface_y])
	var pdata := PackedFloat32Array()
	for p in players:
		p.write_net(pdata)
	var fdata := PackedFloat32Array()
	var spawns := []
	# Resting chunks are skipped, but now and then everything is resent in
	# case the update that put a chunk to rest got lost on the way.
	_snapshots_built += 1
	var resend_all := _snapshots_built % 15 == 0
	for f: Fragment in get_tree().get_nodes_in_group("fragments"):
		if f.is_queued_for_deletion():
			continue
		if not f.net_announced:
			f.net_announced = true
			spawns.append([f.net_id, f._poly, f._body, f._hi])
		var now := Vector3(f.global_position.x, f.global_position.y, f.rotation)
		if now.distance_squared_to(f.net_sent) < 0.09 and not resend_all:
			continue   # resting chunks cost nothing
		f.net_sent = now
		fdata.append_array([f.net_id, now.x, now.y, now.z, f.linear_velocity.x, f.linear_velocity.y])
	var blocks := PackedInt32Array()
	for id in _block_states:
		blocks.append_array([id, _block_states[id]])
	_block_states.clear()
	var gone := _gone_fragments
	_gone_fragments = PackedInt32Array()
	return [header, pdata, fdata, spawns, gone, blocks]


## Client: positions and match state from the server (may arrive out of
## step with apply_events; updates for chunks we don't know yet are skipped).
func apply_state(header: PackedFloat32Array, pdata: PackedFloat32Array, fdata: PackedFloat32Array) -> void:
	var state := int(header[0]) as MatchManager.State
	if state != MatchManager.State.ENDED and MatchManager.state != MatchManager.State.ENDED:
		MatchManager.state = state
	_countdown = header[1]
	Block.clock = header[2]
	lava.surface_y = header[3]

	for i in range(0, pdata.size(), Player.NET_STRIDE):
		var p := player_by_id(int(pdata[i]))
		if p:
			p.read_net(pdata, i)

	for i in range(0, fdata.size(), 6):
		var f := _puppet_fragment(int(fdata[i]))
		if f:
			f.set_net_target(Vector2(fdata[i + 1], fdata[i + 2]), fdata[i + 3], Vector2(fdata[i + 4], fdata[i + 5]))
			f.visible = true


## Client: one-off changes from the server - chunks appearing and going,
## blocks breaking or vanishing.
func apply_events(spawns: Array, gone: PackedInt32Array, blocks: PackedInt32Array) -> void:
	for s in spawns:
		var f := Fragment.new()
		f.setup(s[1], s[2], s[3])
		f.make_puppet(s[0])
		f.visible = false   # until its first position arrives
		map_gen.add_child(f)
		_puppet_fragments[s[0]] = f
	for id in gone:
		var f := _puppet_fragment(id)
		if f:
			f.queue_free()
		_puppet_fragments.erase(id)

	for i in range(0, blocks.size(), 2):
		var b: Block = map_gen.block_by_net_id(blocks[i])
		if b:
			b.apply_net_state(blocks[i + 1])


## Client: the puppet chunk for a net id, or null. Chunks can be freed
## locally (map streaming culls them below the lava) before the server says
## they're gone, so stale entries are dropped here.
func _puppet_fragment(id: int) -> Fragment:
	var f: Variant = _puppet_fragments.get(id)
	if f == null:
		return null
	if not is_instance_valid(f):
		_puppet_fragments.erase(id)
		return null
	return f


## Client tick: send our controls, keep the map and camera following the
## puppets. No deaths, lava or results here - those come from the server.
func _client_tick(_delta: float) -> void:
	for p in players:
		if p.info.is_local() and not p.is_dead:
			p.input.update()
			Net.send_input(p.player_id, p.input.buttons, p.input.move)
	var highest := INF
	var lowest := -INF
	for p in players:
		if not p.is_dead:
			highest = minf(highest, p.global_position.y)
			lowest = maxf(lowest, p.global_position.y)
			p.info.max_height = p.height_meters()
	if highest == INF:
		highest = camera.global_position.y
		lowest = highest
	lava.active = false   # its height comes from the server
	lava.update_lava(0.0, lowest, camera)
	camera.lava_y = lava.surface_y
	Player.lava_y = lava.surface_y
	map_gen.update_stream(highest, lava.surface_y)
	background.set_height(map_gen.height_of(camera.global_position.y))
