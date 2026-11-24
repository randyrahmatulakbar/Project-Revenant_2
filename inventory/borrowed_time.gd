extends Node
## BORROWED TIME (equipment 2x2): satu kali mati diganti hidup kembali dengan 25% HP, lalu artefaknya hancur dan slot-nya kosong.
##
## Dipasang otomatis oleh item_effects.gd sebagai anak "BorrowedTime" (kill switch ada di item_effects: borrowed_time_enabled).
## Cara kerja:
##   1. Mendengarkan sinyal health_changed dari node Health player. Begitu HP <= 0 dan artefak ada di case, kematian dibatalkan.
##   2. Player juga bisa memanggil try_revive(self) di awal _on_died() (patch satu baris, ada di catatan). Dua jalur ini saling menutup,
##      jadi tetap jalan apa pun urutan sinyal di health.gd-mu.
##   3. Artefak dihapus dari case (Inventory.remove_item), HP jadi 25% max, poison dibersihkan, kebal beberapa detik.
##
## ANIMASI = DEATH SCREEN-MU DIPUTAR MUNDUR (konsep dan bahan yang sama: frame terakhir dibekukan, tebasan, layar terbelah, void + abu,
## scanline / pecah warna, kelopak mata):
##   1. TEBAS    : game DI-PAUSE, frame terakhir dibekukan, garis tebasan menyambar, layar terbelah dan menjauh (sfx death_slash)
##   2. FLATLINE : di celah muncul jam dan ikon artefak yang retak, plate "// BORROWED TIME", garis EKG lurus (sfx death_flatline)
##   3. REWIND   : jam berputar mundur, ikon PECAH jadi kepingan piksel dan jatuh (satu-satunya yang tidak ikut mundur),
##                 kedua belahan layar tertarik menutup per langkah, glitch, HP naik, EKG hidup lagi (sfx bt_rewind, bt_shatter, heartbeat)
##   4. KLIK     : belahan menyatu dengan seam menyala, jam berbunyi (bt_snap), game jalan lagi dalam slowmo, mata terbuka (boot_wake),
##                 cincin jam retak jadi 12 pecahan, gelombang kejut mendorong musuh
## Pakai file suara yang sudah ada di sfx/ (death_slash, death_flatline, heartbeat, boot_wake) + 3 baru: bt_rewind, bt_shatter, bt_snap.
## File suara yang tidak ada dilewati saja (tidak error).
##
## Belum diuji di Godot (aku tidak bisa menjalankannya). Tombol "TES EFEK BORROWED TIME" di dev menu (tab FX) memutar animasinya
## tanpa memakai artefak / mengubah HP.

@export var enabled := true
@export_range(0.05, 1.0) var revive_fraction := 0.25     # HP setelah hidup kembali = max HP x ini
@export var invuln_time := 2.5                            # detik kebal setelah jam berbunyi (waktu asli)
@export var cure_poison := true                           # poison dihapus saat hidup kembali (kalau tidak, bisa mati lagi)
@export_group("EFEK (kill switch)")
@export var fx_enabled := true                            # semua animasi (false = hidup kembali langsung tanpa animasi)
@export var pause_on_death := true                        # game di-pause selama tebas + rewind (false = tetap jalan di belakang)
@export var slowmo_enabled := true                        # setelah jam berbunyi, game jalan lambat lalu normal
@export_range(0.02, 1.0) var slowmo_scale := 0.2
@export var shockwave_enabled := true                     # gelombang kejut 3D + musuh terdorong
@export var shockwave_radius := 7.0
@export var shockwave_push := 13.0
@export var shake_enabled := true
@export var shatter_icon := true                          # ikon pecah jadi kepingan piksel
@export_group("SUARA")
@export var sfx_enabled := true
@export var sfx_dir := "res://sfx/"
@export var sfx_volume_db := 0.0

const ITEM_ID := &"borrowed_time"
const Catalog = preload("item_catalog.gd")
const Gren = preload("grenade_projectile.gd")

const FPS := 12.0
const COL_PEACH := Color("dea68a")
const COL_CREAM := Color(0.92, 0.86, 0.8)
const COL_PANEL := Color(0.04, 0.11, 0.10, 0.94)
const COL_TEAL := Color(0.18, 0.37, 0.33)
const FONT_PATH := "res://font/Rajdhani-Bold.ttf"

# garis waktu (detik waktu ASLI)
const T_HIT := 0.07            # hit-stop: garis sudah lewat, frame masih utuh
const T_SPLIT_END := 0.47      # layar selesai terbelah
const T_HOLD_END := 1.2        # flatline selesai, rewind mulai
const T_REW_END := 2.2         # klik: belahan menyatu, game jalan lagi
const T_END := 3.3
const T_SLOW_HOLD := 0.35      # (setelah klik) lama slowmo tertahan
const T_SLOW_BACK := 0.5

const VOID_SHADER := """
shader_type canvas_item;
uniform vec4 center_col : source_color = vec4(0.035, 0.085, 0.08, 1.0);
uniform vec4 edge_col : source_color = vec4(0.0, 0.012, 0.012, 1.0);
uniform float aspect = 1.78;
uniform float glow = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect;
	float k = smoothstep(0.0, 0.85, length(uv));
	vec3 col = mix(center_col.rgb, edge_col.rgb, k);
	col += vec3(0.87, 0.65, 0.54) * glow * (1.0 - k) * 0.35;
	float n = fract(sin(dot(UV * vec2(1234.5, 987.6) + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.035;
	COLOR = vec4(col, 1.0);
}
"""

