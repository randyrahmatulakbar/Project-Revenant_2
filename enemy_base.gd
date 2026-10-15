extends CharacterBody3D
class_name EnemyBase
## Dasar semua musuh: spawn, kena tembak, mati, gerak (navigasi), animasi, suara.
## Jenis musuh (Mauler, Leaper, Spitter) cukup extends script ini dan isi _think().
##
## Struktur scene yang diharapkan (lihat enemy_mauler.tscn):
##   CharacterBody3D (script ini)
##   |- CollisionShape3D
##   |- Model (instance file .glb, di dalamnya ada AnimationPlayer)
##   |- NavigationAgent3D

signal died(enemy: EnemyBase)

enum State { SPAWN, ACTIVE, DEAD }

@export_group("Stat")
@export var max_health: float = 5.0          # peluru pemain = 1 damage per tembakan
@export var move_speed: float = 5.0
@export var accel: float = 35.0
@export var turn_speed: float = 9.0

@export_group("Spawn")
@export var spawn_time: float = 0.6          # lama muncul dari lantai (dulu 0.9)
@export var spawn_sink: float = 1.8          # model mulai segini di bawah lantai

@export_group("Mati")
@export var corpse_time: float = 2.5         # mayat bertahan segini lama sebelum ilang
@export var gore_color: Color = Color(0.75, 0.05, 0.05)
@export var death_speed: float = 1.6         # kecepatan animasi mati (1 = asli, lebih besar = lebih cepat & bertenaga)
@export var death_shove: float = 3.0         # mayat terdorong menjauhi player sekian m/s pas mati
@export var corpse_drag: float = 8.0         # seberapa cepat dorongan itu berhenti
@export var soft_death: bool = true          # true = jatuh "lemas" (percepatan, limbung, mantul). false = animasi mati bawaan

@export_group("Gerak (biar gak kaku)")
@export var move_juice: bool = true          # badan goyang & naik-turun dikit pas jalan
@export var hit_flinch: float = 0.12         # badan tersentak ke belakang tiap kena tembak (0 = mati)

var health: float = 0.0
var state: State = State.SPAWN
var player: Node3D
var model: Node3D
var anim: AnimationPlayer
var nav: NavigationAgent3D

var _flash_mat: StandardMaterial3D
var _flash_tween: Tween
var _repath: float = 0.0
var _anim_name: String = ""
var _juice_tw: Tween                         # ancang-ancang / terjang saat nyerang
var _flinch_tw: Tween                        # tersentak kena tembak
var _bob_phase := 0.0
var _last_step := -1
static var _soft_tex: Texture2D
var _death_fall := 0.5
var _warned := {}
var _rest_rot := {}                          # pose awal tiap node model (buat meluruskan bagian yang gak ikut animasi mati)


func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	model = get_node_or_null("Model") as Node3D
	if model:
		anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	nav = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	_setup_flash()
	_record_rest_pose()
	_find_player()
	_begin_spawn()


# =========================
# ALUR UTAMA
# =========================
func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, corpse_drag * delta)   # mayat meluncur sebentar lalu berhenti
		velocity.z = move_toward(velocity.z, 0.0, corpse_drag * delta)
		_gravity_step(delta)
		move_and_slide()
		return
	if player == null or not is_instance_valid(player):
		_find_player()
	if state == State.ACTIVE:
		_think(delta)
		_move_juice(delta)
	else:
		stop_h(delta)
	_gravity_step(delta)
	move_and_slide()


# --- dioverride jenis musuh ---
func _think(_delta: float) -> void: pass
func _on_spawned() -> void: pass
func _on_hurt(_amount: float) -> void: pass
func _on_died() -> void: pass


