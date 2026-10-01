extends CharacterBody3D

const SPEED = 5.0
const SPRINT_SPEED = 8.0
const CROUCH_SPEED = 2.5
const JUMP_VELOCITY = 4.5
const SENSITIVITY = 0.003
const NORMAL_FOV = 75.0
const SPRINT_FOV = 90.0
const FOV_SPEED = 8.0
const SLIDE_SPEED = 12.0
const SLIDE_DURATION = 0.8
const SLIDE_DECELERATION = 15.0
const SLIDE_JUMP = 3.0
const GROUND_FRICTION = 15.0
const AIR_FRICTION = 2.0
const AIR_CONTROL = 8.0

# --- PROPERTI STATISTIK PLAYER & AMMO ---
@export var hud: CanvasLayer  # Drag node HUD di Inspector

@export_group("Player Stats")
@export var max_health: int = 100
var current_health: int = 100

@export_group("Weapon Stats")
@export var max_ammo: int = 30
@export var max_reserve_ammo: int = 90
var current_ammo: int = 30
var reserve_ammo: int = 90

# slide
var is_sliding = false
var slide_timer = 0.0
var slide_direction = Vector3.ZERO

# Crouch
const CROUCH_HEIGHT = 0.7
var is_crouching = false
var head_start_position = Vector3.ZERO

# Head bobbing
const BOB_FREQUENCY = 8.0
const BOB_AMPLITUDE = 0.07
var bob_time = 0.0
var camera_start_position = Vector3.ZERO

@onready var head = $head
@onready var camera = $head/Camera3D


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Simpan posisi awal
	camera_start_position = camera.position
	head_start_position = head.position

	# Inisialisasi statistik awal
	current_health = max_health
	current_ammo = max_ammo
	reserve_ammo = max_reserve_ammo
	
	# Update HUD di awal game
	update_hud()


func _unhandled_input(event):
	# Mouse look
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY)
		camera.rotate_x(-event.relative.y * SENSITIVITY)

		camera.rotation.x = clamp(
			camera.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(60)
		)


func _physics_process(delta: float) -> void:

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Crouch / Slide
	if Input.is_action_just_pressed("crouch"):
		if Input.is_action_pressed("sprint") and is_on_floor() and velocity.length() > 0.1:
			start_slide()
		else:
			is_crouching = true

	if Input.is_action_just_released("crouch"):
		if is_sliding:
			end_slide()
		else:
			is_crouching = false
		
	handle_crouch(delta)

	# Movement
	var input_dir := Input.get_vector(
		"left",
		"right",
		"foward",
		"back"
	)

	var direction = (
		head.transform.basis *
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()

	# Speed
	var current_speed = SPEED

	if is_sliding:
		current_speed = 0.0
	elif is_crouching:
		current_speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint"):
		current_speed = SPRINT_SPEED

	# Move
	if is_sliding:
		velocity.x = slide_direction.x * SLIDE_SPEED
		velocity.z = slide_direction.z * SLIDE_SPEED

		var slide_speed = Vector2(velocity.x, velocity.z).length()

		slide_speed = move_toward(
			slide_speed,
			0.0,
			SLIDE_DECELERATION * delta
		)

		velocity.x = slide_direction.x * slide_speed
		velocity.z = slide_direction.z * slide_speed

		slide_timer -= delta

		if slide_timer <= 0.0 or slide_speed <= 0.5:
			is_sliding = false

	elif direction:
		if is_on_floor():
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			# Kontrol saat di udara
			velocity.x = move_toward(
				velocity.x,
				direction.x * current_speed,
				AIR_CONTROL * delta
			)

			velocity.z = move_toward(
				velocity.z,
				direction.z * current_speed,
				AIR_CONTROL * delta
			)

	else:
		if is_on_floor():
			# Friction di tanah
			velocity.x = move_toward(
				velocity.x,
				0.0,
				GROUND_FRICTION * delta
			)

			velocity.z = move_toward(
				velocity.z,
				0.0,
				GROUND_FRICTION * delta
			)
		else:
			# Friction di udara
			velocity.x = move_toward(
				velocity.x,
				0.0,
				AIR_FRICTION * delta
			)

			velocity.z = move_toward(
				velocity.z,
				0.0,
				AIR_FRICTION * delta
			)

	# Shoot & Reload
	if Input.is_action_just_pressed("shoot"):
		shoot()
		
	if Input.is_action_just_pressed("reload"):
		reload()

	# Head bobbing
	head_bobbing(delta)

	move_and_slide()


# --- FUNGSI WEAPON & HEALTH ---

func shoot():
	if current_ammo <= 0:
		print("Peluru habis! Tekan R untuk reload.")
		return

	# Kurangi peluru saat menembak
	current_ammo -= 1
	update_hud()

	var space_state = get_world_3d().direct_space_state
	var from = camera.global_position
	var to = from + -camera.global_transform.basis.z * 100.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	if result:
		print("Kena: ", result.collider.name)
		# Jika musuh punya fungsi take_damage, panggil di sini
		if result.collider.has_method("take_damage"):
			result.collider.take_damage(25)
	else:
		print("Tembakan tidak kena apa-apa")


func reload():
	if current_ammo == max_ammo or reserve_ammo <= 0:
		return

	var needed_ammo = max_ammo - current_ammo
	var ammo_to_add = min(needed_ammo, reserve_ammo)

	current_ammo += ammo_to_add
	reserve_ammo -= ammo_to_add

	update_hud()
	print("Reload selesai!")


func take_damage(amount: int):
	current_health -= amount
	current_health = clamp(current_health, 0, max_health)
	update_hud()

	if current_health <= 0:
		die()


func die():
	print("Player Mati!")
	# Logika player mati (misal reload level / game over)


func update_hud():
	if hud:
		if hud.has_method("update_health"):
			hud.update_health(current_health, max_health)
		if hud.has_method("update_ammo"):
			hud.update_ammo(current_ammo, reserve_ammo)


# --- FUNGSI GERAKAN ---

func head_bobbing(delta):
	var is_sprinting = Input.is_action_pressed("sprint") and not is_crouching
	var is_moving = velocity.length() > 0.1 and is_on_floor()

	# FOV
	var target_fov = SPRINT_FOV if is_sprinting else NORMAL_FOV

	camera.fov = lerp(
		camera.fov,
		target_fov,
		delta * FOV_SPEED
	)

	# Bobbing
	if is_moving:
		var current_frequency = BOB_FREQUENCY
		var current_amplitude = BOB_AMPLITUDE

		if is_sprinting:
			current_frequency = BOB_FREQUENCY * 1.35
			current_amplitude = BOB_AMPLITUDE * 1.6

		bob_time += delta * current_frequency

		var bob_offset = Vector3(
			cos(bob_time * 0.5) * current_amplitude,
			sin(bob_time) * current_amplitude,
			0
		)

		camera.position = camera_start_position + bob_offset

	else:
		bob_time = 0.0

		camera.position = camera.position.lerp(
			camera_start_position,
			delta * 5.0
		)


func handle_crouch(delta):
	var target_y = head_start_position.y

	if is_crouching:
		target_y -= CROUCH_HEIGHT

	head.position.y = lerp(
		head.position.y,
		target_y,
		delta * 10.0
	)


func start_slide():
	is_sliding = true
	is_crouching = true
	slide_timer = SLIDE_DURATION

	slide_direction = Vector3(
		velocity.x,
		0,
		velocity.z
	).normalized()


func end_slide():
	is_sliding = false
	is_crouching = false

	# Lompat kecil setelah slide
	velocity.y = SLIDE_JUMP
