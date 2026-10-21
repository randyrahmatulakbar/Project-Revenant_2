extends Node3D
## Pintu belakang ruang ambil senjata. Terbuka otomatis saat semua wave selesai.
## Anak node yang dipakai: Panel (CSGBox3D, pintu yang naik), StatusLamp (CSGBox3D), DoorLight (OmniLight3D).

signal opened

@export var spawner_path: NodePath = ^"../../EnemySpawner"
@export var pickup_path: NodePath = ^"../../PistolPickup"
@export var reveal_lights: Array[NodePath] = [
	^"../particle and light/CorridorLight",
	^"../particle and light/Room2Light",
]
@export var open_height := 3.3
@export var open_time := 2.6
@export var enemy_groups: PackedStringArray = PackedStringArray(["enemy", "enemies"])
@export var clear_delay := 5.0          # cadangan: detik tanpa musuh sebelum dianggap selesai
@export var test_key: Key = KEY_F9      # tombol tes: buka pintu langsung

const CLEAR_SIGNALS := ["all_waves_cleared", "all_waves_finished", "all_waves_complete", "all_waves_done",
	"waves_cleared", "waves_finished", "waves_complete", "waves_done", "cleared", "finished"]
const GREEN := Color(0.2, 1.0, 0.35)
const RED := Color(1.0, 0.12, 0.08)

var shake_amount := 0.0
var _panel: Node3D
var _lamp: CSGBox3D
var _lamp_mat: StandardMaterial3D
var _light: OmniLight3D
var _home := Vector3.ZERO
var _armed := false
var _open := false
var _hooked := false
var _seen_enemy := false
var _empty_time := 0.0
var _poll := 0.0
var _pulse: Tween
var _reveal := {}
var _cam: Camera3D


func _ready() -> void:
	_panel = get_node_or_null("Panel") as Node3D
	_lamp = get_node_or_null("StatusLamp") as CSGBox3D
	_light = get_node_or_null("DoorLight") as OmniLight3D
	_home = _panel.global_position if _panel else global_position
	if _lamp:
		_lamp_mat = _lamp.material as StandardMaterial3D
		if _lamp_mat == null:
			_lamp_mat = StandardMaterial3D.new()
			_lamp_mat.emission_enabled = true
			_lamp.material = _lamp_mat
	_set_lamp(RED, 2.0)
	_start_pulse()

	for p in reveal_lights:                       # lorong dan ruang 2 gelap sampai pintu terbuka
		var l := get_node_or_null(p) as Light3D
		if l:
			_reveal[l] = l.light_energy
			l.light_energy = 0.0

	var pickup := get_node_or_null(pickup_path)
	if pickup and pickup.has_signal("picked_up"):
		pickup.picked_up.connect(_arm)
	_hook_spawner()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == test_key:
		open()


func _arm() -> void:
	_armed = true


func _hook_spawner() -> void:
	var sp := get_node_or_null(spawner_path)
	if sp == null:
		push_warning("BackDoor: spawner tidak ketemu, pakai deteksi musuh")
		return
	for sig in CLEAR_SIGNALS:
		if sp.has_signal(sig):
			var argc := 0
			for info in sp.get_signal_list():
				if info.name == sig:
					argc = info.args.size()
			sp.connect(sig, _on_waves_done.unbind(argc))
			_hooked = true
			print("BackDoor: terhubung ke sinyal spawner '", sig, "'")
			return
	print("BackDoor: spawner tidak punya sinyal selesai wave, pakai deteksi musuh (clear_delay=", clear_delay, ")")


func _on_waves_done() -> void:
	open()


func _process(delta: float) -> void:
	if shake_amount > 0.0:
		if _cam == null or not is_instance_valid(_cam):
			_cam = get_viewport().get_camera_3d()
		if _cam:
			_cam.h_offset = randf_range(-1.0, 1.0) * shake_amount
			_cam.v_offset = randf_range(-1.0, 1.0) * shake_amount
	if _open or _hooked or not _armed:
		return
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	if _count_enemies() > 0:
		_seen_enemy = true
		_empty_time = 0.0
	elif _seen_enemy:
		_empty_time += 0.5
		if _empty_time >= clear_delay:
			open()


func _count_enemies() -> int:
	var found := {}
	for g in enemy_groups:
		for n in get_tree().get_nodes_in_group(g):
			found[n] = true
	var roots: Array = [get_tree().current_scene, get_node_or_null(spawner_path)]
	for r in roots:
		if r == null:
			continue
		for c in r.get_children():
			if c is CharacterBody3D and c.has_method("take_damage") and not c.is_in_group("player"):
				found[c] = true
	for n in found.keys():
		if n.get("dead") == true or n.get("is_dead") == true:
			found.erase(n)
	return found.size()


# ---------- urutan buka ----------
func open() -> void:
	if _open:
		return
	_open = true
	if _pulse:
		_pulse.kill()
	_play("res://sfx/wave_clear.wav", false, -2.0)
	var t := create_tween()
	for i in 3:                                   # lampu kedip merah-putih
		t.tween_callback(_set_lamp.bind(Color(1, 1, 1), 4.0))
		t.tween_interval(0.08)
		t.tween_callback(_set_lamp.bind(RED, 2.0))
		t.tween_interval(0.12)
	t.tween_callback(_unlock)
	t.tween_interval(0.5)
	t.tween_callback(_start_slide)
	t.tween_interval(open_time)
	t.tween_callback(_finish_open)


