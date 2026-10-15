extends Node2D

## Match orchestration: builds the world, runs the countdown, tracks deaths,
## and decides the winner.

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
var title_card := TitleCard.new()

var players: Array[Player] = []
var _deaths := 0
var _match_time := 0.0
var _countdown := 0.0
var _ending := false


func _ready() -> void:
	add_child(background)
	world.name = "World"
	add_child(world)

	map_gen = preload("res://scripts/game/map_generation.gd").new()
	map_gen.name = "Map"
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

	if PlayerManager.players.is_empty():
		PlayerManager.join(Settings.DEVICE_KB_A)   # launched directly (editor / tests)
	_spawn_players()

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	end_screen = EndScreen.new()
	add_child(end_screen)
	add_child(title_card)

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
	var spacing := minf(240.0, 1100.0 / maxf(n, 1))
	for i in n:
		var p := Player.new()
		p.setup(infos[i])
		p.position = Vector2((i - (n - 1) * 0.5) * spacing, FLOOR_Y - Player.RADIUS - 1.0)
		p.facing = -1.0 if p.position.x > 0 else 1.0
		world.add_child(p)
		players.append(p)


func _physics_process(delta: float) -> void:
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
	map_gen.update_stream(highest, lava.surface_y)
	background.set_height(map_gen.height_of(camera.global_position.y))


func _start_match() -> void:
	MatchManager.state = MatchManager.State.PLAYING
	for p in players:
		p.controls_enabled = true
	Sfx.play("go")
	title_card.show_card("LET'S JAM", "", 6, 1.1)
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
	_deaths += 1
	var dead: PlayerInfo = PlayerManager.players.get(player_id)
	if dead and players.size() > 1:
		title_card.show_card("P%d IS OUT" % player_id, "", 3, 0.8, dead.color)
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
		Fx.popup(winner.global_position + Vector2(0, -60), "WINNER!", winner.color, 40)
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
	title_card.show_card("CHAIN x%d" % count, "", mini(3 + count, 8), 0.75)
	SignalBus.screen_shake_requested.emit(4.0 + count)


## Freeze-frame for impact. Uses a real-time timer so it ends on time.
func _hit_stop(duration: float) -> void:
	Engine.time_scale = 0.08
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0


## A controller dropping out mid-match pauses the game so nobody dies to it.
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if not connected and PlayerManager.find_by_device(device) and MatchManager.state != MatchManager.State.ENDED:
		pause_menu.open("Controller %d disconnected" % (device + 1))


## Browsers throttle hidden tabs; pause instead of letting the lava run.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Settings.is_web() and MatchManager.state == MatchManager.State.PLAYING:
		pause_menu.open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and MatchManager.state != MatchManager.State.ENDED:
		get_viewport().set_input_as_handled()
		pause_menu.open()
