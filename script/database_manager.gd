extends Node

# Supabase Configuration - REPLACE WITH YOUR ACTUAL VALUES
const SUPABASE_URL := "https://yivuctiqmyddvfjkyubq.supabase.co"
const SUPABASE_ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlpdnVjdGlxbXlkZHZmamt5dWJxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDgyMTgyODcsImV4cCI6MjA2Mzc5NDI4N30.4XqOBJ6m7A9eHIoFxlh4Zq8oHw0HkxXP65bTrMl8l_A"

# HTTP Request node
@onready var http_request: HTTPRequest

# Cache for quick access
var characters_cache := {}  # Will store: {"Fighter": 1, "Shinobi": 6}
var pets_cache := {}        # Will store: {"Mew": 1, "Squirtle": 2}
var current_player_id := -1
var current_match_id := -1

# Request tracking
enum RequestType {
	LOAD_CHARACTERS,
	LOAD_PETS,
	GET_PLAYER,
	CREATE_PLAYER,
	GET_PLAYERS_FOR_MATCH,
	CREATE_MATCH,
	COMPLETE_MATCH,
	GET_STATS,
	GET_LEADERBOARD,
	GET_RECENT_MATCHES,
	GET_WINNER_ID
}

var current_request_type: RequestType
var pending_data := {}

signal player_created(player_id: int)
signal match_started(match_id: int) 
signal match_completed(winner_name: String)
signal data_loaded()
signal error_occurred(message: String)

func _ready():
	print("🔧 Database Manager initializing...")
	
	# Create HTTPRequest node with proper configuration
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	# Configure HTTPRequest for better reliability
	http_request.timeout = 30.0
	http_request.use_threads = true  # Enable threading for better performance
	
	# Test connection first
	test_connection()

# ========================================
# CONNECTION TESTING
# ========================================

func test_connection():
	print("🔗 Testing database connection...")
	print("🔗 Supabase URL: ", SUPABASE_URL)
	print("🔗 API Key length: ", SUPABASE_ANON_KEY.length())
	
	# Load initial data
	load_characters_and_pets()

# ========================================
# INITIAL DATA LOADING
# ========================================

func load_characters_and_pets():
	print("🔄 Loading characters from database...")
	
	var headers = get_standard_headers()
	
	current_request_type = RequestType.LOAD_CHARACTERS
	var url = SUPABASE_URL + "/rest/v1/characters?select=*"
	
	print("🔄 Making request to: ", url)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	print("🔄 HTTP request result: ", get_result_name(error))
	
	if error != OK:
		print("❌ Failed to make HTTP request: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to connect to database: " + get_result_name(error))

func load_pets():
	print("🔄 Loading pets from database...")
	
	var headers = get_standard_headers()
	
	current_request_type = RequestType.LOAD_PETS
	var url = SUPABASE_URL + "/rest/v1/pets?select=*"
	
	print("🔄 Pets URL: ", url)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("❌ Failed to load pets: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to load pets: " + get_result_name(error))

# ========================================
# HELPER FUNCTIONS
# ========================================

func get_standard_headers() -> Array[String]:
	"""Get standard headers for Supabase requests"""
	return [
		"apikey: " + SUPABASE_ANON_KEY,
		"Authorization: Bearer " + SUPABASE_ANON_KEY,
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: Godot/4.0"  # Add user agent
	]

func get_result_name(result_code: int) -> String:
	match result_code:
		OK:
			return "OK"
		HTTPRequest.RESULT_SUCCESS:
			return "SUCCESS"
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "CHUNKED_BODY_SIZE_MISMATCH"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "CANT_CONNECT"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "CANT_RESOLVE (DNS Lookup Failed)"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "CONNECTION_ERROR"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS_HANDSHAKE_ERROR"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "NO_RESPONSE"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "BODY_SIZE_LIMIT_EXCEEDED"
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "BODY_DECOMPRESS_FAILED"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "REQUEST_FAILED"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "DOWNLOAD_FILE_CANT_OPEN"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "DOWNLOAD_FILE_WRITE_ERROR"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "REDIRECT_LIMIT_REACHED"
		HTTPRequest.RESULT_TIMEOUT:
			return "TIMEOUT"
		_:
			return "UNKNOWN_ERROR (" + str(result_code) + ")"

