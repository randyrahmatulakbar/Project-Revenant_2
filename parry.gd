extends Node
## Tangan kiri. F = mukul. Kalau ada benda "parryable" di depan saat jendela parry -> parry.
## Benda yang bisa di-parry: masuk group "parryable" dan punya fungsi parried(by).

@export var action_name := "parry"
@export var punch_reach := 2.2
@export var punch_damage := 5.0      # damage tinju (tembakan revolver = 11, lihat player-test.gd)
@export var parry_window := 0.25         # lama jendela parry sejak F ditekan
@export var parry_range := 3.0
@export var parry_angle_deg := 50.0      # seberapa lebar "depan" yang dihitung
@export var punch_duration := 0.36
@export var punch_cooldown := 0.3
@export var punch_hit_delay := 0.12
@export var hitstop_time := 0.25
@export var fov_kick := 10.0

var _player = null
var _cooldown := 0.0
var _elapsed := 0.0
var _active := false
var _parried := false
var _hit_done := false
var _side := true


func _ready() -> void:
	_player = get_parent()
	if not InputMap.has_action(action_name):      # otomatis dibuat, tombol F
		InputMap.add_action(action_name)
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event(action_name, ev)


func _exit_tree() -> void:
	Engine.time_scale = 1.0                       # jaga-jaga kalau restart pas hit-stop


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if Input.is_action_just_pressed(action_name):
		_start_punch()
	if not _active:
		return

	_elapsed += delta
	if not _parried and _elapsed <= parry_window:
		_check_parry()
	if not _parried and not _hit_done and _elapsed >= punch_hit_delay:
		_hit_done = true
		_punch_hit()
	if _elapsed >= punch_duration:
		_active = false


func _start_punch() -> void:
	var hud = _player.hud
	if hud == null or hud.intro_mode or not hud.visible or _cooldown > 0.0:
		return
	_cooldown = punch_cooldown
	_active = true
	_elapsed = 0.0
	_parried = false
	_hit_done = false
	hud.play_left_hand("punch")
	_camera_kick(1.5 if _side else -1.5, 2.0)     # hentakan kecil, kiri-kanan gantian
	_side = not _side
	get_tree().call_group("sfx", "play", "punch_whoosh", -3.0, 0.06)


func _check_parry() -> void:
	var cam: Camera3D = _player.camera
	var forward := -cam.global_transform.basis.z
	var origin := cam.global_position
	var cos_limit := cos(deg_to_rad(parry_angle_deg))

	var targets: Array = []
	for n in get_tree().get_nodes_in_group("parryable"):
		if not (n is Node3D):
			continue
		# pakai titik badan musuh (parry_point) kalau ada; global_position itu di kaki, jadi sering di luar sudut parry
		var p: Vector3 = n.parry_point() if n.has_method("parry_point") else n.global_position
		var to: Vector3 = p - origin
		var dist := to.length()
		if dist > parry_range:
			continue
		if dist > 0.05 and forward.dot(to / dist) < cos_limit:
			continue
		targets.append(n)
	if targets.is_empty():
		return

	_parried = true
	for n in targets:
		if n.has_method("parried"):
			n.parried(_player)
	_parry_effects()


func _punch_hit() -> void:
	var cam: Camera3D = _player.camera
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * punch_reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [_player.get_rid()]
	var r: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(q)
	if r:
		if r.collider.has_method("take_damage"):
			r.collider.take_damage(punch_damage)
			_player.spawn_impact_particles(r.position, r.normal, Color(0.8, 0.05, 0.05))
			get_tree().call_group("sfx", "play", "punch_hit", -2.0, 0.06)
		else:
			get_tree().call_group("sfx", "play", "punch_hit", -12.0, 0.1)   # kena tembok: lebih pelan


func _parry_effects() -> void:
	get_tree().call_group("sfx", "play", "parry", 0.0, 0.03)
	var hud = _player.hud
	if hud:
		hud.play_left_hand("parry", 4)          # langsung pose tangan terangkat
		hud.flash_left_hand(hitstop_time)
		hud.parry_fx(hitstop_time)
	_camera_kick(3.0, fov_kick)                    # sentakan lebih kuat saat parry
	Engine.time_scale = 0.01                       # freeze frame
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_interval(hitstop_time)
	tw.tween_callback(func(): Engine.time_scale = 1.0)
	
	
	
	# Hentakan kamera: zoom sekejap + miring sedikit, lalu pulih sendiri
func _camera_kick(roll_deg: float, fov: float) -> void:
	var cam: Camera3D = _player.camera
	cam.fov -= fov
	cam.rotation.z = deg_to_rad(roll_deg)
	var tw := create_tween()
	tw.tween_property(cam, "rotation:z", 0.0, 0.18) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
