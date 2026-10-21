extends Node
## Musik + suasana dinamis:
##   ambil pistol       -> lagu "drop" masuk, ditambah lapisan creepy (drone, bisikan, riser) dan
##                         layar ikut "bernapas": vinyet merah berdenyut mengikuti dentuman bass lagu
##   semua wave selesai -> SLOW-MOTION sesaat (kill terakhir), lalu crossfade ke lagu "clear"
## Pasang: tambahkan Node baru bernama MusicDirector di intro.tscn, pasang script ini. Selesai.
## (Script mencari PistolPickup dan EnemySpawner sendiri lewat nama node.)
## Saat game di-pause (menu pause / death screen) musik diredam otomatis.

@export_file("*.ogg", "*.wav", "*.mp3") var drop_path: String = "res://music/drop_loop.ogg"
@export_file("*.ogg", "*.wav", "*.mp3") var clear_path: String = "res://music/clear_loop.ogg"
@export_file("*.ogg", "*.wav", "*.mp3") var creep_path: String = "res://music/creep_layer.ogg"
@export var pickup_node_name: String = "PistolPickup"
@export var spawner_node_name: String = "EnemySpawner"
@export_group("Musik")
@export var volume_db: float = -4.0
@export var creep_db: float = -6.0
@export var drop_fade_in: float = 3.5
@export var crossfade: float = 2.5
@export var pause_duck_db: float = 10.0
@export var bus: StringName = &"Music"           # kalau bus ini tidak ada, pakai Master
@export_group("Suasana saat action")
@export var pulse_effect: bool = true
@export_range(0.0, 1.0) var pulse_strength: float = 0.7
@export_group("Slow-motion akhir")
@export var slowmo_enabled: bool = true
@export var slowmo_scale: float = 0.12            # kecepatan game saat slow-mo
@export var slowmo_hold: float = 1.1              # detik (waktu nyata) tertahan
@export var slowmo_return: float = 0.9            # detik balik ke normal

const PICKUP_SIGNALS := ["picked_up", "collected", "taken", "pickup", "pickedup", "interacted", "obtained"]
const FX_BUS := &"MusicFX"

