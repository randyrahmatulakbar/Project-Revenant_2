extends Node
# TRIGGER (item equipment): tahan tombol tembak = charge, lepas = charge shot.
# Peluru lebih kencang, damage lebih besar, lalu memantul otomatis ke musuh terdekat yang kelihatan.
# Dipasang oleh player-test.gd (lihat petunjuk di bawah), jadi anak node bernama "ChargeShot".
#
# Phase (waktu = lama menahan tombol):
#   phase 1 -> pantul 2x, phase 2 -> pantul 4x (+ impact frame), phase 3 -> pantul 7x (+ impact frame lebih keras)
# Dilepas sebelum phase 1 = tembakan biasa (player.shoot()).

# ---- kill switch ----
@export var enabled := true
@export var require_item := true                 # false = aktif tanpa item Trigger (buat ngetes)
@export var charge_fx := true                    # ring charge, vignette, getar senjata
@export var impact_frame_fx := true              # frame hitam-putih saat tembak phase 2 ke atas
@export var bounce_enabled := true
@export var gun_fx := true                       # efek di senjata: glow, percikan, petir kecil, kilatan moncong, recoil
@export var muzzle_fx := false                   # percikan + kilatan di moncong (butuh gun_fx_offset pas dengan sprite-mu, makanya default mati)
@export var gun_fx_offset := Vector2(0, -44)     # titik moncong di sprite senjata (koordinat lokal sprite)

@export_group("Phase (detik, dihitung sejak mulai menahan tombol)")
@export var phase_time: Array[float] = [1.5, 3.0, 6.0]
@export var phase_bounces: Array[int] = [2, 4, 7]
@export var phase_damage_mult: Array[float] = [2.0, 3.0, 5.0]    # x gun_damage player
@export var phase_colors: Array[Color] = [
	Color(0.87, 0.65, 0.54),        # peach (warna UI)
	Color(1.0, 0.84, 0.66),         # peach terang
	Color(0.90, 0.33, 0.24),        # merah (sama dengan bar HP)
]

@export_group("Pantulan")
@export var bounce_range := 20.0                 # musuh di bawah jarak ini & kelihatan = ditembak langsung
@export var far_range := 70.0                    # musuh lebih jauh / terhalang tembok dicapai lewat pantulan tembok (sampai jarak ini)
@export var max_wall_bounces := 2                # maks pantulan tembok antar dua musuh (tembok -> tembok -> musuh); tiap pantulan memakai jatah pantulan
@export var ricochet_candidates := 3             # berapa musuh terdekat yang dicoba dicari rutenya (makin besar makin berat)
@export var ricochet_dirs := 72                  # jumlah arah yang dicoba saat mencari rute pantulan tembok
@export var ricochet_tolerance_deg := 22.0       # toleransi sudut pantul (peluru dibelokkan sedikit supaya pas kena)
@export var bounce_falloff := 0.9                # damage tiap pantulan x ini
@export var hop_delay := 0.02                    # jeda tambahan setelah peluru tiba, sebelum lanjut memantul (detik)

@export_group("Tracer")
@export var tracer_speed := 520.0
@export var tracer_length := 7.0
@export var tracer_width := 0.025
@export var bounce_tracer_speed := 200.0         # kecepatan peluru antar pantulan (lebih lambat dari tembakan utama supaya pantulannya kelihatan)
@export var trail_linger := 0.9                  # jejak pantulan bertahan segini lama (detik) lalu memudar bertahap (0 = mati)

@export_group("Senjata berputar")
@export var spin_enabled := false                # senjata berputar (twirl) selama charge, makin cepat per phase
@export var spin_pivot := Vector2(40, 65)        # titik putar senjata relatif ke tengah frame (piksel sprite) = sekitar genggaman. Geser kalau putarannya kurang pas
@export var gun_layer_path := "res://tangan/gun_idle_gun.png"    # sheet idle TANPA tangan (8 frame 180x180)
@export var hand_layer_path := "res://tangan/gun_idle_hand.png"  # sheet idle HANYA tangan (8 frame 180x180)
@export var layer_frame_size := Vector2i(180, 180)
@export var spin_grow := 0.25                     # senjata membesar saat lewat dekat kamera (0 = tidak)
@export var open_hand_enabled := true             # telapak terbuka di bawah senjata selama berputar (pakai sheet tangan reload)
@export var open_hand_path := "res://tangan/gun_open_hand.png"   # sheet telapak membuka (7 frame 180x180)
@export var open_hand_cell := Vector2i(180, 180)
@export var open_hand_cols := 7
@export var open_hand_seq: PackedInt32Array = PackedInt32Array([0, 1, 2, 3, 4, 5, 6])   # frame telapak membuka, frame terakhir ditahan
@export var open_hold_frames := 2                 # tambahan frame ditahan sebelum senjata mulai berputar
@export var open_hand_shift := Vector2(0, 0)     # geser telapak supaya tepat di bawah genggaman (piksel sprite)
@export var open_hand_pad := 0.0                  # koreksi halus posisi horizontal
@export var spin_lift := 24.0                    # senjata terangkat sedikit di puncak putaran (piksel layar)
@export var spin_fps := 24.0                     # putaran dihitung per frame pada kecepatan ini (patah-patah, bukan mulus)

@export_group("Frame per frame")
@export var fx_fps := 12.0                       # semua animasi visual (ring, glow senjata, jejak, ping, kilatan) berubah per frame pada kecepatan ini
@export var camera_kick := false                 # sentakan FOV / miring kamera (gerakannya smooth, makanya default mati)
@export var impact_fps := 20.0                   # frame per detik impact frame
@export var impact_frames_p2 := 3                # jumlah frame di phase 2
@export var impact_frames_p3 := 5                # jumlah frame di phase 3
@export var impact_tail_fps := 14.0              # kecepatan frame ekor (frame tambahan yang memudar di akhir impact frame)

