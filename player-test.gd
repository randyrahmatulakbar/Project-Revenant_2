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


# Damage tembakan revolver (tinju = 5, lihat parry.gd). Semua musuh kena damage yang sama; bedanya cuma di HP musuh.
@export var gun_damage: float = 11.0


# Kamera miring (roll) saat jalan ke samping / belok. Semua bisa diatur di Inspector.
@export_group("Kamera Miring")
@export var tilt_enabled: bool = true
@export var strafe_tilt_deg: float = 2.6      # miring saat jalan ke samping (derajat, max)
@export var turn_tilt_deg: float = 1.8        # miring saat mouse dibelokkan cepat
@export var tilt_speed: float = 9.0           # makin besar makin cepat nyusul / balik tegak

# Wallhop: tekan lompat di udara dekat tembok -> mental dari tembok.
@export_group("Wallhop")
@export var wall_hop_enabled: bool = true
@export var wall_hop_up: float = 5.2          # dorongan ke atas
@export var wall_hop_push: float = 6.5        # dorongan menjauhi tembok
@export var wall_hop_forward: float = 3.0     # tambahan ke arah pandangan (biar bisa lanjut lari)
@export var wall_hop_keep: float = 0.7        # sisa kecepatan yang sejajar tembok
@export var wall_hop_limit: int = 3           # maks wallhop per sekali di udara (0 = tanpa batas)
@export var wall_hop_cooldown: float = 0.18
@export var wall_reach: float = 1.2           # jarak deteksi tembok dari badan
@export var wall_hop_tilt_deg: float = 7.0    # sentakan miring kamera saat wallhop

var _roll := 0.0
var _roll_kick := 0.0
var _mouse_dx := 0.0
var _wall_hops := 0
var _wall_cd := 0.0


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

	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		_sprint_cfg = cfg.get_value("controls", "sprint_toggle", false)
		_sens_cfg = cfg.get_value("controls", "sensitivity", 1.0)
		_fov_cfg = cfg.get_value("gameplay", "fov", 75.0)
		_tilt_cfg = cfg.get_value("gameplay", "camera_tilt", true)
		_bob_cfg = cfg.get_value("gameplay", "head_bob", true)
		_bright_cfg = cfg.get_value("video", "brightness", 1.0)

	var huds = get_tree().get_nodes_in_group("hud")

	if huds.size() > 0:
		hud = huds[0]
		_update_ammo_ui()

	print("HUD found: ", hud)


func _on_health_changed(current: float, max: float) -> void:
	print("HP: ", current, "/", max)

	if hud:
		hud.update_health(int(current), int(max))


var _dead := false

# Sprint: Hold (tahan tombol) atau Toggle (tekan sekali nyala, tekan lagi mati; tetap nyala walau berhenti lalu jalan lagi). Pilihan dari settings (SettingsMenu menaruh Engine meta "sprint_toggle").
var _sprint_on := false
var _sprint_latched := false
var _sprint_cfg := false
var _sens_cfg := 1.0
var _fov_cfg := 75.0
var _tilt_cfg := true
var _bob_cfg := true
var _bright_cfg := 1.0
var _bright_applied := -1.0
var _bright_warned := false


func _meta_or(key: String, fallback: Variant) -> Variant:
	return Engine.get_meta(key) if Engine.has_meta(key) else fallback


# FOV dasar dari settings; sprint = dasar + 15 (dulu 75 -> 90)
func _base_fov() -> float:
	return float(_meta_or("fov", _fov_cfg))


func _tilt_allowed() -> bool:
	return bool(_meta_or("camera_tilt", _tilt_cfg))


func _bob_allowed() -> bool:
	return bool(_meta_or("head_bob", _bob_cfg))


# Kecerahan: dipasang ke WorldEnvironment (adjustment_brightness). Dicek tiap frame, hanya bekerja kalau nilainya berubah.
func _apply_brightness() -> void:
	var b := float(_meta_or("brightness", _bright_cfg))
	if is_equal_approx(b, _bright_applied):
		return
	var scene := get_tree().current_scene
	var we: WorldEnvironment = null
	if scene:
		we = scene.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if we == null or we.environment == null:
		if not _bright_warned:
			_bright_warned = true
			push_warning("Player: WorldEnvironment tidak ketemu, pengaturan Brightness tidak berpengaruh")
		return
	we.environment.adjustment_enabled = not is_equal_approx(b, 1.0)
	we.environment.adjustment_brightness = b
	_bright_applied = b