const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity = 0.0;   // 0..1 seberapa 'creepy' (action)
uniform float kick = 0.0;        // 0..1 denyut bass
uniform float zoom = 0.0;
uniform float desat = 0.0;
uniform float flash = 0.0;
float hash(float x) { return fract(sin(x * 91.3458) * 47453.5453); }
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	vec2 uv = 0.5 + c * (1.0 - zoom - kick * 0.012 * intensity);
	float ca = (0.0006 + 0.0032 * kick) * intensity + zoom * 0.02;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), clamp(desat + intensity * 0.18, 0.0, 1.0));
	float vig = smoothstep(0.28, 0.85, length(c));
	vec3 tint = col * vec3(1.0, 0.28, 0.24) * 0.55;
	col = mix(col, tint, clamp(vig * (0.3 + 0.7 * kick) * intensity, 0.0, 1.0));
	float fl = step(0.965, hash(floor(TIME * 9.0)));
	col *= 1.0 - fl * 0.07 * intensity;
	col += vec3(flash);
	COLOR = vec4(col, 1.0);
}
"""

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _c: AudioStreamPlayer
var _state := 0                                   # 0 sunyi, 1 drop, 2 clear
var _duck := 0.0
var _va := -80.0                                  # volume dasar (sebelum diredam), di-tween
var _vb := -80.0
var _vc := -80.0

var _fx_mat: ShaderMaterial
var _fx_rect: ColorRect
var _analyzer: AudioEffectInstance
var _peak := 0.001
var _kick := 0.0
var _intensity := 0.0:
	set(v):
		_intensity = v
		_set_fx("intensity", v)
var _zoom := 0.0:
	set(v):
		_zoom = v
		_set_fx("zoom", v)
var _desat := 0.0:
	set(v):
		_desat = v
		_set_fx("desat", v)
var _flash := 0.0:
	set(v):
		_flash = v
		_set_fx("flash", v)
var _slow_tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_bus()
	_a = _make_player(FX_BUS)
	_b = _make_player(FX_BUS)
	_c = _make_player(bus if AudioServer.get_bus_index(bus) != -1 else &"Master")
	if pulse_effect:
		_setup_overlay()
	await get_tree().process_frame               # tunggu semua node scene siap
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()

	var pickup := root.find_child(pickup_node_name, true, false)
	if pickup:
		var hooked := false
		for sname in PICKUP_SIGNALS:
			if pickup.has_signal(sname):
				pickup.connect(sname, _on_pickup, CONNECT_ONE_SHOT)
				hooked = true
		# cadangan: pickup dihapus dari scene = sudah diambil
		pickup.tree_exiting.connect(_on_pickup_exiting, CONNECT_ONE_SHOT)
		if not hooked:
			print("MusicDirector: pakai deteksi 'pickup menghilang' (tidak ada sinyal ambil di ", pickup.name, ")")
	else:
		push_warning("MusicDirector: node '%s' tidak ketemu, lagu mulai saat wave pertama" % pickup_node_name)

	var spawner := root.find_child(spawner_node_name, true, false)
	if spawner:
		if spawner.has_signal("wave_started"):
			spawner.connect("wave_started", _on_wave_started)
		if spawner.has_signal("all_cleared"):
			spawner.connect("all_cleared", _on_all_cleared)
	else:
		push_warning("MusicDirector: node '%s' tidak ketemu" % spawner_node_name)


func _exit_tree() -> void:
	# jangan tinggalkan game dalam keadaan lambat kalau scene diganti / mati saat slow-mo
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


func _setup_bus() -> void:
	if AudioServer.get_bus_index(FX_BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, FX_BUS)
		AudioServer.set_bus_send(i, bus if AudioServer.get_bus_index(bus) != -1 else &"Master")
		var an := AudioEffectSpectrumAnalyzer.new()
		an.buffer_length = 0.1
		AudioServer.add_bus_effect(i, an)
	var idx := AudioServer.get_bus_index(FX_BUS)
	for e in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, e) is AudioEffectSpectrumAnalyzer:
			_analyzer = AudioServer.get_bus_effect_instance(idx, e)
			break


func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1                              # di atas 3D, di bawah HUD
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_fx_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FX_SHADER
	_fx_mat.shader = sh
	for p in {"intensity": 0.0, "kick": 0.0, "zoom": 0.0, "desat": 0.0, "flash": 0.0}:
		_fx_mat.set_shader_parameter(p, 0.0)
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.material = _fx_mat
	layer.add_child(_fx_rect)


func _set_fx(pname: String, v: float) -> void:
	if _fx_mat:
		_fx_mat.set_shader_parameter(pname, v)


func _make_player(bus_name: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.bus = bus_name
	p.volume_db = -80.0
	add_child(p)
	return p


func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("MusicDirector: file musik tidak ada: " + path)
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s


func _on_pickup() -> void:
	start_drop()


func _on_pickup_exiting() -> void:
	# tree_exiting juga terjadi saat scene di-reload (mati / restart): abaikan kalau kita ikut hilang
	if not is_inside_tree():
		return                                  # scene sedang diganti (mis. ke main menu)
	var tree := get_tree()
	await tree.process_frame
	if is_inside_tree():
		start_drop()


func _on_wave_started(_i: int, _c: int) -> void:
	start_drop()                                  # cadangan kalau pickup tidak terdeteksi


func _on_all_cleared() -> void:
	if slowmo_enabled and not get_tree().paused:
		_slowmo()
	start_clear()


func start_drop() -> void:
	if _state != 0:
		return
	var s := _load_loop(drop_path)
	if s == null:
		return
	_state = 1
	_a.stream = s
	_va = -60.0
	_a.play()                                     # lagu utama dan lapisan creepy mulai bersamaan -> loop-nya sama panjang
	_tw().tween_property(self, "_va", volume_db, drop_fade_in).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var cs := _load_loop(creep_path)
	if cs:
		_c.stream = cs
		_vc = -50.0
		_c.play()
		_tw().tween_property(self, "_vc", creep_db, 2.5)
	if pulse_effect:
		_tw().tween_property(self, "_intensity", pulse_strength, 1.5)


func start_clear() -> void:
	if _state == 2:
		return
	var s := _load_loop(clear_path)
	if s == null:
		return
	_state = 2
	_b.stream = s
	_vb = -60.0
	_b.play()
	var t := _tw().set_parallel(true)
	t.tween_property(self, "_vb", volume_db, crossfade).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "_va", -60.0, crossfade).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "_vc", -60.0, crossfade * 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(self, "_intensity", 0.0, crossfade).set_trans(Tween.TRANS_SINE)
	t.chain().tween_callback(_a.stop)
	t.chain().tween_callback(_c.stop)


## Slow-motion pas kill terakhir: game melambat, suara ikut jatuh nadanya, layar zoom + pudar warna, lalu balik normal.
func _slowmo() -> void:
	if _slow_tw:
		_slow_tw.kill()
	_slow_tw = _tw()
	var t := _slow_tw
	t.tween_method(_set_speed, 1.0, slowmo_scale, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "_zoom", 0.07, 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "_desat", 0.65, 0.2)
	_flash = 0.4
	t.parallel().tween_property(self, "_flash", 0.0, 0.25)
	t.tween_interval(slowmo_hold)
	t.tween_method(_set_speed, slowmo_scale, 1.0, slowmo_return).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(self, "_zoom", 0.0, slowmo_return).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(self, "_desat", 0.0, slowmo_return)
	t.tween_callback(_set_speed.bind(1.0))


func _set_speed(s: float) -> void:
	Engine.time_scale = s
	AudioServer.playback_speed_scale = lerpf(1.0, maxf(s, 0.25), 0.9)   # nada tidak boleh turun terlalu dalam


func fade_out(time: float = 1.5) -> void:
	var t := _tw().set_parallel(true)
	t.tween_property(self, "_va", -60.0, time)
	t.tween_property(self, "_vb", -60.0, time)
	t.tween_property(self, "_vc", -60.0, time)
	t.tween_property(self, "_intensity", 0.0, time)


func _tw() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


func _process(delta: float) -> void:
	# redam saat pause (menu pause / death screen)
	var target := pause_duck_db if get_tree().paused else 0.0
	_duck = move_toward(_duck, target, delta * 40.0)
	_a.volume_db = _va - _duck
	_b.volume_db = _vb - _duck
	_c.volume_db = _vc - _duck

	# denyut bass: baca energi 40-120 Hz dari lagu yang sedang main
	if _fx_mat and _analyzer and _state == 1:
		var m: float = _analyzer.get_magnitude_for_frequency_range(40.0, 120.0).length()
		_peak = maxf(_peak * (1.0 - delta * 0.25), m)
		var k := clampf((m / maxf(_peak, 0.0001) - 0.55) / 0.45, 0.0, 1.0)
		_kick = maxf(_kick - delta * 5.0, k)
	else:
		_kick = maxf(_kick - delta * 5.0, 0.0)
	_set_fx("kick", _kick)
