extends Node

# Alternative approaches for finding the UI layer:
@onready var ui_layer := get_node("UI")  # Direct path
@onready var match_start_ui = preload("res://scenes/match_start.tscn").instantiate()
@onready var exit_dialog := %ExitDialog

# Database manager reference
@onready var db_manager: Node

var players_ready := 0
var spawned_players := {}
var spawned_pets := {}
var player_characters := {}
var player_names := {}
var player_pets := {}
var game_manager: Node

# Match tracking
var match_start_time := 0
var current_match_data := {}

# Add connection tracking
var connection_established := false

func _ready():
	# Initialize database manager
	db_manager = preload("res://script/database_manager.gd").new()
	add_child(db_manager)
	
	# Connect database signals
	db_manager.match_started.connect(_on_match_started_in_db)
	db_manager.match_completed.connect(_on_match_completed_in_db)
	db_manager.error_occurred.connect(_on_db_error)
	db_manager.player_created.connect(_on_player_created_in_db)
	
	# Wait for database to load before initializing player
	if not db_manager.characters_cache.is_empty():
		db_manager.initialize_player(Global.player_name)
	else:
		await db_manager.data_loaded
		db_manager.initialize_player(Global.player_name)
	
	# Check if ui_layer exists before using it
	if ui_layer == null:
		print("❌ UI layer not found! Make sure you have a node with unique name 'UI'")
		# Fallback: add to current scene
		add_child(match_start_ui)
	else:
		ui_layer.add_child(match_start_ui)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	print("🎮 Game Manager Ready - Is Host: ", Global.is_host, " Player: ", Global.player_name)
	
	if Global.is_host:
		print("🏠 HOST: Initializing host player...")
		var my_id = multiplayer.get_unique_id()
		player_characters[my_id] = Global.selected_character
		player_names[my_id] = Global.player_name
		player_pets[my_id] = Global.selected_pet
		# Host spawns itself
		spawn_player.rpc(my_id, Global.selected_character, Global.player_name, Global.selected_pet)
		match_start_ui.get_node("Waiting").show()
		print("🏠 HOST: Waiting for client to connect...")
	else:
		print("👤 CLIENT: Waiting for connection to establish...")
		match_start_ui.get_node("Waiting").show()
		# Give a small delay to ensure connection is stable
		await get_tree().create_timer(0.5).timeout
		_register_with_host()
	
	add_to_group("game_manager")

func _register_with_host():
	"""Client registers its character info with the host"""
	if Global.is_host:
		return
	
	var my_id = multiplayer.get_unique_id()
	print("👤 CLIENT: Registering with host - ID: ", my_id)
	print("👤 CLIENT: Character: ", Global.selected_character, " Name: ", Global.player_name, " Pet: ", Global.selected_pet)
	
	# Send registration to host
	register_character_choice.rpc_id(1, my_id, Global.selected_character, Global.player_name, Global.selected_pet)

func _on_player_created_in_db(player_id: int):
	print("📊 Player created/found in database with ID: ", player_id)

func _on_peer_connected(peer_id: int) -> void:
	print("🔗 Peer connected:", peer_id, " (I am host: ", Global.is_host, ")")
	
	if Global.is_host:
		print("🏠 HOST: Client connected with ID: ", peer_id)
		# Send existing players to the new client
		for existing_peer_id in player_characters:
			print("🏠 HOST: Sending existing player ", existing_peer_id, " to new client ", peer_id)
			spawn_player.rpc_id(peer_id, existing_peer_id, player_characters[existing_peer_id], player_names[existing_peer_id], player_pets[existing_peer_id])
	else:
		print("👤 CLIENT: Connected to host, registering character...")
		# Small delay to ensure connection is stable
		await get_tree().create_timer(0.2).timeout
		_register_with_host()

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
	
	# Mark match as abandoned if in progress
	if match_start_time > 0:
		db_manager.complete_match("", get_match_duration())

@rpc("any_peer", "call_local")
func register_character_choice(peer_id: int, character_name: String, player_name: String, pet_name: String) -> void:
	print("🎯 HOST: Received character registration from peer ", peer_id)
	print("🎯 HOST: Character: ", character_name, " Name: ", player_name, " Pet: ", pet_name)
	
	if not Global.is_host:
		print("❌ Only host can process character registration")
		return
	
	# Check if this player is already registered
	if player_characters.has(peer_id):
		print("⚠️ Player ", peer_id, " already registered, skipping...")
		return
	
	player_characters[peer_id] = character_name
	player_names[peer_id] = player_name
	player_pets[peer_id] = pet_name
	
	print("🎯 HOST: Registered new player - Total players: ", player_characters.size())
	print("🎯 HOST: Current players: ", player_characters.keys())
	
	# Spawn this player on all clients (including host)
	spawn_player.rpc(peer_id, character_name, player_name, pet_name)

