extends EnemyBase
## LEAPER: pelompat. Mengejar cepat, lalu melompat menerkam dari jauh. Kalau udah dekat, mencakar.
## Animasi "leap" (1.25 s): lepas landas di ~0.40 s. Animasi "attack" (0.8 s): cakar kena ~0.28 s.
## PARRY: cakar bisa di-parry, dan terkaman di udara juga bisa di-parry (musuh jatuh & stun, tanpa damage ke player).

enum Mode { CHASE, WINDUP, AIR, LAND, CLAW, STUN }

@export_group("Darah")
@export var hp: float = 11.0            # HP musuh ini. Damage senjata sama untuk semua musuh (revolver 11, tinju 5)

@export_group("Lompat")
@export var leap_min_range: float = 4.0
@export var leap_max_range: float = 13.0
@export var leap_time: float = 0.5            # lama di udara
@export var leap_takeoff: float = 0.40        # detik dari awal animasi "leap"
@export var leap_cooldown: float = 2.8
@export var leap_damage: float = 14.0
@export var leap_hit_radius: float = 2.4
@export var leap_lead: float = 0.6            # seberapa jauh nembak ke depan gerakan player (0..1)
@export var player_center_height: float = 1.0 # jarak pusat badan player ke kakinya

@export_group("Cakar")
@export var claw_range: float = 2.0
@export var claw_damage: float = 9.0
@export var claw_hit_time: float = 0.28
@export var knockback: float = 4.0

@export_group("Parry")
@export var parry_lead: float = 0.35          # cakar bisa di-parry sekian detik sebelum kena
@export var parry_stun: float = 1.3
@export var parry_knockback: float = 5.0
@export var parry_damage: float = 7.5        # cakar: 2x parry. Parry pas di udara = x1.5 (11.25) -> 1x parry
@export var parry_height: float = 0.9

var mode: Mode = Mode.CHASE
var _leap_cd: float = 1.5
var _air_t: float = 0.0
var _atk_token := 0
var _lean_tw: Tween
var _squash_tw: Tween


# Hook dari EnemyBase saat musuh mati
func _ready() -> void:
	max_health = hp                                  # harus sebelum super(): base mengisi health dari max_health
	super()


func _on_died() -> void:
	_atk_token += 1
	_set_parryable(false)
	if _lean_tw:
		_lean_tw.kill()
	if _squash_tw:
		_squash_tw.kill()
	if model:
		model.rotation.x = 0.0       # jangan bawa miring "kaget" ke animasi mati
		model.scale = Vector3.ONE


func _on_spawned() -> void:
	_leap_cd = 1.0


func _think(delta: float) -> void:
	_leap_cd = maxf(0.0, _leap_cd - delta)
	if player == null:
		stop_h(delta)
		play_anim("idle_loop")
		return

	match mode:
		Mode.CHASE:
			var near := flat_dist() <= claw_range and absf(player.global_position.y - global_position.y) < 3.0
			if near:
				_start_claw()
			elif _leap_cd <= 0.0 and flat_dist() >= leap_min_range and flat_dist() <= leap_max_range \
					and can_see_player(leap_max_range + 3.0):
				_start_leap()
			else:
				var dir := nav_dir_to(player.global_position)
				move_dir(dir, move_speed, delta)
				face_dir(dir, delta)
				play_anim("walk_loop", 0.2, move_speed / 5.0)
		Mode.WINDUP:
			stop_h(delta)
			face_dir(dir_to_player_flat(), delta, 14.0)
		Mode.AIR:
			_air_t += delta
			face_dir(Vector3(velocity.x, 0.0, velocity.z), delta, 12.0)
			if (_air_t > 0.12 and is_on_floor()) or _air_t > 1.6:
				_land()
		Mode.LAND:
			stop_h(delta)
		Mode.CLAW:
			stop_h(delta)
			face_dir(dir_to_player_flat(), delta, 10.0)
		Mode.STUN:
			stop_h(delta)