const SHOW_DELAY := 0.2                          # ring baru muncul setelah ditahan segini (supaya tap biasa tidak berkedip)
const IF_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform float inv = 0.0;
uniform float seed = 0.0;
uniform float amount = 1.0;
uniform float zoom = 1.0;
uniform float colored = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.4, 0.3, 1.0);
uniform float burst = 1.0;
uniform float blur = 1.0;
uniform float rot = 0.0;
uniform float shake = 0.0;
uniform float soft = 0.0;
uniform float gray = 0.0;
uniform float scope = 0.0;
float h(float x) { return fract(sin(x * 12.9898 + seed) * 43758.5453); }
float lum(vec2 u) { return dot(texture(screen_tex, u).rgb, vec3(0.299, 0.587, 0.114)); }
void fragment() {
	vec2 uv0 = center + (SCREEN_UV - center) * zoom;
	uv0 += (vec2(h(1.0), h(2.0)) - 0.5) * shake;
	// blur zoom radial dari titik pusat: sumber garis-garis kabur di sekitar bintang
	float acc = 0.0;
	vec3 sacc = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float k = float(i) / 11.0;
		vec2 su = center + (uv0 - center) * (1.0 - blur * 0.4 * k);
		acc = max(acc, lum(su));
		sacc += texture(screen_tex, su).rgb;
	}
	sacc /= 12.0;
	float scene = smoothstep(0.45, 0.85, pow(acc, 0.6));
	vec2 d = SCREEN_UV - center;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(d);
	float ang = atan(d.y, d.x) + rot;
	float a01 = (ang + 3.14159) / 6.28318;
	// bintang bergerigi: panjang tiap sudut diacak 3 oktaf supaya tepinya compang-camping seperti sapuan kuas
	float jag = h(floor(a01 * 36.0)) * 0.45 + h(floor(a01 * 110.0) + 7.0) * 0.35 + h(floor(a01 * 320.0) + 19.0) * 0.2;
	float arm = pow(abs(cos(2.0 * ang)), 5.0);
	float arm2 = pow(abs(cos(4.0 * ang + 0.8)), 8.0) * 0.5;
	float len = burst * (0.05 + 0.5 * arm + 0.18 * arm2) * (0.35 + 1.05 * jag);
	float star = 1.0 - step(len, r);
	// garis radial tipis memanjang
	float rid = floor(a01 * 140.0) + 31.0;
	float ray = step(0.93, h(rid)) * smoothstep(0.1, 0.4, r) * (1.0 - step(0.25 + 0.7 * h(rid + 5.0), r)) * step(0.01, burst);
	// serpihan putih bergerigi dari tepi layar
	vec2 e = abs(SCREEN_UV - 0.5) * 2.0;
	float bd = max(e.x, e.y);
	float sh_len = (0.1 + 0.28 * h(floor(a01 * 28.0) + 51.0)) * (0.5 + h(floor(a01 * 90.0) + 3.0));
	float shard = step(0.65, h(floor(a01 * 28.0) + 77.0)) * step(1.0 - sh_len * burst, bd);
	// cincin tipis di sekitar bintang
	float ring = (1.0 - step(0.0025, abs(r - 0.15 * (0.6 + 0.4 * burst)))) * 0.8 * step(0.01, burst);
	float v = max(max(scene, star), max(max(ray, shard), ring));
	v = mix(v, 1.0 - v, inv);
	vec3 col = mix(vec3(v), tint.rgb * v, colored);
	vec3 base = texture(screen_tex, SCREEN_UV).rgb;
	vec3 outc = mix(base, col, amount);
	if (soft > 0.5) {
		// overlay lembut: layar asli dengan blur zoom radial (bisa abu-abu), bukan fade
		float g = dot(sacc, vec3(0.299, 0.587, 0.114));
		vec3 sc = mix(sacc, vec3(g), gray);
		sc = (sc - 0.5) * 1.2 + 0.5 + 0.08 * gray;
		// overlay scope: cincin tipis, garis silang, busur tebal di bawah
		float ring = (1.0 - step(0.0028, abs(r - 0.33))) * 0.8;
		float cross_v = (1.0 - step(0.0012, abs(d.x))) * (1.0 - step(0.33, abs(d.y))) * 0.45;
		float cross_h = (1.0 - step(0.0012, abs(d.y))) * (1.0 - step(0.33, abs(d.x))) * 0.45;
		float arc = (1.0 - step(0.007, abs(r - 0.36))) * step(0.22, d.y) * step(abs(d.x), 0.3);
		float ov = clamp(max(max(ring, arc), max(cross_v, cross_h)), 0.0, 1.0) * scope;
		sc = mix(sc, vec3(1.0), ov);
		outc = sc;
	}
	COLOR = vec4(outc, 1.0);
}
"""
const GUN_SHADER := """
shader_type canvas_item;
uniform vec4 line_col : source_color = vec4(1.0);
uniform float strength = 0.0;
uniform float heat = 0.0;
uniform float fill = 0.0;
uniform float sparkle = 0.0;
uniform float seed = 0.0;
uniform float flash = 0.0;
uniform float half_h = 90.0;
varying vec2 lpos;
void vertex() { lpos = VERTEX; }
float hh(vec2 q) { return fract(sin(dot(q + seed, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	// garis tepi 1 piksel mengikuti siluet sprite
	float a1 = max(max(texture(TEXTURE, UV + vec2(px.x, 0.0)).a, texture(TEXTURE, UV - vec2(px.x, 0.0)).a),
			max(texture(TEXTURE, UV + vec2(0.0, px.y)).a, texture(TEXTURE, UV - vec2(0.0, px.y)).a));
	float outline = a1 * (1.0 - c.a);
	// halo 3 piksel di luar siluet: sumber percikan piksel
	float a3 = 0.0;
	for (int i = 0; i < 8; i++) {
		float an = float(i) * 0.785398;
		a3 = max(a3, texture(TEXTURE, UV + vec2(cos(an), sin(an)) * px * 3.0).a);
	}
	float halo = a3 * (1.0 - c.a) * (1.0 - outline);
	float spark = halo * step(1.0 - sparkle * 0.4, hh(floor(lpos / 2.0)));
	// isi charge: dari bawah naik, tepinya berpola dither (piksel)
	float yb = clamp((lpos.y + half_h) / (2.0 * half_h), 0.0, 1.0);
	float edge = 1.0 - fill;
	float filled = step(edge, yb) * step(0.001, fill);
	float rim = step(edge - 0.06, yb) * (1.0 - filled) * mod(floor(lpos.x) + floor(lpos.y), 2.0) * step(0.001, fill);
	float fmask = clamp(filled + rim, 0.0, 1.0) * c.a;
	vec3 rgb = c.rgb;
	rgb = mix(rgb, rgb * (0.5 + line_col.rgb * 1.8) + line_col.rgb * 0.15, fmask * 0.8);
	rgb = mix(rgb, rgb * (0.55 + line_col.rgb * 1.5) + line_col.rgb * 0.1, heat * c.a);
	vec4 o = vec4(rgb, c.a);
	float edge_a = clamp(outline * strength, 0.0, 1.0);
	o = mix(o, vec4(line_col.rgb, 1.0), edge_a);
	o = mix(o, vec4(mix(line_col.rgb, vec3(1.0), 0.6), 1.0), spark);
	if (flash > 1.5) {
		float g = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		o = vec4(vec3(1.0 - step(0.4, g)), c.a);
		o = mix(o, vec4(1.0), max(edge_a, spark));
	} else if (flash > 0.5) {
		o = vec4(vec3(1.0), max(c.a, max(edge_a, spark)));
	}
	COLOR = o;
}
"""
const EDGE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.9);
	float v = smoothstep(0.28, 0.78, length(d));
	COLOR = vec4(tint.rgb, v * amount);
}
"""


# Lingkaran charge di sekitar crosshair
class Ring extends Control:
	var level := 0.0
	var phase := 0
	var marks: Array[float] = []
	var cols: Array[Color] = []
	var bounces: Array[int] = []
	var pulse := 0.0
	var font: Font

	func _draw() -> void:
		var c := size * 0.5
		var col: Color = cols[maxi(phase - 1, 0)] if phase > 0 else Color(0.92, 0.86, 0.81)
		var r := 30.0 * (1.0 + pulse * 0.18)
		draw_arc(c, r, 0.0, TAU, 64, Color(0.92, 0.86, 0.81, 0.18), 2.0, true)
		if level > 0.001:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * level, 64, col, 3.0, true)
		for i in marks.size():
			var a := -PI * 0.5 + TAU * marks[i]
			var dir := Vector2(cos(a), sin(a))
			var reached := phase > i
			draw_line(c + dir * (r - 5.0), c + dir * (r + 6.0), cols[i] if reached else Color(0.92, 0.86, 0.81, 0.45), 2.5 if reached else 1.5)
		if pulse > 0.01:
			draw_arc(c, r + 10.0 * pulse, 0.0, TAU, 48, Color(col, 0.5 * pulse), 2.0, true)
		if font != null:
			_plate(c, r, col)


	# huruf berjarak lebar (seperti label "// STYLE" di HUD-mu)
	func _spaced(t: String, pos: Vector2, fs: int, col: Color, sp: float) -> float:
		var x := pos.x
		for ch in t:
			draw_string(font, Vector2(x, pos.y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + sp
		return x - pos.x


	# plat gaya HUD: miring, teal gelap, garis peach di kiri, segmen phase seperti bar ammo
	func _plate(c: Vector2, r: float, col: Color) -> void:
		var w := 118.0
		var h := 38.0
		var sl := 6.0
		var x0 := c.x - w * 0.5
		var y0 := c.y + r + 16.0
		var teal := Color(0.13, 0.19, 0.19, 0.9)
		var cream := Color(0.92, 0.86, 0.81)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + sl, y0), Vector2(x0 + w, y0), Vector2(x0 + w - sl, y0 + h), Vector2(x0, y0 + h)]), teal)
		draw_polyline(PackedVector2Array([Vector2(x0 + sl, y0), Vector2(x0 + w, y0), Vector2(x0 + w - sl, y0 + h), Vector2(x0, y0 + h), Vector2(x0 + sl, y0)]), Color(col, 0.28), 1.0)
		var bar_col: Color = col if phase > 0 else Color(0.87, 0.65, 0.54)
		draw_colored_polygon(PackedVector2Array([Vector2(x0 + sl, y0), Vector2(x0 + sl + 4.0, y0), Vector2(x0 + 4.0, y0 + h), Vector2(x0, y0 + h)]), bar_col)
		# judul kecil + jumlah pantulan
		_spaced("CHARGE" if phase == 0 else "PHASE %d" % phase, Vector2(x0 + 17.0, y0 + 14.0), 11, Color(cream, 0.7), 2.0)
		if phase > 0 and phase - 1 < bounces.size():
			var txt := "x%d" % bounces[phase - 1]
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			draw_string(font, Vector2(x0 + w - sl - 8.0 - tw, y0 + 17.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col)
		# segmen phase (terisi mulus sesuai level)
		var n := marks.size()
		var sx := x0 + 14.0
		var sw := (w - 14.0 - 14.0 - 4.0 * (n - 1)) / float(maxi(n, 1))
		var prev := 0.0
		for i in n:
			var seg_x := sx + i * (sw + 4.0)
			var seg_y := y0 + h - 12.0
			draw_colored_polygon(PackedVector2Array([Vector2(seg_x + 3.0, seg_y), Vector2(seg_x + sw + 3.0, seg_y), Vector2(seg_x + sw, seg_y + 5.0), Vector2(seg_x, seg_y + 5.0)]), Color(0.25, 0.33, 0.33, 0.8))
			var span := maxf(marks[i] - prev, 0.001)
			var f := clampf((level - prev) / span, 0.0, 1.0)
			if f > 0.0:
				var fw := sw * f
				draw_colored_polygon(PackedVector2Array([Vector2(seg_x + 3.0, seg_y), Vector2(seg_x + fw + 3.0, seg_y), Vector2(seg_x + fw, seg_y + 5.0), Vector2(seg_x, seg_y + 5.0)]), cols[i])
			prev = marks[i]


# Efek di senjata (anak dari sprite senjata HUD): glow moncong, percikan, petir kecil, kilatan tembak
class GunFx extends Node2D:
	var col := Color(0.87, 0.65, 0.54)
	var level := 0.0
	var phase := 0
	var charging := false
	var flash := 0.0
	var sparks: Array = []
	var arcs: Array = []
	var _arc_t := 0.0
	var _acc := 0.0
	var _drawn := false

	func _init() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func burst(c: Color, ph: int) -> void:
		col = c
		flash = 1.0
		for i in 12 + ph * 10:
			var a := randf_range(-PI * 0.95, -PI * 0.05)
			var v := Vector2(cos(a), sin(a)) * randf_range(50.0, 170.0 + 40.0 * ph)
			sparks.append([Vector2.ZERO, v, 0.0, randf_range(0.35, 0.8)])

	func _busy() -> bool:
		return charging or flash > 0.0 or not sparks.is_empty()

	func _process(delta: float) -> void:
		if not _busy():
			if _drawn:
				_drawn = false
				queue_redraw()
			return
		flash = maxf(flash - delta * 4.5, 0.0)
		if charging and phase >= 1:
			_acc += delta * (6.0 + 10.0 * phase)
			while _acc >= 1.0:
				_acc -= 1.0
				var a := randf_range(-PI * 0.9, -PI * 0.1)
				sparks.append([Vector2(randf_range(-4.0, 4.0), 0.0), Vector2(cos(a), sin(a)) * randf_range(25.0, 70.0), 0.0, randf_range(0.3, 0.6)])
		var i := sparks.size() - 1
		while i >= 0:
			var s: Array = sparks[i]
			s[2] += delta
			if s[2] >= s[3]:
				sparks.remove_at(i)
			else:
				s[1] = s[1] + Vector2(0.0, 120.0) * delta
				s[0] = s[0] + s[1] * delta
			i -= 1
		_arc_t -= delta
		if charging and phase >= 2:
			if _arc_t <= 0.0:
				_arc_t = 0.07
				arcs.clear()
				for n in (1 if phase == 2 else 3):
					var pts := PackedVector2Array()
					var dir := Vector2.from_angle(randf() * TAU)
					var reach := randf_range(20.0, 44.0)
					for j in 6:
						var jit := Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)) if j > 0 else Vector2.ZERO
						pts.append(dir * (6.0 + reach * float(j) / 5.0) + jit)
					arcs.append(pts)
		else:
			arcs.clear()
		_drawn = true
		queue_redraw()

	func _draw() -> void:
		if not _busy():
			return
		var k := 0.55 + level * 1.1 + flash * 1.6
		for j in 4:
			draw_circle(Vector2.ZERO, (5.0 + j * 6.0) * k, Color(col, (0.05 + 0.1 * level + 0.25 * flash) / float(j + 1)))
		for pts in arcs:
			draw_polyline(pts, Color(col.lightened(0.55), 0.85), 1.2, true)
		for s in sparks:
			var life := 1.0 - float(s[2]) / float(s[3])
			draw_rect(Rect2(s[0] - Vector2(0.9, 0.9), Vector2(1.8, 1.8)), Color(col.lightened(0.4), life))


