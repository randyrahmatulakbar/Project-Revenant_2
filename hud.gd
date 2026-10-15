extends CanvasLayer

@onready var health_bar = $Control/HealthContainer/HealthBar
@onready var ammo_label = $Control/AmmoContainer/AmmoLabel
@onready var gun = $FirstPersonGun
@onready var reload_hold = $ReloadHold
@onready var stats = $Stats

const LightTint := preload("res://hud_light_tint.gd")


const RELOAD_ACTION := "reload"
const HOLD_THRESHOLD := 0.25    # detik; ditahan lebih dari ini = reload hold

# Jadwal suara reload tap, dalam PERSEN panjang animasi "reload" (0.0 - 1.0)
const RELOAD_TAP_CUES := [
	[0.10, "rev_open", -4.0],
	[0.25, "rev_eject", -4.0],
	[0.38, "rev_shells", -8.0],
	[0.60, "rev_load_all", -3.0],
	[0.85, "rev_close", -3.0],
]

var is_busy := false
var player

# --- mode intro (tangan kosong, belum ada senjata) ---
var intro_mode := false
var fist_hud: Node

# --- tangan kiri (mukul / parry, tombol F) ---
const FIST_SHEET := "res://tangan/fist_all.png"
const FIST_FRAME := Vector2i(640, 270)
const FIST_CROP_W := 405             # ambil bagian kiri frame saja (tangan kiri)
const LEFT_PUNCH_ROW := 4
const LEFT_PARRY_ROW := 6
const LEFT_HAND_FPS := 26.0
const LEFT_HAND_SCALE := 1.41        # sama dengan tangan di hud_intro
const LEFT_HAND_MARGIN := 24.0
var left_hand: AnimatedSprite2D
var _left_token := 0
var _left_tween: Tween
var _left_base := Vector2.ZERO
var _left_exiting := false
var _flash_rect: ColorRect


func _ready():
	player = get_tree().get_first_node_in_group("player")
	gun.play("idle")

	# senjata ikut gelap/terang sesuai cahaya di sekitar player
	var tint = LightTint.new()
	tint.target = gun
	add_child(tint)

	# tiap peluru masuk di animasi -> pindahkan 1 peluru dari cadangan ke magazine
	reload_hold.round_loaded.connect(func(_total):
		player.load_bullets(1)
		get_tree().call_group("sfx", "play", "rev_load", -3.0, 0.05))
	
	_build_left_hand()
	_build_parry_fx()


# =========================
# SHOOT
# =========================
func play_shoot():
	if intro_mode or is_busy:
		return

	is_busy = true

	if player.current_ammo <= 0:
		get_tree().call_group("sfx", "play", "gun_empty", -4.0, 0.03)
		gun.stop()
		gun.play("shoot-empty")

		await get_tree().create_timer(0.2).timeout

		gun.stop()
		gun.play("idle")
		is_busy = false
		return

	get_tree().call_group("sfx", "play", "gun_shot", -2.0, 0.04)
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
		var length := _anim_length(anim)
		for cue in RELOAD_TAP_CUES:
			_cue(cue[1], cue[2], cue[0] * length)
		await gun.animation_finished

	# semua peluru masuk sekaligus di akhir animasi
	player.quick_reload()
	
func _anim_length(anim: String) -> float:
	var frames: SpriteFrames = gun.sprite_frames
	var total := 0.0
	for i in frames.get_frame_count(anim):
		total += frames.get_frame_duration(anim, i)
	return total / (frames.get_animation_speed(anim) * float(gun.speed_scale))


