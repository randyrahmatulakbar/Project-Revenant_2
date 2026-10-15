extends Node
## SFX untuk map: langkah kaki, lompat, mendarat, slide, asap bocor, lampu nyala,
## ambil pistol, puing, ambient, dll.
##
## Pasang sebagai node "MapSfx" di root scene (sudah otomatis masuk group "sfx").
## Script lain tinggal panggil, tanpa perlu referensi node:
##     get_tree().call_group("sfx", "play", "ui_tick")
##     get_tree().call_group("sfx", "play_at", "spawn", posisi)
## File suara ada di res://sfx/ (lihat BANK di bawah).

const SFX_DIR := "res://sfx/"
const BANK := {
	"footstep": ["footstep_1", "footstep_2", "footstep_3", "footstep_4"],
	"jump": ["jump"],
	"land_soft": ["land_soft"],
	"slide": ["slide_loop"],
	"steam": ["steam_leak"],
	"land_impact": ["land_impact"],
	"debris": ["debris_rattle"],
	"lights_on": ["lights_on"],
	"pickup": ["pickup"],
	"drone": ["ambient_drone"],
	"ui_tick": ["ui_tick"],
	"ui_blip": ["ui_blip"],
	"gun_draw": ["gun_draw"],
	"spawn": ["spawn"],
	"wind": ["wind_loop"],
	"gun_shot": ["gun_shot_1", "gun_shot_2", "gun_shot_3"],
	"gun_empty": ["gun_empty"],
	"rev_open": ["rev_open"],
	"rev_eject": ["rev_eject"],
	"rev_shells": ["rev_shells"],
	"rev_load": ["rev_load_1", "rev_load_2", "rev_load_3"],
	"rev_load_all": ["rev_load_all"],
	"rev_close": ["rev_close"],
	"punch_whoosh": ["punch_whoosh_1", "punch_whoosh_2"],
	"punch_hit": ["punch_hit"],
	"parry": ["parry_hit"],
	"punch_swing": ["punch_whoosh_1", "punch_whoosh_2"],
	"enemy_hit": ["enemy_hit"],
	"enemy_death": ["enemy_death"],
	"leap_launch": ["leap_launch"],
	"leap_land": ["leap_land"],
	"claw_slash": ["claw_slash"],
	"spit_charge": ["spit_charge"],
	"spit_shot": ["spit_shot"],
	"glob_splat": ["enemy_hit"],      # dulu belum ada di BANK (dipanggil poison_glob.gd). Ganti ke file splat kalau punya.
}
# Lapisan tambahan biar suara lebih "tebal" (cuma pakai file yang sudah ada, bukan loop).
# Format: [nama_di_BANK, offset_dB, pitch, delay_detik]
const LAYERS := {
	"spawn": [["land_impact", -13.0, 0.55, 0.0], ["debris", -17.0, 1.25, 0.12]],   # bunyi "dug" rendah + gemerincing
	"enemy_death": [["punch_hit", -9.0, 0.65, 0.0], ["land_soft", -7.0, 0.8, 0.35]], # kena + badan jatuh ke lantai
	"parry": [["land_impact", -15.0, 1.4, 0.0], ["enemy_hit", -8.0, 0.9, 0.02]],
	"leap_land": [["land_impact", -10.0, 0.9, 0.0]],
	"enemy_hit": [["punch_hit", -12.0, 0.8, 0.0]],
	"glob_splat": [["land_soft", -6.0, 1.3, 0.0]],
}
# Titik loop (detik) kalau Godot gagal baca loop dari file WAV: [mulai, akhir]. akhir -1 = ujung file.
const LOOPS := {
	"steam_leak": [0.9, -1.0],
	"slide_loop": [0.0, -1.0],
	"ambient_drone": [0.0, -1.0],
	"pistol_shimmer": [0.0, -1.0],
	"wind_loop": [0.0, -1.0],
}
const BUS_NAME := "SFX"