# =========================
# SPAWN
# =========================
func _begin_spawn() -> void:
	state = State.SPAWN
	play_anim("idle_loop", 0.0)
	if model:
		model.position.y = -spawn_sink
		var tw := create_tween()
		tw.tween_property(model, "position:y", 0.0, spawn_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	flash(Color(1, 1, 1), 0.8, 0.7)
	burst(global_position + Vector3(0, 0.2, 0), Color(0.55, 0.5, 0.45), 22, 0.14, 3.0, 0.9)
	burst(global_position + Vector3(0, 0.1, 0), Color(0.5, 0.45, 0.4), 14, 0.1, 5.5, 0.9, Vector3.UP, 20.0)    # tiang debu naik
	burst(global_position + Vector3(0, 0.2, 0), Color(1.0, 0.45, 0.12), 12, 0.05, 6.0, 0.8, Vector3.UP, 45.0) # bara
	vfx_ring(global_position + Vector3(0, 0.08, 0), Color(0.9, 0.3, 0.18, 0.9), 2.6, 0.55)
	vfx_light(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.3, 0.15), 3.5, 0.5, 7.0)
	sfx_at("spawn", -2.0)
	get_tree().create_timer(spawn_time).timeout.connect(_end_spawn)


func _end_spawn() -> void:
	if state != State.SPAWN:
		return
	state = State.ACTIVE
	_on_spawned()


# =========================
# KENA TEMBAK & MATI
# =========================
# dipanggil player-test.gd: result.collider.take_damage(1)
func take_damage(amount: float = 1.0) -> void:
	if state == State.DEAD:
		return
	health -= amount
	flash(Color(1, 1, 1), 0.65, 0.12)
	sfx_at("enemy_hit", -3.0)
	if hit_flinch > 0.0:
		flinch(hit_flinch)
	burst(global_position + Vector3(0, 1.2, 0), gore_color, 7, 0.06, 3.5, 0.45)         # semburan darah kena tembak
	_on_hurt(amount)
	if health <= 0.0:
		_die()


func _die() -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	remove_from_group("enemy")
	collision_layer = 0                      # gak bisa ditembak / ditabrak lagi
	# dorongan kena-hantam: menjauh dari player (gantikan momentum jalan / lompat)
	var away := -dir_to_player_flat()
	velocity.x = away.x * death_shove
	velocity.z = away.z * death_shove
	kill_juice()
	if model:
		model.rotation.x = 0.0
		model.rotation.z = 0.0
		model.scale = Vector3.ONE
	var fall_t := 0.0
	if soft_death and _soft_death():
		fall_t = _death_fall
	else:
		play_anim("death", 0.08, death_speed, true)
		if anim and anim.has_animation("death"):
			fall_t = anim.get_animation("death").length / death_speed * 0.85
	_relax_untracked_parts("death")
	if fall_t > 0.0:
		get_tree().create_timer(fall_t).timeout.connect(_corpse_impact)
	sfx_at("enemy_death", 0.0)
	burst(global_position + Vector3(0, 1.2, 0), gore_color, 30, 0.1, 5.5, 1.2)
	flash(Color(1.0, 0.25, 0.1), 0.7, 0.35)
	vfx_light(global_position + Vector3(0, 1.2, 0), gore_color.lightened(0.3), 3.0, 0.3, 6.0)
	_on_died()
	died.emit(self)
	get_tree().create_timer(corpse_time).timeout.connect(_sink_and_free)


