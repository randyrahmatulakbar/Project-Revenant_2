extends EnemyBase
## FLAYER: mayat kulit-terkelupas yang kurus. Mendekat lalu menonjok kecil (jab ringan, 2x per serangan).
## Animasi "attack" (0.8 s): jab pertama kena ~0.21 s, jab kedua ~0.45 s.
## PARRY: tiap jab bisa di-parry (tekan F pas jab mau kena) -> serangan batal, musuh kaget (stun).

@export_group("Darah")
@export var hp: float = 15.0            # HP musuh ini. Damage senjata sama untuk semua musuh (revolver 11, tinju 5)

@export_group("Serangan")
@export var attack_range: float = 1.7
@export var jab_damage: float = 3.0
@export var jab_times: Array[float] = [0.21, 0.45]
@export var attack_duration: float = 0.8
@export var attack_cooldown: float = 0.7
@export var knockback: float = 0.0           # >0 bikin player kepental sedikit ke atas juga
@export var walk_anim_speed: float = 2.4     # kecepatan jalan yang cocok sama animasi (m/s)

@export_group("Parry")
@export var parry_lead: float = 0.35         # bisa di-parry sekian detik sebelum jab kena
@export var parry_stun: float = 1.0          # lama musuh kaget setelah di-parry
@export var parry_knockback: float = 3.0     # musuh terdorong mundur
@export var parry_damage: float = 7.5        # damage bonus ke musuh (0 = tanpa damage)
@export var parry_height: float = 1.2        # titik parry di atas kaki musuh

var _attacking := false
var _cooldown := 1.0
var _atk_token := 0          # tiap serangan baru / batal -> token naik, timer lama otomatis diabaikan
var _stunned := false
var _lean_tw: Tween


# Hook dari EnemyBase saat musuh mati
func _ready() -> void:
	max_health = hp                                  # harus sebelum super(): base mengisi health dari max_health
	super()


func _on_died() -> void:
	_atk_token += 1
	_attacking = false
	_set_parryable(false)
	if _lean_tw:
		_lean_tw.kill()
	if model:
		model.rotation.x = 0.0       # jangan bawa miring "kaget" ke animasi mati


func _think(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if player == null:
		stop_h(delta)
		play_anim("idle_loop")
		return

	if _stunned:
		stop_h(delta)
		return

	if _attacking:
		stop_h(delta)
		face_dir(dir_to_player_flat(), delta, 6.0)
		return

	var near := flat_dist() <= attack_range and absf(player.global_position.y - global_position.y) < 3.0
	if near and _cooldown <= 0.0:
		_start_attack()
	elif near:
		stop_h(delta)
		face_dir(dir_to_player_flat(), delta)
		play_anim("idle_loop")
	else:
		var dir := nav_dir_to(player.global_position)
		move_dir(dir, move_speed, delta)
		face_dir(dir, delta)
		play_anim("walk_loop", 0.2, move_speed / walk_anim_speed)


func _start_attack() -> void:
	_attacking = true
	_atk_token += 1
	var tok := _atk_token
	play_anim("attack", 0.08, 1.0, true)
	juice_attack(jab_times, 9.0)                 # ancang-ancang + hentak badan tiap jab
	for t in jab_times:
		after(maxf(t - 0.14, 0.0), func():
			if tok == _atk_token: lunge(2.5))   # melangkah dikit ke depan
		after(maxf(t - 0.12, 0.0), func():
			if tok == _atk_token: sfx_at("punch_swing", -8.0))
		after(maxf(t - parry_lead, 0.0), func():
			if tok == _atk_token:
				_set_parryable(true)
				vfx_cue())                      # tanda: sekarang bisa di-parry
		after(maxf(t - 0.04, 0.0), func():
			if tok == _atk_token:                # garis ayunan tinju
				vfx_slash(global_position + (-global_transform.basis.z) * 1.0 + Vector3(0, 1.2, 0), Color(1.0, 0.85, 0.75, 0.9), 1, 0.9, randf_range(-25.0, 25.0)))
		after(t + 0.05, func():
			if tok == _atk_token: _set_parryable(false))
		after(t, func():
			if tok == _atk_token: _jab())
	after(attack_duration, func():
		if tok == _atk_token:
			_set_parryable(false)
			_attacking = false
			_cooldown = attack_cooldown)


func _jab() -> void:
	if player == null:
		return
	var in_front := dir_to_player_flat().dot(-global_transform.basis.z) > 0.2
	if flat_dist() <= attack_range + 0.5 and in_front:
		hurt_player(jab_damage, knockback)
		sfx_at("punch_hit", -6.0)


# ---------- PARRY ----------
func _set_parryable(on: bool) -> void:
	if on and not is_in_group("parryable"):
		add_to_group("parryable")
	elif not on and is_in_group("parryable"):
		remove_from_group("parryable")


## Titik yang dihitung parry.gd (badan, bukan kaki)
func parry_point() -> Vector3:
	return global_position + Vector3(0.0, parry_height, 0.0)


## Dipanggil parry.gd kalau parry berhasil
func parried(_by) -> void:
	if state != State.ACTIVE or not _attacking:
		return
	_atk_token += 1                     # batalin sisa jab
	kill_juice()
	_attacking = false
	_stunned = true
	_set_parryable(false)
	play_anim("idle_loop", 0.05)
	vfx_parry(parry_stun)
	sfx_at("enemy_hit", -2.0)
	velocity += -dir_to_player_flat() * parry_knockback
	_stagger_lean()
	if parry_damage > 0.0 and has_method("take_damage"):
		call("take_damage", parry_damage)
	after(parry_stun, func():
		if state == State.ACTIVE:
			_stunned = false
			_cooldown = attack_cooldown)


func _stagger_lean() -> void:
	if model == null:
		return
	if _lean_tw:
		_lean_tw.kill()
	_lean_tw = create_tween()
	_lean_tw.tween_property(model, "rotation:x", deg_to_rad(-22.0), 0.08)
	_lean_tw.tween_interval(maxf(parry_stun - 0.4, 0.1))
	_lean_tw.tween_property(model, "rotation:x", 0.0, 0.3)
