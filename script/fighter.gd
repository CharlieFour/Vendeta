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

# State
var is_attacking := false
var is_hurt := false
var is_dead := false
var health := 100
var attack_timer := 0.0
const ATTACK_TIMEOUT := 1.0

# For sync interpolation
var target_position: Vector2
var target_anim: String = "idle"
var target_flip_h: bool = false

func _ready():
	print("Spawned Fighter. My ID:", multiplayer.get_unique_id(), " Authority:", get_multiplayer_authority())
	await get_tree().create_timer(0.1).timeout
	# Only allow non-authority instances to receive replication
	sync.set_process(!is_multiplayer_authority())
	sync.public_visibility = true
	# Initialize target position for non-authoritative player
	if not is_multiplayer_authority():
		target_position = global_position

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_process_local_player(delta)
		# Sync position, animation, and flip_h for remote players
		rpc("sync_state", global_position, sprite.animation, sprite.flip_h)
	else:
		# Remote player: interpolate to sync position smoothly
		global_position = global_position.lerp(target_position, 10 * delta)
		if sprite.animation != target_anim:
			sprite.play(target_anim)
		sprite.flip_h = target_flip_h

func _process_local_player(delta: float) -> void:
	if is_dead:
		velocity.x = 0
		sprite.play("dead")
		return

	if is_hurt:
		velocity.x = 0
		sprite.play("hurt")
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

	if not is_attacking or not is_on_floor():
		velocity.x = direction * current_speed
	else:
		velocity.x = 0

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
			if velocity.y < 0:
				sprite.play("jump")
		elif is_moving:
			sprite.play("sprint" if is_running else "walk")
		else:
			sprite.play("idle")

	move_and_slide()

# Corrected sync_state without "unreliable" annotation
@rpc
func sync_state(pos: Vector2, anim: String, flip: bool) -> void:
	if is_multiplayer_authority():
		return
	# Set target values for remote players to follow
	target_position = pos
	target_anim = anim
	target_flip_h = flip

func start_attack(animation_name: String) -> void:
	is_attacking = true
	attack_timer = 0.0
	if is_on_floor():
		velocity.x = 0
	sprite.play(animation_name)
	hitbox_area.monitoring = true

func take_damage(amount: int) -> void:
	if is_dead:
		return

	var damage := amount
	if Input.is_action_pressed("shield"):
		damage *= 0.3

	health -= damage

	if health <= 0:
		is_dead = true
		sprite.play("dead")
	else:
		is_hurt = true
		sprite.play("hurt")

func _on_HitboxArea_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(10)
	if body.has_method("apply_knockback"):
		var direction := 1 if not sprite.flip_h else -1
		body.apply_knockback(Vector2(200 * direction, -100))

func _on_animated_sprite_2d_animation_finished() -> void:
	if sprite.animation in ["attack1", "attack2", "attack3"]:
		is_attacking = false
		hitbox_area.monitoring = false
		sprite.play("idle")
	elif sprite.animation == "hurt":
		is_hurt = false
		sprite.play("idle")
	elif sprite.animation == "dead":
		pass

func _process(delta: float) -> void:
	if is_attacking:
		attack_timer += delta
		if attack_timer > ATTACK_TIMEOUT:
			is_attacking = false
			hitbox_area.monitoring = false
			sprite.play("idle")
			attack_timer = 0.0
