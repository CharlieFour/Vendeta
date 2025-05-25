extends Control

var peer = ENetMultiplayerPeer.new()
var is_host := false

func _on_host_pressed() -> void:
	Global.is_host = true
	peer.create_server(135)
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_join_pressed() -> void:
	Global.is_host = false
	peer.create_client("localhost", 135)
	multiplayer.multiplayer_peer = peer
	get_tree().change_scene_to_file("res://scenes/game.tscn")


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