# ========================================
# PLAYER MANAGEMENT
# ========================================

func create_or_get_player(player_name: String):
	print("👤 Creating/Getting player: ", player_name)
	
	var headers = get_standard_headers()
	
	current_request_type = RequestType.GET_PLAYER
	pending_data["player_name"] = player_name
	
	var url = SUPABASE_URL + "/rest/v1/players?player_name=eq." + player_name.uri_encode() + "&select=*"
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("❌ Failed to get player: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to get player: " + get_result_name(error))

func create_new_player(player_name: String):
	print("✨ Creating new player: ", player_name)
	
	var headers = get_standard_headers()
	headers.append("Prefer: return=representation")
	
	var data = {"player_name": player_name}
	current_request_type = RequestType.CREATE_PLAYER
	
	var url = SUPABASE_URL + "/rest/v1/players"
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))
	if error != OK:
		print("❌ Failed to create player: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to create player: " + get_result_name(error))

# ========================================
# MATCH MANAGEMENT
# ========================================

func start_match(host_name: String, client_name: String, host_character: String, client_character: String, host_pet: String, client_pet: String):
	print("🎮 Starting match: ", host_name, " vs ", client_name)
	
	# Wait for data to load if not ready
	if characters_cache.is_empty() or pets_cache.is_empty():
		print("⏳ Waiting for data to load...")
		await data_loaded
	
	var host_char_id = get_character_id(host_character)
	var client_char_id = get_character_id(client_character)
	var host_pet_id = get_pet_id(host_pet)
	var client_pet_id = get_pet_id(client_pet)
	
	print("🔍 Debug - Character IDs: ", host_character, "=", host_char_id, ", ", client_character, "=", client_char_id)
	print("🔍 Debug - Pet IDs: ", host_pet, "=", host_pet_id, ", ", client_pet, "=", client_pet_id)
	
	if host_char_id == -1 or client_char_id == -1 or host_pet_id == -1 or client_pet_id == -1:
		emit_signal("error_occurred", "Invalid character or pet selection")
		return
	
	# Store match data for when we get player IDs
	pending_data["match_data"] = {
		"host_name": host_name,
		"client_name": client_name,
		"host_char_id": host_char_id,
		"client_char_id": client_char_id,
		"host_pet_id": host_pet_id,
		"client_pet_id": client_pet_id
	}
	
	get_players_for_match(host_name, client_name)

func get_players_for_match(host_name: String, client_name: String):
	var headers = get_standard_headers()
	
	current_request_type = RequestType.GET_PLAYERS_FOR_MATCH
	
	# Get both players in one request using OR condition
	var url = SUPABASE_URL + "/rest/v1/players?or=(player_name.eq." + host_name.uri_encode() + ",player_name.eq." + client_name.uri_encode() + ")&select=*"
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("❌ Failed to get players for match: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to get players for match: " + get_result_name(error))

func create_match_record(host_player_id: int, client_player_id: int, host_char_id: int, client_char_id: int, host_pet_id: int, client_pet_id: int):
	var headers = get_standard_headers()
	headers.append("Prefer: return=representation")
	
	var data = {
		"host_player_id": host_player_id,
		"client_player_id": client_player_id,
		"host_character_id": host_char_id,
		"client_character_id": client_char_id,
		"host_pet_id": host_pet_id,
		"client_pet_id": client_pet_id,
		"status": "in_progress"
	}
	
	current_request_type = RequestType.CREATE_MATCH
	
	var url = SUPABASE_URL + "/rest/v1/matches"
	var error = http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(data))
	if error != OK:
		print("❌ Failed to create match: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to create match: " + get_result_name(error))

func complete_match(winner_name: String, match_duration: int = 0):
	if current_match_id == -1:
		print("❌ No active match to complete")
		return
	
	print("🏆 Completing match - Winner: ", winner_name, " Duration: ", match_duration, "s")
	print("🏆 Current Match ID: ", current_match_id)
	
	# If no winner (abandoned match), just update status
	if winner_name == "":
		print("🏆 Match abandoned - updating status only")
		update_match_status("abandoned", 0, match_duration)
		return
	
	# For completed matches with winner, get winner ID first
	print("🏆 Getting winner player ID for: ", winner_name)
	
	var headers = get_standard_headers()
	
	pending_data["winner_name"] = winner_name
	pending_data["winner_duration"] = match_duration
	current_request_type = RequestType.GET_WINNER_ID
	
	var url = SUPABASE_URL + "/rest/v1/players?player_name=eq." + winner_name.uri_encode() + "&select=player_id"
	print("🏆 Winner lookup URL: ", url)
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	if error != OK:
		print("❌ Failed to get winner ID: ", get_result_name(error))
		print("🏆 Fallback: completing match without winner ID")
		update_match_status("completed", 0, match_duration)

