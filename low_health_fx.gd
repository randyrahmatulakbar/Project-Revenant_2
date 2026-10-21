extends Node
## EFEK SEKARAT. Saat HP player rendah:
##   - layar menyempit (tunnel vision), memudar warna, tepi memerah dan berdenyut mengikuti detak jantung
##   - detak jantung "lub-dub" yang makin cepat saat HP makin rendah
##   - suara game meredam (low-pass di bus Music dan SFX); detak jantung tetap jernih
##   - semua memudar halus saat HP pulih (mis. heal dari style meter)
## Pasang: tambahkan Node biasa bernama LowHealthFX di intro.tscn, pasang script ini. Selesai.
## Player dicari otomatis (CharacterBody3D yang punya anak "Health").

@export_group("KILL SWITCH")
@export var enabled := true
@export var vignette_enabled := true
@export var heartbeat_enabled := true
@export var muffle_enabled := true
@export_group("Pengaturan")
@export_range(0.05, 0.9) var threshold := 0.35      # efek mulai di bawah sekian persen HP
@export var bpm_min := 66.0                         # detak saat baru masuk zona sekarat
@export var bpm_max := 130.0                        # detak saat nyaris mati
@export var heartbeat_db := -4.0
@export var muffle_hz := 1500.0                     # batas frekuensi saat paling parah
@export var heart_path := "res://sfx/heartbeat.wav"
@export var spawner_node_name := ""                 # tidak dipakai; cadangan kalau nanti mau dikaitkan wave

const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float sev = 0.0;     // 0..1 tingkat sekarat
uniform float kick = 0.0;    // 0..1 denyut jantung
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c);
	float vig = smoothstep(0.16, 0.78, r);
	float lod = vig * sev * 3.2;
	vec2 off = normalize(c + vec2(0.00001)) * (0.0006 + 0.0045 * kick) * sev * r * 5.0;
	vec3 col;
	col.r = textureLod(screen_tex, SCREEN_UV + off, lod).r;
	col.g = textureLod(screen_tex, SCREEN_UV, lod).g;
	col.b = textureLod(screen_tex, SCREEN_UV - off, lod).b;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g), sev * 0.55);
	col *= 1.0 - sev * 0.16;
	vec3 blood = vec3(0.5, 0.015, 0.015);
	col = mix(col, blood, clamp(vig * (0.32 + 0.68 * kick) * sev * 1.15, 0.0, 0.85));
	col *= 1.0 + kick * sev * 0.05;
	COLOR = vec4(col, 1.0);
}
"""

var _player: Node
var _sev := 0.0
var _target := 0.0
var _kick := 0.0
var _beat_t := 0.0
var _subs: Array[float] = []         # sisa waktu denyut kedua ("dub") yang menunggu
var _fx_mat: ShaderMaterial
var _fx_layer: CanvasLayer
var _heart: AudioStreamPlayer
var _filters: Array = []             # [bus_index, effect, ...]
var _dead := false


func _ready() -> void:
	if not enabled:
		set_process(false)
		return
	_build_overlay()
	_heart = AudioStreamPlayer.new()
	_heart.volume_db = heartbeat_db
	add_child(_heart)
	if ResourceLoader.exists(heart_path):
		_heart.stream = load(heart_path)
	if muffle_enabled:
		_setup_muffle()
	await get_tree().process_frame
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	var cands: Array = []
	var p := get_parent()
	if p is CharacterBody3D and p.has_node("Health"):
		cands.append(p)                               # dipasang di scene player
	cands.append_array(root.find_children("*", "CharacterBody3D", true, false))
	for c in cands:
		if c.has_node("Health"):
			_player = c
			var h: Node = c.get_node("Health")
			if h.has_signal("health_changed"):
				h.health_changed.connect(_on_health)
			if h.has_signal("died"):
				h.died.connect(_on_died)
			break
	if _player == null:
		push_warning("LowHealthFX: player (CharacterBody3D dengan anak 'Health') tidak ketemu")


func _exit_tree() -> void:
	for f in _filters:
		var bi: int = f[0]
		for e in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, e) == f[1]:
				AudioServer.remove_bus_effect(bi, e)
				break
	_filters.clear()


func _build_overlay() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = -1                              # di atas 3D, di bawah HUD
	add_child(_fx_layer)
	_fx_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FX_SHADER
	_fx_mat.shader = sh
	_fx_mat.set_shader_parameter("sev", 0.0)
	_fx_mat.set_shader_parameter("kick", 0.0)
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = _fx_mat
	r.visible = false
	_fx_layer.add_child(r)


func _setup_muffle() -> void:
	for bn in ["Music", "SFX"]:
		var bi := AudioServer.get_bus_index(bn)
		if bi == -1:
			continue
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = 20500.0
		AudioServer.add_bus_effect(bi, f)
		AudioServer.set_bus_effect_enabled(bi, AudioServer.get_bus_effect_count(bi) - 1, false)
		_filters.append([bi, f])


func _on_health(current: float, maximum: float) -> void:
	if maximum <= 0.0 or _dead:
		return
	var frac := current / maximum
	_target = clampf((threshold - frac) / threshold, 0.0, 1.0) if current > 0.0 else 0.0


func _on_died() -> void:
	_dead = true
	_target = 0.0                                     # death screen mengambil alih
	_sev = 0.0
	_apply()


func _process(delta: float) -> void:
	_sev = move_toward(_sev, _target, delta * (1.3 if _target > _sev else 0.55))

	# jadwal detak jantung
	if heartbeat_enabled and _sev > 0.04 and not _dead:
		_beat_t -= delta
		if _beat_t <= 0.0:
			var bpm := lerpf(bpm_min, bpm_max, _sev)
			_beat_t = 60.0 / bpm
			_kick = 1.0                               # "lub"
			_subs.append(_beat_t * 0.30)              # "dub" menyusul
			if _heart.stream:
				_heart.pitch_scale = lerpf(0.9, 1.15, _sev)
				_heart.volume_db = heartbeat_db + lerpf(-6.0, 2.0, _sev)
				_heart.play()
	else:
		_beat_t = 0.0
	var i := 0
	while i < _subs.size():
		_subs[i] -= delta
		if _subs[i] <= 0.0:
			_kick = maxf(_kick, 0.7)                  # "dub"
			_subs.remove_at(i)
		else:
			i += 1
	_kick = maxf(_kick - delta * 3.2, 0.0)
	_apply()


func _apply() -> void:
	if _fx_mat == null:
		return
	var on := vignette_enabled and _sev > 0.002
	_fx_layer.get_child(0).visible = on
	if on:
		_fx_mat.set_shader_parameter("sev", _sev)
		_fx_mat.set_shader_parameter("kick", _kick)
	for f in _filters:
		var bi: int = f[0]
		var eff: AudioEffectLowPassFilter = f[1]
		eff.cutoff_hz = lerpf(20500.0, muffle_hz, _sev)
		for e in AudioServer.get_bus_effect_count(bi):
			if AudioServer.get_bus_effect(bi, e) == eff:
				AudioServer.set_bus_effect_enabled(bi, e, _sev > 0.01)
				break
