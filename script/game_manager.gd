extends Node

# Alternative approaches for finding the UI layer:
@onready var ui_layer := get_node("UI")  # Direct path
@onready var match_start_ui = preload("res://scenes/match_start.tscn").instantiate()
@onready var exit_dialog := %ExitDialog

var players_ready := 0
var spawned_players := {}
var spawned_pets := {}
var player_characters := {}
var player_names := {}
var player_pets := {}
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
		player_pets[my_id] = Global.selected_pet
		# Host calls spawn_player with call_local to spawn on all clients including self
		spawn_player.rpc(my_id, Global.selected_character, Global.player_name, Global.selected_pet)
		match_start_ui.get_node("Waiting").show()
	else:
		match_start_ui.get_node("Waiting").hide()

func _on_peer_connected(peer_id: int) -> void:
	print("🔗 Peer connected:", peer_id)
	if Global.is_host:
		# When a client connects, send them info about all existing players (including host)
		for existing_peer_id in player_characters:
			spawn_player.rpc_id(peer_id, existing_peer_id, player_characters[existing_peer_id], player_names[existing_peer_id], player_pets[existing_peer_id])
	else:
		# Send name + character + pet to host only
		register_character_choice.rpc_id(1, multiplayer.get_unique_id(), Global.selected_character, Global.player_name, Global.selected_pet)

func _on_peer_disconnected(peer_id: int) -> void:
	print("❌ Peer disconnected:", peer_id)
	if spawned_players.has(peer_id):
		spawned_players[peer_id].queue_free()
		spawned_players.erase(peer_id)
		player_characters.erase(peer_id)
		player_names.erase(peer_id)
		player_pets.erase(peer_id)
		players_ready = max(0, players_ready - 1)
	
	if spawned_pets.has(peer_id):
		spawned_pets[peer_id].queue_free()
		spawned_pets.erase(peer_id)

@rpc("any_peer")
func register_character_choice(peer_id: int, character_name: String, player_name: String, pet_name: String) -> void:
	if not Global.is_host:
		return
	
	player_characters[peer_id] = character_name
	player_names[peer_id] = player_name
	player_pets[peer_id] = pet_name
	
	# Spawn this player on all clients
	spawn_player.rpc(peer_id, character_name, player_name, pet_name)

@rpc("authority", "call_local")
func spawn_player(peer_id: int, character_name: String, player_name: String, pet_name: String):
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
	
	# Spawn the pet
	spawn_pet(peer_id, pet_name, is_host_player)
	
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

func spawn_pet(peer_id: int, pet_name: String, is_host_player: bool):
	if spawned_pets.has(peer_id):
		return
	
	var pet_scene_path = "res://scenes/%s.tscn" % pet_name.to_lower()
	var pet_scene = load(pet_scene_path)
	if pet_scene == null:
		print("❌ Failed to load pet:", pet_name)
		return
	
	var pet = pet_scene.instantiate()
	add_child(pet)
	pet.name = "%s_pet_%s" % [pet_name, str(peer_id)]
	spawned_pets[peer_id] = pet
	
	# Set pet position based on player position
	if is_host_player:
		# Player1 pet: position (-100, -46), facing right
		pet.global_position = Vector2(-100, -46)
		if pet.has_node("AnimatedSprite2D"):
			pet.get_node("AnimatedSprite2D").flip_h = false
	else:
		# Player2 pet: position (190, -46), facing left
		pet.global_position = Vector2(190, -46)
		if pet.has_node("AnimatedSprite2D"):
			pet.get_node("AnimatedSprite2D").flip_h = true
	
	# Apply pet perks to the player
	apply_pet_perks(peer_id, pet_name)
	
	# Start the glow animation with intervals
	start_pet_glow_animation(pet)
	print("✅ Spawned pet", pet_name, "for peer", peer_id)

func apply_pet_perks(peer_id: int, pet_name: String):
	var player = spawned_players[peer_id]
	if not player:
		return
	
	match pet_name.to_lower():
		"mew":
			# Mew: +50 HP (adding to base 100 HP)
			player.health += 50
			# Add variables to track pet bonuses
			player.set("pet_bonus_hp", 50)
			# Update UI immediately
			player.call_deferred("update_health_ui")
			print("✨ Mew perk applied: +50 HP to player", peer_id, "- Total HP:", player.health)
		
		"squirtle":
			# Squirtle: +50% attack damage multiplier
			player.set("pet_attack_multiplier", 1.5)
			print("✨ Squirtle perk applied: +50% attack damage to player", peer_id)
		
		"yeti":
			# Yeti: -30% damage taken (damage reduction)
			player.set("pet_damage_reduction", 0.3)
			print("✨ Yeti perk applied: -30% damage reduction to player", peer_id)
		
		_:
			print("⚠️ Unknown pet:", pet_name, "- no perks applied")

func start_pet_glow_animation(pet: Node):
	# Create a timer for periodic glow animation
	var glow_timer = Timer.new()
	add_child(glow_timer)
	glow_timer.wait_time = randf_range(3.0, 6.0)  # Random interval between 3-6 seconds
	glow_timer.timeout.connect(func(): play_pet_glow(pet, glow_timer))
	glow_timer.start()

func play_pet_glow(pet: Node, timer: Timer):
	if pet == null or not is_instance_valid(pet):
		timer.queue_free()
		return
	
	# Play glow animation if pet has AnimatedSprite2D
	if pet.has_node("AnimatedSprite2D"):
		var sprite = pet.get_node("AnimatedSprite2D")
		if sprite.sprite_frames and sprite.sprite_frames.has_animation("glow"):
			sprite.play("glow")
	
	# Set next random interval
	timer.wait_time = randf_range(3.0, 6.0)

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		show_exit_dialog()

func show_exit_dialog():
	exit_dialog.popup_centered()

func _on_exit_dialog_confirmed():
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