func _cue(sfx: String, db: float, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_busy:
		get_tree().call_group("sfx", "play", sfx, db, 0.03)


# ---- HOLD: peluru masuk satu-satu, bisa dibatalkan ----
func _reload_hold():
	if player.current_ammo >= player.max_ammo_per_clip or player.reserve_ammo <= 0:
		return

	gun.visible = false
	reload_hold.start_with_ammo(player.current_ammo, player.reserve_ammo)
	get_tree().call_group("sfx", "play", "rev_open", -4.0, 0.03)
	get_tree().call_group("sfx", "play", "rev_eject", -4.0, 0.03)

	while reload_hold.is_active():
		if not Input.is_action_pressed(RELOAD_ACTION):
			reload_hold.release()   # dilepas = batal, silinder menutup setelah siklus ini
		await get_tree().process_frame
	
	get_tree().call_group("sfx", "play", "rev_close", -3.0, 0.03)

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
# Gaya "boot-up": HP naik + panel nyala, ammo keisi satu-satu,
# senjata kedip-kedip nyala, crosshair nge-lock.
func play_enter_animation() -> void:
	var stats = $Stats
	var snap: Dictionary = stats.snapshot()
	var gun_pos: Vector2 = gun.position
	var crosshair: Control = $Crosshairmas/crosshair

	# 1. tangan kosong turun keluar layar
	if fist_hud and is_instance_valid(fist_hud):
		var fist: Node2D = fist_hud.get_node("FirstPersonFist")
		var out := create_tween()
		out.tween_property(fist, "position:y", fist.position.y + 380.0, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		await out.finished
		fist_hud.queue_free()
		fist_hud = null

	# 2. siapin: semua elemen HUD tempur masih "mati"
	var max_hp: int = snap.max_hp
	var start_hp := int(max_hp * 0.55)
	intro_mode = false
	visible = true
	$Crosshairmas.visible = false
	gun.visible = false
	stats.boot_prepare(start_hp, max_hp, snap.reserve)

	# 3. HP: panel nyala (kilatan putih) + angka naik dari 55%
	stats._hp_flash = 1.0
	get_tree().call_group("sfx", "play", "ui_blip", -6.0)
	var t_hp := create_tween().set_parallel(true)
	t_hp.tween_method(func(v: float): stats.hp_reveal = v, 0.0, 1.0, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t_hp.tween_method(func(v: float): stats.update_health(int(v), max_hp),
		float(start_hp), float(snap.hp), 0.8).set_ease(Tween.EASE_OUT)

	# 4. AMMO: panel nyala, kotak peluru keisi satu-satu
	await get_tree().create_timer(0.3).timeout
	var total: int = snap.ammo
	stats.update_ammo(mini(1, total), snap.reserve)
	stats._ammo_flash = 1.0
	get_tree().call_group("sfx", "play", "ui_tick", -8.0)
	create_tween().tween_method(func(v: float): stats.ammo_reveal = v, 0.0, 1.0, 0.2) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in range(2, total + 1):
		await get_tree().create_timer(0.07).timeout
		stats.update_ammo(i, snap.reserve)
		get_tree().call_group("sfx", "play", "ui_tick", -8.0)

	# 5. SENJATA: naik dari bawah layar, sama kayak tangan
	await get_tree().create_timer(0.12).timeout
	var screen_h := get_viewport().get_visible_rect().size.y
	var gun_h := 300.0
	var tex: Texture2D = gun.sprite_frames.get_frame_texture("idle", 0)
	if tex:
		gun_h = tex.get_height() * gun.scale.y
	# mulai sepenuhnya di bawah tepi layar
	var from_y := maxf(360.0, screen_h - gun_pos.y + gun_h * 0.5 + 20.0)
	gun.modulate = Color.WHITE
	gun.position = gun_pos + Vector2(0, from_y)
	gun.visible = true
	get_tree().call_group("sfx", "play", "gun_draw", -4.0)
	var t_gun := create_tween()
	# naik cepat di awal lalu melambat, agak kebablasan ke atas
	t_gun.tween_property(gun, "position", gun_pos + Vector2(0, -16), 1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# turun pelan ke posisi diam
	t_gun.tween_property(gun, "position", gun_pos, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 6. CROSSHAIR: muncul pas senjata hampir sampai, gede lalu "nge-lock"
	$Crosshairmas.visible = true
	crosshair.pivot_offset = crosshair.size / 2.0
	crosshair.scale = Vector2(3, 3)
	crosshair.modulate = Color(2, 2, 2, 0)
	var t_ch := create_tween().set_parallel(true)
	t_ch.tween_property(crosshair, "scale", Vector2.ONE, 0.3).set_delay(0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t_ch.tween_property(crosshair, "modulate", Color.WHITE, 0.3).set_delay(0.6)

	await t_gun.finished
	gun.play("idle")
	is_busy = false    
	
# Dipanggil TitleCard saat judul hilang: crosshair muncul dengan animasi "lock"
func show_crosshair() -> void:
	var crosshair: Control = $Crosshairmas/crosshair
	$Crosshairmas.visible = true
	crosshair.pivot_offset = crosshair.size / 2.0
	crosshair.scale = Vector2(4, 4)
	crosshair.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(crosshair, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(crosshair, "modulate:a", 1.0, 0.2)                  # senjata siap dipakai

# =========================
# TANGAN KIRI (dipanggil parry.gd)
# =========================
func _build_left_hand() -> void:
	var sheet: Texture2D = load(FIST_SHEET)
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_row(frames, "punch", sheet, LEFT_PUNCH_ROW, 9)
	_add_row(frames, "parry", sheet, LEFT_PARRY_ROW, 8)

	left_hand = AnimatedSprite2D.new()
	left_hand.sprite_frames = frames
	left_hand.scale = Vector2(LEFT_HAND_SCALE, LEFT_HAND_SCALE)
	left_hand.offset = Vector2(-(FIST_FRAME.x - FIST_CROP_W) / 2.0, 0)   # posisi sama kayak frame asli
	left_hand.visible = false
	add_child(left_hand)
	move_child(left_hand, stats.get_index())      # di bawah panel HP/ammo

	var tint = LightTint.new()
	tint.target = left_hand
	add_child(tint)

	_fit_left_hand()
	get_viewport().size_changed.connect(_fit_left_hand)


func _add_row(frames: SpriteFrames, anim: String, sheet: Texture2D, row: int, count: int) -> void:
	frames.add_animation(anim)
	frames.set_animation_speed(anim, LEFT_HAND_FPS)
	frames.set_animation_loop(anim, false)
	for c in count:
		var tex := AtlasTexture.new()
		tex.atlas = sheet
		tex.region = Rect2(c * FIST_FRAME.x, row * FIST_FRAME.y, FIST_CROP_W, FIST_FRAME.y)
		frames.add_frame(anim, tex)


func _fit_left_hand() -> void:
	if left_hand == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var half_h := FIST_FRAME.y * LEFT_HAND_SCALE * 0.5
	_left_base = Vector2(screen.x * 0.5, screen.y - half_h + LEFT_HAND_MARGIN)
	if not left_hand.visible:
		left_hand.position = _left_base


# anim: "punch" atau "parry"
func play_left_hand(anim: String, start_frame: int = 0) -> void:
	if left_hand == null or intro_mode:
		return
	_left_token += 1
	var my := _left_token
	if _left_tween:
		_left_tween.kill()

	var fresh := not left_hand.visible or _left_exiting
	_left_exiting = false
	if fresh:                                   # naik dari bawah-kiri, bukan muncul mendadak
		left_hand.visible = true
		left_hand.self_modulate = Color(1, 1, 1, 0)
		left_hand.position = _left_base + Vector2(-30, 70)
		left_hand.rotation = deg_to_rad(-6.0)
		_left_tween = create_tween().set_parallel(true)
		_left_tween.tween_property(left_hand, "self_modulate:a", 1.0, 0.05)
		_left_tween.tween_property(left_hand, "position", _left_base, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_left_tween.tween_property(left_hand, "rotation", 0.0, 0.12)

	left_hand.play(anim)
	if start_frame > 0:
		left_hand.set_frame_and_progress(start_frame, 0.0)   # mulai dari pose tangan terangkat
	await left_hand.animation_finished
	if my != _left_token:
		return

	_left_exiting = true                        # turun halus, lalu hilang
	_left_tween = create_tween().set_parallel(true)
	_left_tween.tween_property(left_hand, "position", _left_base + Vector2(-20, 90), 0.1) \
		.set_ease(Tween.EASE_IN)
	_left_tween.tween_property(left_hand, "self_modulate:a", 0.0, 0.1)
	await _left_tween.finished
	if my == _left_token:
		left_hand.visible = false
		_left_exiting = false


func flash_left_hand(freeze: float = 0.1) -> void:
	if left_hand == null:
		return
	left_hand.self_modulate = Color(4, 4, 4, 1)      # tangan jadi siluet putih
	var t := create_tween()
	t.set_ignore_time_scale(true)
	t.tween_interval(freeze)
	t.tween_property(left_hand, "self_modulate", Color.WHITE, 0.25)


# =========================
# EFEK PARRY (flash putih + freeze frame)
# =========================
func _build_parry_fx() -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color.WHITE
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.modulate.a = 0.0
	add_child(_flash_rect)
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


# Flash putih: ditahan selama freeze, lalu memudar. Dipanggil parry.gd
func parry_fx(freeze: float) -> void:
	_flash_rect.modulate.a = 0.65
	var tf := create_tween()
	tf.set_ignore_time_scale(true)
	tf.tween_interval(freeze)
	tf.tween_property(_flash_rect, "modulate:a", 0.0, 0.25)
