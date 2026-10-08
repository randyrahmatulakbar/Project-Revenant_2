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

const INTERACTION_DISTANCE = 3.0

# Prompt interaksi di HUD (diisi otomatis, lihat _get_interaction_prompt)
var interaction_prompt: Control = null


# HUD
var hud: CanvasLayer = null


# Ammo
@export var max_ammo_per_clip: int = 6
@export var starting_reserve_ammo: int = 24
var current_ammo: int = 0
var reserve_ammo: int = 0


# Bullet hole (isi 3 texture di Inspector; tiap tembakan memilih salah satu secara acak)
@export var bullet_hole_textures: Array[Texture2D] = []
const MAX_DECALS = 50
const DECAL_LIFETIME = 8.0
const DECAL_FADE_TIME = 1.5
var decals: Array = []


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	camera_start_position = camera.position
	head_start_position = head.position

	$Health.health_changed.connect(_on_health_changed)
	$Health.died.connect(_on_died)

	current_ammo = max_ammo_per_clip
	reserve_ammo = starting_reserve_ammo

	var huds = get_tree().get_nodes_in_group("hud")

	if huds.size() > 0:
		hud = huds[0]
		_update_ammo_ui()

	print("HUD found: ", hud)


func _on_health_changed(current: float, max: float) -> void:
	print("HP: ", current, "/", max)

	if hud:
		hud.update_health(int(current), int(max))


func _on_died() -> void:
	print("Player mati!")
	get_tree().reload_current_scene()


func _unhandled_input(event):
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

		if is_sliding:
			is_sliding = false


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


	# =========================
	# WEAPON ANIMATION
	# =========================

	var is_moving = direction.length() > 0.1 and is_on_floor()
	var is_sprinting = (
		Input.is_action_pressed("sprint")
		and is_moving
		and not is_crouching
	)

	if hud:
		hud.update_weapon_animation(is_moving, is_sprinting)


	# =========================
	# SHOOT
	# =========================

	if Input.is_action_just_pressed("shoot"):
		shoot()


	# =========================
	# RELOAD
	# =========================

	if InputMap.has_action("reload") and Input.is_action_just_pressed("reload"):
		reload()


	# Head bobbing
	head_bobbing(delta)

	check_interaction()

	move_and_slide()


func shoot():
	if hud and hud.is_busy:
		return

	if current_ammo <= 0:
		print("Peluru habis!")

		if hud:
			hud.play_shoot()

		return

	current_ammo -= 1

	_update_ammo_ui()

	if hud:
		hud.play_shoot()


	var space_state = get_world_3d().direct_space_state

	var from = camera.global_position
	var to = from + -camera.global_transform.basis.z * 100.0

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	if result:
		print("Kena: ", result.collider.name)

		if result.collider.has_method("take_damage"):
			result.collider.take_damage(1)

			spawn_impact_particles(
				result.position,
				result.normal,
				Color(0.8, 0.05, 0.05)
			)

		else:
			spawn_bullet_hole(
				result.position,
				result.normal
			)

			spawn_impact_particles(
				result.position,
				result.normal
			)

	else:
		print("Tembakan tidak kena apa-apa")


func reload():
	if reserve_ammo <= 0 or current_ammo >= max_ammo_per_clip:
		return

	if hud and hud.is_busy:
		return

	if hud:
		hud.play_reload()   # HUD yang memanggil load_bullets() / quick_reload() sesuai animasinya
	else:
		quick_reload()


# Reload tahan: tambah peluru satu per satu (dipanggil HUD tiap peluru masuk).
func load_bullets(n: int) -> int:
	var take = mini(n, mini(max_ammo_per_clip - current_ammo, reserve_ammo))
	if take <= 0:
		return 0

	current_ammo += take
	reserve_ammo -= take
	_update_ammo_ui()
	return take


# Reload cepat (tap R): buang semua peluru di silinder, ambil magazine penuh dari cadangan.
func quick_reload() -> int:
	var take = mini(max_ammo_per_clip, reserve_ammo)
	if take <= 0:
		return 0

	current_ammo = take          # peluru lama hilang (sengaja merugikan pemain)
	reserve_ammo -= take
	_update_ammo_ui()
	return take


