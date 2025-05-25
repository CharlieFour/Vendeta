extends Control

var peer = ENetMultiplayerPeer.new()

func _on_host_pressed() -> void:
	peer.create_server(135)  # Port to host on
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("Hosting on port 135")
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_join_pressed() -> void:
	peer.create_client("localhost", 135)  # Replace with host IP for real connection
	multiplayer.multiplayer_peer = peer
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	print("Attempting to join...")
	get_tree().change_scene_to_file("res://scenes/.tscn")

func _on_connected():
	print("Successfully connected to host.")

func _on_connection_failed():
	print("Connection failed.")

func _on_peer_connected(id):
	print("Peer connected with ID:", id)

func _on_peer_disconnected(id):
	print("Peer disconnected with ID:", id)

func _on_options_pressed() -> void:
	# This loads a local version of the game — you might want to remove this later
	get_tree().change_scene_to_file("res://scenes/option_menu.tscn")

func _on_exit_pressed() -> void:
	get_tree().quit()
