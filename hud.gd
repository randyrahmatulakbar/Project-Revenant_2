extends CanvasLayer

@onready var health_bar = $Control/HealthContainer/HealthBar
@onready var ammo_label = $Control/AmmoContainer/AmmoLabel
@onready var gun = $FirstPersonGun
@onready var reload_hold = $ReloadHold
@onready var stats = $Stats


const RELOAD_ACTION := "reload"
const HOLD_THRESHOLD := 0.25    # detik; ditahan lebih dari ini = reload hold

var is_busy := false
var player

# --- mode intro (tangan kosong, belum ada senjata) ---
var intro_mode := false
var fist_hud: Node


func _ready():
	player = get_tree().get_first_node_in_group("player")
	gun.play("idle")

	# tiap peluru masuk di animasi -> pindahkan 1 peluru dari cadangan ke magazine
	reload_hold.round_loaded.connect(func(_total): player.load_bullets(1))


# =========================
# SHOOT
# =========================
func play_shoot():
	if intro_mode or is_busy:
		return

	is_busy = true

	if player.current_ammo <= 0:
		gun.stop()
		gun.play("shoot-empty")

		await get_tree().create_timer(0.2).timeout

		gun.stop()
		gun.play("idle")
		is_busy = false
		return

	gun.stop()
	gun.play("shoot")

	await get_tree().create_timer(0.5).timeout

	gun.stop()
	gun.play("idle")
	is_busy = false


# =========================
# RELOAD
# tap   -> animasi "reload" (biasa), diputar penuh sampai selesai
# tahan -> ReloadHold: peluru masuk satu-satu, bisa dibatalkan
# =========================
func play_reload():
	if intro_mode or is_busy:
		return

	is_busy = true

	# hentikan walk/sprint selama deteksi tap/hold
	gun.stop()
	gun.play("idle")

	# dilepas cepat = tap, masih ditahan = hold
	var t := 0.0
	while Input.is_action_pressed(RELOAD_ACTION) and t < HOLD_THRESHOLD:
		await get_tree().process_frame
		t += get_process_delta_time()

	if Input.is_action_pressed(RELOAD_ACTION):
		await _reload_hold()
	else:
		await _reload_tap()

	gun.stop()
	gun.play("idle")
	is_busy = false


# ---- TAP: animasi "reload" penuh, peluru terisi di akhir ----
func _reload_tap():
	var anim := "reload"
	ammo_label.text = "... / " + str(player.reserve_ammo)

	if gun.sprite_frames.has_animation(anim):
		# diputar SEKALI, lalu tunggu sampai benar-benar selesai
		gun.sprite_frames.set_animation_loop(anim, false)
		gun.stop()
		gun.play(anim)
		await gun.animation_finished

	# semua peluru masuk sekaligus di akhir animasi
	player.quick_reload()


# ---- HOLD: peluru masuk satu-satu, bisa dibatalkan ----
func _reload_hold():
	if player.current_ammo >= player.max_ammo_per_clip or player.reserve_ammo <= 0:
		return

	gun.visible = false
	reload_hold.start_with_ammo(player.current_ammo, player.reserve_ammo)

	while reload_hold.is_active():
		if not Input.is_action_pressed(RELOAD_ACTION):
			reload_hold.release()   # dilepas = batal, silinder menutup setelah siklus ini
		await get_tree().process_frame

	gun.visible = true


# =========================
# WALK / SPRINT / IDLE
# =========================
func update_weapon_animation(is_moving: bool, is_sprinting: bool):
	if intro_mode:
		if fist_hud and is_instance_valid(fist_hud):
			fist_hud.update_weapon_animation(is_moving, is_sprinting)
		return

	if is_busy:
		return

	if not is_moving:
		gun.play("idle")

	elif is_sprinting:
		gun.play("sprint")

	else:
		gun.play("walk")


# =========================
# HEALTH
# =========================
func update_health(hp, max_hp):
	$Stats.update_health(hp, max_hp)
	if health_bar:
		health_bar.max_value = max_hp
	health_bar.value = hp


# =========================
# AMMO
# =========================
func update_ammo(ammo, reserve_ammo):
	$Stats.update_ammo(ammo, reserve_ammo)
	if ammo_label:
		ammo_label.text = str(ammo) + " / " + str(reserve_ammo)


# =========================
# MODE INTRO
# =========================
func enter_intro_mode(fist: Node) -> void:
	intro_mode = true
	is_busy = true                       # player-test.gd cek hud.is_busy -> nembak & reload otomatis keblok
	fist_hud = fist
	visible = false                      # semua HUD tempur disembunyiin
	$Crosshairmas.visible = false        # crosshair-nya pakai punya hud_intro


# Dipanggil pas pistol diambil. Pakai: await hud.play_enter_animation()
func play_enter_animation() -> void:
	var gun_pos: Vector2 = gun.position
	var stats_pos: Vector2 = $Stats.position
	var crosshair: Control = $Crosshairmas/crosshair

	# 1. tangan kosong turun keluar layar
	if fist_hud and is_instance_valid(fist_hud):
		var fist: Node2D = fist_hud.get_node("FirstPersonFist")
		var out := create_tween()
		out.tween_property(fist, "position:y", fist.position.y + 380.0, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await out.finished
		fist_hud.queue_free()
		fist_hud = null

	# 2. siapin posisi awal (di luar layar)
	intro_mode = false
	visible = true
	$Crosshairmas.visible = true
	gun.position = gun_pos + Vector2(60, 460)
	gun.rotation = deg_to_rad(22)
	gun.modulate = Color(3, 3, 3, 1)             # kilatan terang pas masuk
	$Stats.position = stats_pos + Vector2(0, 200)
	crosshair.pivot_offset = crosshair.size / 2.0
	crosshair.scale = Vector2(4, 4)
	crosshair.modulate.a = 0.0

	# 3. senjata naik + muter ke posisi, overshoot (mantul dikit)
	var t := create_tween().set_parallel(true)
	t.tween_property(gun, "position", gun_pos, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(gun, "rotation", 0.0, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(gun, "modulate", Color.WHITE, 0.45)

	# 4. panel HP & ammo naik dari bawah, telat dikit
	t.tween_property($Stats, "position", stats_pos, 0.55) \
		.set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 5. crosshair "nge-lock": gede -> kecil
	t.tween_property(crosshair, "scale", Vector2.ONE, 0.35) \
		.set_delay(0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(crosshair, "modulate:a", 1.0, 0.2).set_delay(0.3)

	await t.finished
	gun.play("idle")
	is_busy = false                      # senjata siap dipakai
