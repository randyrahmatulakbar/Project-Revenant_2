extends Area3D
## Bola racun dari Spitter. Kena player -> damage + racun (damage berkelanjutan).
## Kena tembok / lantai -> pecah jadi genangan racun.

const PoisonDot := preload("res://poison_dot.gd")
const PoisonPuddle := preload("res://poison_puddle.gd")

var velocity: Vector3 = Vector3.ZERO
var damage: float = 8.0
var poison_dps: float = 3.0
var poison_time: float = 3.0
var _shooter: Node
var _life: float = 5.0
var _done := false

# --- PARRY: tekan F pas bola dekat -> dipantulkan balik ke penembak ---
@export var reflect_speed_mult: float = 1.4
@export var reflect_damage: float = 20.0      # damage ke musuh yang kena bola pantulan
@export var reflect_hit_radius: float = 1.0   # jarak ke badan musuh yang dihitung kena
var _reflected := false


var _trail: CPUParticles3D


func _ready() -> void:
	add_to_group("parryable")                 # dicek oleh parry.gd
	_trail = _make_trail(Color(0.5, 1.0, 0.15, 0.9))
	body_entered.connect(_on_body_entered)
	var model := get_node_or_null("Model")
	if model:
		var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap and ap.has_animation("spin_loop"):
			ap.play("spin_loop")


func launch(target: Vector3, speed: float, shooter: Node, dmg: float, dps: float, t: float) -> void:
	_shooter = shooter
	damage = dmg
	poison_dps = dps
	poison_time = t
	var dir := (target - global_position).normalized()
	velocity = dir * speed
	if absf(dir.dot(Vector3.UP)) < 0.98:
		look_at(global_position + dir, Vector3.UP)


func _physics_process(delta: float) -> void:
	if _done:
		return
	global_position += velocity * delta
	_life -= delta
	if _reflected:
		_check_reflect_hit()
	if _life <= 0.0:
		_splash()


## Dipanggil parry.gd kalau parry kena bola ini
func parried(by) -> void:
	if _done or _reflected:
		return
	_reflected = true
	remove_from_group("parryable")
	if _trail:
		_trail.queue_free()
	_trail = _make_trail(Color(1.0, 0.85, 0.3, 0.95))           # bola pantulan jadi emas
	_burst(Color(1.0, 0.9, 0.4), 18)
	_life = 4.0
	var from := global_position
	var target := from - velocity.normalized() * 10.0              # default: balik arah datang
	if is_instance_valid(_shooter) and _shooter is Node3D:
		target = (_shooter as Node3D).global_position + Vector3(0, 1.2, 0)   # arahkan ke badan penembak
	var speed := velocity.length() * reflect_speed_mult
	velocity = (target - from).normalized() * speed
	get_tree().call_group("sfx", "play_at", "parry", global_position, -4.0)


# Bola pantulan kena musuh? (dicek lewat jarak, jadi gak tergantung collision mask)
func _check_reflect_hit() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("take_damage"):
			continue
		var center: Vector3 = (e as Node3D).global_position + Vector3(0, 1.0, 0)
		if center.distance_to(global_position) <= reflect_hit_radius:
			e.take_damage(reflect_damage)
			_burst(Color(1.0, 0.85, 0.3), 22)
			get_tree().call_group("sfx", "play_at", "glob_splat", global_position, 0.0)
			_done = true
			queue_free()
			return


func _on_body_entered(body: Node3D) -> void:
	if _done or body == _shooter or body.is_in_group("enemy"):
		return
	if _reflected and body.is_in_group("player"):
		return                                  # bola pantulan gak nyakitin player
	if body.is_in_group("player"):
		var h := body.get_node_or_null("Health")
		if h:
			body.set_meta("last_hit_by", "Spitter")
			body.set_meta("last_hit_time", Time.get_ticks_msec())
			h.take_damage(damage)
		PoisonDot.apply(body, poison_dps, poison_time)
		get_tree().call_group("sfx", "play_at", "glob_splat", global_position, -1.0)
		_burst(Color(0.5, 1.0, 0.15), 16)
		_done = true
		queue_free()
		return
	_splash()


func _splash() -> void:
	if _done:
		return
	_done = true
	var p := Area3D.new()
	p.set_script(PoisonPuddle)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	_burst(Color(0.5, 1.0, 0.15), 20)
	get_tree().call_group("sfx", "play_at", "glob_splat", global_position, 0.0)
	queue_free()


# ---------- VFX ----------
func _fx_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = color
	return m


# Jejak partikel yang ngikutin bola
func _make_trail(color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.1
	mesh.material = _fx_mat(color)
	p.mesh = mesh
	p.amount = 30
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.gravity = Vector3(0, -3.0, 0)
	p.local_coords = false
	add_child(p)
	p.emitting = true
	return p


# Muncratan sekali meledak di posisi bola
func _burst(color: Color, amount: int) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.08
	mesh.material = _fx_mat(color)
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.8, 0)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)
