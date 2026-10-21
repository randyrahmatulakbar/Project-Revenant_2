class_name DeathScreen
extends CanvasLayer
## DEATH SCREEN "TEBAS + SINYAL PUTUS". Cepat (~2 detik sampai bisa restart).
## Dipanggil dari player: DeathScreen.play(self, "Flayer")
##
## Urutan:
##   1. TEBAS    : frame terakhir game dibeku-kan, garis tebasan menyambar, layar terbelah & jatuh
##   2. LAMBANG  : silinder revolver menghantam dari dekat, lalu ikut ditebas
##   3. END CARD : lambang naik, "D E C E A S E D" + garis EKG flatline + pembunuh + saran
##   4. ULANG    : tekan apa saja -> glitch, scene reload, mata terbuka sebentar
## Game di-pause selama death screen. Setelah restart intro boot TIDAK diputar ulang.

@export_group("Waktu")
@export var skip_after: float = 0.9            # setelah sekian detik, tombol apa saja langsung ulang
@export var auto_restart: float = 10.0         # ulang otomatis kalau gak ada input (0 = nunggu terus)
@export var font: Font                         # kosong = font monospace sistem
@export_group("Suara")
@export var sfx_dir: String = "res://sfx/"
@export var sfx_volume_db: float = 0.0
@export_group("Warna")
@export var bone_color: Color = Color(0.95, 0.92, 0.84)
@export var accent_color: Color = Color(1.0, 0.72, 0.27)
@export var bad_color: Color = Color(1.0, 0.3, 0.25)

const VOID_SHADER := """
shader_type canvas_item;
uniform vec4 center_col : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 edge_col : source_color = vec4(0.0, 0.0, 0.01, 1.0);
uniform float aspect = 1.78;
uniform float glow = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= aspect;
	float k = smoothstep(0.0, 0.85, length(uv));
	vec3 col = mix(center_col.rgb, edge_col.rgb, k);
	col += vec3(1.0, 0.7, 0.3) * glow * (1.0 - k) * 0.35;
	float n = fract(sin(dot(UV * vec2(1234.5, 987.6) + TIME, vec2(12.9898, 78.233))) * 43758.5453);
	col += (n - 0.5) * 0.035;
	COLOR = vec4(col, 1.0);
}
"""

# Belahan frame game (TextureRect): buang separuh bidang di satu sisi garis tebasan.
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

