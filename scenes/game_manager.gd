extends Node

@onready var fighter_scene = preload("res://scenes/fighter.tscn")

func _ready():
	# For all peers (host and client)
	multiplayer.peer_connected.connect(spawn_player)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Spawn for self
	spawn_player(multiplayer.get_unique_id())

func spawn_player(peer_id: int) -> void:
	await get_tree().create_timer(0.1).timeout  # Delay to avoid premature sync

	var fighter = fighter_scene.instantiate()
	add_child(fighter)

	fighter.set_multiplayer_authority(peer_id)
	fighter.name = "Fighter_%s" % str(peer_id)  # Helps debug and avoids node conflicts
	fighter.global_position = Vector2(10 + 290 * (peer_id % 2), 0)



func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected:", peer_id)
	for child in get_children():
		if child.get_multiplayer_authority() == peer_id:
			child.queue_free()
