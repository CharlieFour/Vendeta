extends Node

# Supabase Configuration - REPLACE WITH YOUR ACTUAL VALUES
const SUPABASE_URL := "https://yivuctiqmyddvfjkyubq.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlpdnVjdGlxbXlkZHZmamt5dWJxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgyMTgyODcsImV4cCI6MjA2Mzc5NDI4N30.4XqOBJ6m7A9eHIoFxlh4Zq8oHw0HkxXP65bTrMl8l_A"

# HTTP Request nodes
@onready var http_request: HTTPRequest

# Cache for quick access
var characters_cache := {}
var pets_cache := {}
var current_player_id := -1
var current_match_id := -1

signal player_created(player_id: int)
signal match_started(match_id: int) 
signal match_completed(winner_name: String)
signal data_loaded()
signal error_occurred(message: String)

func _ready():
	# Create HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Load initial data
	load_characters_and_pets()

# ========================================
# INITIAL DATA LOADING
# ========================================

func load_characters_and_pets():
	print("🔄 Loading characters and pets from database...")
	
	# Load characters first
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/characters"
	http_request.request(url, headers, HTTPClient.METHOD_GET)


func load_pets():
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/pets"
	http_request.request(url, headers, HTTPClient.METHOD_GET)

# ========================================
# PLAYER MANAGEMENT
# ========================================

func create_or_get_player(player_name: String):
	print("👤 Creating/Getting player: ", player_name)
	
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	# First try to get existing player
	var url = SUPABASE_URL + "/rest/v1/players?player_name=eq." + player_name.uri_encode()
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func create_new_player(player_name: String):
	print("✨ Creating new player: ", player_name)
	
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Prefer: return=representation"
	]
	
	var data = {
		"player_name": player_name
	}
	
	var url = SUPABASE_URL + "/rest/v1/players"
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

# ========================================
# MATCH MANAGEMENT
# ========================================

func start_match(host_name: String, client_name: String, host_character: String, client_character: String, host_pet: String, client_pet: String):
	print("🎮 Starting match: ", host_name, " vs ", client_name)
	
	# Get character and pet IDs
	var host_char_id = get_character_id(host_character)
	var client_char_id = get_character_id(client_character)
	var host_pet_id = get_pet_id(host_pet)
	var client_pet_id = get_pet_id(client_pet)
	
	if host_char_id == -1 or client_char_id == -1 or host_pet_id == -1 or client_pet_id == -1:
		emit_signal("error_occurred", "Invalid character or pet selection")
		return
	
	# Get player IDs (assuming they exist)
	get_player_ids_for_match.call_deferred(host_name, client_name, host_char_id, client_char_id, host_pet_id, client_pet_id)

func get_player_ids_for_match(host_name: String, client_name: String, host_char_id: int, client_char_id: int, host_pet_id: int, client_pet_id: int):
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	# Get both players in one request
	var url = SUPABASE_URL + "/rest/v1/players?or=(player_name.eq." + host_name.uri_encode() + ",player_name.eq." + client_name.uri_encode() + ")"
	
	# Store match data for later use
	set_meta("pending_match", {
		"host_name": host_name,
		"client_name": client_name,
		"host_char_id": host_char_id,
		"client_char_id": client_char_id,
		"host_pet_id": host_pet_id,
		"client_pet_id": client_pet_id
	})
	
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func create_match_record(host_player_id: int, client_player_id: int, host_char_id: int, client_char_id: int, host_pet_id: int, client_pet_id: int):
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Prefer: return=representation"
	]
	
	var data = {
		"host_player_id": host_player_id,
		"client_player_id": client_player_id,
		"host_character_id": host_char_id,
		"client_character_id": client_char_id,
		"host_pet_id": host_pet_id,
		"client_pet_id": client_pet_id,
		"status": "in_progress"
	}
	
	var url = SUPABASE_URL + "/rest/v1/matches"
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))

func complete_match(winner_name: String, match_duration: int = 0):
	if current_match_id == -1:
		print("❌ No active match to complete")
		return
	
	print("🏆 Completing match - Winner: ", winner_name)
	
	# Get winner player ID
	var winner_id = await get_player_id_by_name(winner_name)
	
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var data = {
		"winner_player_id": winner_id,
		"match_duration": match_duration,
		"status": "completed"
	}
	
	var url = SUPABASE_URL + "/rest/v1/matches?match_id=eq." + str(current_match_id)
	http_request.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(data))

# ========================================
# STATS AND LEADERBOARD
# ========================================