func update_match_status(status: String, winner_id: int = 0, duration: int = 0):
	print("🏆 Updating match status - ID: ", current_match_id, " Status: ", status, " Winner ID: ", winner_id, " Duration: ", duration)
	
	var headers = get_standard_headers()
	
	var data = {
		"status": status,
		"match_duration": duration
	}
	
	if winner_id > 0:
		data["winner_player_id"] = winner_id
		print("🏆 Including winner_player_id: ", winner_id)
	
	current_request_type = RequestType.COMPLETE_MATCH
	
	var url = SUPABASE_URL + "/rest/v1/matches?match_id=eq." + str(current_match_id)
	print("🏆 Match update URL: ", url)
	print("🏆 Match update data: ", JSON.stringify(data))
	
	var error = http_request.request(url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(data))
	if error != OK:
		print("❌ Failed to complete match: ", get_result_name(error))
		emit_signal("error_occurred", "Failed to complete match: " + get_result_name(error))
	else:
		print("✅ Match update request sent successfully")

# ========================================
# HELPER FUNCTIONS
# ========================================

func get_character_id(character_name: String) -> int:
	if characters_cache.has(character_name):
		return characters_cache[character_name]
	print("❌ Character not found in cache: ", character_name)
	print("❌ Available characters: ", characters_cache.keys())
	return -1

func get_pet_id(pet_name: String) -> int:
	if pets_cache.has(pet_name):
		return pets_cache[pet_name]
	print("❌ Pet not found in cache: ", pet_name)
	print("❌ Available pets: ", pets_cache.keys())
	return -1

# ========================================
# HTTP RESPONSE HANDLER
# ========================================

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("=".repeat(50))
	print("📡 HTTP Response Received")
	print("📡 Result Code: ", result, " (", get_result_name(result), ")")
	print("📡 Response Code: ", response_code)
	print("📡 Request Type: ", RequestType.keys()[current_request_type])
	
	# Check for network errors first
	if result != HTTPRequest.RESULT_SUCCESS:
		print("❌ Network error: ", result, " - ", get_result_name(result))
		
		# Provide specific troubleshooting for common errors
		match result:
			HTTPRequest.RESULT_CANT_RESOLVE:
				print("🔧 DNS Resolution failed. Possible fixes:")
				print("   - Check your internet connection")
				print("   - Verify the Supabase URL is correct")
				print("   - Try using a different DNS server")
				print("   - Check if your firewall is blocking the connection")
			HTTPRequest.RESULT_CANT_CONNECT:
				print("🔧 Connection failed. Possible fixes:")
				print("   - Check your internet connection")
				print("   - Verify the Supabase URL is accessible in a browser")
				print("   - Check firewall settings")
			HTTPRequest.RESULT_TIMEOUT:
				print("🔧 Request timed out. Possible fixes:")
				print("   - Check your internet connection speed")
				print("   - Try again later")
				print("   - Increase timeout value")
		
		emit_signal("error_occurred", "Network connection failed: " + get_result_name(result))
		return
	
	# Check response code
	if response_code < 200 or response_code >= 300:
		print("❌ HTTP Error: ", response_code)
		var error_body = body.get_string_from_utf8()
		print("❌ Error body: ", error_body)
		
		# Check for specific Supabase errors
		match response_code:
			401:
				print("❌ Authentication failed - check your API key")
			404:
				print("❌ Table not found - check your table names")
			400:
				print("❌ Bad request - check your query syntax")
			403:
				print("❌ Forbidden - check your RLS policies")
			429:
				print("❌ Rate limited - too many requests")
		
		emit_signal("error_occurred", "Server error: " + str(response_code))
		return
	
	# Parse JSON response
	var json_string = body.get_string_from_utf8()
	print("📡 Raw response length: ", json_string.length())
	
	if json_string.is_empty():
		print("❌ Empty response")
		# For PATCH requests, empty response might be OK
		if current_request_type == RequestType.COMPLETE_MATCH:
			print("✅ Match update completed (empty response is OK for PATCH)")
			_handle_complete_match_response({})
			return
		emit_signal("error_occurred", "Empty response from server")
		return
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	
	if parse_result != OK:
		print("❌ JSON parse error: ", json.get_error_message())
		print("❌ Error at line: ", json.get_error_line())
		print("❌ Raw response: ", json_string)
		emit_signal("error_occurred", "Failed to parse server response")
		return
	
	var data = json.data
	print("📡 Parsed data type: ", typeof(data))
	if data is Array:
		print("📡 Array size: ", data.size())
	elif data is Dictionary:
		print("📡 Dictionary keys: ", data.keys())
	
	print("=".repeat(50))
	
	_handle_successful_response(data)