@onready var p = get_parent()                    # player (CharacterBody3D, player-test.gd)

var _charging := false
var _t := 0.0
var _phase := 0
var _last_ms := 0

var _layer: CanvasLayer
var _ring: Ring
var _edge_rect: ColorRect
var _edge_mat: ShaderMaterial
var _if_rect: ColorRect
var _if_mat: ShaderMaterial
var _cross: Control
var _if_busy := false
var _warned := false
var _gunfx: GunFx
var _gun_mat: ShaderMaterial
var _gun_pulse := 0.0
var _gun_tw: Tween
var _spin_clock := 0.0
var _spin_acc := 0.0
var _gl: Sprite2D                                 # layer senjata (berputar)
var _hl: Sprite2D                                 # layer pergelangan idle
var _ol: Sprite2D                                 # layer telapak terbuka
var _oh_frames: Array[AtlasTexture] = []
var _open_failed := false
var _open_i := 0
var _spin_ang := 0.0
var _gl_frames: Array[AtlasTexture] = []
var _hl_frames: Array[AtlasTexture] = []
var _gun_was_visible := true
var _layers_failed := false
var _vis_acc := 1.0
var _step_i := 0


func _ready() -> void:
	_build_fx()


func _exit_tree() -> void:
	if _if_busy:
		Engine.time_scale = 1.0
	_spin_reset()


func is_active() -> bool:
	if not enabled:
		return false
	return (not require_item) or Inventory.has_item(&"trigger")