func get_player_stats(player_name: String):
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/player_stats?player_name=eq." + player_name.uri_encode()
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func get_leaderboard(limit: int = 10):
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/player_stats?order=total_wins.desc,win_percentage.desc&limit=" + str(limit)
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func get_recent_matches(limit: int = 10):
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/match_details?order=created_at.desc&limit=" + str(limit)
	http_request.request(url, headers, HTTPClient.METHOD_GET)

# ========================================
# HELPER FUNCTIONS
# ========================================

func get_character_id(character_name: String) -> int:
	for char_id in characters_cache:
		if characters_cache[char_id] == character_name:
			return char_id
	return -1

func get_pet_id(pet_name: String) -> int:
	for pet_id in pets_cache:
		if pets_cache[pet_id]["name"] == pet_name:
			return pet_id
	return -1

func get_player_id_by_name(player_name: String) -> int:
	var headers = [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json"
	]
	
	var url = SUPABASE_URL + "/rest/v1/players?player_name=eq." + player_name.uri_encode()
	http_request.request(url, headers, HTTPClient.METHOD_GET)
	
	await http_request.request_completed
	var response = get_meta("last_response", [])
	if response.size() > 0:
		return response[0]["player_id"]
	return -1

# ========================================
# HTTP RESPONSE HANDLER
# ========================================

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	var json_string = body.get_string_from_utf8()
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		emit_signal("error_occurred", "Failed to parse response")
		return
	
	var data = json.data
	set_meta("last_response", data)
	
	print("📡 Response Code: ", response_code)
	print("📡 Response Data: ", data)
	
	if response_code >= 200 and response_code < 300:
		_handle_successful_response(data)
	else:
		emit_signal("error_occurred", "Request failed: " + str(response_code))

func _handle_successful_response(data):
	# Handle different types of responses based on the data structure
	if data is Array and data.size() > 0:
		var first_item = data[0]
		
		# Characters data
		if first_item.has("charac_id"):
			for character in data:
				characters_cache[character["charac_id"]] = character["charac_name"]
			print("✅ Loaded ", data.size(), " characters")
			load_pets() # Load pets after characters
		
		# Pets data  
		elif first_item.has("pet_id"):
			for pet in data:
				pets_cache[pet["pet_id"]] = {
					"name": pet["pet_name"],
					"perk": pet["pet_perk"]
				}
			print("✅ Loaded ", data.size(), " pets")
			emit_signal("data_loaded")
		
		# Player data
		elif first_item.has("player_id"):
			if has_meta("pending_match"):
				# Handle match creation
				var match_data = get_meta("pending_match")
				var host_player_id = -1
				var client_player_id = -1
				
				for player in data:
					if player["player_name"] == match_data["host_name"]:
						host_player_id = player["player_id"]
					elif player["player_name"] == match_data["client_name"]:
						client_player_id = player["player_id"]
				
				if host_player_id != -1 and client_player_id != -1:
					create_match_record(host_player_id, client_player_id, 
						match_data["host_char_id"], match_data["client_char_id"],
						match_data["host_pet_id"], match_data["client_pet_id"])
				remove_meta("pending_match")
			else:
				# Regular player lookup
				current_player_id = first_item["player_id"]
				emit_signal("player_created", current_player_id)
		
		# Match data
		elif first_item.has("match_id"):
			current_match_id = first_item["match_id"]
			emit_signal("match_started", current_match_id)
		
		# Stats or leaderboard data
		elif first_item.has("total_wins"):
			print("📊 Stats loaded: ", data)
	
	# Handle single record creation (like new player)
	elif data is Dictionary and data.has("player_id"):
		current_player_id = data["player_id"]
		emit_signal("player_created", current_player_id)
	elif data is Dictionary and data.has("match_id"):
		current_match_id = data["match_id"]
		emit_signal("match_started", current_match_id)

# ========================================
# CONVENIENCE FUNCTIONS FOR GAME SCENES
# ========================================

func initialize_player(player_name: String):
	"""Call this when the game starts to set up the player"""
	create_or_get_player(player_name)

func start_new_match(host_name: String, client_name: String):
	"""Call this when match begins - gets data from Global"""
	var host_char = Global.selected_character
	var client_char = "Fighter" # You'll need to get this from the other player
	var host_pet = Global.selected_pet  
	var client_pet = "Mew" # You'll need to get this from the other player
	
	start_match(host_name, client_name, host_char, client_char, host_pet, client_pet)

func finish_current_match(winner_name: String, duration: int = 0):
	"""Call this when match ends"""
	complete_match(winner_name, duration)
	emit_signal("match_completed", winner_name)