# Pengali sensitivitas mouse dari settings (Engine meta diisi SettingsMenu; cadangan: baca dari file)
func _sens_mult() -> float:
	if Engine.has_meta("mouse_sensitivity"):
		return float(Engine.get_meta("mouse_sensitivity"))
	return _sens_cfg


func _sprint_toggle_mode() -> bool:
	if Engine.has_meta("sprint_toggle"):
		return Engine.get_meta("sprint_toggle")
	return _sprint_cfg                  # settings belum pernah dimuat di sesi ini: baca dari file


func _update_sprint() -> void:
	if not _sprint_toggle_mode():
		_sprint_latched = false
		_sprint_on = Input.is_action_pressed("sprint")
		return
	if Input.is_action_just_pressed("sprint"):
		_sprint_latched = not _sprint_latched
	_sprint_on = _sprint_latched


func _on_died() -> void:
	if _dead:
		return                          # sinyal bisa datang lagi (mis. racun masih menetes)
	_dead = true
	print("Player mati!")

	set_physics_process(false)
	set_process_unhandled_input(false)

	# siapa yang terakhir nyakitin (dicatat enemy_base.hurt_player / poison_glob), cuma dipakai kalau barusan
	var killer := ""
	if has_meta("last_hit_by") and Time.get_ticks_msec() - int(get_meta("last_hit_time", 0)) < 6000:
		killer = str(get_meta("last_hit_by"))

	DeathScreen.play(self, killer)      # death_screen.gd: pause game, animasi, lalu reload scene sendiri


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		head.rotate_y(-event.relative.x * SENSITIVITY * _sens_mult())
		_mouse_dx += event.relative.x
		camera.rotate_x(-event.relative.y * SENSITIVITY * _sens_mult())

		camera.rotation.x = clamp(
			camera.rotation.x,
			deg_to_rad(-80),
			deg_to_rad(60)
		)


func _physics_process(delta: float) -> void:

	if is_on_floor():
		_wall_hops = 0
	_wall_cd = maxf(0.0, _wall_cd - delta)
	_update_sprint()

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

		if is_sliding:
			is_sliding = false


	# Jump
	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif wall_hop_enabled:
			_try_wall_hop()


	# Crouch / Slide
	if Input.is_action_just_pressed("crouch"):
		if _sprint_on and is_on_floor() and velocity.length() > 0.1:
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
		Basis(Vector3.UP, head.rotation.y) *       # yaw saja: roll kamera gak boleh ikut ngubah arah jalan
		Vector3(input_dir.x, 0, input_dir.y)
	).normalized()


	# Speed
	var current_speed = SPEED

	if is_sliding:
		current_speed = 0.0
	elif is_crouching:
		current_speed = CROUCH_SPEED
	elif _sprint_on:
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
		_sprint_on
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


func _process(delta: float) -> void:
	_apply_brightness()
	_update_camera_tilt(delta)


# Kamera miring ke arah gerak: jalan ke samping & belok. Dipasang di head (roll), bukan camera,
# supaya gak tabrakan dengan sentakan kamera parry (parry.gd mainin camera.rotation.z).
func _update_camera_tilt(delta: float) -> void:
	var target := _roll_kick if _tilt_allowed() else 0.0
	if tilt_enabled and _tilt_allowed():
		var local_v := Basis(Vector3.UP, head.rotation.y).inverse() * velocity
		var strafe := clampf(local_v.x / SPRINT_SPEED, -1.0, 1.0)
		var turn := clampf(_mouse_dx / 40.0, -1.0, 1.0)
		target += deg_to_rad(-strafe * strafe_tilt_deg - turn * turn_tilt_deg)
	_mouse_dx = 0.0
	_roll = lerpf(_roll, target, 1.0 - exp(-tilt_speed * delta))
	head.rotation.z = _roll
	_roll_kick = lerpf(_roll_kick, 0.0, 1.0 - exp(-6.0 * delta))


# Cari tembok terdekat di sekeliling badan (8 arah). Kosong = gak ada.
func _find_wall() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0.0, 0.9, 0.0)
	var best := {}
	var best_d := INF
	for i in 8:
		var dir := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * wall_reach)
		q.exclude = [get_rid()]
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var col = r.collider
		if col is Node and (col.is_in_group("enemy") or col.has_method("take_damage")):
			continue                                   # musuh bukan tembok
		if absf(r.normal.y) > 0.3:
			continue                                   # lantai / plafon bukan tembok
		var d := origin.distance_to(r.position)
		if d < best_d:
			best_d = d
			best = r
	return best


