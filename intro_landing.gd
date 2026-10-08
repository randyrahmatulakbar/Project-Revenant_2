extends Node
## Intro landing:
## 1. Player jatuh, semua kontrol mati (cuma jatuh).
## 2. Pas kena lantai: screen shake + debu + puing jatuh (gempa).
## 3. HUD tangan (HUDIntro) "boot up": naik dari bawah + kedip nyala.
## 4. Kontrol player nyala lagi.
##
## Pasang di node Node biasa bernama "IntroLanding" (anak dari root scene intro).

signal landed

@export var player: CharacterBody3D
@export var fist_hud: CanvasLayer

@export_group("Jatuh")
@export var fall_gravity := 16.0
@export var max_fall_speed := 40.0

@export_group("Setelah mendarat")
@export var boot_delay := 0.25      # jeda sebelum HUD tangan boot up
@export var unlock_delay := 0.6     # jeda sebelum player boleh gerak lagi

@export_group("Screen shake (meter)")
@export var shake_impact := 0.12    # kuat saat tabrak lantai
@export var shake_rumble := 0.025   # getaran pelan sesudahnya
@export var rumble_time := 2.0

@export_group("Partikel")
@export var debris_height := 5.5    # tinggi puing mulai jatuh dari lantai
@export var debris_spread := 1.1    # setengah lebar area puing (shaft lebar dalam ~2.8)

var shake_amount := 0.0

var _falling := false
var _saved := {}
var _camera: Camera3D
var _hidden_crosshairs: Array[CanvasItem] = []


func _ready() -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		player = get_node_or_null("../CharacterBody3D") as CharacterBody3D
	if fist_hud == null:
		fist_hud = get_node_or_null("../HUDIntro") as CanvasLayer
	if player == null:
		push_warning("IntroLanding: player tidak ketemu, isi di Inspector.")
		return

	# tunggu 1 frame supaya _ready player dan HUD selesai dulu
	await get_tree().process_frame
	_lock_player()
	if fist_hud:
		fist_hud.visible = false
		_hide_crosshairs()
	_falling = true


func _physics_process(delta: float) -> void:
	if not _falling:
		return
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.velocity.y = maxf(player.velocity.y - fall_gravity * delta, -max_fall_speed)
	player.move_and_slide()
	if player.is_on_floor():
		_falling = false
		_on_landed()


func _process(_delta: float) -> void:
	if shake_amount <= 0.0:
		return
	if _camera == null or not is_instance_valid(_camera):
		return
	_camera.h_offset = randf_range(-1.0, 1.0) * shake_amount
	_camera.v_offset = randf_range(-1.0, 1.0) * shake_amount


# ---------- kunci / buka kontrol player ----------

func _lock_player() -> void:
	_saved = {
		"physics": player.is_physics_processing(),
		"process": player.is_processing(),
		"input": player.is_processing_input(),
		"unhandled": player.is_processing_unhandled_input(),
		"unhandled_key": player.is_processing_unhandled_key_input(),
	}
	player.set_physics_process(false)
	player.set_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.set_process_unhandled_key_input(false)
	player.velocity = Vector3.ZERO


func _unlock_player() -> void:
	player.velocity = Vector3.ZERO
	player.set_physics_process(_saved.get("physics", true))
	player.set_process(_saved.get("process", true))
	player.set_process_input(_saved.get("input", true))
	player.set_process_unhandled_input(_saved.get("unhandled", true))
	player.set_process_unhandled_key_input(_saved.get("unhandled_key", true))


# ---------- mendarat ----------

func _on_landed() -> void:
	var hit := player.global_position
	var col := player.get_last_slide_collision()
	if col:
		hit = col.get_position()

	_camera = get_viewport().get_camera_3d()
	_spawn_dust(hit)
	_spawn_debris(hit)
	_start_shake()
	landed.emit()

	# pakai tween milik node ini (bukan SceneTree timer) supaya ikut mati saat scene di-restart
	var tw := create_tween()
	tw.tween_interval(boot_delay)
	tw.tween_callback(_boot_hud)
	tw.tween_interval(maxf(unlock_delay - boot_delay, 0.0))
	tw.tween_callback(_unlock_player)


