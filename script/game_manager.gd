extends Node

# Alternative approaches for finding the UI layer:
@onready var ui_layer := get_node("UI")  # Direct path
@onready var match_start_ui = preload("res://scenes/match_start.tscn").instantiate()
@onready var exit_dialog := %ExitDialog

var players_ready := 0
var spawned_players := {}
var player_characters := {}
var player_names := {}

func _ready():
	# Check if ui_layer exists before using it
	if ui_layer == null:
		print("❌ UI layer not found! Make sure you have a node with unique name 'UI'")
		# Fallback: add to current scene
		add_child(match_start_ui)
	else:
		ui_layer.add_child(match_start_ui)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if Global.is_host:
		var my_id = multiplayer.get_unique_id()
		player_characters[my_id] = Global.selected_character
		player_names[my_id] = Global.player_name
		# Host calls spawn_player with call_local to spawn on all clients including self
		spawn_player.rpc(my_id, Global.selected_character, Global.player_name)
		match_start_ui.get_node("Waiting").show()
	else:
		match_start_ui.get_node("Waiting").hide()

func _on_peer_connected(peer_id: int) -> void:
	print("🔗 Peer connected:", peer_id)
	if Global.is_host:
		# When a client connects, send them info about all existing players (including host)
		for existing_peer_id in player_characters:
			spawn_player.rpc_id(peer_id, existing_peer_id, player_characters[existing_peer_id], player_names[existing_peer_id])
	else:
		# Send name + character to host only
		register_character_choice.rpc_id(1, multiplayer.get_unique_id(), Global.selected_character, Global.player_name)

func _on_peer_disconnected(peer_id: int) -> void:
	print("❌ Peer disconnected:", peer_id)
	if spawned_players.has(peer_id):
		spawned_players[peer_id].queue_free()
		spawned_players.erase(peer_id)
		player_characters.erase(peer_id)
		player_names.erase(peer_id)
		players_ready = max(0, players_ready - 1)

@rpc("any_peer")
func register_character_choice(peer_id: int, character_name: String, player_name: String) -> void:
	if not Global.is_host:
		return
	
	player_characters[peer_id] = character_name
	player_names[peer_id] = player_name
	
	# Spawn this player on all clients
	spawn_player.rpc(peer_id, character_name, player_name)

@rpc("authority", "call_local")
func spawn_player(peer_id: int, character_name: String, player_name: String):
	if spawned_players.has(peer_id):
		return
	
	var scene_path = "res://scenes/%s.tscn" % character_name.to_lower()
	var character_scene = load(scene_path)
	if character_scene == null:
		print("❌ Failed to load character:", character_name)
		return
	
	var character = character_scene.instantiate()
	add_child(character)
	character.set_multiplayer_authority(peer_id)
	character.name = "%s_%s" % [character_name, str(peer_id)]
	spawned_players[peer_id] = character
	
	# Position logic: Host is always on left, Client is always on right
	var is_host_player = (peer_id == 1)  # Host always has ID 1
	
	if is_host_player:
		# Host player goes on the left
		character.global_position = Vector2(-500, 0)
		character.get_node("AnimatedSprite2D").flip_h = false
	else:
		# Client player goes on the right
		character.global_position = Vector2(500, 0)
		character.get_node("AnimatedSprite2D").flip_h = true
	
	# Pass the name and position info to the player scene
	character.call_deferred("set_player_info", player_name, is_host_player)
	print("✅ Spawned", character_name, "for peer", peer_id, "- Host:", is_host_player)
	
	players_ready += 1
	if Global.is_host and players_ready == 2:
		start_match_sequence.rpc()

@rpc("authority", "call_local")
func start_match_sequence():
	match_start_ui.get_node("Waiting").hide()
	var anim = match_start_ui.get_node("AnimationPlayer")
	anim.play("match_start")
	await anim.animation_finished
	
	# Enable control for all players - call on each player directly
	for peer_id in spawned_players:
		spawned_players[peer_id].start_player_control()
	
	match_start_ui.queue_free()

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		show_exit_dialog()

func show_exit_dialog():
	exit_dialog.popup_centered()

func _on_exit_dialog_confirmed():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