# ---------- LOMPAT ----------
func _start_leap() -> void:
	mode = Mode.WINDUP
	_atk_token += 1
	var tok := _atk_token
	play_anim("leap", 0.1, 1.0, true)
	_squash(Vector3(1.14, 0.78, 1.14), leap_takeoff * 0.9, Tween.TRANS_QUAD, Tween.EASE_OUT)   # jongkok ancang-ancang
	after(leap_takeoff, func():
		if tok == _atk_token: _takeoff())


func _takeoff() -> void:
	if mode != Mode.WINDUP or player == null:
		return
	var target := player.global_position
	target.y -= player_center_height
	if "velocity" in player:
		target += Vector3(player.velocity.x, 0.0, player.velocity.z) * leap_time * leap_lead
	var flat := target - global_position
	flat.y = 0.0
	target -= flat.normalized() * 0.8                       # mendarat sedikit sebelum player
	var dp := target - global_position
	var g := get_gravity().length()
	var v := Vector3(dp.x / leap_time, dp.y / leap_time + 0.5 * g * leap_time, dp.z / leap_time)
	var hv := Vector2(v.x, v.z)
	if hv.length() > 20.0:
		hv = hv.normalized() * 20.0
	velocity = Vector3(hv.x, v.y, hv.y)
	mode = Mode.AIR
	_air_t = 0.0
	_set_parryable(true)                                     # selama di udara bisa di-parry
	burst(global_position + Vector3(0, 0.1, 0), Color(0.55, 0.5, 0.45), 14, 0.12, 3.5, 0.6)          # debu pas lepas landas
	vfx_ring(global_position + Vector3(0, 0.08, 0), Color(0.7, 0.65, 0.55, 0.8), 1.6, 0.3)
	vfx_emitter(self, Color(1.0, 0.3, 0.18, 0.9), 26, 0.45, leap_time + 0.3, 0.1, 0.6, Vector3.UP, 180.0, Vector3(0, 0.9, 0))   # jejak saat melayang
	vfx_cue()
	_squash(Vector3(0.88, 1.18, 0.88), 0.08, Tween.TRANS_QUAD, Tween.EASE_OUT, Vector3.ONE, 0.4)   # badan memanjang pas melesat
	sfx_at("leap_launch", -1.0)


func _land() -> void:
	mode = Mode.LAND
	_set_parryable(false)
	var tok := _atk_token
	velocity.x = 0.0
	velocity.z = 0.0
	_leap_cd = leap_cooldown
	sfx_at("leap_land", 0.0)
	_squash(Vector3(1.22, 0.72, 1.22), 0.05, Tween.TRANS_QUAD, Tween.EASE_OUT, Vector3.ONE, 0.3)   # penyet pas mendarat
	burst(global_position + Vector3(0, 0.15, 0), Color(0.55, 0.5, 0.45), 28, 0.14, 4.0, 0.8)
	burst(global_position + Vector3(0, 0.1, 0), Color(0.45, 0.4, 0.35), 12, 0.1, 6.0, 0.7, Vector3.UP, 30.0)
	vfx_ring(global_position + Vector3(0, 0.08, 0), Color(0.8, 0.7, 0.55, 0.9), 3.6, 0.45)
	vfx_light(global_position + Vector3(0, 0.5, 0), Color(1.0, 0.6, 0.3), 2.0, 0.2, 5.0)
	if flat_dist() <= leap_hit_radius and absf(player.global_position.y - global_position.y) < 3.0:
		hurt_player(leap_damage, knockback * 1.5)
		sfx_at("punch_hit", -1.0)
	after(0.45, func():
		if tok == _atk_token and mode == Mode.LAND:
			mode = Mode.CHASE)