func _handle_successful_response(data):
	match current_request_type:
		RequestType.LOAD_CHARACTERS:
			_handle_characters_response(data)
		RequestType.LOAD_PETS:
			_handle_pets_response(data)
		RequestType.GET_PLAYER:
			_handle_get_player_response(data)
		RequestType.CREATE_PLAYER:
			_handle_create_player_response(data)
		RequestType.GET_PLAYERS_FOR_MATCH:
			_handle_players_for_match_response(data)
		RequestType.CREATE_MATCH:
			_handle_create_match_response(data)
		RequestType.COMPLETE_MATCH:
			_handle_complete_match_response(data)
		RequestType.GET_WINNER_ID:
			_handle_winner_lookup_response(data)
		_:
			print("❌ Unhandled request type: ", current_request_type)

func _handle_winner_lookup_response(data):
	print("🏆 Processing winner lookup response...")
	print("🏆 Winner lookup data: ", data)
	
	if not data is Array or data.size() == 0:
		print("❌ Winner not found in database")
		var duration = pending_data.get("winner_duration", 0)
		print("🏆 Completing match without winner ID")
		update_match_status("completed", 0, duration)
		return
	
	var winner_data = data[0]
	if winner_data.has("player_id"):
		var winner_id = int(winner_data["player_id"])
		var duration = pending_data.get("winner_duration", 0)
		print("✅ Found winner ID: ", winner_id, " - updating match")
		update_match_status("completed", winner_id, duration)
	else:
		print("❌ Winner data missing player_id field")
		var duration = pending_data.get("winner_duration", 0)
		update_match_status("completed", 0, duration)

func _handle_characters_response(data):
	print("🎭 Processing characters response...")
	
	if not data is Array:
		print("❌ Expected array for characters, got: ", typeof(data))
		emit_signal("error_occurred", "Invalid characters data format")
		return
	
	print("🎭 Found ", data.size(), " characters")
	
	characters_cache.clear()
	for i in range(data.size()):
		var character = data[i]
		print("🎭 Processing character ", i, ": ", character)
		
		if character.has("charac_id") and character.has("charac_name"):
			var char_id = int(character["charac_id"])
			var char_name = character["charac_name"]
			characters_cache[char_name] = char_id
			print("✅ Added character: ", char_name, " -> ", char_id)
		else:
			print("❌ Character missing required fields: ", character)
	
	print("✅ Loaded ", characters_cache.size(), " characters: ", characters_cache)
	load_pets()

func _handle_pets_response(data):
	print("🐾 Processing pets response...")
	
	if not data is Array:
		print("❌ Expected array for pets, got: ", typeof(data))
		emit_signal("error_occurred", "Invalid pets data format")
		return
	
	print("🐾 Found ", data.size(), " pets")
	
	pets_cache.clear()
	for i in range(data.size()):
		var pet = data[i]
		print("🐾 Processing pet ", i, ": ", pet)
		
		if pet.has("pet_id") and pet.has("pet_name"):
			var pet_id = int(pet["pet_id"])
			var pet_name = pet["pet_name"]
			pets_cache[pet_name] = pet_id
			print("✅ Added pet: ", pet_name, " -> ", pet_id)
		else:
			print("❌ Pet missing required fields: ", pet)
	
	print("✅ Loaded ", pets_cache.size(), " pets: ", pets_cache)
	print("🎉 All data loaded successfully!")
	emit_signal("data_loaded")

