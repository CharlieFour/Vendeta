extends CharacterBody2D

@rpc("unreliable") func sync_state(position: Vector2, anim: String, flip: bool) -> void:
	if is_multiplayer_authority():
		return  # Don't overwrite local player's own state
	if not is_inside_tree():
		return  # Safety check
	global_position = position
	sprite.play(anim)
	sprite.flip_h = flip


# Movement
const SPEED := 300.0
const RUN_SPEED := 600.0
const JUMP_VELOCITY := -500.0
const GRAVITY := 1200.0

# State
var is_attacking := false
var is_hurt := false
var is_dead := false

# Health
var health := 100

# Attack
var attack_timer := 0.0
const ATTACK_TIMEOUT := 1.0


# Nodes
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hitbox_area: Area2D = $HitBox


func _ready():
	print("Spawned Fighter with authority: ", multiplayer.get_unique_id(), " | This fighter: ", get_multiplayer_authority())
	await get_tree().create_timer(0.1).timeout  # Safety wait before sending RPCs


var last_animation := ""

func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if !multiplayer.has_multiplayer_peer():
		return  # Multiplayer is not active

	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return  # Avoid rpc before connection is ready
		
	if is_dead:
		velocity.x = 0
		sprite.play("dead")
		return

	if is_hurt:
		velocity.x = 0
		sprite.play("hurt")
		return

	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		sprite.play("jump")

	# Movement
	var direction := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var is_moving := direction != 0
	var is_running := is_moving and Input.is_action_pressed("run")
	var current_speed := RUN_SPEED if is_running else SPEED

	# Allow movement even when attacking in air
	if not is_attacking or not is_on_floor():
		velocity.x = direction * current_speed
	else:
		velocity.x = 0  # Lock movement during ground attacks

	if direction != 0:
		sprite.flip_h = direction < 0

	# Shielding
	if Input.is_action_pressed("shield") and is_on_floor() and not is_attacking:
		velocity.x = 0
		sprite.play("shield")

	# Attacks
	elif Input.is_action_just_pressed("attack1") and not is_attacking:
		start_attack("attack1")
	elif Input.is_action_just_pressed("attack2") and not is_attacking:
		start_attack("attack2")
	elif Input.is_action_just_pressed("attack3") and not is_attacking:
		start_attack("attack3")

	# Movement animations
	elif not is_attacking:
		if not is_on_floor():
			if velocity.y < 0:
				sprite.play("jump")
			else:
				pass
		elif is_moving:
			sprite.play("sprint" if is_running else "walk")
		else:
			sprite.play("idle")

	move_and_slide()
	
	if last_animation != sprite.animation:
		last_animation = sprite.animation
		rpc("sync_state", global_position, sprite.animation, sprite.flip_h)


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

func _on_HitboxArea_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(10)

	if body.has_method("apply_knockback"):
		var direction := 1 if not sprite.flip_h else -1
		body.apply_knockback(Vector2(200 * direction, -100))


func _on_animated_sprite_2d_animation_finished() -> void:
	print("Finished animation:", sprite.animation)

	if sprite.animation in ["attack1", "attack2", "attack3"]:
		is_attacking = false
		hitbox_area.monitoring = false

		# Return to appropriate animation
		if not is_on_floor():
			sprite.play("idle" if velocity.y > 0 else "jump")
		else:
			sprite.play("idle")

	elif sprite.animation == "jump" and is_on_floor():
		sprite.play("idle")

	elif sprite.animation == "fall" and is_on_floor():
		sprite.play("idle")

	elif sprite.animation == "hurt":
		is_hurt = false
		sprite.play("idle")

	elif sprite.animation == "dead":
		# Optional: queue_free() or emit signal
		pass


var counter := 0


func _process(delta: float) -> void:
	if is_attacking:
		attack_timer += delta
		if attack_timer > ATTACK_TIMEOUT:
			print("Force resetting attack")
			is_attacking = false
			hitbox_area.monitoring = false
			sprite.play("idle")
			attack_timer = 0.0


func _on_hit_box_body_entered(body: Node2D) -> void:
	counter = counter + 1
	print("hit" + str(counter))
	