# ---------- CAKAR ----------
func _start_claw() -> void:
	mode = Mode.CLAW
	_atk_token += 1
	var tok := _atk_token
	play_anim("attack", 0.08, 1.0, true)
	juice_attack([claw_hit_time], 13.0)
	after(maxf(claw_hit_time - 0.14, 0.0), func():
		if tok == _atk_token: lunge(3.5))
	after(claw_hit_time - 0.12, func():
		if tok == _atk_token: sfx_at("claw_slash", -3.0))
	after(maxf(claw_hit_time - parry_lead, 0.0), func():
		if tok == _atk_token:
			_set_parryable(true)
			vfx_cue())
	after(maxf(claw_hit_time - 0.04, 0.0), func():
		if tok == _atk_token:                  # 3 goresan cakar
			vfx_slash(global_position + (-global_transform.basis.z) * 1.1 + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.35, 0.95), 3, 1.2, -40.0))
	after(claw_hit_time + 0.05, func():
		if tok == _atk_token: _set_parryable(false))
	after(claw_hit_time, func():
		if tok == _atk_token: _claw_hit())
	after(0.8, func():
		if tok == _atk_token and mode == Mode.CLAW:
			_set_parryable(false)
			mode = Mode.CHASE
			_leap_cd = maxf(_leap_cd, 0.8))


func _claw_hit() -> void:
	if mode != Mode.CLAW or player == null:
		return
	var in_front := dir_to_player_flat().dot(-global_transform.basis.z) > 0.2
	if flat_dist() <= claw_range + 0.7 and in_front:
		hurt_player(claw_damage, knockback)
		sfx_at("punch_hit", -2.0)


# ---------- PARRY ----------
func _set_parryable(on: bool) -> void:
	if on and not is_in_group("parryable"):
		add_to_group("parryable")
	elif not on and is_in_group("parryable"):
		remove_from_group("parryable")


func parry_point() -> Vector3:
	return global_position + Vector3(0.0, parry_height, 0.0)


func parried(_by) -> void:
	if state != State.ACTIVE or (mode != Mode.CLAW and mode != Mode.AIR):
		return
	var was_air := mode == Mode.AIR
	vfx_parry(parry_stun)
	_atk_token += 1                      # batalin sisa timer cakar / lompatan
	kill_juice()
	_squash(Vector3.ONE, 0.15, Tween.TRANS_QUAD, Tween.EASE_OUT)
	var tok := _atk_token
	mode = Mode.STUN
	_set_parryable(false)
	_leap_cd = leap_cooldown
	sfx_at("enemy_hit", -2.0)
	var back := -dir_to_player_flat()
	if was_air:
		velocity = Vector3(back.x * parry_knockback, 3.0, back.z * parry_knockback)   # terpental di udara, jatuh sendiri
	else:
		play_anim("idle_loop", 0.05)
		velocity += back * parry_knockback
		_stagger_lean()
	if parry_damage > 0.0 and has_method("take_damage"):
		call("take_damage", parry_damage * (1.5 if was_air else 1.0))
	after(parry_stun, func():
		if tok == _atk_token and state == State.ACTIVE and mode == Mode.STUN:
			mode = Mode.CHASE)


# Penyet / memanjang. Kalau back_to diisi: setelah sampai ke target, balik ke back_to selama back_time.
func _squash(target: Vector3, time: float, trans: Tween.TransitionType, ease_type: Tween.EaseType, back_to: Vector3 = Vector3.ZERO, back_time: float = 0.0) -> void:
	if model == null:
		return
	if _squash_tw:
		_squash_tw.kill()
	_squash_tw = create_tween()
	_squash_tw.tween_property(model, "scale", target, time).set_trans(trans).set_ease(ease_type)
	if back_time > 0.0:
		_squash_tw.tween_property(model, "scale", back_to, back_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _stagger_lean() -> void:
	if model == null:
		return
	if _lean_tw:
		_lean_tw.kill()
	_lean_tw = create_tween()
	_lean_tw.tween_property(model, "rotation:x", deg_to_rad(-22.0), 0.08)
	_lean_tw.tween_interval(maxf(parry_stun - 0.4, 0.1))
	_lean_tw.tween_property(model, "rotation:x", 0.0, 0.3)