# Dipanggil player-test.gd tiap physics frame selama Trigger aktif (menggantikan tembak biasa)
func tick(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _charging and now - _last_ms > 250:            # game sempat berhenti (pause / inventory): batalkan
		_cancel()
	_last_ms = now

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if _charging:
			_cancel()
		return

	var h = p.hud
	if not _charging:
		if Input.is_action_just_pressed("shoot"):
			if (h != null and h.is_busy) or p.current_ammo <= 0:
				p.shoot()                             # sibuk / peluru habis: biarkan logika biasa (klik kosong dll.)
				return
			_begin()
		return

	if (h != null and h.is_busy) or p.current_ammo <= 0:
		_cancel()                                     # mulai reload saat charge, dst.
		return
	if not Input.is_action_pressed("shoot"):
		_release()
		return

	_t += delta
	var ph := 0
	for i in phase_time.size():
		if _t >= phase_time[i]:
			ph = i + 1
	if ph > _phase:
		_phase = ph
		_phase_up(ph)
	_update_fx(delta)


func _begin() -> void:
	_charging = true
	_t = 0.0
	_phase = 0
	_vis_acc = 1.0
	_last_ms = Time.get_ticks_msec()
	var h = p.hud
	if h != null:
		_cross = h.get_node_or_null("Crosshairmas/crosshair")


func _cancel() -> void:
	_charging = false
	_t = 0.0
	_phase = 0
	_end_fx()


func _release() -> void:
	var ph := _phase
	_charging = false
	_t = 0.0
	_phase = 0
	_end_fx()
	if ph <= 0:
		p.shoot()                                     # dilepas sebelum phase 1: tembakan biasa
		return
	_fire(ph)


func _phase_up(ph: int) -> void:
	get_tree().call_group("sfx", "play", "ui_tick", -8.0 + ph * 2.0, 0.02)
	if camera_kick and p.camera != null:
		p.camera.fov -= 2.0 + ph * 1.2                # sentakan kecil, FOV balik sendiri
	if camera_kick and "_roll_kick" in p:
		p._roll_kick = deg_to_rad(1.2 * ph) * (1.0 if randf() > 0.5 else -1.0)
	if _ring != null:
		_ring.pulse = 1.0
	_gun_pulse = 1.0
	_spin_clock = 0.0                                   # naik phase = putaran baru langsung mulai
	if _gunfx != null:
		_gunfx.col = phase_colors[mini(ph, phase_colors.size()) - 1]
		_gunfx.flash = 0.6


# =========================================================== tembak
func _fire(ph: int) -> void:
	p.current_ammo -= 1
	p._update_ammo_ui()
	if p.hud != null:
		p.hud.play_shoot()
	get_tree().call_group("sfx", "play", "gun_shot", 1.0, 0.02)
	get_tree().call_group("sfx", "play", "punch_whoosh", -4.0, 0.05)

	var col: Color = phase_colors[mini(ph, phase_colors.size()) - 1]
	var cam: Camera3D = p.camera
	if camera_kick:
		cam.fov -= 6.0 + 3.0 * ph
		if "_roll_kick" in p:
			p._roll_kick = deg_to_rad(2.5 + ph) * (1.0 if randf() > 0.5 else -1.0)

	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * 150.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [p.get_rid()]
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var res: Dictionary = space.intersect_ray(q)
	var end: Vector3 = res.position if not res.is_empty() else to
	var muzzle: Vector3 = cam.global_transform * p.muzzle_offset

	# rencanakan seluruh rantai pantulan dulu (tanpa damage)
	var dmg: float = float(p.gun_damage) * phase_damage_mult[mini(ph, phase_damage_mult.size()) - 1]
	var last: Node = null
	var origin: Vector3 = end
	var enemy_hit := false
	if not res.is_empty():
		if _can_hit(res.collider):
			last = res.collider
			origin = _aim(last)
			enemy_hit = true
		else:
			origin = res.position + res.normal * 0.15     # tembok: tetap memantul ke musuh terdekat
	var plan: Array = []
	if bounce_enabled and not res.is_empty():
		plan = _plan_bounces(origin, last, phase_bounces[mini(ph, phase_bounces.size()) - 1])

	# semuanya mulai saat tembak: jejak langsung muncul, impact frame jalan bersamaan
	_gun_fire(ph, col)
	_impact_frame(ph, end)
	_tracer(muzzle, end, col, 1.0 + 0.5 * ph, -1.0, trail_linger * 0.7)
	if res.is_empty():
		return

	if enemy_hit:
		_hit(last, dmg, res.position, res.normal, col)
	else:
		p.spawn_bullet_hole(res.position, res.normal)
		p.spawn_impact_particles(res.position, res.normal, col)
		_flash(res.position + res.normal * 0.2, col)

	for st in plan:
		if not is_instance_valid(p):
			return
		var en = st["enemy"]
		var ap: Vector3 = st["pos"]
		var travel := clampf(origin.distance_to(ap) / bounce_tracer_speed, 0.04, 0.12)
		_tracer(origin, ap, col, 1.0 + 0.3 * ph, bounce_tracer_speed, trail_linger)   # peluru terbang ke titik berikutnya
		await get_tree().create_timer(travel + hop_delay, true, false, true).timeout    # waktu nyata: tetap jalan saat hit-stop
		if not is_instance_valid(p):
			return
		if en == null:                                                                # pantulan tembok
			var nrm: Vector3 = st["normal"]
			p.spawn_bullet_hole(ap, nrm)
			p.spawn_impact_particles(ap, nrm, col)
			_flash(ap + nrm * 0.2, col)
			_ping(ap, col)
			get_tree().call_group("sfx", "play", "ui_tick", -11.0, 0.12)
			origin = ap + nrm * 0.08
			continue
		if not _can_hit(en):
			break
		dmg *= bounce_falloff
		_hit(en, dmg, ap, (origin - ap).normalized(), col)
		_ping(ap, col)
		get_tree().call_group("sfx", "play", "ui_tick", -9.0, 0.08)
		origin = ap


# Rencana seluruh rantai pantulan (tanpa damage), terdiri dari langkah:
#   {"pos": titik, "normal": normal permukaan, "enemy": musuh atau null (null = pantulan tembok)}
# Tiap langkah (tembok maupun musuh) memakai satu jatah pantulan.
func _plan_bounces(origin: Vector3, last: Node, hops: int) -> Array:
	var out: Array = []
	var o := origin
	var l := last
	var left := hops
	while left > 0:
		var steps := _next_steps(o, l, left)
		if steps.is_empty():
			break
		for st in steps:
			out.append(st)
		left -= steps.size()
		var fin: Dictionary = steps[steps.size() - 1]
		l = fin["enemy"]
		o = fin["pos"] if fin["enemy"] != null else fin["pos"] + (fin["normal"] as Vector3) * 0.08
	return out


# Langkah berikutnya dari titik o: tembak langsung ke musuh dekat yang kelihatan; kalau tidak ada (jauh / terhalang tembok),
# cari rute lewat 1-2 pantulan tembok ke musuh terdekat yang bisa dijangkau; terakhir, tembak langsung ke musuh jauh yang kelihatan.
func _next_steps(o: Vector3, last: Node, left: int) -> Array:
	var ex: Array[RID] = [p.get_rid()]
	if last is CollisionObject3D:
		ex.append((last as CollisionObject3D).get_rid())
	var cands: Array = []
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or e == last or not _can_hit(e):
			continue
		var ap := _aim(e)
		var d := o.distance_to(ap)
		if d <= far_range:
			cands.append([d, e, ap])
	if cands.is_empty():
		if not _warned and get_tree().get_nodes_in_group("enemy").is_empty():
			_warned = true
			push_warning("ChargeShot: tidak ada node di group 'enemy', pantulan tidak punya target")
		return []
	cands.sort_custom(func(a, b): return a[0] < b[0])

	# 1) musuh dekat & kelihatan: langsung
	for c in cands:
		if c[0] >= bounce_range:
			break
		if _los(o, c[2], c[1], ex):
			return [{"pos": c[2], "normal": Vector3.UP, "enemy": c[1]}]

	# 2) lewat pantulan tembok (butuh sisa jatah: tembok + musuh)
	if left >= 2:
		var best: Dictionary = {}
		var tried := 0
		for c in cands:
			if tried >= ricochet_candidates:
				break
			tried += 1
			var route := _ricochet(o, c[1], c[2], ex, mini(max_wall_bounces, left - 1))
			if not route.is_empty() and (best.is_empty() or route["cost"] < best["cost"]):
				best = route
				best["enemy"] = c[1]
				best["ap"] = c[2]
		if not best.is_empty():
			var out: Array = []
			for w in best["walls"]:
				out.append({"pos": w[0], "normal": w[1], "enemy": null})
			out.append({"pos": best["ap"], "normal": Vector3.UP, "enemy": best["enemy"]})
			return out

	# 3) tidak ada rute tembok: musuh jauh yang kelihatan tetap ditembak langsung
	for c in cands:
		if _los(o, c[2], c[1], ex):
			return [{"pos": c[2], "normal": Vector3.UP, "enemy": c[1]}]
	return []


# Cari rute pantulan tembok dari o ke titik bidik ap: coba banyak arah, pantulkan secara fisik (sudut datang = sudut pantul),
# setelah tiap pantulan cek apakah arahnya kira-kira menuju musuh & jalurnya bebas. Dipilih rute terpendek.
# Mengembalikan {"cost": panjang total, "walls": [[titik, normal], ...]} atau {} kalau tidak ada.
func _ricochet(o: Vector3, target: Node, ap: Vector3, ex: Array[RID], max_walls: int) -> Dictionary:
	if max_walls <= 0:
		return {}
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var tol := deg_to_rad(ricochet_tolerance_deg)
	var best: Dictionary = {}
	var best_cost := far_range * 1.8
	var n := maxi(ricochet_dirs, 8)
	var th0 := randf() * TAU
	for i in n:
		var y := 1.0 - 2.0 * (float(i) + 0.5) / float(n)                       # arah tersebar rata di bola
		var rr := sqrt(maxf(1.0 - y * y, 0.0))
		var th := th0 + float(i) * 2.399963
		var dir := Vector3(cos(th) * rr, y, sin(th) * rr)
		var pos := o
		var cost := 0.0
		var walls: Array = []
		for depth in max_walls:
			var q := PhysicsRayQueryParameters3D.create(pos, pos + dir * far_range)
			q.exclude = ex
			var r := space.intersect_ray(q)
			if r.is_empty() or _can_hit(r.collider):
				break
			var hp: Vector3 = r.position
			var nrm: Vector3 = r.normal
			cost += pos.distance_to(hp)
			if cost >= best_cost:
				break
			walls.append([hp, nrm])
			var out_dir := dir.bounce(nrm)
			var np := hp + nrm * 0.08
			var to_t := ap - np
			var dist := to_t.length()
			if dist > 0.5 and out_dir.angle_to(to_t / dist) <= tol and cost + dist < best_cost and _los(np, ap, target, ex):
				best_cost = cost + dist
				best = {"cost": best_cost, "walls": walls.duplicate(true)}
			pos = np
			dir = out_dir
	return best


# garis pandang bebas dari from ke to (kecuali target itu sendiri)
func _los(from: Vector3, to: Vector3, target: Node, ex: Array[RID]) -> bool:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = ex
	var r := space.intersect_ray(q)
	if r.is_empty():
		return true
	var c: Node = r.collider
	return c == target or target.is_ancestor_of(c)


func _hit(target: Node, dmg: float, pos: Vector3, normal: Vector3, col: Color) -> void:
	if target.has_method("take_damage"):
		target.take_damage(dmg)
	p.spawn_impact_particles(pos, normal, Color(0.8, 0.05, 0.05))
	p.spawn_impact_particles(pos, normal, col)
	_flash(pos, col)


# ----- cari musuh berikutnya: terdekat, hidup, kelihatan dari titik pantul, bukan yang barusan kena
func _next_target(origin: Vector3, last: Node) -> Node3D:
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var best: Node3D = null
	var best_d := bounce_range
	var list := get_tree().get_nodes_in_group("enemy")
	if list.is_empty() and not _warned:
		_warned = true
		push_warning("ChargeShot: tidak ada node di group 'enemy', pantulan tidak punya target")
	for n in list:
		var e := n as Node3D
		if e == null or e == last or not is_instance_valid(e) or not _can_hit(e):
			continue
		var ap := _aim(e)
		var d := origin.distance_to(ap)
		if d >= best_d:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, ap)
		var ex: Array[RID] = [p.get_rid()]
		if last is CollisionObject3D:
			ex.append((last as CollisionObject3D).get_rid())
		q.exclude = ex
		var r := space.intersect_ray(q)
		if not r.is_empty():
			var c: Node = r.collider
			if c != e and not e.is_ancestor_of(c):
				continue                              # ada tembok di antara
		best = e
		best_d = d
	return best