# ---------- GERAK SEKUNDER (biar gak kaku) ----------
# Ancang-ancang mundur sebelum tiap pukulan, lalu menghentak ke depan tepat saat kena.
# hits = waktu (detik sejak serangan mulai) tiap pukulan kena.
func juice_attack(hits: Array, lean: float = 10.0) -> void:
	if model == null:
		return
	kill_juice()
	_juice_tw = create_tween()
	var t := 0.0
	for h in hits:
		var wind_end := maxf(float(h) - 0.12, t + 0.02)
		_juice_tw.tween_property(model, "rotation:x", deg_to_rad(lean * 0.7), wind_end - t) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)                  # condong ke belakang (ancang-ancang)
		_juice_tw.tween_property(model, "rotation:x", deg_to_rad(-lean), maxf(float(h) - wind_end, 0.04)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)                   # hentak ke depan
		t = maxf(float(h), wind_end + 0.04)
	_juice_tw.tween_property(model, "rotation:x", 0.0, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func kill_juice() -> void:
	if _juice_tw:
		_juice_tw.kill()


# Melangkah / terjang sedikit ke depan (arah hadap musuh)
func lunge(speed: float) -> void:
	if state != State.ACTIVE:
		return
	var f := -global_transform.basis.z
	velocity.x += f.x * speed
	velocity.z += f.z * speed


# Badan tersentak ke belakang sebentar (kena tembak / recoil)
func flinch(amount: float = 0.12) -> void:
	if model == null or state == State.DEAD:
		return
	if _flinch_tw:
		_flinch_tw.kill()
	_flinch_tw = create_tween()
	_flinch_tw.tween_property(model, "position:z", amount, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flinch_tw.tween_property(model, "position:z", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# Goyang & naik-turun dikit saat berjalan di tanah
func _move_juice(delta: float) -> void:
	if model == null or not move_juice:
		return
	var sp := Vector2(velocity.x, velocity.z).length()
	var k := clampf(sp / maxf(move_speed, 0.1), 0.0, 1.0) if is_on_floor() else 0.0
	_bob_phase += delta * sp * 2.2
	var step := int(floor(_bob_phase / PI))
	if step != _last_step:
		_last_step = step
		if k > 0.3:                                          # tiap telapak kena tanah: debu kecil + bunyi langkah
			burst(global_position + Vector3(0, 0.05, 0), Color(0.5, 0.45, 0.4), 3, 0.08, 1.4, 0.5, Vector3.UP, 60.0)
			sfx_at("footstep", -17.0)
	model.position.y = absf(sin(_bob_phase)) * 0.06 * k
	model.rotation.z = sin(_bob_phase) * deg_to_rad(3.0) * k


# Mati "lemas": animasi mati bawaan dibaca lalu dimainkan ulang per-bagian dengan timing sendiri:
# pinggul jatuh makin cepat lalu mantul, anggota badan menyusul telat & berayun (follow-through).
# Return false kalau struktur modelnya gak cocok -> pakai animasi mati biasa.
func _soft_death() -> bool:
	if anim == null or model == null or not anim.has_animation("death"):
		return false
	var a := anim.get_animation("death")
	var root := anim.get_node_or_null(anim.root_node)
	if root == null:
		return false
	var rots: Array = []
	var poss: Array = []
	for i in a.get_track_count():
		var ty := a.track_get_type(i)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D:
			continue
		var p := str(a.track_get_path(i))
		if ":" in p:
			return false                                     # track tulang (Skeleton3D) -> gak didukung
		var node := root.get_node_or_null(NodePath(p)) as Node3D
		var kc := a.track_get_key_count(i)
		if node == null or kc < 1:
			continue
		if ty == Animation.TYPE_ROTATION_3D:
			rots.append([node, a.rotation_track_interpolate(i, a.length)])
		else:
			poss.append([node, a.position_track_interpolate(i, a.length)])
	if rots.is_empty():
		return false

	anim.active = false                                      # matikan animasi bawaan; pose sekarang = titik awal
	var fall := clampf(a.length * 0.5 / maxf(death_speed, 0.5) * 1.4, 0.38, 0.8)
	_death_fall = fall
	var hips: Node3D = poss[0][0] if not poss.is_empty() else null
	var base_depth := _depth_of(hips) if hips else 0

	for r in rots:
		var node: Node3D = r[0]
		var q1: Quaternion = r[1]
		var q0: Quaternion = node.quaternion
		var is_hips := node == hips
		var tw := create_tween()
		if not is_hips:
			tw.tween_interval(maxf(_depth_of(node) - base_depth, 0) * 0.03)   # makin ujung makin telat
		var tm := tw.tween_method(func(t: float): node.quaternion = q0.slerp(q1, t), 0.0, 1.0,
				fall if is_hips else fall * 0.8 + 0.3)
		if is_hips:
			tm.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)             # jatuh makin cepat
		else:
			tm.set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)          # sampai lalu berayun

	for pe in poss:
		var node: Node3D = pe[0]
		var p1: Vector3 = pe[1]
		var pt := create_tween()
		pt.tween_property(node, "position", p1, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if node == hips:                                                       # mantul pas kena lantai
			pt.tween_property(node, "position:y", p1.y + 0.14, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pt.tween_property(node, "position:y", p1.y, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			pt.tween_property(node, "position:y", p1.y + 0.04, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			pt.tween_property(node, "position:y", p1.y, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# hentakan kena hantam: badan terlempar ke belakang sebentar
	if _flinch_tw:
		_flinch_tw.kill()
	_flinch_tw = create_tween()
	_flinch_tw.tween_property(model, "position:z", 0.3, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flinch_tw.tween_property(model, "position:z", 0.0, fall).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	return true


func _depth_of(n: Node) -> int:
	var d := 0
	var p: Node = n.get_parent() if n else null
	while p != null and p != model:
		d += 1
		p = p.get_parent()
	return d


# Badan menghantam lantai: debu + bunyi "bruk"
func _corpse_impact() -> void:
	if not is_inside_tree():
		return
	burst(global_position + Vector3(0, 0.15, 0), Color(0.55, 0.5, 0.45), 14, 0.12, 2.5, 0.6)
	burst(global_position + Vector3(0, 0.3, 0), gore_color, 12, 0.07, 3.0, 0.6)
	vfx_ring(global_position + Vector3(0, 0.08, 0), Color(0.7, 0.65, 0.55, 0.8), 2.0, 0.4)
	vfx_blood_pool(global_position, gore_color)
	sfx_at("land_soft", -2.0)


# Catat rotasi awal semua node model (sebelum animasi apa pun jalan)
func _record_rest_pose() -> void:
	if model == null:
		return
	for n in model.find_children("*", "Node3D", true, false):
		_rest_rot[n] = (n as Node3D).rotation


# Animasi "death" gak punya track untuk kaki / tangan / kepalan / leher dll, jadi bagian itu
# membeku di pose terakhir (mis. kepalan masih nonjok, kaki masih melangkah).
# Di sini bagian-bagian itu dikembalikan pelan-pelan ke pose awal.
func _relax_untracked_parts(anim_name: String, time: float = 0.25) -> void:
	if anim == null or model == null or not anim.has_animation(anim_name):
		return
	var a := anim.get_animation(anim_name)
	var root := anim.get_node_or_null(anim.root_node)
	if root == null:
		return
	var tracked := {}
	for i in a.get_track_count():
		tracked[str(a.track_get_path(i)).get_slice(":", 0)] = true
	var tw := create_tween().set_parallel(true)
	var any := false
	for n in _rest_rot:
		if not is_instance_valid(n) or tracked.has(str(root.get_path_to(n))):
			continue
		tw.tween_property(n, "rotation", _rest_rot[n], time)
		any = true
	if not any:
		tw.kill()


func _sink_and_free() -> void:
	if model == null:
		queue_free()
		return
	var tw := create_tween()
	tw.tween_property(model, "position:y", -1.6, 0.9)
	tw.tween_callback(queue_free)


# =========================
# GERAK
# =========================
func _gravity_step(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _find_player() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D


func flat_dist() -> float:
	if player == null:
		return 9999.0
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length()


func dir_to_player_flat() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var d := player.global_position - global_position
	d.y = 0.0
	return d.normalized()


# arah jalan menuju target lewat navmesh; kalau navmesh belum ada, lurus aja
func nav_dir_to(target: Vector3) -> Vector3:
	var dir := target - global_position
	dir.y = 0.0
	if nav:
		_repath -= get_physics_process_delta_time()
		if _repath <= 0.0:
			nav.target_position = target
			_repath = 0.25
		if not nav.is_navigation_finished():
			var step := nav.get_next_path_position() - global_position
			step.y = 0.0
			if step.length() > 0.05:
				dir = step
	return dir.normalized()


func move_dir(dir: Vector3, speed: float, delta: float) -> void:
	var sep := _separation()
	var want := (dir + sep).normalized() * speed if (dir + sep).length() > 0.01 else Vector3.ZERO
	velocity.x = move_toward(velocity.x, want.x, accel * delta)
	velocity.z = move_toward(velocity.z, want.z, accel * delta)


func stop_h(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, accel * delta)
	velocity.z = move_toward(velocity.z, 0.0, accel * delta)


func face_dir(dir: Vector3, delta: float, speed: float = -1.0) -> void:
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	var yaw := atan2(-dir.x, -dir.z)           # model menghadap -Z
	rotation.y = lerp_angle(rotation.y, yaw, clampf((speed if speed > 0.0 else turn_speed) * delta, 0.0, 1.0))


# dorong menjauh dari musuh lain biar gak numpuk
func _separation() -> Vector3:
	var push := Vector3.ZERO
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == self or not (e is Node3D):
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 1.3:
			push += d.normalized() * (1.3 - l)
	return push * 0.8


func can_see_player(max_dist: float) -> bool:
	if player == null:
		return false
	var from := global_position + Vector3(0, 1.4, 0)
	var to := player.global_position
	if from.distance_to(to) > max_dist:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [self]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == player


# =========================
# SERANG PEMAIN
# =========================
func hurt_player(amount: float, knockback: float = 0.0) -> void:
	if player == null:
		return
	var h := player.get_node_or_null("Health")
	if h and h.has_method("take_damage"):
		h.take_damage(amount)
		hit_fx(int(clampf(amount, 6.0, 20.0)))
	if knockback > 0.0 and "velocity" in player:
		var d := player.global_position - global_position
		d.y = 0.0
		player.velocity += d.normalized() * knockback + Vector3(0, 1.2, 0)


# =========================
# ANIMASI, EFEK, SUARA
# =========================
func play_anim(anim_name: String, blend: float = 0.15, speed: float = 1.0, restart: bool = false) -> void:
	if anim == null:
		return
	if not anim.has_animation(anim_name):
		if not _warned.has(anim_name):
			_warned[anim_name] = true
			push_warning("%s: animasi '%s' tidak ada di model. Yang ada: %s" % [name, anim_name, ", ".join(anim.get_animation_list())])
		return
	if not restart and _anim_name == anim_name and anim.is_playing() and is_equal_approx(anim.speed_scale, 1.0):
		return
	_anim_name = anim_name
	anim.play(anim_name, blend, speed, speed < 0.0)


# jalankan fn setelah t detik (batal kalau musuh udah mati)
func after(t: float, fn: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(func():
		if state != State.DEAD and is_inside_tree():
			fn.call())


func sfx_at(sfx_name: String, db: float = 0.0) -> void:
	get_tree().call_group("sfx", "play_at", sfx_name, global_position + Vector3(0, 1.0, 0), db)


func _setup_flash() -> void:
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.albedo_color = Color(1, 1, 1, 0)
	if model:
		for n in model.find_children("*", "MeshInstance3D", true, false):
			(n as MeshInstance3D).material_overlay = _flash_mat


func flash(color: Color = Color(1, 1, 1), strength: float = 0.6, time: float = 0.12) -> void:
	if _flash_mat == null:
		return
	if _flash_tween:
		_flash_tween.kill()
	_flash_mat.albedo_color = Color(color.r, color.g, color.b, strength)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, time)


func burst(pos: Vector3, color: Color, amount: int, size: float, speed: float, life: float, dir: Vector3 = Vector3.UP, spread: float = 80.0) -> void:
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size, size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mesh.material = mat
	p.mesh = mesh
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -9.8, 0)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


# =========================
# VFX (semua dibuat lewat kode, tanpa file aset)
# =========================
func _soft_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


func _fx_mat(color: Color, additive: bool = true, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	if tex:
		m.albedo_texture = tex
	return m


# Cincin kejut yang melebar di lantai
func vfx_ring(pos: Vector3, color: Color, radius: float = 2.0, time: float = 0.4) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.9
	tm.outer_radius = 1.0
	tm.rings = 32
	tm.ring_segments = 8
	var mat := _fx_mat(color)
	tm.material = mat
	mi.mesh = tm
	mi.scale = Vector3.ONE * 0.2
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, time).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


# Kilatan cahaya sesaat
func vfx_light(pos: Vector3, color: Color, energy: float = 3.0, time: float = 0.3, light_range: float = 6.0) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false
	get_tree().current_scene.add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


# Genangan darah yang melebar di lantai, lalu pudar
func vfx_blood_pool(pos: Vector3, color: Color, size: float = 1.5) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var c := Color(color.r * 0.55, color.g * 0.55, color.b * 0.55, 0.85)
	var mat := _fx_mat(c, false, _soft_texture())
	q.material = mat
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = pos + Vector3(0, 0.03, 0)
	mi.rotation = Vector3(-PI * 0.5, randf() * TAU, 0.0)
	mi.scale = Vector3(0.2, 0.2, 1.0)
	var sx := size * randf_range(0.85, 1.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(sx, sx * randf_range(0.8, 1.1), 1.0), 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(corpse_time + 3.0)
	tw.tween_property(mat, "albedo_color:a", 0.0, 1.5)
	tw.tween_callback(mi.queue_free)


# Goresan tebasan (garis cahaya miring) menghadap kamera
func vfx_slash(pos: Vector3, color: Color = Color(1.0, 0.8, 0.65, 0.95), count: int = 3, length: float = 1.1, tilt_deg: float = -35.0) -> void:
	var cam := get_viewport().get_camera_3d()
	for i in count:
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(length * randf_range(0.8, 1.1), 0.06)
		var mat := _fx_mat(color)
		q.material = mat
		mi.mesh = q
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		get_tree().current_scene.add_child(mi)
		mi.global_position = pos
		if cam and cam.global_position.distance_to(pos) > 0.1:
			mi.look_at(cam.global_position, Vector3.UP)
		mi.rotate_object_local(Vector3(0, 0, 1), deg_to_rad(tilt_deg + randf_range(-6.0, 6.0)))
		mi.translate_object_local(Vector3(0, (float(i) - float(count - 1) * 0.5) * 0.16, 0))
		mi.scale = Vector3(0.1, 1.0, 1.0)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_property(mi, "scale:x", 1.0, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(mat, "albedo_color:a", 0.0, 0.2).set_delay(0.05)
		tw.chain().tween_callback(mi.queue_free)


# Partikel yang terus keluar selama active_time (jejak, gelembung, bintang pusing, dll.)
func vfx_emitter(parent: Node3D, color: Color, amount: int, life: float, active_time: float, size: float = 0.08,
		speed: float = 1.0, dir: Vector3 = Vector3.UP, spread: float = 40.0, offset: Vector3 = Vector3.ZERO) -> CPUParticles3D:
	if parent == null or not is_instance_valid(parent):
		return null
	var p := CPUParticles3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * size
	mesh.material = _fx_mat(color)
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -2.0, 0)
	p.local_coords = false
	p.position = offset
	parent.add_child(p)
	p.emitting = true
	get_tree().create_timer(active_time).timeout.connect(func():
		if is_instance_valid(p):
			p.emitting = false)
	get_tree().create_timer(active_time + life + 0.3).timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())
	return p


# Percik darah di dekat player pas kena serang
func hit_fx(amount: int = 10) -> void:
	if player == null:
		return
	var p := player.global_position - dir_to_player_flat() * 0.5
	burst(p, Color(0.85, 0.08, 0.06), amount, 0.06, 4.5, 0.45)
	burst(p, Color(1.0, 0.85, 0.7), amount / 2, 0.04, 6.0, 0.25)


# Tanda "sekarang bisa di-parry": percik kuning di kepala + kilat
func vfx_cue() -> void:
	if state != State.ACTIVE:
		return
	burst(global_position + Vector3(0, 1.9, 0), Color(1.0, 0.9, 0.35), 8, 0.05, 3.5, 0.3, Vector3.UP, 70.0)
	flash(Color(1.0, 0.85, 0.3), 0.45, 0.2)


# Efek musuh kena parry: ledakan percik emas, cincin, kilat, bintang pusing selama stun
func vfx_parry(stun_time: float = 1.0) -> void:
	var c := global_position + Vector3(0, 1.2, 0)
	burst(c, Color(1.0, 0.85, 0.3), 20, 0.06, 7.0, 0.45, Vector3.UP, 180.0)
	vfx_ring(c, Color(1.0, 0.9, 0.5, 0.95), 1.8, 0.28)
	vfx_light(c, Color(1.0, 0.8, 0.4), 4.0, 0.22, 6.0)
	flash(Color(1.0, 0.95, 0.6), 0.8, 0.25)
	if model:
		vfx_emitter(model, Color(1.0, 0.9, 0.3), 7, 0.5, stun_time, 0.06, 1.0, Vector3.UP, 25.0, Vector3(0, 2.0, 0))