func _handle_get_player_response(data):
	print("👤 Processing get player response...")
	
	if not data is Array:
		print("❌ Expected array for player lookup, got: ", typeof(data))
		return
	
	print("👤 Player lookup result - found ", data.size(), " players")
	
	if data.size() == 0:
		# Player doesn't exist, create new one
		var player_name = pending_data.get("player_name", "")
		if player_name != "":
			print("👤 Player not found, creating new player: ", player_name)
			create_new_player(player_name)
		else:
			print("❌ No player name in pending data")
	else:
		# Player exists
		var player_data = data[0]
		print("👤 Player found: ", player_data)
		if player_data.has("player_id"):
			current_player_id = int(player_data["player_id"])
			print("✅ Player ID set to: ", current_player_id)
			emit_signal("player_created", current_player_id)
		else:
			print("❌ Player data missing player_id field")

func _handle_create_player_response(data):
	print("✨ Processing create player response...")
	
	if data is Array and data.size() > 0:
		data = data[0]  # Sometimes wrapped in array
	
	print("✨ Create player data: ", data)
	
	if data is Dictionary and data.has("player_id"):
		current_player_id = int(data["player_id"])
		print("✅ New player created with ID: ", current_player_id)
		emit_signal("player_created", current_player_id)
	else:
		print("❌ Invalid player creation response: ", data)
		emit_signal("error_occurred", "Failed to create player")

func _handle_players_for_match_response(data):
	if not data is Array or data.size() < 2:
		print("❌ Need exactly 2 players for match, got: ", data.size())
		emit_signal("error_occurred", "Players not found for match")
		return
	
	var match_data = pending_data.get("match_data", {})
	if match_data.is_empty():
		print("❌ No pending match data")
		return
	
	var host_player_id = -1
	var client_player_id = -1
	
	for player in data:
		if player["player_name"] == match_data["host_name"]:
			host_player_id = int(player["player_id"])
		elif player["player_name"] == match_data["client_name"]:
			client_player_id = int(player["player_id"])
	
	if host_player_id != -1 and client_player_id != -1:
		create_match_record(
			host_player_id, client_player_id,
			match_data["host_char_id"], match_data["client_char_id"],
			match_data["host_pet_id"], match_data["client_pet_id"]
		)
	else:
		print("❌ Could not find both players")
		emit_signal("error_occurred", "Players not found")

func _handle_create_match_response(data):
	if data is Array and data.size() > 0:
		data = data[0]
	
	if data is Dictionary and data.has("match_id"):
		current_match_id = int(data["match_id"])
		emit_signal("match_started", current_match_id)
		print("✅ Match created with ID: ", current_match_id)
	else:
		print("❌ Invalid match creation response")

func _handle_complete_match_response(data):
	print("✅ Match completed successfully in database")
	var winner_name = pending_data.get("winner_name", "")
	emit_signal("match_completed", winner_name)
	
	# Reset match state
	current_match_id = -1
	pending_data.clear()

# ========================================
# CONVENIENCE FUNCTIONS
# ========================================

func initialize_player(player_name: String):
	"""Call this when the game starts to set up the player"""
	create_or_get_player(player_name)

func get_data_status() -> Dictionary:
	"""Check if data is loaded"""
	return {
		"characters_loaded": not characters_cache.is_empty(),
		"pets_loaded": not pets_cache.is_empty(),
		"characters_count": characters_cache.size(),
		"pets_count": pets_cache.size(),
		"characters_cache": characters_cache,
		"pets_cache": pets_cache
	}

# Add manual testing functions
func manual_test_characters():
	print("🧪 Manual test - loading characters...")
	load_characters_and_pets()

func manual_test_pets():
	print("🧪 Manual test - loading pets...")
	load_pets()

# Debug function to test connection manually
func debug_test_connection():
	print("🧪 Testing basic connection...")
	var headers = get_standard_headers()
	var url = SUPABASE_URL + "/rest/v1/"  # Just test base endpoint
	
	current_request_type = RequestType.LOAD_CHARACTERS  # Dummy type
	var error = http_request.request(url, headers, HTTPClient.METHOD_GET)
	print("🧪 Test connection result: ", get_result_name(error))