# sama dengan death_screen.gd: buang separuh bidang di satu sisi garis tebasan
const SPLIT_SHADER := """
shader_type canvas_item;
uniform vec2 p = vec2(0.5, 0.5);
uniform vec2 n = vec2(0.47, 0.88);
uniform float side = 1.0;
uniform float aspect = 1.78;
uniform float sat = 1.0;
uniform float dim = 1.0;
uniform float edge_glow = 0.0;
void fragment() {
	vec2 a = vec2((UV.x - p.x) * aspect, UV.y - p.y);
	float d = dot(a, n) * side;
	if (d < 0.0) { discard; }
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 col = mix(vec3(g), c.rgb, sat) * dim;
	col += vec3(1.0, 0.85, 0.5) * edge_glow * smoothstep(0.045, 0.0, d);
	COLOR = vec4(col, 1.0);
}
"""

# sama dengan death_screen.gd: scanline, pecah warna, vinyet, glitch, kelopak mata
const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float crt = 0.0;
uniform float glitch = 0.0;
uniform float blur = 0.0;
uniform float lid = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float t = TIME;
	vec2 cc = SCREEN_UV - 0.5;
	vec2 uv = SCREEN_UV;
	float band = floor(uv.y * 36.0);
	float st = floor(t * 20.0);
	float on_band = step(1.0 - glitch * 0.45, hash(vec2(band, st)));
	uv.x += on_band * (hash(vec2(band, st + 7.0)) - 0.5) * 0.22 * glitch;
	float ca = crt * 0.0016 + glitch * 0.012;
	vec3 col;
	col.r = textureLod(screen_tex, uv + vec2(ca, 0.0), blur).r;
	col.g = textureLod(screen_tex, uv, blur).g;
	col.b = textureLod(screen_tex, uv - vec2(ca, 0.0), blur).b;
	col += textureLod(screen_tex, uv, 3.0 + blur).rgb * 0.35 * crt;
	float line = sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159);
	col *= 1.0 - crt * 0.2 * (0.5 - 0.5 * line);
	col *= 1.0 + crt * (0.03 * sin(t * 55.0) + 0.02 * sin(t * 7.0));
	col += (hash(uv * vec2(900.0, 600.0) + t) - 0.5) * 0.05 * crt;
	float vig = smoothstep(0.25, 0.78, length(cc));
	col *= 1.0 - vig * 0.5 * max(crt, 1.0 - lid);

	float x2 = 4.0 * cc.x * cc.x;
	float edge = lid * 0.62 * (1.0 - 0.75 * x2) + lid * lid * lid;
	float vis = (1.0 - smoothstep(edge - 0.05, edge + 0.03, abs(cc.y))) * smoothstep(0.0, 0.05, lid);
	col *= vis;
	COLOR = vec4(col, 1.0);
}
"""

# bentuk detak EKG (x 0..1, y positif = naik), sama dengan garis flatline death screen
const EKG := [Vector2(0, 0), Vector2(0.28, 0), Vector2(0.30, 0.12), Vector2(0.32, 0), Vector2(0.335, -0.12),
		Vector2(0.35, 0.5), Vector2(0.365, -0.55), Vector2(0.38, 0), Vector2(0.42, 0.1), Vector2(0.45, 0), Vector2(1, 0)]


class Overlay extends Control:
	var host: Node

	func _draw() -> void:
		if host != null:
			host.call("_paint", self)


var _hooked: Node
var _playing := false
var _real_mode := false
var _t0_ms := 0
var _last_step := -1
var _pt := 0.0                      # waktu yang sudah di-"stepped" ke 12 FPS
var _prev_ts := 1.0
var _slow_on := false
var _paused_by_us := false
var _inv_until_ms := 0
var _hp_floor := 0.0
var _hp_from := 1.0
var _hp_to := 25.0
var _hp_max := 100.0
var _hp_disp := 0.0
var _icon: Texture2D
var _shards: Array = []
var _ev := {}
var _vp := Vector2(1280, 720)
var _sc := 1.0
var _slash_dir := Vector2.RIGHT
var _slash_n := Vector2.DOWN
var _slash_c := Vector2.ZERO
var _layer: CanvasLayer
var _void: ColorRect
var _void_mat: ShaderMaterial
var _ash: CPUParticles2D
var _stage: Control
var _halves: Array[TextureRect] = []
var _hmat: Array[ShaderMaterial] = []
var _beam: ColorRect
var _overlay: Overlay
var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _font: Font


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS             # tetap jalan walau game di-pause, supaya time_scale / pause pasti dikembalikan
	add_to_group("borrowed_time")
	_font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font


func _exit_tree() -> void:
	_restore_time()
	if _paused_by_us and get_tree() != null:
		get_tree().paused = false
		_paused_by_us = false


# ---------------------------------------------------------------- hook ke Health

func _health() -> Node:
	var p := get_tree().get_first_node_in_group("player")
	return p.get_node_or_null("Health") if p != null else null


func _poll_hook() -> void:
	var h := _health()
	if h == _hooked:
		return
	if _hooked != null and is_instance_valid(_hooked) and _hooked.has_signal("health_changed") \
			and _hooked.health_changed.is_connected(_on_hp):
		_hooked.health_changed.disconnect(_on_hp)
	_hooked = h
	if h != null and h.has_signal("health_changed"):
		h.health_changed.connect(_on_hp)


func _on_hp(_cur: float, _mx: float) -> void:
	if not enabled:
		return
	var h := _health()
	if h == null:
		return
	if float(h.get("current_health")) <= 0.0:           # baca nilai asli, argumen sinyal bisa basi
		try_revive()


func _physics_process(_delta: float) -> void:
	_poll_hook()
	# masa kebal: HP tidak boleh turun di bawah lantai
	if Time.get_ticks_msec() < _inv_until_ms:
		var h := _health()
		if h != null and float(h.get("current_health")) < _hp_floor:
			_set_hp(h, _hp_floor)


func _set_hp(h: Node, v: float) -> void:
	var mx := float(h.get("max_health"))
	v = clampf(v, 0.0, mx)
	h.set("current_health", v)
	if h.has_signal("health_changed"):
		h.emit_signal("health_changed", v, mx)


# ---------------------------------------------------------------- inti: hidup kembali

## Dipanggil player di awal _on_died(). Return true = kematian dibatalkan (player jangan lanjut mati).
func try_revive(player: Node = null) -> bool:
	if not enabled:
		return false
	var h := _health()
	if h == null:
		return false
	if Time.get_ticks_msec() < _inv_until_ms:            # masih kebal / baru saja hidup lagi: telan kematiannya
		_clear_dead_flags(h)
		_set_hp(h, maxf(_hp_floor, 1.0))
		return true
	if not Inventory.has_item(ITEM_ID):
		return false
	var p: Node = player if player != null else get_tree().get_first_node_in_group("player")
	if p != null and p.get("_dead") == true:
		return false                                       # sudah terlanjur mati (death screen jalan)
	if _playing:
		return false
	if not Inventory.remove_item(ITEM_ID):
		return false
	_hp_max = maxf(float(h.get("max_health")), 1.0)
	_hp_to = maxf(1.0, roundf(_hp_max * revive_fraction))
	_hp_floor = 1.0
	_inv_until_ms = Time.get_ticks_msec() + int((T_REW_END + invuln_time) * 1000.0)
	_clear_dead_flags(h)
	_set_hp(h, 1.0)                                        # bangun dengan 1 HP, lalu naik per langkah selama rewind
	if p != null:
		p.set_physics_process(true)
		p.set_process_unhandled_input(true)
	_reset_low_health_fx()
	if cure_poison and get_parent() != null and get_parent().has_method("_cure_poison"):
		get_parent().call("_cure_poison")
	Inventory.message.emit("Borrowed Time hancur: hidup kembali")
	_start(true)
	return true


func _clear_dead_flags(h: Node) -> void:
	for n in ["is_dead", "dead", "_dead", "dying", "is_dying", "_is_dead"]:
		if h.get(n) is bool:
			h.set(n, false)


func _reset_low_health_fx() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	var lh := root.find_child("LowHealthFX", true, false)
	if lh != null and lh.get("_dead") == true:
		lh.set("_dead", false)                            # LowHealthFX menandai "mati" waktu sinyal died, kembalikan


## Putar animasinya saja (dev menu): tidak memakai artefak, tidak mengubah HP.
func preview() -> void:
	if _playing:
		return
	_hp_max = 100.0
	_hp_to = roundf(_hp_max * revive_fraction)
	_start(false)


# ---------------------------------------------------------------- animasi (death screen versi mundur)

func _start(real: bool) -> void:
	_playing = true
	_real_mode = real
	_t0_ms = Time.get_ticks_msec()
	_last_step = -1
	_pt = 0.0
	_ev.clear()
	_hp_from = 1.0
	_hp_disp = 0.0
	_shards.clear()
	_icon = null
	var item: ItemData = Catalog.get_item(ITEM_ID)
	if item != null:
		_icon = item.icon
	if not fx_enabled:
		# tanpa animasi: langsung hidup kembali
		if real:
			var h := _health()
			if h != null:
				_set_hp(h, _hp_to)
				_hp_floor = _hp_to
		_playing = false
		_snap_event()
		return
	_vp = get_viewport().get_visible_rect().size
	_sc = _vp.y / 720.0
	# ambil frame terakhir game SEBELUM di-pause (sama seperti death screen)
	var frame_tex: Texture2D = null
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		frame_tex = ImageTexture.create_from_image(img)
	else:
		frame_tex = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	if pause_on_death and not get_tree().paused:
		get_tree().paused = true
		_paused_by_us = true
	if not _slow_on:
		_prev_ts = Engine.time_scale
	# garis tebasan: miring acak, lewat sekitar tengah layar
	var ang := deg_to_rad(randf_range(18.0, 38.0)) * (1.0 if randf() < 0.5 else -1.0)
	_slash_dir = Vector2.from_angle(ang)
	_slash_n = Vector2(-_slash_dir.y, _slash_dir.x)
	_slash_c = _vp * 0.5 + _slash_n * randf_range(-0.1, 0.1) * _vp.y
	_build_overlay(frame_tex)
	set_process(true)


func _build_overlay(frame_tex: Texture2D) -> void:
	_free_overlay()
	_layer = CanvasLayer.new()
	_layer.layer = 190                                     # di atas HUD / dev menu, di bawah death screen (200)
	add_child(_layer)
	# void (celah di antara belahan) + abu
	_void_mat = ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = VOID_SHADER
	_void_mat.shader = vs
	_void_mat.set_shader_parameter("aspect", _vp.x / _vp.y)
	_void = _rect(Color.WHITE)
	_void.material = _void_mat
	_ash = _make_ash()
	_ash.position = Vector2(_vp.x * 0.5, _vp.y + 10.0)
	_ash.emission_rect_extents = Vector2(_vp.x * 0.5, 4.0)
	_layer.add_child(_ash)
	# dua belahan frame terakhir
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_stage)
	var split := Shader.new()
	split.code = SPLIT_SHADER
	_halves.clear()
	_hmat.clear()
	for i in 2:
		var h := TextureRect.new()
		h.texture = frame_tex
		h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.stretch_mode = TextureRect.STRETCH_SCALE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.pivot_offset = _vp * 0.5
		var m := ShaderMaterial.new()
		m.shader = split
		m.set_shader_parameter("side", 1.0 if i == 0 else -1.0)
		m.set_shader_parameter("p", _slash_c / _vp)
		m.set_shader_parameter("n", _slash_n)
		m.set_shader_parameter("aspect", _vp.x / _vp.y)
		m.set_shader_parameter("edge_glow", 0.0)
		m.set_shader_parameter("sat", 1.0)
		m.set_shader_parameter("dim", 1.0)
		h.material = m
		_stage.add_child(h)
		_halves.append(h)
		_hmat.append(m)
	# garis tebasan (additif)
	_beam = ColorRect.new()
	_beam.color = Color(1.0, 0.95, 0.82)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beam.material = add_mat
	var length := _vp.length() * 1.3
	var thick := 3.0 * _sc
	_beam.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_beam.size = Vector2(length, thick)
	_beam.pivot_offset = Vector2(length * 0.5, thick * 0.5)    # berpusat di tengah garis: bisa melebar / menyusut dari tengah
	_beam.rotation = _slash_dir.angle()
	_beam.position = _slash_c - Vector2(length * 0.5, thick * 0.5)
	_beam.scale = Vector2(0.0, 1.0)
	_beam.visible = false
	_layer.add_child(_beam)
	# gambar jam / plate / EKG / kilatan
	_overlay = Overlay.new()
	_overlay.host = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_layer.add_child(_overlay)
	# lapisan monitor paling atas
	_fx_mat = ShaderMaterial.new()
	var fs := Shader.new()
	fs.code = FX_SHADER
	_fx_mat.shader = fs
	for pn in {"crt": 0.0, "glitch": 0.0, "blur": 0.0, "lid": 1.0}:
		_fx_mat.set_shader_parameter(pn, {"crt": 0.0, "glitch": 0.0, "blur": 0.0, "lid": 1.0}[pn])
	_fx = _rect(Color.WHITE)
	_fx.material = _fx_mat


func _rect(c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(r)
	return r


func _make_ash() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 60
	p.lifetime = 9.0
	p.preprocess = 4.0
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 14.0
	p.initial_velocity_max = 44.0
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.87, 0.65, 0.54, 0.0), Color(0.87, 0.65, 0.54, 0.4), Color(0.87, 0.65, 0.54, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = g
	return p


func _free_overlay() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_void = null
	_void_mat = null
	_ash = null
	_stage = null
	_beam = null
	_overlay = null
	_fx = null
	_fx_mat = null
	_halves.clear()
	_hmat.clear()


func _fire(key: String) -> bool:
	if _ev.has(key):
		return false
	_ev[key] = true
	return true


func _process(_delta: float) -> void:
	if not _playing:
		return
	var t := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	if t >= T_END:
		_finish()
		return
	_anim(t)
	var step := int(t * FPS)
	if step != _last_step:
		_last_step = step
		_pt = float(step) / FPS
		_step_update()


static func _eo(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


static func _expo(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)


static func _io4(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 8.0 * x * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 4.0) / 2.0


static func _back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


static func _a(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, col.a * clampf(a, 0.0, 1.0))


static func _hash(n: float) -> float:
	return fmod(absf(sin(n * 127.1) * 43758.5453), 1.0)


## Bagian mulus (tiap frame): belahan layar, garis tebasan, shader monitor, suara, waktu.
func _anim(t: float) -> void:
	if _stage == null:
		return
	# ---- suara & kejadian satu kali
	if _fire("slash"):
		_play("death_slash", 0.0, 1.0)
	if t >= T_HIT and _fire("sparks"):
		_sparks(_slash_c, _slash_n, 60, 520.0)
		_sparks(_slash_c, -_slash_n, 60, 520.0)
	if t >= 0.6 and _fire("flat"):
		_play("death_flatline", -3.0, 1.0)
	if t >= T_HOLD_END and _fire("rewind"):
		_play("bt_rewind", 0.0, 1.0)
		_play("bt_shatter", -3.0, 1.0)
		if fx_enabled and shatter_icon:
			_build_shards()
	if t >= T_REW_END - 0.18 and _fire("heart"):
		_play("heartbeat", 0.0, 1.0)
	if t >= T_REW_END and _fire("snap"):
		_snap_now()

	var ts := t - T_REW_END
	var dist := 0.0
	var sat := 1.0
	var dimv := 1.0
	var glow := 0.0
	var bx := 0.0
	var by := 1.0
	var ba := 0.0
	var vglow := 0.0
	if t < T_HIT:
		bx = _expo(t / T_HIT)
		ba = 1.0
		glow = 1.0
	elif t < T_SPLIT_END:
		var k := (t - T_HIT) / (T_SPLIT_END - T_HIT)
		var e := _expo(k)
		dist = 60.0 * _sc * e
		sat = lerpf(1.0, 0.15, clampf(k / 0.6, 0.0, 1.0))
		glow = 1.0 - k
		bx = 1.0
		by = lerpf(1.0, 14.0, e)
		ba = 1.0 - k
	elif t < T_HOLD_END:
		var k2 := (t - T_SPLIT_END) / (T_HOLD_END - T_SPLIT_END)
		dist = lerpf(60.0, 95.0, sin(k2 * PI * 0.5)) * _sc
		sat = 0.15
		dimv = lerpf(1.0, 0.55, k2)
		vglow = k2
		bx = 1.0
	elif t < T_REW_END:
		# REWIND: kebalikan dari tebasan, bergerak per langkah (rasa pita diputar mundur)
		var k3 := (t - T_HOLD_END) / (T_REW_END - T_HOLD_END)
		var kq := floorf(k3 * 18.0) / 18.0
		dist = 95.0 * _sc * (1.0 - _io4(kq))
		sat = lerpf(0.15, 1.0, kq)
		dimv = lerpf(0.55, 1.0, kq)
		vglow = 1.0 - kq
		glow = clampf((kq - 0.6) / 0.4, 0.0, 1.0)         # seam memanas saat belahan bertemu
		bx = 1.0
		by = lerpf(14.0, 1.0, kq)
		ba = clampf((kq - 0.4) / 0.4, 0.0, 1.0) * 0.9
	if t < T_REW_END:
		for i in 2:
			var sgn := 1.0 if i == 0 else -1.0
			_halves[i].position = _slash_n * dist * sgn
			_halves[i].rotation = deg_to_rad(2.2) * (dist / (60.0 * _sc)) * sgn
			_hmat[i].set_shader_parameter("sat", sat)
			_hmat[i].set_shader_parameter("dim", dimv)
			_hmat[i].set_shader_parameter("edge_glow", glow)
		_beam.scale = Vector2(bx, by)
		_beam.modulate.a = ba
		_beam.visible = ba > 0.01
		_void_mat.set_shader_parameter("glow", vglow)
		# getar saat tebasan
		var off := Vector2.ZERO
		if t < 0.3:
			off = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 12.0 * _sc * (1.0 - t / 0.3)
		_stage.position = off
		_overlay.position = off

	# ---- shader monitor
	var crt := 0.0
	var glitch := 0.0
	var lid := 1.0
	var blur := 0.0
	if t < T_REW_END:
		crt = lerpf(0.0, 0.45, clampf((t - 0.5) / 0.7, 0.0, 1.0))
		if t >= T_HOLD_END:
			var kk := (t - T_HOLD_END) / (T_REW_END - T_HOLD_END)
			var gs := floorf(Time.get_ticks_msec() / 80.0)
			glitch = (0.25 + 0.5 * _hash(gs)) * (0.4 + 0.6 * kk)
	else:
		crt = lerpf(0.45, 0.0, clampf(ts / 0.5, 0.0, 1.0))
		glitch = maxf(1.0 - ts / 0.25, 0.0) * 0.8
		# mata terbuka (sama dengan restart death screen)
		if ts < 0.2:
			lid = lerpf(0.0, 0.5, _eo(ts / 0.2))
			blur = lerpf(6.0, 4.0, ts / 0.2)
		elif ts < 0.28:
			lid = lerpf(0.5, 0.25, (ts - 0.2) / 0.08)
			blur = lerpf(4.0, 5.0, (ts - 0.2) / 0.08)
		else:
			var w := clampf((ts - 0.28) / 0.5, 0.0, 1.0)
			lid = lerpf(0.25, 1.0, _eo(w))
			blur = lerpf(5.0, 0.0, w)
		# slowmo setelah game jalan lagi
		if slowmo_enabled:
			_slow_on = true
			Engine.time_scale = _prev_ts * _slow_factor(ts)
	_fx_mat.set_shader_parameter("crt", crt)
	_fx_mat.set_shader_parameter("glitch", glitch)
	_fx_mat.set_shader_parameter("lid", lid)
	_fx_mat.set_shader_parameter("blur", blur)


func _slow_factor(ts: float) -> float:
	if ts < T_SLOW_HOLD:
		return slowmo_scale
	if ts < T_SLOW_HOLD + T_SLOW_BACK:
		var k := (ts - T_SLOW_HOLD) / T_SLOW_BACK
		return lerpf(slowmo_scale, 1.0, k * k)
	return 1.0


## Bagian per frame 12 FPS: HP naik, gambar ulang jam / plate.
func _step_update() -> void:
	var p := clampf((_pt - T_HOLD_END) / (T_REW_END - T_HOLD_END), 0.0, 1.0)
	if _pt < T_HOLD_END:
		_hp_disp = 0.0
	else:
		_hp_disp = roundf(lerpf(_hp_from, _hp_to, _eo(p)))
	if _real_mode and _pt >= T_HOLD_END:
		var h := _health()
		if h != null:
			_hp_floor = maxf(_hp_floor, _hp_disp)
			if float(h.get("current_health")) < _hp_disp:
				_set_hp(h, _hp_disp)
	if _overlay != null:
		_overlay.queue_redraw()


## Klik: belahan menyatu, game jalan lagi, jam berbunyi.
func _snap_now() -> void:
	_play("bt_snap", 0.0, 1.0)
	_play("boot_wake", -2.0, 1.2)
	if _stage != null:
		_stage.visible = false
		_void.visible = false
		_ash.visible = false
		_beam.visible = false
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	if _real_mode:
		var h := _health()
		if h != null:
			_hp_floor = _hp_to
			_set_hp(h, _hp_to)
	_snap_event()


## Dunia 3D: kejut kamera, gelombang kejut, musuh terdorong.
func _snap_event() -> void:
	if shake_enabled:
		Gren.shake_camera(get_viewport(), 1.4)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var pos := pl.global_position
	if shockwave_enabled:
		for en in get_tree().get_nodes_in_group("enemy"):
			if not (en is Node3D):
				continue
			var d: Vector3 = (en as Node3D).global_position - pos
			d.y = 0.0
			if d.length() > shockwave_radius:
				continue
			var away := d.normalized() if d.length() > 0.01 else Vector3.FORWARD
			if "velocity" in en:
				en.velocity += away * shockwave_push * (1.0 - d.length() / (shockwave_radius * 1.4)) + Vector3(0, 3.0, 0)
			if en.has_method("flinch"):
				en.flinch(0.6)
	if fx_enabled:
		var par := get_parent()
		if par != null and par.has_method("_fx_ring3d"):
			par.call("_fx_ring3d", pos, COL_PEACH, shockwave_radius, 0.55, 0.15)
			par.call("_fx_ring3d", pos, COL_CREAM, shockwave_radius * 0.55, 0.4, 0.1)
		if par != null and par.has_method("_fx_particles"):
			par.call("_fx_particles", pos + Vector3(0, 1.0, 0), COL_PEACH, 36, 0.07, 7.0, 0.9, 180.0, -3.0)
			par.call("_fx_particles", pos + Vector3(0, 1.0, 0), COL_CREAM, 14, 0.05, 4.0, 0.7, 180.0, -2.0)
		_flash_light(5.5, 0.0, 0.7)


func _flash_light(from_e: float, to_e: float, time: float) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var root := get_tree().current_scene
	if pl == null or root == null:
		return
	var l := OmniLight3D.new()
	l.light_color = COL_PEACH
	l.omni_range = 9.0
	l.shadow_enabled = false
	l.light_energy = from_e
	root.add_child(l)
	l.global_position = pl.global_position + Vector3(0, 1.2, 0)
	var tw := l.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(l, "light_energy", to_e, time)
	tw.tween_callback(l.queue_free)


func _sparks(pos: Vector2, dir: Vector2, count: int, speed: float) -> void:
	if _layer == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = false
	p.amount = count
	p.lifetime = 0.9
	p.lifetime_randomness = 0.4
	p.explosiveness = 1.0
	p.direction = dir
	p.spread = 55.0
	p.gravity = Vector2(0, 520.0 * _sc)
	p.initial_velocity_min = speed * 0.3 * _sc
	p.initial_velocity_max = speed * _sc
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), COL_PEACH, Color(COL_PEACH, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	p.color_ramp = g
	_layer.add_child(p)
	_layer.move_child(p, _beam.get_index() + 1 if _beam != null else -1)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _play(sfx_name: String, db: float, pitch: float) -> void:
	if not sfx_enabled:
		return
	var path := sfx_dir.path_join(sfx_name + ".wav")
	if not ResourceLoader.exists(path):
		return                                             # file suara belum ada: lewati saja
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db + sfx_volume_db
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _build_shards() -> void:
	_shards.clear()
	if _icon == null:
		return
	var img := _icon.get_image()
	if img == null:
		return
	if img.is_compressed():
		img.decompress()
	var big_r := minf(_vp.x, _vp.y) * 0.15
	var iw := img.get_width()
	var ih := img.get_height()
	var sc := _icon_scale(big_r, iw, ih)
	var blk := 4
	var y := 0
	while y < ih:
		var x := 0
		while x < iw:
			var col := img.get_pixel(mini(x + blk / 2, iw - 1), mini(y + blk / 2, ih - 1))
			if col.a > 0.2:
				var off := (Vector2(x + blk / 2.0, y + blk / 2.0) - Vector2(iw, ih) * 0.5) * float(sc)
				var dir := off.normalized() if off.length() > 1.0 else Vector2.from_angle(randf() * TAU)
				_shards.append({
					"off": off,
					"vel": dir * randf_range(160.0, 520.0) + Vector2(randf_range(-60.0, 60.0), randf_range(-420.0, -120.0)),
					"col": col,
					"size": float(blk * sc),
				})
			x += blk
		y += blk


func _icon_scale(big_r: float, iw: int, ih: int) -> int:
	return maxi(1, int(big_r * 0.9 / float(maxi(iw, ih))))


func _finish() -> void:
	_playing = false
	_restore_time()
	if _paused_by_us:
		get_tree().paused = false
		_paused_by_us = false
	_free_overlay()
	_shards.clear()
	set_process(false)


func _restore_time() -> void:
	if _slow_on:
		Engine.time_scale = _prev_ts
		_slow_on = false


# ---------------------------------------------------------------- gambar (dipanggil Overlay._draw)

func _spaced(c: Control, pos: Vector2, s: String, size: int, col: Color, sp: float) -> float:
	var x := pos.x
	for ch in s:
		c.draw_string(_font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		x += _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + sp
	return x - pos.x


func _ekg(u: float) -> float:
	for i in EKG.size() - 1:
		var a: Vector2 = EKG[i]
		var b: Vector2 = EKG[i + 1]
		if u >= a.x and u <= b.x:
			return lerpf(a.y, b.y, (u - a.x) / maxf(b.x - a.x, 0.0001))
	return 0.0


func _paint(c: Control) -> void:
	var sz := c.size
	var t := _pt
	var ts := t - T_REW_END
	var ctr := Vector2(sz.x * 0.5, sz.y * 0.46)
	var R := minf(sz.x, sz.y) * 0.15
	var step := int(t * FPS)
	var rew := clampf((t - T_HOLD_END) / (T_REW_END - T_HOLD_END), 0.0, 1.0)

	# --- jam di celah layar
	var cin := _back((t - 0.5) / 0.3)
	var r := R * cin
	if t >= 0.5 and ts < 0.0:
		var isz := Vector2.ZERO
		if _icon != null and t < T_HOLD_END:
			isz = _icon.get_size() * float(_icon_scale(R, int(_icon.get_width()), int(_icon.get_height())))
			var jit := Vector2(_hash(step * 3.1) - 0.5, _hash(step * 5.7) - 0.5) * 5.0
			c.draw_texture_rect(_icon, Rect2(ctr - isz * 0.5 + jit, isz), false, Color(1, 1, 1, 0.55 + 0.25 * _hash(step * 1.3)))
			# retakan menjalar di ikon selama flatline
			var kc := clampf((t - T_SPLIT_END) / (T_HOLD_END - T_SPLIT_END), 0.0, 1.0)
			var cp := [Vector2(-0.1, -0.5), Vector2(0.05, -0.3), Vector2(-0.08, -0.1), Vector2(0.1, 0.1), Vector2(-0.04, 0.3), Vector2(0.06, 0.5)]
			var line := PackedVector2Array()
			for i in 2 + int(kc * 4.0):
				var q: Vector2 = cp[mini(i, 5)]
				line.append(ctr + Vector2(q.x * isz.x, q.y * isz.y))
			c.draw_polyline(line, _a(COL_CREAM, 0.9), 2.0)
		var rot := -t * 0.5
		if t >= T_HOLD_END:
			rot = -T_HOLD_END * 0.5 + (t - T_HOLD_END) * 6.0 * _eo(1.0 - rew * 0.4)
		_draw_ring(c, ctr, r, rot, 1.0)
		var p := _eo(rew)
		var am := lerpf(-PI * 0.5 + 2.4, -PI * 0.5 - TAU * 3.0, p)
		var ah := lerpf(-PI * 0.5 + 0.7, -PI * 0.5 - TAU, p)
		if t < T_HOLD_END:
			am += (_hash(step * 2.3) - 0.5) * 0.06                     # jarum berkedut, jam macet
		c.draw_line(ctr - Vector2.from_angle(am) * r * 0.12, ctr + Vector2.from_angle(am) * r * 0.80, COL_PEACH, 4.0)
		c.draw_line(ctr - Vector2.from_angle(ah) * r * 0.10, ctr + Vector2.from_angle(ah) * r * 0.50, COL_CREAM, 6.0)
		c.draw_rect(Rect2(ctr - Vector2(6, 6), Vector2(12, 12)), COL_PEACH)
	elif ts >= 0.0:
		# cincin retak: 12 pecahan melayang keluar, memudar (di atas game yang sudah jalan lagi)
		var k := _eo(ts / 0.9)
		var fade := 1.0 - clampf(ts / 1.0, 0.0, 1.0)
		for i in 12:
			var a0 := TAU * float(i) / 12.0 + 0.04
			var mid := a0 + TAU / 24.0
			var offr := Vector2.from_angle(mid) * (R * 0.9 * k) + Vector2(0, 60.0 * ts * ts)
			c.draw_arc(ctr + offr, R, a0, a0 + TAU / 12.0 - 0.08, 6, _a(COL_PEACH, fade), 4.0)
		var rr := R + ts * R * 3.2
		c.draw_arc(ctr, rr, 0.0, TAU, 64, _a(COL_CREAM, 0.8 * (1.0 - clampf(ts / 0.5, 0.0, 1.0))), 3.0)

	# --- kepingan ikon: jatuh sementara semuanya mundur
	var sts := t - T_HOLD_END
	if sts >= 0.0 and not _shards.is_empty():
		var shard_fade := 1.0 - clampf((sts - 0.8) / 0.5, 0.0, 1.0)
		if shard_fade > 0.0:
			for s in _shards:
				var off: Vector2 = s["off"]
				var vel: Vector2 = s["vel"]
				var scol: Color = s["col"]
				var ss: float = s["size"]
				var pos := ctr + off + vel * sts + Vector2(0, 700.0 * sts * sts)
				c.draw_rect(Rect2(pos - Vector2(ss, ss) * 0.5, Vector2(ss, ss)), _a(scol, shard_fade))

	# --- plate HUD + EKG
	var pa := clampf((t - 0.55) / 0.2, 0.0, 1.0) * (1.0 - clampf((t - (T_END - 0.6)) / 0.5, 0.0, 1.0))
	if pa > 0.0:
		var w := 340.0
		var h := 70.0
		var slide := (1.0 - _eo((t - 0.55) / 0.25)) * -60.0
		var px := ctr.x - w * 0.5 + slide
		var py := ctr.y + R + 44.0
		var sl := 10.0
		c.draw_colored_polygon(PackedVector2Array([Vector2(px + sl, py), Vector2(px + w, py), Vector2(px + w - sl, py + h), Vector2(px, py + h)]), _a(COL_PANEL, pa))
		c.draw_colored_polygon(PackedVector2Array([Vector2(px + sl, py), Vector2(px + sl + 5.0, py), Vector2(px + 5.0, py + h), Vector2(px, py + h)]), _a(COL_PEACH, pa))
		c.draw_line(Vector2(px + sl + 5.0, py), Vector2(px + w, py), _a(COL_TEAL, pa), 2.0)
		_spaced(c, Vector2(px + 28.0, py + 24.0), "// BORROWED TIME", 15, _a(COL_PEACH, pa), 3.0)
		var status := "F L A T L I N E"
		if t >= T_HOLD_END:
			status = "REWINDING" + ".".repeat(int(t * FPS / 3.0) % 4)
		if ts >= 0.0:
			status = "REVIVED" if ts < 1.0 else "ARTEFAK HANCUR"
		_spaced(c, Vector2(px + 28.0, py + 54.0), status, 27, _a(COL_CREAM, pa), 3.0)
		var hx := px + w - 100.0
		_spaced(c, Vector2(hx, py + 24.0), "HP", 15, _a(COL_TEAL.lightened(0.35), pa), 3.0)
		_spaced(c, Vector2(hx, py + 54.0), "%d" % int(_hp_disp), 27, _a(COL_PEACH, pa), 2.0)
		var segs := 10
		var bx := px + 28.0
		var bw := (w - 60.0 - 22.0) / float(segs)
		var fill := _hp_disp / maxf(_hp_max, 1.0) * float(segs)
		for i in segs:
			var sx := bx + float(i) * (bw + 2.0)
			c.draw_rect(Rect2(sx, py + h - 9.0, bw, 4.0), _a(COL_TEAL, pa * 0.6))
			var part := clampf(fill - float(i), 0.0, 1.0)
			if part > 0.0:
				c.draw_rect(Rect2(sx, py + h - 9.0, bw * part, 4.0), _a(COL_PEACH, pa))
		# EKG: lurus saat flatline, hidup lagi selama rewind
		var ey := py + h + 34.0
		var amp := 0.0
		if t >= T_HOLD_END:
			amp = lerpf(0.25, 1.0, rew)
		if ts >= 0.0:
			amp = 1.0
		var pts := PackedVector2Array()
		var xx := 0.0
		while xx <= w:
			var u := xx / w
			var v := _ekg(fposmod(u * 2.0 - t * 2.5, 1.0)) * amp
			pts.append(Vector2(px + xx, ey - v * 24.0))
			xx += 4.0
		c.draw_polyline(pts, _a(COL_PEACH, 0.25 * pa), 7.0)
		c.draw_polyline(pts, _a(COL_PEACH, pa), 2.2)

	# --- kilatan (kasar, per frame)
	if t < 0.25:
		var fa: float = [0.8, 0.45, 0.18][clampi(step, 0, 2)]
		c.draw_rect(Rect2(Vector2.ZERO, sz), _a(COL_CREAM, fa))
	elif ts >= 0.0 and ts < 0.25:
		var fb: float = [0.6, 0.32, 0.12][clampi(int(ts * FPS), 0, 2)]
		c.draw_rect(Rect2(Vector2.ZERO, sz), _a(COL_PEACH, fb))


func _draw_ring(c: Control, ctr: Vector2, r: float, rot: float, alpha: float) -> void:
	# cincin putus-putus + garis dalam + 12 tanda jam
	var n := 48
	for i in n:
		if i % 2 == 0:
			var a0 := rot + TAU * float(i) / float(n)
			c.draw_arc(ctr, r, a0, a0 + TAU / float(n) * 0.9, 3, _a(COL_PEACH, alpha), 3.0)
	c.draw_arc(ctr, r * 0.82, 0.0, TAU, 48, _a(COL_TEAL, alpha), 2.0)
	for i in 12:
		var ang := TAU * float(i) / 12.0
		var major := i % 3 == 0
		var d := Vector2.from_angle(ang)
		c.draw_line(ctr + d * r * (0.84 if major else 0.9), ctr + d * r * 0.98, _a(COL_CREAM, alpha), 4.0 if major else 2.0)