func _can_hit(n: Object) -> bool:
	if n == null or not is_instance_valid(n) or not (n is Node):
		return false
	var nd := n as Node
	if not nd.has_method("take_damage") or nd.is_queued_for_deletion():
		return false
	for k in ["dead", "is_dead", "_dead"]:
		var v = nd.get(k)
		if v is bool and v:
			return false
	var hp = nd.get("hp")
	if hp == null:
		hp = nd.get("health")
	if (hp is float or hp is int) and hp <= 0:
		return false
	return true


# titik bidik di badan musuh: tengah CollisionShape3D-nya (atau 1m di atas kaki)
func _aim(n: Node) -> Vector3:
	if n.has_method("get_aim_point"):
		return n.get_aim_point()
	for c in n.get_children():
		if c is CollisionShape3D:
			return (c as CollisionShape3D).global_position
	return (n as Node3D).global_position + Vector3.UP


# =========================================================== visual dunia
func _tracer(a: Vector3, b: Vector3, col: Color, width_mult: float, speed := -1.0, linger := 0.0) -> void:
	var dist := a.distance_to(b)
	var scene := get_tree().current_scene
	if dist < 0.3 or scene == null:
		return
	var dir := (b - a) / dist
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var b0 := Basis.looking_at(dir, up)
	var root := Node3D.new()
	for k in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(1.0, 0.97, 0.9, 1.0) if k == 0 else Color(col, 0.45)
		var bm := BoxMesh.new()
		var w := tracer_width * width_mult * (1.0 if k == 0 else 3.5)
		bm.size = Vector3(w, w, 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	scene.add_child(root)
	root.visible = false
	var spd := tracer_speed if speed <= 0.0 else speed
	var tl := minf(tracer_length, dist * 0.55)
	var dur := maxf((dist + tl) / spd, 0.05)
	var steps := maxi(3, int(dur * fx_fps))               # peluru maju per frame, bukan mulus
	var tw := root.create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_method(_tracer_step.bind(root, a, dir, b0, dist, tl, steps), 0.0, 1.0, dur)
	tw.tween_callback(root.queue_free)
	if linger > 0.0:
		_trail(a, b, col, width_mult, linger)


func _tracer_step(k: float, root: Node3D, a: Vector3, dir: Vector3, b0: Basis, dist: float, tl: float, steps: int) -> void:
	if not is_instance_valid(root):
		return
	k = floorf(k * steps) / float(steps)
	var pos := k * (dist + tl)
	var head := minf(pos, dist)
	var tail := clampf(pos - tl, 0.0, dist)
	var seg := head - tail
	if seg < 0.01:
		root.visible = false
		return
	root.visible = true
	root.global_transform = Transform3D(b0 * Basis.from_scale(Vector3(1.0, 1.0, seg)), a + dir * (tail + seg * 0.5))


# Jejak garis yang tertinggal (menipis lalu hilang): supaya lintasan pantulan terbaca, bukan cuma garis cepat yang lewat
func _trail(a: Vector3, b: Vector3, col: Color, width_mult: float, life: float) -> void:
	var dist := a.distance_to(b)
	var scene := get_tree().current_scene
	if dist < 0.3 or scene == null:
		return
	var dir := (b - a) / dist
	var side := dir.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up2 := dir.cross(side).normalized()

	var mc := StandardMaterial3D.new()                      # inti putih-panas
	var mg := StandardMaterial3D.new()                      # glow warna phase
	for m in [mc, mg]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mc.albedo_color = Color(1.0, 0.97, 0.9, 1.0)
	mg.albedo_color = Color(col.lightened(0.15), 0.5)

	# garis bergerigi (seperti petir) dari a ke b, supaya terbaca sebagai pantulan bukan garis lurus biasa
	var pts: Array[Vector3] = [a]
	var segs := clampi(int(dist / 2.0) + 3, 4, 9)
	var amp := minf(0.22, dist * 0.02)
	for k in range(1, segs):
		var f := float(k) / float(segs)
		pts.append(a + dir * dist * f + side * randf_range(-amp, amp) + up2 * randf_range(-amp, amp))
	pts.append(b)

	var root := Node3D.new()
	scene.add_child(root)
	root.global_transform = Transform3D.IDENTITY
	var meshes: Array = []                                  # [mesh, ukuran dasar, apakah z (panjang) ikut mengecil]
	var w := tracer_width * width_mult
	for k in pts.size() - 1:
		var sa := pts[k]
		var sb := pts[k + 1]
		var sl := sa.distance_to(sb)
		if sl < 0.01:
			continue
		var sd := (sb - sa) / sl
		var sup := Vector3.UP if absf(sd.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
		var bs := Basis.looking_at(sd, sup)
		for layer in 2:
			var bm := BoxMesh.new()
			var base := Vector3(w, w, sl) if layer == 0 else Vector3(w * 4.0, w * 4.0, sl)
			bm.size = base
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.material_override = mc if layer == 0 else mg
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)
			mi.transform = Transform3D(bs, sa + sd * sl * 0.5)
			meshes.append([bm, base, false])
	# kotak kecil di tiap sudut pantulan (titik sambungan tetap menyala sebentar)
	for pt in [b]:
		var cm := BoxMesh.new()
		var cb := Vector3.ONE * w * 7.0
		cm.size = cb
		var ci := MeshInstance3D.new()
		ci.mesh = cm
		ci.material_override = mc
		ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ci)
		ci.transform = Transform3D(Basis(Vector3.RIGHT, randf() * TAU) * Basis(Vector3.UP, randf() * TAU), pt)
		meshes.append([cm, cb, true])

	var dt := 1.0 / maxf(fx_fps, 1.0)
	var n := maxi(3, int(life / dt))
	var tw := root.create_tween()
	tw.set_ignore_time_scale(true)
	for k in range(1, n + 1):                               # memudar & menipis bertahap per frame
		tw.tween_interval(dt)
		tw.tween_callback(_trail_step.bind(root, mc, mg, meshes, 1.0 - float(k) / float(n)))
	tw.tween_callback(root.queue_free)