@export_group("Kualitas suara")
@export var layers_enabled := true
@export var reverb_wet := 0.10          # reverb ringan di bus SFX (0 = mati)
@export var reverb_room := 0.45

@export_group("Node (otomatis dicari)")
@export var landing_path: NodePath = ^"../IntroLanding"
@export var pickup_path: NodePath = ^"../PistolPickup"
@export var leak_path: NodePath = ^"../pipeleak/LeakParticles"
@export var shimmer_path: NodePath = ^"../PistolPickup/Shimmer"

@export_group("Volume (dB)")
@export var drone_db := -22.0
@export var step_db := -7.0
@export var steam_db := -3.0
@export var slide_db := -8.0
@export var wind_db := -3.0            # volume angin saat jatuh paling cepat
@export var wind_min_db := -30.0       # volume angin pas baru mulai jatuh
@export var wind_full_speed := 20.0    # kecepatan jatuh (m/s) saat angin paling keras

@export_group("Langkah kaki")
@export var walk_stride := 2.0      # jarak (m) tiap langkah saat jalan
@export var sprint_stride := 2.5
@export var crouch_stride := 1.4

var _cache := {}
var _last_idx := {}
var _player: CharacterBody3D
var _leak: GPUParticles3D
var _steam_player: AudioStreamPlayer3D
var _steam_on := false
var _slide_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _step_acc := 0.0
var _was_on_floor := true
var _air_time := 0.0
var _fall_speed := 0.0


func _ready() -> void:
	add_to_group("sfx")
	await get_tree().process_frame     # tunggu node lain selesai _ready

	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	_leak = get_node_or_null(leak_path) as GPUParticles3D

	var landing := get_node_or_null(landing_path)
	if landing and landing.has_signal("landed"):
		landing.landed.connect(_on_landed)
		_start_wind()

	var pickup := get_node_or_null(pickup_path)
	if pickup and pickup.has_signal("picked_up"):
		pickup.picked_up.connect(_on_picked_up)

	var shimmer := get_node_or_null(shimmer_path) as AudioStreamPlayer3D
	if shimmer and shimmer.stream:
		_ensure_loop(shimmer.stream, "pistol_shimmer")
		shimmer.play()   # mulai ulang biar loop-nya kepakai

	_setup_reverb()
	_start_drone()


# Reverb ringan di bus SFX supaya ruangan terasa luas (cuma ditambah kalau belum ada)
func _setup_reverb() -> void:
	if reverb_wet <= 0.0:
		return
	var idx := AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectReverb:
			return
	var rv := AudioEffectReverb.new()
	rv.room_size = reverb_room
	rv.damping = 0.6
	rv.wet = reverb_wet
	rv.dry = 1.0
	AudioServer.add_bus_effect(idx, rv)


# =========================
# API
# =========================
func play(sfx: String, db: float = 0.0, pitch_var: float = 0.05) -> AudioStreamPlayer:
	var s := _pick(sfx)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.bus = _bus()
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	_play_layers(sfx, db, false, Vector3.ZERO, 40.0)
	return p


func play_at(sfx: String, pos: Vector3, db: float = 0.0, max_dist: float = 40.0, pitch_var: float = 0.06) -> AudioStreamPlayer3D:
	var s := _pick(sfx)
	if s == null:
		return null
	var p := _make_3d(s, pos, db, max_dist, 1.0 + randf_range(-pitch_var, pitch_var))
	_play_layers(sfx, db, true, pos, max_dist)
	return p