func _unlock() -> void:
	_set_lamp(GREEN, 3.0)
	if _light:
		_light.light_energy = 2.5
	_play("res://sfx/door_unlock.wav")
	_dust(_home + Vector3(0, -1.2, 0.4), 14, 0.5, 1.0)
	_sparks(_home + Vector3(0, 0.4, 0.3), 12)


func _start_slide() -> void:
	_play("res://sfx/door_slide.wav")
	if _panel:
		var tw := create_tween()
		tw.tween_property(_panel, "position:y", _panel.position.y + open_height, open_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_falling_dust(open_time)
	_sparks(_home + Vector3(0, -1.0, 0.3), 22)
	var ts := create_tween()                      # gemuruh kamera
	ts.tween_property(self, "shake_amount", 0.035, 0.4)
	ts.tween_interval(maxf(open_time - 0.8, 0.1))
	ts.tween_property(self, "shake_amount", 0.0, 0.4)
	ts.tween_callback(_end_shake)


func _finish_open() -> void:
	_play("res://sfx/door_open_end.wav")
	_dust(_home + Vector3(0, -1.5, 0.5), 30, 0.7, 2.0)
	if _light:
		_light.light_energy = 5.0
		create_tween().tween_property(_light, "light_energy", 0.8, 1.2)
	for l in _reveal.keys():                      # lorong dan ruang 2 menyala pelan-pelan
		if is_instance_valid(l):
			create_tween().tween_property(l, "light_energy", _reveal[l], 1.6)
	opened.emit()


func _end_shake() -> void:
	shake_amount = 0.0
	if _cam and is_instance_valid(_cam):
		_cam.h_offset = 0.0
		_cam.v_offset = 0.0


# ---------- lampu status ----------
func _set_lamp(c: Color, e: float) -> void:
	if _lamp_mat:
		_lamp_mat.albedo_color = c.darkened(0.7)
		_lamp_mat.emission = c
		_lamp_mat.emission_energy_multiplier = e
	if _light:
		_light.light_color = c


func _start_pulse() -> void:
	_pulse = create_tween().set_loops()
	_pulse.tween_method(_pulse_step, 0.0, 1.0, 0.9)
	_pulse.tween_method(_pulse_step, 1.0, 0.0, 0.9)


func _pulse_step(v: float) -> void:
	if _lamp_mat:
		_lamp_mat.emission_energy_multiplier = lerpf(0.5, 2.2, v)
	if _light:
		_light.light_energy = lerpf(0.2, 1.1, v)


# ---------- suara ----------
func _play(path: String, positional := true, db := 0.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = load(path)
		p3.unit_size = 12.0
		p3.max_distance = 70.0
		p3.volume_db = db
		add_child(p3)
		p3.global_position = _home
		p3.play()
		p = p3
	else:
		var p2 := AudioStreamPlayer.new()
		p2.stream = load(path)
		p2.volume_db = db
		add_child(p2)
		p2.play()
		p = p2
	p.finished.connect(p.queue_free)


# ---------- partikel ----------
func _dust(pos: Vector3, amount: int, life: float, power: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life + 0.8
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.2, 0.2, 0.2)
	p.direction = Vector3(0, 0.3, 1.0)
	p.spread = 70.0
	p.gravity = Vector3(0, 0.15, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6 * power
	p.damping_min = 1.5
	p.damping_max = 3.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.55, 0.45, 0.0), Color(0.7, 0.55, 0.45, 0.7), Color(0.3, 0.22, 0.18, 0.0)])
	p.color_ramp = g
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _soft_mat(false)
	p.mesh = quad
	_spawn(p, pos)


func _falling_dust(duration: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.2
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.2, 0.05, 0.15)
	p.direction = Vector3.DOWN
	p.spread = 12.0
	p.gravity = Vector3(0, -5.0, 0)
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.5
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.55, 0.45, 0.0), Color(0.7, 0.55, 0.45, 0.6), Color(0.4, 0.3, 0.25, 0.0)])
	p.color_ramp = g
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _soft_mat(false)
	p.mesh = quad
	_spawn(p, _home + Vector3(0, 1.6, 0.2), duration)


func _sparks(pos: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.6
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1.1, 0.05, 0.05)
	p.direction = Vector3(0, 0.5, 1.0)
	p.spread = 80.0
	p.gravity = Vector3(0, -9.8, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.4, 0.1, 0.0)])
	p.color_ramp = g
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	quad.material = _soft_mat(true)
	p.mesh = quad
	_spawn(p, pos)


func _spawn(p: CPUParticles3D, pos: Vector3, stop_after := -1.0) -> void:
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var tw := p.create_tween()                   # ikut mati bersama node kalau scene di-restart
	if stop_after > 0.0:
		tw.tween_interval(stop_after)
		tw.tween_callback(func(): p.emitting = false)
	tw.tween_interval(p.lifetime + 0.5)
	tw.tween_callback(p.queue_free)


func _soft_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
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
	t.width = 16
	t.height = 16
	return t