func _trail_step(root: Node3D, mc: StandardMaterial3D, mg: StandardMaterial3D, meshes: Array, f: float) -> void:
	if not is_instance_valid(root):
		return
	var c := mc.albedo_color
	c.a = f
	mc.albedo_color = c
	var g := mg.albedo_color
	g.a = 0.5 * f
	mg.albedo_color = g
	var sc := lerpf(0.25, 1.0, f)
	for e in meshes:
		var bm: BoxMesh = e[0]
		var base: Vector3 = e[1]
		bm.size = Vector3(base.x * sc, base.y * sc, base.z * (sc if e[2] else 1.0))


# Titik pantul: bola cahaya yang membesar cepat lalu hilang, supaya kelihatan "kena lalu belok"
func _ping(pos: Vector3, col: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.lightened(0.5), 1.0)
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(mi)
	mi.global_position = pos
	var dt := 1.0 / maxf(fx_fps, 1.0)
	var tw := mi.create_tween()
	tw.set_ignore_time_scale(true)
	var seq := [[0.2, 1.0], [0.45, 0.65], [0.7, 0.3]]        # 3 frame: kecil -> besar -> pudar
	for st in seq:
		tw.tween_callback(_ping_step.bind(mi, m, st[0], st[1]))
		tw.tween_interval(dt)
	tw.tween_callback(mi.queue_free)


func _ping_step(mi: MeshInstance3D, m: StandardMaterial3D, sc: float, a: float) -> void:
	if not is_instance_valid(mi):
		return
	mi.scale = Vector3.ONE * sc
	var c := m.albedo_color
	c.a = a
	m.albedo_color = c


func _flash(pos: Vector3, col: Color) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 4.5
	l.shadow_enabled = false
	scene.add_child(l)
	l.global_position = pos
	var dt := 1.0 / maxf(fx_fps, 1.0)
	var tw := l.create_tween()
	tw.set_ignore_time_scale(true)
	for e in [1.6, 0.6]:                                   # meredup per frame
		tw.tween_interval(dt)
		tw.tween_callback(_flash_step.bind(l, e))
	tw.tween_interval(dt)
	tw.tween_callback(l.queue_free)


func _flash_step(l: OmniLight3D, e: float) -> void:
	if is_instance_valid(l):
		l.light_energy = e


# =========================================================== visual layar
func _build_fx() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	var sh := Shader.new()
	sh.code = EDGE_SHADER
	_edge_mat = ShaderMaterial.new()
	_edge_mat.shader = sh
	_edge_rect = ColorRect.new()
	_edge_rect.material = _edge_mat
	_edge_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge_rect.visible = false
	_layer.add_child(_edge_rect)
	_edge_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_ring = Ring.new()
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.custom_minimum_size = Vector2(120, 120)
	_ring.size = Vector2(120, 120)
	_ring.visible = false
	var n := phase_time.size()
	for i in n:
		_ring.marks.append(phase_time[i] / phase_time[n - 1])
	_ring.cols = phase_colors.duplicate()
	_ring.bounces = phase_bounces.duplicate()
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_ring.font = load("res://font/Rajdhani-Bold.ttf")
	_layer.add_child(_ring)

	var sh2 := Shader.new()
	sh2.code = IF_SHADER
	_if_mat = ShaderMaterial.new()
	_if_mat.shader = sh2
	_if_rect = ColorRect.new()
	_if_rect.material = _if_mat
	_if_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_if_rect.visible = false
	_layer.add_child(_if_rect)
	_if_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _update_fx(delta: float) -> void:
	if not charge_fx or _ring == null:
		return
	var total: float = phase_time[phase_time.size() - 1]
	var level := clampf(_t / total, 0.0, 1.0)
	var show := _t >= SHOW_DELAY
	var col: Color = phase_colors[maxi(_phase, 1) - 1]

	# indikator tengah (ring + crosshair): MULUS, diperbarui tiap frame
	_ring.visible = show
	if show:
		_ring.position = get_viewport().get_visible_rect().size * 0.5 - _ring.size * 0.5
		_ring.level = level
		_ring.phase = _phase
		_ring.pulse = maxf(_ring.pulse - delta * 4.0, 0.0)
		_ring.queue_redraw()
		if _cross != null and is_instance_valid(_cross):
			_cross.pivot_offset = _cross.size * 0.5
			_cross.scale = Vector2.ONE * lerpf(1.0, 0.72, level)
			_cross.modulate = Color.WHITE.lerp(col, clampf(level * 1.5, 0.0, 1.0))

	# senjata berputar: dihitung pada spin_fps (per frame), terpisah dari kecepatan fx lain
	if spin_enabled and show:
		_spin_acc += delta
		var sdt := 1.0 / maxf(spin_fps, 1.0)
		if _spin_acc >= sdt:
			_spin_acc = fmod(_spin_acc, sdt)
			_spin_clock += sdt
			_apply_spin()

	# vignette tepi + senjata: FRAME PER FRAME pada fx_fps
	_vis_acc += delta
	var dt := 1.0 / maxf(fx_fps, 1.0)
	if _vis_acc < dt:
		return
	_vis_acc = fmod(_vis_acc, dt)
	_step_i += 1
	_edge_rect.visible = show and _phase > 0
	_update_gun(show, snappedf(level, 0.05))
	if show:
		_edge_mat.set_shader_parameter("tint", col)
		_edge_mat.set_shader_parameter("amount", snappedf(0.12 * _phase + 0.25 * _ring.pulse, 0.04))


func _end_fx() -> void:
	if _ring != null:
		_ring.visible = false
		_ring.level = 0.0
		_ring.phase = 0
		_ring.pulse = 0.0
		_edge_rect.visible = false
	if _cross != null and is_instance_valid(_cross):
		_cross.scale = Vector2.ONE
		_cross.modulate = Color.WHITE
	var h = p.hud
	if h != null and h.gun != null:
		h.gun.offset = Vector2.ZERO
		h.gun.self_modulate = Color.WHITE
	if _gunfx != null:
		_gunfx.charging = false
		_gunfx.level = 0.0
		_gunfx.phase = 0
	_spin_reset()
	_gun_off()


# ---------------------------------------------------------- senjata berputar
# Twirl: senjata berputar 360 derajat mengelilingi spin_pivot (seperti memutar revolver di jari), terangkat sedikit di puncak.
# Phase 1: sesekali, phase 2: lebih sering & cepat, phase 3: terus-menerus. Posisi/skala/rotasi dikembalikan saat charge selesai.
func _load_layers() -> bool:
	if not _gl_frames.is_empty():
		return true
	if _layers_failed:
		return false
	if not (ResourceLoader.exists(gun_layer_path) and ResourceLoader.exists(hand_layer_path)):
		_layers_failed = true
		push_warning("ChargeShot: sheet layer senjata/tangan tidak ditemukan (%s, %s). Putaran dimatikan." % [gun_layer_path, hand_layer_path])
		return false
	var gt: Texture2D = load(gun_layer_path)
	var ht: Texture2D = load(hand_layer_path)
	var n: int = maxi(gt.get_width() / layer_frame_size.x, 1)
	for i in n:
		var ga := AtlasTexture.new()
		ga.atlas = gt
		ga.region = Rect2(i * layer_frame_size.x, 0, layer_frame_size.x, layer_frame_size.y)
		_gl_frames.append(ga)
		var ha := AtlasTexture.new()
		ha.atlas = ht
		ha.region = Rect2(i * layer_frame_size.x, 0, layer_frame_size.x, layer_frame_size.y)
		_hl_frames.append(ha)
	return true