func _make_3d(s: AudioStream, pos: Vector3, db: float, max_dist: float, pitch: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.attenuation_filter_cutoff_hz = 6000.0   # makin jauh makin "tumpul", lebih natural
	p.bus = _bus()
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


func _play_layers(sfx: String, db: float, is_3d: bool, pos: Vector3, max_dist: float) -> void:
	if not layers_enabled or not LAYERS.has(sfx):
		return
	for l in LAYERS[sfx]:
		var s := _pick(l[0])
		if s == null:
			continue
		var layer_db: float = db + l[1]
		var pitch: float = l[2] * (1.0 + randf_range(-0.05, 0.05))
		var delay: float = l[3]
		if delay > 0.0:
			await get_tree().create_timer(delay).timeout
		if is_3d:
			_make_3d(s, pos, layer_db, max_dist, pitch)
		else:
			var p := AudioStreamPlayer.new()
			p.stream = s
			p.volume_db = layer_db
			p.pitch_scale = pitch
			p.bus = _bus()
			add_child(p)
			p.finished.connect(p.queue_free)
			p.play()


# =========================
# KEJADIAN INTRO
# =========================
func _on_landed() -> void:
	_stop_wind()
	play("land_impact", 0.0, 0.0)
	await get_tree().create_timer(0.25).timeout
	play("debris", -6.0, 0.0)


func _on_picked_up() -> void:
	play("pickup", -2.0, 0.0)
	play("lights_on", -3.0, 0.0)


func _start_drone() -> void:
	var s := _pick("drone")
	if s == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -60.0
	p.bus = _bus()
	add_child(p)
	p.play()
	create_tween().tween_property(p, "volume_db", drone_db, 4.0)


# =========================
# LOOP / PER-FRAME
# =========================
func _physics_process(delta: float) -> void:
	_watch_steam()
	_watch_player(delta)
	_update_wind()


# Asap bocor: ikut LeakParticles (nyala pas particles nyala, mati pas particles mati)
func _watch_steam() -> void:
	if _leak == null or not is_instance_valid(_leak):
		return
	var on := _leak.emitting
	if on and not _steam_on:
		_steam_on = true
		_start_steam()
	elif not on and _steam_on:
		_steam_on = false
		_stop_steam()


func _start_steam() -> void:
	var s := _pick("steam")
	if s == null:
		return
	if is_instance_valid(_steam_player):
		_steam_player.queue_free()
	_steam_player = AudioStreamPlayer3D.new()
	_steam_player.stream = s
	_steam_player.volume_db = steam_db
	_steam_player.unit_size = 6.0
	_steam_player.max_distance = 45.0
	_steam_player.bus = _bus()
	add_child(_steam_player)
	_steam_player.global_position = _leak.global_position
	_steam_player.play()


func _stop_steam() -> void:
	if not is_instance_valid(_steam_player):
		return
	var p := _steam_player
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -40.0, 0.8)
	tw.tween_callback(p.queue_free)


# Langkah, lompat, mendarat, slide: baca status player tiap frame
func _watch_player(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# kontrol player lagi dikunci (intro landing) -> diam
	if not _player.is_physics_processing():
		_was_on_floor = _player.is_on_floor()
		_step_acc = walk_stride * 0.6
		_air_time = 0.0
		_fall_speed = 0.0
		_set_slide(false)
		return

	var on_floor := _player.is_on_floor()
	var v := _player.velocity
	var flat := Vector2(v.x, v.z).length()
	var sliding: bool = _player.get("is_sliding") == true
	var crouching: bool = _player.get("is_crouching") == true

	# lompat
	if _was_on_floor and not on_floor and v.y > 1.5:
		play("jump", -10.0, 0.06)

	# melayang / mendarat
	if not on_floor:
		_air_time += delta
		_fall_speed = minf(_fall_speed, v.y)
	elif not _was_on_floor:
		if _air_time > 0.2 and _fall_speed < -4.0:
			var db := remap(clampf(_fall_speed, -20.0, -4.0), -4.0, -20.0, -10.0, 0.0)
			play("land_soft", db, 0.06)
		_air_time = 0.0
		_fall_speed = 0.0
	_was_on_floor = on_floor

	# langkah kaki (per jarak tempuh, jadi otomatis ikut cepat/lambat)
	if on_floor and not sliding and flat > 0.8:
		var stride := walk_stride
		var db := step_db
		if crouching:
			stride = crouch_stride
			db -= 9.0
		elif flat > 6.5:
			stride = sprint_stride
			db += 3.0
		_step_acc += flat * delta
		if _step_acc >= stride:
			_step_acc -= stride
			play("footstep", db, 0.08)
	else:
		_step_acc = walk_stride * 0.6   # langkah pertama langsung bunyi pas mulai jalan

	_set_slide(sliding and on_floor)


func _set_slide(on: bool) -> void:
	if on:
		if is_instance_valid(_slide_player):
			return
		var s := _pick("slide")
		if s == null:
			return
		_slide_player = AudioStreamPlayer.new()
		_slide_player.stream = s
		_slide_player.volume_db = -40.0
		_slide_player.bus = _bus()
		add_child(_slide_player)
		_slide_player.play()
		create_tween().tween_property(_slide_player, "volume_db", slide_db, 0.08)
	elif is_instance_valid(_slide_player):
		var p := _slide_player
		_slide_player = null
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -40.0, 0.15)
		tw.tween_callback(p.queue_free)