# ---------- screen shake ----------

func _start_shake() -> void:
	shake_amount = shake_impact
	var t := create_tween()
	t.tween_property(self, "shake_amount", shake_rumble, 0.35).set_ease(Tween.EASE_OUT)
	t.tween_interval(rumble_time)
	t.tween_property(self, "shake_amount", 0.0, 1.0)
	t.finished.connect(_end_shake)


func _end_shake() -> void:
	shake_amount = 0.0
	if _camera and is_instance_valid(_camera):
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


# ---------- partikel ----------

func _spawn_dust(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 48
	p.lifetime = 1.6
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.25
	p.direction = Vector3.UP
	p.spread = 85.0
	p.gravity = Vector3(0, 0.2, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4

	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([
		Color(0.75, 0.55, 0.45, 0.0),
		Color(0.75, 0.55, 0.45, 0.8),
		Color(0.3, 0.2, 0.18, 0.0),
	])
	p.color_ramp = g

	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	quad.material = _dust_material()
	p.mesh = quad

	get_parent().add_child(p)
	p.global_position = pos + Vector3(0, 0.1, 0)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(p.lifetime + 0.5)
	tw.tween_callback(p.queue_free)


func _spawn_debris(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.amount = 36
	p.lifetime = 1.3
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(debris_spread, 0.05, debris_spread)
	p.direction = Vector3.DOWN
	p.spread = 8.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.gravity = Vector3(0, -12.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2

	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.07, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.55, 0.42, 0.34)
	box.material = m
	p.mesh = box

	get_parent().add_child(p)
	p.global_position = pos + Vector3(0, debris_height, 0)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(rumble_time)
	tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(p.lifetime + 0.5)
	tw.tween_callback(p.queue_free)


func _dust_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	return m


func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 16   # kecil + filter nearest = puff pixelated
	t.height = 16
	return t


# ---------- boot up HUD tangan ----------

func _boot_hud() -> void:
	_show_crosshairs()
	if fist_hud == null:
		return
	var sprite := fist_hud.get_node_or_null("FirstPersonFist") as CanvasItem

	fist_hud.visible = true
	fist_hud.offset = Vector2(0, 260)
	if sprite:
		sprite.modulate = Color(0.5, 1.0, 1.0, 0.0)

	# naik dari bawah layar
	var slide := create_tween()
	slide.tween_property(fist_hud, "offset", Vector2.ZERO, 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# kedip nyala (terang - mati - terang), berakhir putih normal
	if sprite:
		var blink: Array[Color] = [
			Color(0.5, 1.0, 1.0, 1.0),
			Color(0.5, 1.0, 1.0, 0.0),
			Color(0.8, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.2),
			Color(0.5, 1.0, 1.0, 1.0),
			Color(1.0, 1.0, 1.0, 0.0),
			Color(1.0, 1.0, 1.0, 1.0),
		]
		var wait: Array[float] = [0.05, 0.07, 0.05, 0.08, 0.06, 0.12, 0.0]
		var flicker := create_tween()
		for i in blink.size():
			var c: Color = blink[i]
			flicker.tween_callback(func(): sprite.modulate = c)
			flicker.tween_interval(wait[i])

func _hide_crosshairs() -> void:
	_hidden_crosshairs.clear()
	for n in get_tree().root.find_children("crosshair", "CanvasItem", true, false):
		var c := n as CanvasItem
		if c and c.visible:
			c.visible = false
			_hidden_crosshairs.append(c)


func _show_crosshairs() -> void:
	for c in _hidden_crosshairs:
		if is_instance_valid(c):
			c.visible = true
	_hidden_crosshairs.clear()
