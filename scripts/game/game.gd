extends Node2D

@export var player_scenes: Dictionary = {
	1: preload("res://scenes/player/player_1.tscn"),
	2: preload("res://scenes/player/player_2.tscn")
}

const PlayerUI = preload("res://scenes/player/player_ui.tscn")

var active_player_nodes: Dictionary = {}
var active_ui_nodes: Dictionary = {}

func _ready() -> void:
	SignalBus.player_died.connect(_on_player_died)

	await get_tree().process_frame
	await get_tree().physics_frame

	_init_map()
	setup_game()

func _init_map() -> void:
	var map_gen = get_node_or_null("MapGeneration")
	if map_gen and map_gen.has_method("generate_map"):
		for child in map_gen.get_children():
			child.queue_free()
		map_gen.generate_map()

func setup_game() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		p.queue_free()

	for ui in active_ui_nodes.values():
		if is_instance_valid(ui):
			ui.queue_free()
	active_player_nodes.clear()
	active_ui_nodes.clear()

	var players = PlayerManager.active_players
	if players.is_empty():
		PlayerManager.join_player(-1)
		players = PlayerManager.active_players

	var spawn_points = _get_spawn_points(players.size())

	var i = 0
	var player_nodes: Array[Node2D] = []
	for p_id in players:
		var p_data = players[p_id]
		var p_node = _spawn_player(p_data, spawn_points[i])
		active_player_nodes[p_id] = p_node
		player_nodes.append(p_node)

		var ui = PlayerUI.instantiate()
		ui.player_id = p_id
		add_child(ui)
		active_ui_nodes[p_id] = ui
		i += 1

	if player_nodes.is_empty():
		return

	var pcam = get_node_or_null("PhantomCamera2D")
	if pcam:
		pcam.follow_targets = player_nodes
		if pcam.has_method("update_phantom_camera"):
			pcam.update_phantom_camera()

func _get_spawn_points(count: int) -> Array[Vector2]:
	match count:
		1: return [Vector2(0, -200)]
		2: return [Vector2(-200, -200), Vector2(200, -200)]
		3: return [Vector2(-300, -200), Vector2(0, -200), Vector2(300, -200)]
		4: return [Vector2(-450, -200), Vector2(-150, -200), Vector2(150, -200), Vector2(450, -200)]
	return [Vector2.ZERO]

func _spawn_player(data: PlayerData, pos: Vector2) -> CharacterBody2D:
	var scene = player_scenes.get(data.player_id, player_scenes.get(1))
	var player = scene.instantiate()
	add_child(player)
	player.global_position = pos
	if player.has_method("setup_with_data"):
		player.setup_with_data(data)
	if not player.is_in_group("player"):
		player.add_to_group("player")
	return player

func _on_player_died(player_id: int) -> void:
	if MatchManager.current_state != MatchManager.GameState.PLAYING:
		return

	# Remove dead player from camera follow targets
	var pcam = get_node_or_null("PhantomCamera2D")
	if pcam and active_player_nodes.has(player_id):
		pcam.erase_follow_targets(active_player_nodes[player_id])

	var alive_count = 0
	var winner_id = -1

	for p_id in active_player_nodes:
		if is_instance_valid(active_player_nodes[p_id]) and not active_player_nodes[p_id].is_dead:
			alive_count += 1
			winner_id = p_id

	if alive_count <= 1:
		var results = {"winner": winner_id}
		MatchManager.end_match(results)

func _input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		SignalBus.game_paused.emit(true)