# =========================
# BANTUAN
# =========================
func _bus() -> StringName:
	return StringName(BUS_NAME) if AudioServer.get_bus_index(BUS_NAME) != -1 else &"Master"


# Ambil 1 suara dari BANK (variasi dipilih acak, tidak kembar dua kali berturut-turut)
func _pick(sfx: String) -> AudioStream:
	if not BANK.has(sfx):
		push_warning("MapSfx: suara '%s' tidak ada di BANK" % sfx)
		return null
	var files: Array = BANK[sfx]
	var idx := 0
	if files.size() > 1:
		idx = randi() % files.size()
		if idx == _last_idx.get(sfx, -1):
			idx = (idx + 1) % files.size()
		_last_idx[sfx] = idx
	var file: String = files[idx]
	if not _cache.has(file):
		var path := SFX_DIR + file + ".wav"
		if ResourceLoader.exists(path):
			_cache[file] = load(path)
			_ensure_loop(_cache[file], file)
		else:
			push_warning("MapSfx: file tidak ketemu: " + path)
			_cache[file] = null
	return _cache[file]


# Kalau loop dari file WAV gak terbaca, set manual dari tabel LOOPS
func _ensure_loop(stream: AudioStream, file: String) -> void:
	if not LOOPS.has(file) or not (stream is AudioStreamWAV):
		return
	var wav := stream as AudioStreamWAV
	if wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		return
	var pts: Array = LOOPS[file]
	var rate := float(wav.mix_rate)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = int(pts[0] * rate)
	wav.loop_end = int(wav.get_length() * rate) if pts[1] < 0.0 else int(pts[1] * rate)
	
# Angin pas jatuh: makin cepat jatuh, makin keras dan makin tinggi nadanya
func _start_wind() -> void:
	var s := _pick("wind")
	if s == null:
		return
	_wind_player = AudioStreamPlayer.new()
	_wind_player.stream = s
	_wind_player.volume_db = wind_min_db
	_wind_player.bus = _bus()
	add_child(_wind_player)
	_wind_player.play()


func _update_wind() -> void:
	if not is_instance_valid(_wind_player) or _player == null or not is_instance_valid(_player):
		return
	var speed := clampf(-_player.velocity.y, 0.0, wind_full_speed)
	_wind_player.volume_db = remap(speed, 0.0, wind_full_speed, wind_min_db, wind_db)
	_wind_player.pitch_scale = remap(speed, 0.0, wind_full_speed, 0.85, 1.1)


func _stop_wind() -> void:
	if not is_instance_valid(_wind_player):
		return
	var p := _wind_player
	_wind_player = null
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, 0.12)
	tw.tween_callback(p.queue_free)