@rpc("authority", "call_local")
func spawn_player(peer_id: int, character_name: String, player_name: String, pet_name: String):
	print("👥 Spawning player - Peer: ", peer_id, " Character: ", character_name, " Name: ", player_name)
	
	if spawned_players.has(peer_id):
		print("⚠️ Player already spawned for peer ", peer_id)
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
	
	# Update ready count
	players_ready += 1
	print("🎯 Players ready: ", players_ready, "/2")
	
	# Check if we can start the match (only on host)
	if Global.is_host:
		print("🏠 HOST: Checking if match can start...")
		print("🏠 HOST: Players ready: ", players_ready, " Total registered: ", player_characters.size())
		
		# Start match when we have exactly 2 players spawned
		if players_ready == 2 and player_characters.size() == 2:
			print("🎮 HOST: All conditions met - Starting match!")
			# Small delay to ensure everything is set up
			await get_tree().create_timer(1.0).timeout
			start_database_match()
		else:
			print("🏠 HOST: Not ready yet - need 2 spawned players and 2 registered players")

func start_database_match():
	"""Initialize match in database"""
	print("📊 Preparing database match...")
	
	# Wait for data to be loaded
	if db_manager.characters_cache.is_empty() or db_manager.pets_cache.is_empty():
		print("⏳ Waiting for database data to load...")
		await db_manager.data_loaded
	
	var host_name = ""
	var client_name = ""
	var host_character = ""
	var client_character = ""
	var host_pet = ""
	var client_pet = ""
	
	# Get match data from spawned players
	for peer_id in player_names:
		if peer_id == 1:  # Host
			host_name = player_names[peer_id]
			host_character = player_characters[peer_id]
			host_pet = player_pets[peer_id]
		else:  # Client
			client_name = player_names[peer_id]
			client_character = player_characters[peer_id]  
			client_pet = player_pets[peer_id]
	
	print("🎮 Match Data - Host: ", host_name, "(", host_character, "+", host_pet, ") vs Client: ", client_name, "(", client_character, "+", client_pet, ")")
	
	# Validate all data is present
	if host_name == "" or client_name == "" or host_character == "" or client_character == "" or host_pet == "" or client_pet == "":
		print("❌ Missing match data, cannot start database match")
		print("❌ Debug - Host data: ", host_name, ", ", host_character, ", ", host_pet)
		print("❌ Debug - Client data: ", client_name, ", ", client_character, ", ", client_pet)
		return
	
	# Store match data for later
	current_match_data = {
		"host_name": host_name,
		"client_name": client_name,
		"host_character": host_character,
		"client_character": client_character,
		"host_pet": host_pet,
		"client_Pet": client_pet
	}
	
	# Start match in database
	print("📊 Starting database match...")
	db_manager.start_match(host_name, client_name, host_character, client_character, host_pet, client_pet)

@rpc("authority", "call_local")
func start_match_sequence():
	print("🎬 Starting match sequence animation...")
	match_start_ui.get_node("Waiting").hide()
	var anim = match_start_ui.get_node("AnimationPlayer")
	anim.play("match_start")
	await anim.animation_finished
	
	# Record match start time
	match_start_time = Time.get_ticks_msec()
	print("⏰ Match timer started at: ", match_start_time)
	
	# Enable control for all players - call on each player directly
	for peer_id in spawned_players:
		spawned_players[peer_id].start_player_control()
		print("🎮 Enabled controls for player ", peer_id)
	
	match_start_ui.queue_free()
	print("🎬 Match sequence complete - FIGHT!")

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

# ========================================
# MATCH COMPLETION HANDLING
# ========================================

func on_player_defeated(defeated_player_name: String):
	"""Called when a player is defeated - determines winner and saves to database"""
	if match_start_time == 0:
		return  # Match hasn't started yet
	
	var winner_name = ""
	
	# Determine winner (the one who didn't lose)
	for peer_id in player_names:
		if player_names[peer_id] != defeated_player_name:
			winner_name = player_names[peer_id]
			break
	
	if winner_name != "":
		var match_duration = get_match_duration()
		db_manager.complete_match(winner_name, match_duration)
		print("🏆 Match completed - Winner: ", winner_name, " Duration: ", match_duration, "s")

func get_match_duration() -> int:
	"""Get match duration in seconds"""
	if match_start_time == 0:
		return 0
	return int((Time.get_ticks_msec() - match_start_time) / 1000.0)

# ========================================
# DATABASE EVENT HANDLERS  
# ========================================

func _on_match_started_in_db(match_id: int):
	print("📊 Match started in database with ID: ", match_id)
	# Now start the visual match sequence
	start_match_sequence.rpc()

func _on_match_completed_in_db(winner_name: String):
	print("📊 Match saved to database - Winner: ", winner_name)

func _on_db_error(message: String):
	print("❌ Database error: ", message)

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
	# Save match as abandoned if in progress
	if match_start_time > 0:
		db_manager.complete_match("", get_match_duration())
	
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