# Potong gambar buatan _draw (lambang): pakai posisi lokal, bukan UV.
const CUT_SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(0.0);
uniform vec2 n = vec2(0.0, 1.0);
uniform float side = 1.0;
varying vec2 v_pos;
void vertex() { v_pos = VERTEX; }
void fragment() {
	if (dot(v_pos - center, n) * side < 0.0) { discard; }
}
"""

# Lapisan layar monitor di paling atas: scanline, pecah warna, vinyet, + kelopak mata saat restart.
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

# Tulisan per pembunuh: judul (spasi otomatis), kalimat, dan tips. Dipilih acak, tidak sama dua kali berturut-turut.
const LINES := {
	"flayer": {
		"titles": ["SHREDDED", "FLAYED", "CARVED UP", "OPENED"],
		"lines": ["THE FLAYER TOOK ITS TIME.", "FLAYED BEFORE YOU COULD BLINK.", "A FLURRY OF CLAWS. THEN NOTHING.", "IT NEVER STOPPED SWINGING."],
		"tips": [
			"PARRY ITS JABS JUST BEFORE THEY LAND. TWO PARRIES DROP IT.",
			"IT IS FAST. DO NOT RUN FROM IT, MEET THE JAB WITH A PARRY.",
			"BACK AWAY AND IT FOLLOWS. PARRY THE NEXT JAB INSTEAD.",
		],
	},
	"mauler": {
		"titles": ["MAULED", "CRUSHED", "BROKEN", "FLATTENED"],
		"lines": ["THE MAULER DID NOT EVEN SLOW DOWN.", "ONE BLOW TOO MANY.", "YOU TRADED BLOWS WITH A WALL.", "SOME THINGS ARE NOT MEANT TO BE PUNCHED."],
		"tips": [
			"DO NOT TRADE BLOWS. PARRY, THEN SHOOT.",
			"IT HITS SLOW AND HARD. PARRY THE SWING, THEN BACK OFF AND FIRE.",
			"KEEP YOUR DISTANCE UNTIL YOU CAN PARRY.",
		],
	},
	"leaper": {
		"titles": ["POUNCED", "RUN DOWN", "TORN DOWN", "TACKLED"],
		"lines": ["THE LEAPER CAME FROM NOWHERE.", "YOU LOOKED AWAY FOR ONE SECOND.", "IT CLOSED THE GAP IN A SINGLE BOUND.", "NOWHERE LEFT TO RUN."],
		"tips": [
			"PARRY THE POUNCE MID-AIR. 1.5X DAMAGE KILLS IT OUTRIGHT.",
			"A LEAPER IN THE AIR CAN BE PARRIED. A LEAPER ON YOUR BACK CANNOT.",
			"DO NOT TURN YOUR BACK ON ANYTHING THAT JUMPS.",
		],
	},
	"spitter": {
		"titles": ["MELTED", "DISSOLVED", "POISONED", "CORRODED"],
		"lines": ["THE SPITTER NEVER CAME CLOSE.", "YOU STOOD IN THE ACID.", "SLOWLY, THEN ALL AT ONCE.", "DEATH BY A THOUSAND DROPS."],
		"tips": [
			"PARRY THE GLOB. IT RETURNS TO SENDER FOR 20 DAMAGE.",
			"KEEP MOVING. POISON PUNISHES ANYONE STANDING STILL.",
			"CLOSE THE DISTANCE OR BREAK LINE OF SIGHT. DO NOT STAND IN ITS RANGE.",
		],
	},
	"the fall": {
		"titles": ["FELL", "LOST YOUR FOOTING", "DROPPED", "MISSED THE LEDGE"],
		"lines": ["THE SHAFT KEPT WHAT YOU DROPPED.", "THE FLOOR WAS FARTHER THAN IT LOOKED.", "GRAVITY ALWAYS WINS EVENTUALLY.", "NOBODY HEARD YOU LAND."],
		"tips": [
			"SPRINT BEFORE A LONG JUMP. JUMP AT THE VERY EDGE.",
			"WALL JUMP TO RECOVER HEIGHT. LANDING RESETS THE COUNT.",
			"CRACKED PLATES DO NOT HOLD. DO NOT STOP ON THEM.",
		],
	},
}
const GENERIC := {
	"titles": ["D E C E A S E D"],
	"lines": [""],
	"tips": [
		"KEEP MOVING. NOBODY SURVIVES STANDING STILL.",
		"RELOAD BEFORE YOU ARE CORNERED.",
		"SLIDE TO BREAK OUT OF A CROWD.",
		"THE FIST HITS HARD ENOUGH. USE IT.",
	],
}
const REPEAT_LINES := ["AGAIN.", "THE SAME ONE. AGAIN.", "YOU KNOW HOW THIS GOES.", "IT REMEMBERS YOU."]

static var _last_killer: String = ""
static var _streak: int = 0
static var _last_pick := {}

static var deaths: int = 0

var killer: String = ""

var _void: ColorRect
var _void_mat: ShaderMaterial
var _ash: CPUParticles2D
var _stage: Control
var _halves: Array[TextureRect] = []
var _hmat: Array[ShaderMaterial] = []
var _beam: ColorRect
var _ui: Control
var _emblem: Control
var _eh: Array[Cylinder] = []
var _emat: Array[ShaderMaterial] = []
var _flat: Flat
var _l_count: Label
var _l_title: Label
var _l_killer: Label
var _l_tip: Label
var _l_prompt: Label
var _flash: ColorRect
var _cover: ColorRect
var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _font: Font

var _vp := Vector2(1280, 720)
var _sc := 1.0
var _t0 := 0.0
var _restarting := false
var _idle := false
var _spin := 0.0
var _slash_dir := Vector2.RIGHT
var _slash_n := Vector2.DOWN
var _slash_c := Vector2.ZERO
var _ly := {}


# ---------- API ----------
static func play(from: Node, killer_name: String = "") -> DeathScreen:
	var ds := DeathScreen.new()
	ds.killer = killer_name
	from.get_tree().root.add_child(ds)      # di root: tetap hidup waktu scene di-reload
	return ds


# ---------- SETUP ----------
func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	deaths += 1
	Engine.time_scale = 1.0
	_vp = get_viewport().get_visible_rect().size

	# ambil frame terakhir game SEBELUM di-pause
	var frame_tex: Texture2D = null
	var img := get_viewport().get_texture().get_image()
	if img != null and not img.is_empty():
		frame_tex = ImageTexture.create_from_image(img)
	else:
		frame_tex = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGB8))
	get_tree().paused = true

	if font:
		_font = font
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
		_font = sf

	_void_mat = ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = VOID_SHADER
	_void_mat.shader = vs
	_void = _rect(Color.WHITE, self)
	_void.material = _void_mat

	_ash = _make_ash()
	add_child(_ash)

	# garis tebasan: miring acak, lewat sekitar tengah layar
	var ang := deg_to_rad(randf_range(18.0, 38.0)) * (1.0 if randf() < 0.5 else -1.0)
	_slash_dir = Vector2.from_angle(ang)
	_slash_n = Vector2(-_slash_dir.y, _slash_dir.x)
	_slash_c = _vp * 0.5 + _slash_n * randf_range(-0.1, 0.1) * _vp.y

	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)

	var split := Shader.new()
	split.code = SPLIT_SHADER
	for i in 2:
		var h := TextureRect.new()
		h.texture = frame_tex
		h.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.stretch_mode = TextureRect.STRETCH_SCALE
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = split
		m.set_shader_parameter("side", 1.0 if i == 0 else -1.0)
		m.set_shader_parameter("edge_glow", 0.0)
		m.set_shader_parameter("sat", 1.0)
		m.set_shader_parameter("dim", 1.0)
		h.material = m
		_stage.add_child(h)
		_halves.append(h)
		_hmat.append(m)

	_beam = ColorRect.new()
	_beam.color = Color(1.0, 0.95, 0.82)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beam.material = add_mat
	_beam.visible = false
	add_child(_beam)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	# lambang silinder revolver (2 belahan, dipotong shader)
	_emblem = Control.new()
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emblem.visible = false
	_ui.add_child(_emblem)
	var cut := Shader.new()
	cut.code = CUT_SHADER
	for i in 2:
		var c := Cylinder.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.tint = bone_color
		c.accent = accent_color
		var m2 := ShaderMaterial.new()
		m2.shader = cut
		m2.set_shader_parameter("side", 1.0 if i == 0 else -1.0)
		c.material = m2
		_emblem.add_child(c)
		_eh.append(c)
		_emat.append(m2)

	_flat = Flat.new()
	_flat.color = accent_color
	_flat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flat.modulate.a = 0.0
	_ui.add_child(_flat)

	_l_count = _label(_ui)
	_l_title = _label(_ui)
	_l_killer = _label(_ui)
	_l_tip = _label(_ui)
	_l_prompt = _label(_ui)
	_l_title.add_theme_color_override("font_color", bone_color)
	_l_killer.add_theme_color_override("font_color", accent_color)
	_l_count.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))
	_l_tip.add_theme_color_override("font_color", Color(0.82, 0.78, 0.7))
	_l_prompt.add_theme_color_override("font_color", Color(0.65, 0.62, 0.58))

	_flash = _rect(Color.WHITE, self)
	_flash.modulate.a = 0.0
	_cover = _rect(Color.BLACK, self)
	_cover.visible = false
	move_child(_beam, _flash.get_index())          # garis tebasan di atas belahan layar & lambang, di bawah flash

	_fx_mat = ShaderMaterial.new()
	var fs := Shader.new()
	fs.code = FX_SHADER
	_fx_mat.shader = fs
	var init := {"crt": 0.0, "glitch": 0.0, "blur": 0.0, "lid": 1.0}
	for pn in init:
		_fx_mat.set_shader_parameter(pn, init[pn])
	_fx = _rect(Color.WHITE, self)
	_fx.material = _fx_mat

	get_viewport().size_changed.connect(_layout)
	_layout()
	_t0 = Time.get_ticks_msec() / 1000.0
	_run()


func _rect(c: Color, parent: Node) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _label(parent: Node) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.modulate.a = 0.0
	parent.add_child(l)
	return l


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
	g.colors = PackedColorArray([Color(0.9, 0.8, 0.6, 0.0), Color(0.9, 0.8, 0.6, 0.4), Color(0.9, 0.8, 0.6, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	p.color_ramp = g
	return p


func _layout() -> void:
	_vp = get_viewport().get_visible_rect().size
	_sc = _vp.y / 720.0
	for h in _halves:
		h.pivot_offset = _vp * 0.5
	for m in _hmat:
		m.set_shader_parameter("p", _slash_c / _vp)
		m.set_shader_parameter("n", _slash_n)
		m.set_shader_parameter("aspect", _vp.x / _vp.y)
	_ash.position = Vector2(_vp.x * 0.5, _vp.y + 10.0)
	_ash.emission_rect_extents = Vector2(_vp.x * 0.5, 4.0)

	var s := minf(_vp.x, _vp.y) * 0.34
	_emblem.size = Vector2(s, s)
	_emblem.pivot_offset = Vector2(s, s) * 0.5
	for i in 2:
		_eh[i].size = Vector2(s, s)
		_eh[i].pivot_offset = Vector2(s, s) * 0.5
		_emat[i].set_shader_parameter("center", Vector2(s, s) * 0.5)

	var fsz := {_l_count: 14, _l_title: 46, _l_killer: 24, _l_tip: 17, _l_prompt: 16}
	var ys := {_l_count: 0.475, _l_title: 0.515, _l_killer: 0.67, _l_tip: 0.725, _l_prompt: 0.88}
	for l in fsz:
		var f: int = int(fsz[l] * _sc)
		l.add_theme_font_size_override("font_size", f)
		l.size = Vector2(_vp.x * 0.84, f * 2.2)
		l.position = Vector2(_vp.x * 0.08, _vp.y * float(ys[l]))
		_ly[l] = l.position.y
	_flat.size = Vector2(_vp.x * 0.34, 34.0 * _sc)
	_flat.pivot_offset = _flat.size * 0.5
	_flat.px = _sc
	_flat.position = Vector2((_vp.x - _flat.size.x) * 0.5, _vp.y * 0.615)
	_ly[_flat] = _flat.position.y


func _process(delta: float) -> void:
	_void_mat.set_shader_parameter("aspect", _vp.x / _vp.y)
	if _emblem.visible:
		_spin += delta * 0.55
		for c in _eh:
			c.spin = _spin
		if _idle:
			_emblem.rotation = sin(Time.get_ticks_msec() / 1000.0 * 1.1) * 0.025


# ---------- URUTAN ----------
func _run() -> void:
	# ===== 1. TEBAS =====
	_play("death_slash", 0.0, 1.0)
	_setup_beam(_slash_c, _slash_dir.angle(), _vp.length() * 1.3, 3.0 * _sc)
	_flash.modulate.a = 0.7
	_tw().tween_property(_flash, "modulate:a", 0.0, 0.2)
	for m in _hmat:
		m.set_shader_parameter("edge_glow", 1.0)
	_tw().tween_property(_beam, "scale:x", 1.0, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_shake(12.0 * _sc, 0.25)
	await _wait(0.07)                                  # hit-stop: garis sudah lewat, frame masih utuh
	if _restarting: return

	var t := _tw().set_parallel(true)
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		t.tween_property(_halves[i], "position", _slash_n * 60.0 * _sc * sgn, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(_halves[i], "rotation", deg_to_rad(2.2) * sgn, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tpm(t, _hmat[i], "sat", 1.0, 0.15, 0.25)
		_tpm(t, _hmat[i], "edge_glow", 1.0, 0.0, 0.4)
	t.tween_property(_beam, "scale:y", 14.0, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_beam, "modulate:a", 0.0, 0.4)
	_sparks(_slash_c, _slash_n, 60, 520.0)
	_sparks(_slash_c, -_slash_n, 60, 520.0)
	await _wait(0.28)
	if _restarting: return

	# ===== 2. LAMBANG MENGHANTAM =====
	var reach := _vp.length()
	t = _tw().set_parallel(true)
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		t.tween_property(_halves[i], "position", _slash_n * reach * sgn, 0.6).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		t.tween_property(_halves[i], "rotation", deg_to_rad(9.0) * sgn, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tpm(t, _hmat[i], "dim", 1.0, 0.1, 0.5)
	await _wait(0.2)
	if _restarting: return

	_emblem.position = _vp * 0.5 - _emblem.size * 0.5
	_emblem.pivot_offset = _emblem.size * 0.5
	_emblem.scale = Vector2.ONE * 3.2
	_emblem.rotation = -0.5
	_emblem.modulate.a = 1.0
	_emblem.visible = true
	_play("death_cut", -2.0, 0.85)
	_shake(14.0 * _sc, 0.3)
	var sl := _tw().set_parallel(true)
	sl.tween_property(_emblem, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	sl.tween_property(_emblem, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tpm(sl, _void_mat, "glow", 0.0, 1.0, 0.25)
	await _wait(0.3)
	if _restarting: return
	for h in _halves:
		h.visible = false

	# tebasan kedua: lambang terbelah
	await _wait(0.1)
	if _restarting: return
	var ang2 := -_slash_dir.angle() + deg_to_rad(randf_range(-10.0, 10.0))
	var dir2 := Vector2.from_angle(ang2)
	var n2 := Vector2(-dir2.y, dir2.x)
	var ec := _vp * 0.5
	_play("death_slash", -4.0, 1.25)
	_setup_beam(ec, ang2, _emblem.size.x * 2.0, 3.0 * _sc)
	_flash.modulate.a = 0.3
	_tw().tween_property(_flash, "modulate:a", 0.0, 0.18)
	_tw().tween_property(_beam, "scale:x", 1.0, 0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	for m in _emat:
		m.set_shader_parameter("n", n2)
	_shake(7.0 * _sc, 0.2)
	await _wait(0.05)
	if _restarting: return
	t = _tw().set_parallel(true)
	for i in 2:
		var sgn := 1.0 if i == 0 else -1.0
		t.tween_property(_eh[i], "position", n2 * 16.0 * _sc * sgn, 0.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(_eh[i], "rotation", deg_to_rad(4.5) * sgn, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(_eh[i], "tint", Color(0.62, 0.6, 0.58), 1.0).set_trans(Tween.TRANS_SINE)
	t.tween_property(_beam, "scale:y", 9.0, 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(_beam, "modulate:a", 0.0, 0.4)
	_tpm(t, _void_mat, "glow", 1.0, 0.0, 0.9)
	_sparks(ec, n2, 36, 380.0)
	_sparks(ec, -n2, 36, 380.0)
	_tw().tween_property(_eh[0], "position", n2 * 16.0 * _sc + Vector2(0, 11.0 * _sc), 2.0).set_delay(0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _wait(0.2)
	if _restarting: return

	# ===== 3. END CARD =====
	_show_text()
	var up := _tw().set_parallel(true)
	var target := Vector2(_vp.x * 0.5, _vp.y * 0.25) - _emblem.size * 0.5
	up.tween_property(_emblem, "position", target, 0.55).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	up.tween_property(_emblem, "scale", Vector2.ONE * 0.78, 0.55).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tpm(up, _fx_mat, "crt", 0.0, 0.45, 0.6)                # sentuhan monitor: scanline + pecah warna
	_idle = true
	_reveal(_l_count, 0.05)
	_reveal(_l_title, 0.1, 30.0)
	_reveal(_flat, 0.25, 10.0)
	_flat.sweep()
	_reveal(_l_killer, 0.35)
	_reveal(_l_tip, 0.5)
	_reveal(_l_prompt, 0.75, 10.0)
	await _wait(1.2)
	if _restarting: return
	var blink := _l_prompt.create_tween().set_ignore_time_scale(true).set_loops()
	blink.tween_property(_l_prompt, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE)
	blink.tween_property(_l_prompt, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)

	if auto_restart > 0.0:
		await _wait(auto_restart)
		if not _restarting:
			_restart()


# Ambil satu elemen acak dari pool, hindari yang sama dengan sebelumnya.
func _pick(key: String, pool: Array) -> String:
	if pool.size() == 1:
		return pool[0]
	var last: int = _last_pick.get(key, -1)
	var i := randi() % pool.size()
	if i == last:
		i = (i + 1 + randi() % (pool.size() - 1)) % pool.size()
	_last_pick[key] = i
	return pool[i]


func _spaced(s: String) -> String:
	if s.length() > 1 and s[1] == " ":
		return s                                   # sudah berspasi (mis. "D E C E A S E D")
	var words := PackedStringArray()
	for w in s.split(" "):
		var chars := PackedStringArray()
		for i in w.length():
			chars.append(w[i])
		words.append(" ".join(chars))
	return "   ".join(words)


func _show_text() -> void:
	_l_count.text = "ATTEMPT %02d" % deaths
	var k := killer.strip_edges()
	var key := k.to_lower()
	var set_: Dictionary = LINES.get(key, GENERIC)
	var repeat := key != "" and key == _last_killer
	_streak = _streak + 1 if repeat else 1
	_last_killer = key

	_l_title.text = _spaced(_pick(key + "_t", set_["titles"]))
	var line := ""
	if k == "":
		line = ""
	elif LINES.has(key):
		line = _pick(key + "_l", set_["lines"])
		if _streak >= 2:
			line = "%s  %s" % [_pick("rep", REPEAT_LINES), "(x%d)" % _streak]
	else:
		line = "SLAIN BY %s" % k.to_upper()
	_l_killer.text = line
	_l_tip.text = _pick(key + "_p", set_["tips"])
	_l_prompt.text = "PRESS ANY KEY TO RE-INITIALIZE"


# ---------- INPUT & ULANG ----------
func _input(event: InputEvent) -> void:
	if _restarting:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.pressed
	if not pressed:
		return
	get_viewport().set_input_as_handled()       # termasuk Esc: menu pause jangan kebuka
	if _elapsed() < skip_after:
		return                                  # klik/tembak pas mati jangan langsung kebaca
	for a in ["ui_cancel", "pause"]:
		if InputMap.has_action(a) and event.is_action(a):
			return                              # Esc cuma ditelan, bukan restart
	_restart()


func _restart() -> void:
	if _restarting:
		return
	_restarting = true
	Engine.set_meta("skip_boot_intro", true)    # restart setelah mati: intro boot jangan diputar lagi (dibaca boot_sequence.gd)
	_play("boot_glitch", -4.0, 1.0)
	_fx_mat.set_shader_parameter("glitch", 1.0)
	await _wait(0.15)
	_stage.visible = false
	_ui.visible = false
	_void.visible = false
	_ash.visible = false
	_beam.visible = false
	_cover.visible = true
	var end_state := {"crt": 0.0, "glitch": 0.0, "blur": 6.0, "lid": 0.0}
	for pn in end_state:
		_fx_mat.set_shader_parameter(pn, end_state[pn])
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().reload_current_scene()
	await get_tree().process_frame
	await get_tree().process_frame
	await _wait(0.15)

	# mata terbuka sebentar di scene baru
	_cover.visible = false
	_play("boot_wake", -2.0, 1.2)
	var t := _tw()
	_tp(t, "lid", 0.0, 0.5, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tp(t, "lid", 0.5, 0.25, 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tp(t, "lid", 0.25, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var b := _tw()
	_tp(b, "blur", 6.0, 4.0, 0.4)
	_tp(b, "blur", 4.0, 5.0, 0.12)
	_tp(b, "blur", 5.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _wait(1.3)
	queue_free()


# ---------- UTIL ----------
func _elapsed() -> float:
	return Time.get_ticks_msec() / 1000.0 - _t0


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _tw() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


## Animasi parameter shader lewat set_shader_parameter (tween_property ke "shader_parameter/..." gak selalu terbaca)
func _tpm(t: Tween, mat: ShaderMaterial, pname: String, from_v: float, to_v: float, dur: float) -> MethodTweener:
	return t.tween_method(func(v: float): mat.set_shader_parameter(pname, v), from_v, to_v, dur)


func _tp(t: Tween, pname: String, from_v: float, to_v: float, dur: float) -> MethodTweener:
	return _tpm(t, _fx_mat, pname, from_v, to_v, dur)


func _setup_beam(center: Vector2, ang: float, length: float, thick: float) -> void:
	var dir := Vector2.from_angle(ang)
	_beam.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_beam.size = Vector2(length, thick)
	_beam.pivot_offset = Vector2(0.0, thick * 0.5)
	_beam.rotation = ang
	_beam.position = center - dir * length * 0.5 - Vector2(0.0, thick * 0.5)
	_beam.scale = Vector2(0.0, 1.0)
	_beam.modulate.a = 1.0
	_beam.visible = true


func _reveal(l: Control, delay: float, rise: float = 24.0) -> void:
	var base: float = _ly.get(l, l.position.y)
	l.position.y = base + rise * _sc
	var t := _tw().set_parallel(true)
	t.tween_property(l, "modulate:a", 1.0, 0.35).set_delay(delay)
	t.tween_property(l, "position:y", base, 0.6).set_delay(delay).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _shake(amount: float, time: float) -> void:
	var t := _tw()
	t.tween_method(_shake_step.bind(amount), 0.0, 1.0, time)
	t.tween_callback(_shake_step.bind(1.0, 0.0))


func _shake_step(k: float, amount: float) -> void:
	var off := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * amount * (1.0 - k)
	_stage.position = off
	_ui.position = off


# Percikan api: semburan satu arah
func _sparks(pos: Vector2, dir: Vector2, count: int, speed: float) -> void:
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
	g.colors = PackedColorArray([Color(1.0, 0.95, 0.8, 1.0), accent_color, Color(accent_color, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	p.color_ramp = g
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _play(sfx_name: String, db: float, pitch: float) -> void:
	var path := sfx_dir.path_join(sfx_name + ".wav")
	if not ResourceLoader.exists(path):
		return                                   # file suara belum ada: lewati saja
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = db + sfx_volume_db
	p.pitch_scale = pitch
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


# =========================================================
# LAMBANG: silinder revolver (ring bersudut, 6 ruang peluru, 1 masih terisi)
# =========================================================
class Cylinder extends Control:
	var tint: Color = Color(0.95, 0.92, 0.84):
		set(v):
			tint = v
			queue_redraw()
	var accent: Color = Color(1.0, 0.72, 0.27)
	var spin: float = 0.0:
		set(v):
			spin = v
			queue_redraw()

	func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in n + 1:
			out.append(c + Vector2.from_angle(rot + TAU * float(i % n) / float(n)) * r)
		return out

	func _draw() -> void:
		var R := minf(size.x, size.y) * 0.46
		var c := size * 0.5
		draw_polyline(_ngon(c, R, 12, 0.26), tint, R * 0.07)
		draw_polyline(_ngon(c, R * 0.84, 12, 0.26), Color(tint, 0.55), R * 0.022)
		draw_colored_polygon(_ngon(c, R * 0.15, 6, spin * 0.5).slice(0, 6), tint)
		for i in 6:
			var a := spin + TAU * i / 6.0
			var cc := c + Vector2.from_angle(a) * R * 0.52
			draw_polyline(_ngon(cc, R * 0.17, 8, a), tint, R * 0.05)
			if i == 2:
				draw_colored_polygon(_ngon(cc, R * 0.085, 8, a).slice(0, 8), accent)
		for i in 6:
			var a2 := spin * 0.5 + TAU * (i + 0.5) / 6.0
			draw_line(c + Vector2.from_angle(a2) * R * 0.75, c + Vector2.from_angle(a2) * R * 0.84, Color(tint, 0.7), R * 0.035)


# =========================================================
# GARIS EKG FLATLINE: satu detak terakhir, lalu lurus
# =========================================================
class Flat extends Control:
	var color: Color = Color(1.0, 0.72, 0.27)
	var px: float = 1.0
	var reveal: float = 1.0:
		set(v):
			reveal = v
			queue_redraw()

	func sweep() -> void:
		reveal = 0.0
		var t := create_tween()
		t.set_ignore_time_scale(true)
		t.tween_property(self, "reveal", 1.0, 0.7).set_delay(0.25).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var m := h * 0.5
		var pts := PackedVector2Array([
			Vector2(0, m), Vector2(w * 0.28, m), Vector2(w * 0.30, m - h * 0.12),
			Vector2(w * 0.32, m), Vector2(w * 0.335, m + h * 0.12), Vector2(w * 0.35, m - h * 0.5),
			Vector2(w * 0.365, m + h * 0.55), Vector2(w * 0.38, m), Vector2(w * 0.42, m - h * 0.1),
			Vector2(w * 0.45, m), Vector2(w, m)])
		# potong sesuai reveal (kiri -> kanan)
		var cut := PackedVector2Array()
		var lim := w * reveal
		for p in pts:
			if p.x <= lim:
				cut.append(p)
			else:
				break
		if cut.size() < 2:
			return
		cut.append(Vector2(lim, m))
		draw_polyline(cut, Color(color, 0.25), 7.0 * px)
		draw_polyline(cut, color, 2.2 * px)