func _mk_layer(gun: AnimatedSprite2D) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.centered = gun.centered
	sp.texture_filter = gun.texture_filter
	sp.z_index = gun.z_index
	sp.z_as_relative = gun.z_as_relative
	sp.flip_h = gun.flip_h
	sp.flip_v = gun.flip_v
	return sp


func _load_open_hand() -> bool:
	if not _oh_frames.is_empty():
		return true
	if _open_failed or not open_hand_enabled:
		return false
	if not ResourceLoader.exists(open_hand_path):
		_open_failed = true
		push_warning("ChargeShot: sheet tangan terbuka tidak ditemukan (%s). Telapak terbuka dimatikan, ubah open_hand_path." % open_hand_path)
		return false
	var t: Texture2D = load(open_hand_path)
	for idx in open_hand_seq:
		var at := AtlasTexture.new()
		at.atlas = t
		at.region = Rect2((idx % open_hand_cols) * open_hand_cell.x, (idx / open_hand_cols) * open_hand_cell.y, open_hand_cell.x, open_hand_cell.y)
		_oh_frames.append(at)
	return true


func _apply_spin() -> void:
	var h = p.hud
	if _phase < 1 or h == null or h.gun == null or not _load_layers():
		return
	var gun: AnimatedSprite2D = h.gun
	var par: Node = gun.get_parent()
	var use_open: bool = _load_open_hand()
	if _gl == null or not is_instance_valid(_gl):
		_gun_was_visible = gun.visible
		_gl = _mk_layer(gun)
		_hl = _mk_layer(gun)
		_ol = _mk_layer(gun)
		par.add_child(_hl)
		par.add_child(_ol)
		par.add_child(_gl)
		var gi := gun.get_index()
		par.move_child(_hl, gi + 1)                 # urutan: pergelangan -> telapak terbuka -> senjata (paling depan)
		par.move_child(_ol, gi + 2)
		par.move_child(_gl, gi + 3)
		_open_i = 0
		_spin_ang = 0.0
	gun.visible = false
	var n := _gl_frames.size()
	var fr: int = (gun.frame % n) if gun.animation == &"idle" else 0
	_gl.texture = _gl_frames[fr]
	_hl.texture = _hl_frames[fr]
	_gl.material = gun.material                    # garis tepi / isi / percikan menempel ke senjata saja
	_gl.offset = gun.offset
	_hl.offset = Vector2.ZERO

	var bpos := gun.position
	var bscale := gun.scale
	var brot := gun.rotation
	var step := 1.0 / maxf(spin_fps, 1.0)

	# 1) telapak membuka dulu (frame demi frame), baru senjata mulai berputar
	var opened := true
	if use_open:
		var last := _oh_frames.size() - 1
		_open_i = mini(_open_i + 1, last + open_hold_frames)
		opened = _open_i >= last + open_hold_frames
		_ol.visible = true
		_ol.texture = _oh_frames[mini(_open_i, last)]
		_ol.offset = Vector2(-(open_hand_cell.x - layer_frame_size.x) * 0.5 + open_hand_pad, 0.0) + open_hand_shift
		_ol.position = bpos
		_ol.rotation = brot
		_ol.scale = bscale
	else:
		_ol.visible = false
	var rdy := 1.0 if opened else clampf(float(_open_i) / float(maxi(_oh_frames.size() + open_hold_frames, 1)), 0.0, 1.0)

	# 2) senjata berputar TERUS (searah jarum jam) sampai tombol dilepas; makin cepat tiap phase
	if opened:
		var dur: float = [0.0, 0.8, 0.55, 0.38][clampi(_phase, 0, 3)]
		_spin_ang += TAU * step / maxf(dur, 0.05)
		_spin_ang = fmod(_spin_ang, TAU)
	var a := _spin_ang
	var grow := 1.0 + spin_grow * 0.5 * (1.0 - cos(a - PI / 3.0)) * rdy   # lewat dekat kamera = membesar
	var lift := spin_lift * rdy
	var pv := bpos + (spin_pivot * bscale).rotated(brot)
	var rel := bpos - pv
	_gl.rotation = brot + a
	_gl.position = pv + rel.rotated(a) * grow + Vector2(0.0, -lift)
	_gl.scale = bscale * grow

	# pergelangan idle tidak diapa-apakan (tidak diskala / diputar) supaya telapak tidak rusak
	_hl.rotation = brot
	_hl.position = bpos
	_hl.scale = bscale


func _spin_reset() -> void:
	_spin_clock = 0.0
	_spin_ang = 0.0
	_open_i = 0
	var h = p.hud if p != null else null
	for l in [_gl, _hl, _ol]:
		if l != null and is_instance_valid(l):
			l.queue_free()
	if _gl != null or _hl != null:
		if h != null and h.gun != null:
			h.gun.visible = _gun_was_visible
	_gl = null
	_hl = null
	_ol = null


# ---------------------------------------------------------- senjata di HUD
# Efek mengikuti siluet sprite senjata sendiri: garis tepi warna phase + sprite menghangat. Tidak butuh tebakan posisi.
func _ensure_gun_fx(h) -> bool:
	if not gun_fx or h == null or h.gun == null:
		return false
	if _gun_mat == null:
		var sh := Shader.new()
		sh.code = GUN_SHADER
		_gun_mat = ShaderMaterial.new()
		_gun_mat.shader = sh
	if muzzle_fx and (_gunfx == null or not is_instance_valid(_gunfx)):
		_gunfx = GunFx.new()
		_gunfx.position = gun_fx_offset
		h.gun.add_child(_gunfx)
	return true


func _gun_off() -> void:
	var h = p.hud
	if h != null and h.gun != null and _gun_mat != null and h.gun.material == _gun_mat and not _charging:
		if _gun_tw != null and _gun_tw.is_valid():
			return                                          # sedang memudar, nanti dilepas sendiri
		h.gun.material = null


func _update_gun(show: bool, level: float) -> void:
	var h = p.hud
	if not _ensure_gun_fx(h):
		return
	var gun: AnimatedSprite2D = h.gun
	if _gunfx != null:
		_gunfx.position = gun_fx_offset
		_gunfx.charging = show
	if not show:
		return
	if _gun_tw != null and _gun_tw.is_valid():
		_gun_tw.kill()
	var col: Color = phase_colors[maxi(_phase, 1) - 1]
	gun.material = _gun_mat
	_gun_pulse = maxf(_gun_pulse - 0.34, 0.0)
	var beat := float(_step_i % 2)                         # berkedip per frame, bukan berdenyut mulus
	var sparkle: float = [0.0, 0.3, 0.55, 0.85][clampi(_phase, 0, 3)]
	_gun_mat.set_shader_parameter("line_col", col.lightened(0.25) if _phase >= 3 else col)
	_gun_mat.set_shader_parameter("strength", snappedf(clampf(level * 0.8 + 0.15 + _gun_pulse * 0.6 + beat * 0.12 * _phase, 0.0, 1.0), 0.25))
	_gun_mat.set_shader_parameter("heat", snappedf(clampf(float(_phase) * 0.12 + _gun_pulse * 0.4, 0.0, 0.6), 0.1))
	_gun_mat.set_shader_parameter("fill", snappedf(level, 0.1))
	_gun_mat.set_shader_parameter("sparkle", clampf(sparkle + _gun_pulse * 0.4, 0.0, 1.0))
	_gun_mat.set_shader_parameter("seed", randf() * 100.0)  # piksel percikan berganti tiap frame
	_gun_mat.set_shader_parameter("flash", 0.0)
	_gun_mat.set_shader_parameter("half_h", _gun_half_h(gun))
	var amp := 0.5 * _phase                            # getar senjata makin kuat per phase
	gun.offset = Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
	if _gunfx != null:
		_gunfx.col = col
		_gunfx.level = level
		_gunfx.phase = _phase


# tinggi frame sprite senjata saat ini (setengahnya), dipakai untuk isi charge dari bawah ke atas
func _gun_half_h(gun: AnimatedSprite2D) -> float:
	if gun.sprite_frames != null and gun.sprite_frames.has_animation(gun.animation):
		var tex := gun.sprite_frames.get_frame_texture(gun.animation, gun.frame)
		if tex != null:
			return tex.get_height() * 0.5
	return 90.0


