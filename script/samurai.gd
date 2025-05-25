extends CharacterBody2D

# Nodes
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = $HitBox
@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer

# Movement
const SPEED := 300.0
const RUN_SPEED := 600.0
const JUMP_VELOCITY := -500.0
const GRAVITY := 1200.0

# Health
var health := 100
var is_dead := false
var is_attacking := false
var is_hurt := false
var attack_timer := 0.0
const ATTACK_TIMEOUT := 1.0

# For network sync interpolation
var target_position: Vector2
var target_anim: String = "idle"
var target_flip_h: bool = false

# UI references (setup once in _ready)
@onready var health_bar: ProgressBar
var name_label: Label

var can_control := false
var player_name := ""
var is_host_player := false

@rpc("any_peer")
func start_player_control():
	can_control = true

func _ready():
	print("Spawned Fighter. My ID:", multiplayer.get_unique_id(), " Authority:", get_multiplayer_authority())

	await get_tree().create_timer(0.1).timeout

	var root = get_tree().root.get_node("Game")
	var ui = root.get_node("UI")

	# UI assignment based on whether this player is the host or client
	# Host player always uses Player1 UI, Client player always uses Player2 UI
	if is_host_player:
		health_bar = ui.get_node("Player1HealthBar")
		name_label = ui.get_node("Player1Label")
	else:
		health_bar = ui.get_node("Player2HealthBar")
		name_label = ui.get_node("Player2Label")

	health_bar.value = health
	
	# Set label text based on who is viewing
	if is_multiplayer_authority():
		name_label.text = "%s (You)" % player_name
	else:
		name_label.text = "%s (Enemy)" % player_name

	sync.set_process(!is_multiplayer_authority())
	sync.public_visibility = true

	if not is_multiplayer_authority():
		target_position = global_position

	if not sprite.animation_finished.is_connected(_on_animated_sprite_2d_animation_finished):
		sprite.animation_finished.connect(_on_animated_sprite_2d_animation_finished)

func _physics_process(delta):
	if is_multiplayer_authority():
		_process_local_player(delta)
		rpc("sync_state", global_position, sprite.animation, sprite.flip_h)
	else:
		global_position = global_position.lerp(target_position, 10 * delta)
		if sprite.animation != target_anim:
			sprite.play(target_anim)
		sprite.flip_h = target_flip_h

func _process_local_player(delta):
	if not can_control:
		return
		
	if is_dead:
		velocity.x = 0
		if sprite.animation != "dead":
			sprite.play("dead")
		return

	if is_attacking:
		velocity.x = 0
		return

	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		sprite.play("jump")

	var direction := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var is_moving := direction != 0
	var is_running := is_moving and Input.is_action_pressed("run")
	var current_speed := RUN_SPEED if is_running else SPEED

	velocity.x = direction * current_speed if not is_attacking else 0
	if direction != 0:
		sprite.flip_h = direction < 0

	if Input.is_action_pressed("shield") and is_on_floor() and not is_attacking:
		velocity.x = 0
		sprite.play("shield")
	elif Input.is_action_just_pressed("attack1") and not is_attacking:
		start_attack("attack1")
	elif Input.is_action_just_pressed("attack2") and not is_attacking:
		start_attack("attack2")
	elif Input.is_action_just_pressed("attack3") and not is_attacking:
		start_attack("attack3")
	elif not is_attacking:
		if not is_on_floor():
			sprite.play("jump")
		elif is_moving:
			sprite.play("sprint" if is_running else "walk")
		else:
			sprite.play("idle")

	move_and_slide()

func _process(delta):
	if is_attacking:
		attack_timer += delta
		if attack_timer > ATTACK_TIMEOUT:
			is_attacking = false
			hitbox_area.monitoring = false
			sprite.play("idle")
			attack_timer = 0.0

@rpc
func sync_state(pos: Vector2, anim: String, flip: bool):
	if is_multiplayer_authority(): return
	target_position = pos
	target_anim = anim
	target_flip_h = flip

func start_attack(anim_name: String):
	is_attacking = true
	attack_timer = 0.0
	if is_on_floor():
		velocity.x = 0
	sprite.play(anim_name)
	hitbox_area.monitoring = true

@rpc("any_peer")
func remote_take_damage(amount: int, from_left: bool):
	take_damage(amount)
	apply_knockback(Vector2(200 * (1 if from_left else -1), -100))

@rpc("any_peer", "reliable")
func broadcast_defeat(defeated_peer_id: int):
	if defeated_peer_id != multiplayer.get_unique_id():
		await get_tree().create_timer(1.5).timeout
		show_win_screen()

func show_win_screen():
	print("You win!")
	get_tree().change_scene_to_file("res://scenes/win_screen.tscn")

func show_loss_screen():
	print("You lose.")
	get_tree().change_scene_to_file("res://scenes/loss_screen.tscn")

func take_damage(amount: int) -> void:
	if is_dead:
		return

	var damage := amount
	if Input.is_action_pressed("shield"):
		damage *= 0.3

	health -= damage

	# Sync to both peers
	sync_health.rpc(health)
	sync_health(health) # ← LOCAL call too

	if health <= 0:
		is_dead = true
		sprite.play("dead")
		
		# Tell ALL players who died (by their peer ID)
		rpc("broadcast_defeat", multiplayer.get_unique_id())

		# Show loss screen locally
		await get_tree().create_timer(1.5).timeout
		show_loss_screen()
	else:
		is_hurt = true
		sprite.play("hurt")

@rpc("any_peer")
func sync_health(hp: int) -> void:
	health = hp
	update_health_ui()

func update_health_ui() -> void:
	var ui = get_tree().root.get_node("Game/UI")

	# Update UI based on host/client status, not authority
	if is_host_player:
		ui.get_node("Player1HealthBar").value = health
		if is_multiplayer_authority():
			ui.get_node("Player1Label").text = "You: %d HP" % health
		else:
			ui.get_node("Player1Label").text = "Enemy: %d HP" % health
	else:
		ui.get_node("Player2HealthBar").value = health
		if is_multiplayer_authority():
			ui.get_node("Player2Label").text = "You: %d HP" % health
		else:
			ui.get_node("Player2Label").text = "Enemy: %d HP" % health

func apply_knockback(force: Vector2):
	velocity += force

func _on_hit_box_body_entered(body: Node2D):
	if body == self or not is_attacking: return
	if body.has_method("remote_take_damage"):
		var from_left = global_position.x < body.global_position.x
		body.rpc_id(body.get_multiplayer_authority(), "remote_take_damage", 10, from_left)

func _on_animated_sprite_2d_animation_finished() -> void:
	if sprite.animation in ["attack1", "attack2", "attack3"]:
		is_attacking = false
		hitbox_area.monitoring = false
		sprite.play("idle")
	elif sprite.animation == "hurt":
		is_hurt = false
		if not is_dead:
			sprite.play("idle")
	elif sprite.animation == "dead":
		# Stay dead
		pass

func set_player_info(name: String, is_host: bool):
	player_name = name
	is_host_player = is_host

# Keep for backwards compatibility
func set_player_name(name: String):
	player_name = name
