extends EnemyBase
## SPITTER: penyembur racun. Menjaga jarak, berhenti, lalu menembakkan bola racun dari node "muzzle".
## Animasi "spit" (1.3 s): racun keluar di ~0.58 s.

enum Mode { MOVE, SPIT }

@export var glob_scene: PackedScene           # poison_glob.tscn

@export_group("Darah")
@export var hp: float = 20.0                   # HP musuh ini. Damage senjata sama untuk semua musuh (revolver 11, tinju 5)

@export_group("Jarak")
@export var preferred_min: float = 6.0        # lebih dekat dari ini -> mundur
@export var preferred_max: float = 15.0       # lebih jauh dari ini / gak kelihatan -> maju

@export_group("Tembakan")
@export var spit_cooldown: float = 2.4
@export var fire_time: float = 0.58
@export var glob_speed: float = 14.0
@export var glob_damage: float = 8.0
@export var poison_dps: float = 3.0
@export var poison_time: float = 3.0
@export var aim_height: float = 0.2           # sasaran di atas pusat badan player

var mode: Mode = Mode.MOVE
var _cd: float = 1.2
var _aiming := false


func _ready() -> void:
	max_health = hp                                  # harus sebelum super(): base mengisi health dari max_health
	super()                                          # WAJIB: jalankan _ready milik EnemyBase dulu
	if gore_color.is_equal_approx(Color(0.75, 0.05, 0.05)):
		gore_color = Color(0.45, 0.85, 0.12)         # darah hijau racun


func _on_died() -> void:
	burst(global_position + Vector3(0, 1.0, 0), Color(0.5, 0.95, 0.15), 26, 0.09, 5.0, 1.0)    # kantung racun pecah


func _on_spawned() -> void:
	_cd = 1.0


func _think(delta: float) -> void:
	_cd = maxf(0.0, _cd - delta)
	if player == null:
		stop_h(delta)
		play_anim("idle_loop")
		return

	if mode == Mode.SPIT:
		stop_h(delta)
		if _aiming:
			face_dir(dir_to_player_flat(), delta, 12.0)
		return

	var d := flat_dist()
	var sees := can_see_player(preferred_max + 4.0)

	if sees and d <= preferred_max and d >= preferred_min * 0.6 and _cd <= 0.0:
		_start_spit()
	elif not sees or d > preferred_max:
		var dir := nav_dir_to(player.global_position)
		move_dir(dir, move_speed, delta)
		face_dir(dir, delta)
		play_anim("walk_loop", 0.2, move_speed / 3.0)
	elif d < preferred_min:
		var away := -dir_to_player_flat()
		move_dir(away, move_speed * 0.8, delta)
		face_dir(dir_to_player_flat(), delta)
		play_anim("walk_loop", 0.2, -0.8)              # jalan mundur
	else:
		stop_h(delta)
		face_dir(dir_to_player_flat(), delta)
		play_anim("idle_loop")


func _start_spit() -> void:
	mode = Mode.SPIT
	_aiming = true
	play_anim("spit", 0.1, 1.0, true)
	juice_attack([fire_time], 14.0)                 # condong ke belakang lalu menyembur ke depan
	sfx_at("spit_charge", -2.0)
	var muzzle_n := model.find_child("muzzle", true, false) as Node3D if model else null
	vfx_emitter(muzzle_n if muzzle_n else self, Color(0.5, 1.0, 0.15, 0.9), 16, 0.45, fire_time, 0.07, 0.8, Vector3.UP, 180.0,
			Vector3.ZERO if muzzle_n else Vector3(0, 1.4, 0))                # gelembung racun ngumpul
	after(fire_time, _fire)
	after(1.3, func():
		mode = Mode.MOVE
		_cd = spit_cooldown)


func _fire() -> void:
	_aiming = false
	if glob_scene == null or player == null:
		push_warning("Spitter: Glob Scene belum diisi di Inspector (poison_glob.tscn)")
		return
	var g := glob_scene.instantiate()
	get_tree().current_scene.add_child(g)
	var muzzle := model.find_child("muzzle", true, false) as Node3D if model else null
	g.global_position = muzzle.global_position if muzzle else global_position + Vector3(0, 1.4, 0)
	var target := player.global_position + Vector3(0, aim_height, 0)
	g.call("launch", target, glob_speed, self, glob_damage, poison_dps, poison_time)
	sfx_at("spit_shot", -1.0)
	burst(g.global_position, Color(0.5, 1.0, 0.15), 16, 0.07, 5.0, 0.5, Vector3.UP, 120.0)     # muncratan pas nembak
	vfx_light(g.global_position, Color(0.5, 1.0, 0.2), 2.5, 0.2, 5.0)
	flinch(0.15)                                    # hentakan balik pas menyembur