func _try_wall_hop() -> bool:
	if _wall_cd > 0.0:
		return false
	if wall_hop_limit > 0 and _wall_hops >= wall_hop_limit:
		return false
	var hit := _find_wall()
	if hit.is_empty():
		return false

	var n: Vector3 = hit.normal
	n.y = 0.0
	n = n.normalized()
	var yaw := Basis(Vector3.UP, head.rotation.y)
	var look: Vector3 = -yaw.z
	look.y = 0.0
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var parallel := hv - n * hv.dot(n)                          # kecepatan sejajar tembok tetap sebagian
	var look_off := look - n * minf(look.dot(n), 0.0)           # arah pandang tanpa komponen yang masuk ke tembok
	var h := parallel * wall_hop_keep + n * wall_hop_push + look_off.normalized() * wall_hop_forward
	velocity.x = h.x
	velocity.z = h.z
	velocity.y = wall_hop_up

	_wall_hops += 1
	get_tree().call_group("style", "register", "wallhop")
	_wall_cd = wall_hop_cooldown
	is_sliding = false

	# efek: kamera tersentak miring menjauhi tembok, FOV nyentak, debu, suara
	var side := signf(n.dot(yaw.x))
	if _tilt_allowed():
		_roll_kick = -side * deg_to_rad(wall_hop_tilt_deg)
	camera.fov -= 5.0
	spawn_impact_particles(hit.position, hit.normal, Color(0.75, 0.7, 0.62))
	get_tree().call_group("sfx", "play", "land_soft", -3.0, 0.06)
	get_tree().call_group("sfx", "play", "punch_whoosh", -8.0, 0.08)
	return true


# ---------------------------------------------------------------
#  BULLET TRAIL: garis peluru melesat dari moncong ke titik kena
# ---------------------------------------------------------------
@export_group("Bullet Trail")
@export var tracer_enabled := true
@export var tracer_color := Color(1.0, 0.72, 0.32)
@export var tracer_speed := 240.0                # m/detik (makin besar makin 'instan')
@export var tracer_length := 4.5                 # panjang ekor garis
@export var tracer_width := 0.014
@export var muzzle_offset := Vector3(0.2, -0.17, -0.6)   # titik moncong relatif kamera (kanan-bawah-depan)

var _tracer_mat_core: StandardMaterial3D
var _tracer_mat_glow: StandardMaterial3D


func _tracer_materials() -> void:
	if _tracer_mat_core:
		return
	for k in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(1.0, 0.96, 0.85, 1.0) if k == 0 else Color(tracer_color, 0.32)
		if k == 0:
			_tracer_mat_core = m
		else:
			_tracer_mat_glow = m


func _spawn_tracer(end: Vector3) -> void:
	if not tracer_enabled:
		return
	_tracer_materials()
	var start: Vector3 = camera.global_transform * muzzle_offset
	var dist := start.distance_to(end)
	if dist < 0.6:
		return
	var dir := (end - start) / dist
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var basis0 := Basis.looking_at(dir, up)

	var root := Node3D.new()
	for k in 2:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var w := tracer_width * (1.0 if k == 0 else 4.0)
		bm.size = Vector3(w, w, 1.0)
		mi.mesh = bm
		mi.material_override = _tracer_mat_core if k == 0 else _tracer_mat_glow
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var scene := get_tree().current_scene
	if scene == null:
		return
	scene.add_child(root)
	root.visible = false

	var total := (dist + tracer_length) / tracer_speed
	var tw := root.create_tween()
	tw.tween_method(_tracer_step.bind(root, start, dir, basis0, dist), 0.0, 1.0, maxf(total, 0.04))
	tw.tween_callback(root.queue_free)


func _tracer_step(k: float, root: Node3D, start: Vector3, dir: Vector3, b: Basis, dist: float) -> void:
	var p := k * (dist + tracer_length)
	var head := minf(p, dist)
	var tail := clampf(p - tracer_length, 0.0, dist)
	var seg := head - tail
	if seg < 0.01:
		root.visible = false
		return
	root.visible = true
	root.global_transform = Transform3D(b * Basis.from_scale(Vector3(1.0, 1.0, seg)), start + dir * (tail + seg * 0.5))


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

	_spawn_tracer(result.position if result else to)

	if result:
		print("Kena: ", result.collider.name)

		if result.collider.has_method("take_damage"):
			result.collider.take_damage(gun_damage)

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
	var is_sprinting = _sprint_on and not is_crouching and Vector2(velocity.x, velocity.z).length() > 1.0   # FOV lebar hanya saat benar-benar bergerak
	var is_moving = velocity.length() > 0.1 and is_on_floor()

	# FOV
	var base_fov := _base_fov()
	var target_fov = (base_fov + (SPRINT_FOV - NORMAL_FOV)) if is_sprinting else base_fov

	camera.fov = lerp(
		camera.fov,
		target_fov,
		delta * FOV_SPEED
	)


	# Bobbing
	if is_moving and _bob_allowed():
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