func _update_ammo_ui() -> void:
	if hud:
		hud.update_ammo(current_ammo, reserve_ammo)


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

	var horizontal_velocity = Vector3(
		velocity.x,
		0,
		velocity.z
	)

	if horizontal_velocity.length() > 0.01:
		slide_direction = horizontal_velocity.normalized()
	else:
		slide_direction = -head.global_transform.basis.z


func end_slide():
	is_sliding = false
	is_crouching = false

	velocity.y = SLIDE_JUMP


func check_interaction():
	var prompt := _get_interaction_prompt()

	var space_state = get_world_3d().direct_space_state

	var from = camera.global_position
	var to = from + -camera.global_transform.basis.z * INTERACTION_DISTANCE

	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [self]

	var result = space_state.intersect_ray(query)

	var can_interact := false

	if result:
		var object = result.collider

		if object.has_method("interact"):
			can_interact = true

			if Input.is_action_just_pressed("interact"):
				object.interact()

	# tampilkan / sembunyikan prompt HUD (aman dipanggil tiap frame)
	if prompt:
		prompt.set_active(can_interact)


# Cari prompt interaksi (Control dengan fungsi set_active). Dicari sekali, lalu disimpan.
func _get_interaction_prompt() -> Control:
	if is_instance_valid(interaction_prompt):
		return interaction_prompt

	var node = get_tree().get_first_node_in_group("interaction_prompt")
	if node == null:
		node = get_node_or_null("../CanvasLayer/interek")   # path lama sebagai cadangan

	if node and node.has_method("set_active"):
		interaction_prompt = node

	return interaction_prompt


func spawn_bullet_hole(pos: Vector3, normal: Vector3) -> void:
	var decal = Decal.new()

	# ukuran sedikit acak supaya tiap lubang tidak terlihat sama persis
	var hole_size := randf_range(0.2, 0.3)

	decal.size = Vector3(
		hole_size,
		0.25,
		hole_size
	)

	if bullet_hole_textures.size() > 0:
		decal.texture_albedo = bullet_hole_textures.pick_random()

	else:
		var grad = Gradient.new()

		grad.colors = PackedColorArray([
			Color(0, 0, 0, 0.9),
			Color(0, 0, 0, 0.9),
			Color(0, 0, 0, 0)
		])

		grad.offsets = PackedFloat32Array([
			0.0,
			0.5,
			1.0
		])

		var tex = GradientTexture2D.new()

		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64

		decal.texture_albedo = tex


	get_tree().current_scene.add_child(decal)

	decal.global_position = pos


	var up = Vector3.UP if abs(normal.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT

	var x_axis = normal.cross(up).normalized()
	var z_axis = x_axis.cross(normal).normalized()

	decal.global_transform.basis = Basis(
		x_axis,
		normal,
		z_axis
	)

	decal.rotate_object_local(
		Vector3.UP,
		randf() * TAU
	)


	decals.append(decal)

	decal.tree_exiting.connect(
		func():
			decals.erase(decal)
	)

	if decals.size() > MAX_DECALS:
		var old = decals[0]

		if is_instance_valid(old):
			old.queue_free()


	var tween = decal.create_tween()

	tween.tween_interval(DECAL_LIFETIME)

	tween.tween_property(
		decal,
		"modulate:a",
		0.0,
		DECAL_FADE_TIME
	)

	tween.tween_callback(decal.queue_free)


func spawn_impact_particles(
	pos: Vector3,
	normal: Vector3,
	color: Color = Color(1.0, 0.8, 0.4)
) -> void:

	var p = CPUParticles3D.new()


	var mesh = SphereMesh.new()

	mesh.radius = 0.03
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3


	var mat = StandardMaterial3D.new()

	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color

	mesh.material = mat

	p.mesh = mesh


	p.one_shot = true
	p.emitting = false
	p.local_coords = true
	p.amount = 12
	p.lifetime = 0.7
	p.explosiveness = 1.0
	p.direction = normal
	p.spread = 40.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)


	get_tree().current_scene.add_child(p)

	p.global_position = pos + normal * 0.02


	await get_tree().process_frame

	if not is_instance_valid(p):
		return

	p.emitting = true


	var tween = p.create_tween()

	tween.tween_interval(0.3)

	tween.tween_property(
		mat,
		"albedo_color:a",
		0.0,
		0.4
	)

	tween.tween_callback(p.queue_free)
