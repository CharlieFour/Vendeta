extends Node

@onready var fighter_scene = preload("res://scenes/fighter.tscn")

@onready var match_start_ui = preload("res://scenes/match_start.tscn").instantiate()
@onready var ui_layer := get_parent().get_node("UI")

var players_ready := 0
var spawned_players := {}

func _ready():
	# Instance match start UI and add it to scene
	ui_layer.add_child(match_start_ui)

	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if Global.is_host:
		match_start_ui.get_node("Waiting").show()
	else:
		match_start_ui.get_node("Waiting").hide()

	spawn_player(multiplayer.get_unique_id())

func spawn_player(peer_id: int) -> void:
	await get_tree().create_timer(0.1).timeout
	if spawned_players.has(peer_id): return

	var fighter = fighter_scene.instantiate()
	add_child(fighter)
	fighter.set_multiplayer_authority(peer_id)
	fighter.name = "Fighter_%s" % str(peer_id)
	spawned_players[peer_id] = fighter

	# Set spawn positions and orientation
	if peer_id == 1:
		fighter.global_position = Vector2(-250, 0)
		fighter.get_node("AnimatedSprite2D").flip_h = false
	else:
		fighter.global_position = Vector2(650, 0)
		fighter.get_node("AnimatedSprite2D").flip_h = true

	players_ready += 1
	if players_ready == 2:
		start_match_sequence()

func _on_peer_connected(peer_id: int) -> void:
	print("Peer connected:", peer_id)
	if not spawned_players.has(peer_id):
		spawn_player(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer disconnected:", peer_id)
	if spawned_players.has(peer_id):
		spawned_players[peer_id].queue_free()
		spawned_players.erase(peer_id)
		players_ready = max(0, players_ready - 1)

# Start the match after countdown
func start_match_sequence():
	match_start_ui.get_node("Waiting").hide()

	var anim = match_start_ui.get_node("AnimationPlayer")
	anim.play("match_start")
	await anim.animation_finished

	# Enable control
	for fighter in spawned_players.values():
		fighter.rpc("start_player_control")

	# Optionally remove UI
	match_start_ui.queue_free()


# Countdown before enabling player control
func countdown() -> void:
	var countdown_label = match_start_ui.get_node("Countdown")
	countdown_label.show()
	for step in [3, 2, 1, "Fight!"]:
		countdown_label.text = str(step)
		await get_tree().create_timer(1).timeout
	countdown_label.text = ""
	countdown_label.hide()