# --- collider ikut mengecil saat nunduk/slide (supaya muat di bawah duct) ---
const CROUCH_COLLIDER_H := 0.75     # tinggi badan saat jongkok (lebih kecil = lebih pendek)
const SLIDE_COLLIDER_H := 0.5       # tinggi badan saat slide
const SLIDE_HEAD_DROP := 0.95       # kamera turun segini saat slide (jongkok biasa pakai CROUCH_HEIGHT)
var _col: CollisionShape3D
var _col_h_stand := 0.0
var _col_r_stand := 0.0
var _col_y_stand := 0.0
var _col_ready := false

func _setup_collider() -> void:
	_col_ready = true
	for c in find_children("*", "CollisionShape3D", true, false):
		var sh = (c as CollisionShape3D).shape
		if sh is CapsuleShape3D or sh is BoxShape3D or sh is CylinderShape3D:
			_col = c
			break
	if _col == null:
		push_warning("Player: CollisionShape3D (capsule/box/cylinder) tidak ketemu, collider tidak mengecil saat nunduk")
		return
	_col.shape = _col.shape.duplicate()
	_col_h_stand = _shape_h(_col.shape)
	_col_r_stand = _shape_r(_col.shape)
	_col_y_stand = _col.position.y
	print("Player collider: ", _col.name, " ", _col.shape.get_class(), " h=", _col_h_stand, " y=", _col_y_stand)


func _shape_r(sh: Shape3D) -> float:
	if sh is CapsuleShape3D:
		return (sh as CapsuleShape3D).radius
	if sh is CylinderShape3D:
		return (sh as CylinderShape3D).radius
	return 0.0


func _set_shape_r(sh: Shape3D, r: float) -> void:
	if sh is CapsuleShape3D:
		(sh as CapsuleShape3D).radius = r
	elif sh is CylinderShape3D:
		(sh as CylinderShape3D).radius = r


func _shape_h(sh: Shape3D) -> float:
	if sh is CapsuleShape3D:
		return (sh as CapsuleShape3D).height
	if sh is CylinderShape3D:
		return (sh as CylinderShape3D).height
	return (sh as BoxShape3D).size.y


func _set_shape_h(sh: Shape3D, h: float) -> void:
	if sh is CapsuleShape3D:
		(sh as CapsuleShape3D).height = h
	elif sh is CylinderShape3D:
		(sh as CylinderShape3D).height = h
	else:
		(sh as BoxShape3D).size.y = h


func _update_collider() -> void:
	if not _col_ready:
		_setup_collider()
	if _col == null:
		return
	var h := _col_h_stand
	if is_sliding:
		h = SLIDE_COLLIDER_H
	elif is_crouching:
		h = CROUCH_COLLIDER_H
	# kapsul tidak boleh lebih pendek dari 2x jari-jarinya, jadi jari-jari ikut mengecil kalau perlu.
	# Jari-jari dikembalikan saat berdiri (kalau tidak, badan jadi kurus selamanya).
	if _col_r_stand > 0.0:
		_set_shape_r(_col.shape, minf(_col_r_stand, h * 0.5))
	_set_shape_h(_col.shape, h)
	# telapak kaki tetap di tempat: geser tengah collider turun separuh selisihnya
	_col.position.y = _col_y_stand - (_col_h_stand - h) * 0.5


func handle_crouch(delta):
	_update_collider()
	var target_y = head_start_position.y

	if is_sliding:
		target_y -= SLIDE_HEAD_DROP
	elif is_crouching:
		target_y -= CROUCH_HEIGHT

	head.position.y = lerp(
		head.position.y,
		target_y,
		delta * 10.0
	)


func start_slide():
	is_sliding = true
	get_tree().call_group("style", "register", "slide")
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
	var prompt_text := ""

	if result:
		var object = result.collider

		if object.has_method("interact"):
			can_interact = true

			# teks khusus objek (opsional); kosong = teks default prompt
			var t = object.get("interact_text")
			if t is String:
				prompt_text = t

			if Input.is_action_just_pressed("interact"):
				object.interact()

	# tampilkan / sembunyikan prompt HUD (aman dipanggil tiap frame)
	if prompt:
		prompt.set_active(can_interact, prompt_text)


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