# Tembak: garis tepi + panas menyambar lalu memudar, senjata terhentak (naik cepat, balik pelan)
func _gun_fire(ph: int, col: Color) -> void:
	var h = p.hud
	if not _ensure_gun_fx(h):
		return
	var gun: AnimatedSprite2D = h.gun
	if _gunfx != null:
		_gunfx.burst(col, ph)
	var base := gun.position
	var kick := Vector2(5.0 * ph, 18.0 + 8.0 * ph)
	var dt := 1.0 / maxf(fx_fps, 1.0)
	gun.material = _gun_mat
	gun.offset = Vector2.ZERO
	_gun_mat.set_shader_parameter("line_col", col.lightened(0.3))
	_gun_mat.set_shader_parameter("half_h", _gun_half_h(gun))
	# [flash(0/1 siluet putih/2 negatif), garis tepi, panas, isi, percikan, hentakan, lama (x dt)]
	var seq := [
		[1.0, 1.0, 0.0, 0.0, 1.0, 1.0, 0.5],
		[2.0, 1.0, 0.0, 0.0, 1.0, 0.8, 0.5],
		[0.0, 1.0, 0.9, 1.0, 0.9, 0.5, 1.0],
		[0.0, 0.75, 0.6, 0.7, 0.6, 0.25, 1.0],
		[0.0, 0.5, 0.35, 0.4, 0.3, 0.0, 1.0],
		[0.0, 0.25, 0.15, 0.2, 0.0, 0.0, 1.0],
		[0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
	]
	for st in seq:
		if not is_instance_valid(gun):
			return
		_gun_mat.set_shader_parameter("flash", st[0])
		_gun_mat.set_shader_parameter("strength", st[1])
		_gun_mat.set_shader_parameter("heat", st[2])
		_gun_mat.set_shader_parameter("fill", st[3])
		_gun_mat.set_shader_parameter("sparkle", st[4])
		_gun_mat.set_shader_parameter("seed", randf() * 100.0)
		gun.position = base + kick * st[5]
		if st[6] > 0.0:
			await get_tree().create_timer(dt * st[6], true, false, true).timeout
	if is_instance_valid(gun):
		gun.position = base
	_gun_clear()


func _gun_clear() -> void:
	var h = p.hud
	if not _charging and h != null and h.gun != null and h.gun.material == _gun_mat:
		h.gun.material = null


# Impact frame (phase 2+): animasi per-frame ala stop-motion pada `impact_fps` (frame per detik), tiap frame digambar ulang
# (bintang bergerigi baru, rotasi baru). Hitam pekat + bintang putih, negatif selang-seling, phase 3 ada frame berwarna.
# Bagian akhir memudar bertahap (bukan mulus), semua juga per-frame. Game ditahan (hit-stop) selama frame utama.
func _impact_frame(ph: int, hit_pos: Vector3) -> void:
	if not impact_frame_fx or ph < 2 or _if_busy or _if_rect == null:
		return
	_if_busy = true
	var cam: Camera3D = p.camera
	var vp := get_viewport().get_visible_rect().size
	var sp := vp * 0.5
	if not cam.is_position_behind(hit_pos):
		sp = cam.unproject_position(hit_pos)
	var col: Color = phase_colors[mini(ph, phase_colors.size()) - 1]
	var ctr := ((sp / vp) * 0.6 + Vector2(0.5, 0.5) * 0.4).clamp(Vector2(0.25, 0.25), Vector2(0.75, 0.75))
	_if_mat.set_shader_parameter("center", ctr)
	_if_mat.set_shader_parameter("tint", col)
	_if_mat.set_shader_parameter("amount", 1.0)
	var n := maxi(impact_frames_p2 if ph == 2 else impact_frames_p3, 3)
	var dt := 1.0 / maxf(impact_fps, 1.0)
	var rot0 := randf() * 1.5708
	var color_i := n - 3 if ph >= 3 else -1                   # satu frame berwarna di phase 3
	var prev := Engine.time_scale
	Engine.time_scale = 0.03
	_if_rect.visible = true
	# ---- awal: overlay scope abu-abu dengan blur zoom (layar asli, bukan fade). Frame muncul langsung penuh.
	var pre_blur: Array = [0.55, 0.95] if ph == 2 else [0.45, 0.75, 1.0]
	_if_mat.set_shader_parameter("soft", 1.0)
	_if_mat.set_shader_parameter("gray", 1.0)
	_if_mat.set_shader_parameter("scope", 1.0)
	_if_mat.set_shader_parameter("inv", 0.0)
	_if_mat.set_shader_parameter("colored", 0.0)
	for k in pre_blur.size():
		_if_mat.set_shader_parameter("blur", pre_blur[k])
		_if_mat.set_shader_parameter("zoom", 0.97 - 0.02 * k)
		_if_mat.set_shader_parameter("shake", 0.003)
		_if_mat.set_shader_parameter("seed", randf() * 100.0)
		await get_tree().create_timer(dt, true, false, true).timeout
	_if_mat.set_shader_parameter("soft", 0.0)
	_if_mat.set_shader_parameter("gray", 0.0)
	_if_mat.set_shader_parameter("scope", 0.0)
	for i in n:
		var t := float(i) / float(n - 1)
		_if_mat.set_shader_parameter("burst", lerpf(0.35, 1.25, minf(t * 1.6, 1.0)))     # bintang membesar cepat lalu tertahan
		_if_mat.set_shader_parameter("blur", lerpf(0.4, 1.0, minf(t * 2.0, 1.0)))
		_if_mat.set_shader_parameter("zoom", lerpf(0.97, 0.88, t))                      # zoom-in makin dalam
		_if_mat.set_shader_parameter("shake", 0.004 + 0.012 * t)
		var neg := 1.0 if (i >= 2 and i % 2 == 0) else 0.0                                # negatif selang-seling mulai frame ke-3
		if i == color_i:
			neg = 0.0
		_if_mat.set_shader_parameter("inv", neg)
		_if_mat.set_shader_parameter("colored", 1.0 if i == color_i else 0.0)
		_if_mat.set_shader_parameter("rot", rot0 + randf_range(-0.2, 0.2))
		_if_mat.set_shader_parameter("seed", randf() * 100.0)                            # bentuk gerigi beda tiap frame
		await get_tree().create_timer(dt, true, false, true).timeout
	Engine.time_scale = prev if prev > 0.2 else 1.0
	if camera_kick:
		if p.camera != null:
			p.camera.fov -= 5.0 * ph
		if "_roll_kick" in p:
			p._roll_kick = deg_to_rad(3.0 * ph) * (1.0 if randf() > 0.5 else -1.0)
	_if_mat.set_shader_parameter("inv", 0.0)
	_if_mat.set_shader_parameter("colored", 0.0)
	_if_mat.set_shader_parameter("shake", 0.0)
	# ---- akhir: layar asli dengan blur zoom yang mengendur bertahap (abu-abu kembali berwarna), tanpa fade transparan
	var tail_blur: Array = [0.9, 0.6, 0.32, 0.12] if ph == 2 else [1.0, 0.8, 0.6, 0.4, 0.22, 0.08]
	var tdt := 1.0 / maxf(impact_tail_fps, 1.0)
	_if_mat.set_shader_parameter("amount", 1.0)
	_if_mat.set_shader_parameter("soft", 1.0)
	_if_mat.set_shader_parameter("scope", 0.0)
	for k in tail_blur.size():
		var f := float(k) / float(tail_blur.size() - 1)
		_if_mat.set_shader_parameter("blur", tail_blur[k])
		_if_mat.set_shader_parameter("gray", maxf(0.6 - 0.6 * f * 1.6, 0.0))
		_if_mat.set_shader_parameter("zoom", lerpf(0.92, 1.0, f))
		_if_mat.set_shader_parameter("shake", 0.0)
		_if_mat.set_shader_parameter("seed", randf() * 100.0)
		await get_tree().create_timer(tdt, true, false, true).timeout
	_if_mat.set_shader_parameter("soft", 0.0)
	_if_rect.visible = false
	_if_busy = false
