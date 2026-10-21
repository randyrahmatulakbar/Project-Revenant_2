class_name BootSequence
extends CanvasLayer
## INTRO "COLD BOOT". Terminal CRT amber, lalu pemain "membuka mata" masuk ke game.
##
## PASANG: di scene intro (yang dimuat tombol Play), tambah node CanvasLayer baru di root,
## kasih nama BootSequence, pasang script ini. Selesai. Gak perlu node lain.
##
## Urutan:
##   1. Layar CRT menyala dari garis putih tipis
##   2. Teks boot diketik (progress bar, detak jantung, prompt Y/N yang "ditimpa" mesin)
##   3. Layar dibersihkan (glitch), laporan status, 3 baris merah
##   4. CRT mati -> hitam -> 2x detak jantung
##   5. Kelopak mata terbuka: gambar game mulai buram lalu fokus
## Game di-pause selama teks; lanjut jalan begitu mata mulai terbuka.
## Tekan apa saja = lewati teks. Setelah mati lalu restart, intro TIDAK diulang.

## Diisi true oleh DeathScreen waktu restart (biar intro gak muncul lagi tiap mati)
static var skip_next: bool = false

@export var enabled: bool = true
@export var font: Font                         # kosong = font monospace sistem
@export var type_speed: float = 1.0            # 2 = ngetik 2x lebih cepat
@export var sfx_dir: String = "res://sfx/"
@export var sfx_volume_db: float = 0.0
@export_group("Warna")
@export var amber: Color = Color(1.0, 0.72, 0.27)
@export var dim: Color = Color(0.72, 0.5, 0.2)
@export var hot: Color = Color(1.0, 0.94, 0.82)
@export var ok_color: Color = Color(0.4, 1.0, 0.85)
@export var bad_color: Color = Color(1.0, 0.27, 0.22)

const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float crt = 1.0;        // 0 = bersih, 1 = efek CRT penuh
uniform float glitch = 0.0;     // robekan horizontal + pecah warna
uniform float blur = 0.0;       // buram (lod)
uniform float lid = 1.0;        // kelopak mata: 0 tutup, 1 terbuka penuh
uniform float power = 1.0;      // layar CRT menyala: 0 garis tipis, 1 penuh
uniform float flash = 0.0;      // denyut merah (detak jantung)
uniform vec3 flash_col : source_color = vec3(0.75, 0.0, 0.03);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	float t = TIME;
	vec2 cc = SCREEN_UV - 0.5;
	vec2 uv = 0.5 + cc * (1.0 + crt * 0.12 * dot(cc, cc));          // cembung ala tabung
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);

	// robekan per pita horizontal
	float band = floor(uv.y * 36.0);
	float st = floor(t * 20.0);
	float on_band = step(1.0 - glitch * 0.45, hash(vec2(band, st)));
	uv.x += on_band * (hash(vec2(band, st + 7.0)) - 0.5) * 0.22 * glitch;

	float ca = crt * 0.0012 + glitch * 0.012;
	vec3 col;
	col.r = textureLod(screen_tex, uv + vec2(ca, 0.0), blur).r;
	col.g = textureLod(screen_tex, uv, blur).g;
	col.b = textureLod(screen_tex, uv - vec2(ca, 0.0), blur).b;

	// pendar fosfor
	col += textureLod(screen_tex, uv, 3.0 + blur).rgb * 0.55 * crt;
	// garis pindai, kedip, bintik
	float line = sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159);
	col *= 1.0 - crt * 0.16 * (0.5 - 0.5 * line);
	col *= 1.0 + crt * (0.03 * sin(t * 55.0) + 0.02 * sin(t * 7.0));
	col += (hash(uv * vec2(900.0, 600.0) + t) - 0.5) * 0.06 * crt;
	col *= mix(1.0, inside, crt);

	float vig = smoothstep(0.25, 0.78, length(cc));
	col *= 1.0 - vig * 0.55 * max(crt, 1.0 - lid);

	// layar CRT menyala dari garis tipis
	float hh = max(power * 0.5, 0.0018);
	float m_pow = power >= 0.999 ? 1.0 : 1.0 - smoothstep(hh - 0.003, hh + 0.003, abs(cc.y));
	col = mix(col, vec3(1.0, 0.95, 0.85), (1.0 - smoothstep(0.0, 0.3, power)) * m_pow);
	col *= m_pow;

	// kelopak mata (bentuk lensa)
	float x2 = 4.0 * cc.x * cc.x;
	float edge = lid * 0.62 * (1.0 - 0.75 * x2) + lid * lid * lid;
	float vis = (1.0 - smoothstep(edge - 0.05, edge + 0.03, abs(cc.y))) * smoothstep(0.0, 0.05, lid);
	col *= vis;

	col += flash_col * flash * (0.3 + 0.7 * vig);
	COLOR = vec4(col, 1.0);
}
"""

var _bg: ColorRect
var _term: Control
var _cursor: ColorRect
var _fx: ColorRect
var _mat: ShaderMaterial
var _font: Font
var _fs := 20
var _cw := 12.0
var _lh := 30.0
var _x0 := 80.0
var _y0 := 70.0
var _col2 := 300.0
var _line := 0
var _vp := Vector2(1280, 720)
var _in_text := true
var _skip := false
var _cur_label: Label = null


# ---------- SETUP ----------
func _ready() -> void:
	layer = 150
	process_mode = Node.PROCESS_MODE_ALWAYS
	var skip := skip_next or bool(Engine.get_meta("skip_boot_intro", false))
	skip_next = false
	Engine.set_meta("skip_boot_intro", false)
	if not enabled or skip:
		queue_free()
		return

	get_tree().paused = true
	_vp = get_viewport().get_visible_rect().size

	if font:
		_font = font
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Menlo", "DejaVu Sans Mono", "Courier New", "monospace"])
		_font = sf
	var sc := _vp.y / 720.0
	_fs = int(round(20.0 * sc))
	_cw = _font.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	_lh = _fs * 1.55
	_x0 = _vp.x * 0.07
	_y0 = _vp.y * 0.09
	_col2 = _x0 + _cw * 24.0

	_bg = ColorRect.new()
	_bg.color = Color.BLACK
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_term = Control.new()
	_term.set_anchors_preset(Control.PRESET_FULL_RECT)
	_term.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_term)

	_cursor = ColorRect.new()
	_cursor.color = amber
	_cursor.size = Vector2(_cw * 0.7, _fs * 1.0)
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.visible = false
	add_child(_cursor)

	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = FX_SHADER
	_mat.shader = sh
	for pn in {"crt": 1.0, "glitch": 0.0, "blur": 0.0, "lid": 1.0, "power": 0.0, "flash": 0.0}:
		_mat.set_shader_parameter(pn, {"crt": 1.0, "glitch": 0.0, "blur": 0.0, "lid": 1.0, "power": 0.0, "flash": 0.0}[pn])
	_fx = ColorRect.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.material = _mat
	add_child(_fx)

	_run()


func _process(_d: float) -> void:
	if _cur_label != null and is_instance_valid(_cur_label) and _in_text:
		var w := _font.get_string_size(_cur_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
		_cursor.position = _cur_label.position + Vector2(w + _cw * 0.15, _fs * 0.15)
		_cursor.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.5 or _cursor_hold > 0.0
	else:
		_cursor.visible = false
	_cursor_hold = maxf(0.0, _cursor_hold - _d)


var _cursor_hold := 0.0


func _input(event: InputEvent) -> void:
	if not _in_text:
		return
	var pressed := false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton or event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		get_viewport().set_input_as_handled()      # termasuk Esc: menu pause jangan kebuka
		_skip = true


# ---------- URUTAN ----------
func _run() -> void:
	# 1. CRT menyala
	_play("boot_power", -2.0, 1.0)
	await _wait(0.12)
	_tp(_tw(), "power", 0.0, 1.0, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	await _wait(0.6)

	# 2-3. teks
	await _boot_text()

	# 4-5. mati -> detak -> buka mata
	await _wake()
	queue_free()


func _boot_text() -> void:
	var h := _new_line(hot)
	await _type(h, "REVENANT // RECLAMATION UNIT 07", 90)
	var h2 := _new_line(dim)
	await _type(h2, "COLD BOOT SEQUENCE", 90)
	_line += 1
	await _wait(0.25)

	var v: Label = await _kv("POWER RAIL", "STABLE", ok_color)
	v = await _bar_row("NEURAL LATCH", "SEATED")
	v = await _kv("HEARTBEAT", "0 BPM", bad_color)
	await _wait(0.55)
	if not _skip:
		_play("boot_beep", -6.0, 0.8)
	v.text = ""
	v.add_theme_color_override("font_color", amber)
	await _type(v, "SYNTHETIC / 58 BPM", 70)
	v = await _kv("MEMORY", "3 OF 9 FRAGMENTS", amber)
	await _type_after(v, "   6 LOST", bad_color, 70)
	_line += 1
	await _wait(0.2)

	# prompt Y/N: mesin bilang N, lalu ditimpa
	var q := _new_line(hot)
	await _type(q, "RESTORE SUBJECT? [Y/N] ", 80)
	var ans := _label_after(q, "", hot)
	await _wait(0.4)
	await _type(ans, "N", 5, true)
	await _wait(0.6)
	_glitch_burst(0.5)
	await _wait(0.12)
	ans.text = ""
	await _wait(0.25)
	await _type(ans, "Y", 5, true)
	await _wait(0.2)
	await _type_after(ans, "  OVERRIDE ACCEPTED", ok_color, 60)
	await _wait(0.9)

	# laporan status
	_cls()
	await _wait(0.25)
	var t1 := _new_line(hot)
	await _type(t1, "STATUS REPORT", 80)
	var t2 := _new_line(dim)
	await _type(t2, "================================", 200)
	await _kv("SUBJECT", "UNNAMED", hot, 80)
	await _kv("STATE", "DECEASED / 412 DAYS", bad_color, 80)
	await _kv("LOCATION", "SUBLEVEL 9 / QUARANTINE", amber, 80)
	await _kv("DIRECTIVE", "RECOVER SIDEARM", hot, 80)
	_line += 1
	await _wait(0.7)
	for s in ["THE DEAD ARE HUNGRY.", "YOU ARE STILL WARM.", "MAKE THEM REGRET IT."]:
		var r := _new_line(bad_color)
		await _type(r, s, 24)
		if not _skip:
			_play("boot_beep", -4.0, 0.55)
		await _wait(0.55)
	await _wait(1.0)


func _wake() -> void:
	_in_text = false
	_cur_label = null
	_cursor.visible = false

	# CRT mati
	_play("boot_off", -2.0, 1.0)
	_glitch_burst(1.0, 0.25)
	await _wait(0.22)
	var off := _tw()
	_tp(off, "power", 1.0, 0.0, 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	await _wait(0.2)
	_term.visible = false
	_bg.color = Color.BLACK
	_mat.set_shader_parameter("power", 1.0)
	_mat.set_shader_parameter("lid", 0.0)
	_mat.set_shader_parameter("crt", 0.0)
	_mat.set_shader_parameter("glitch", 0.0)
	_mat.set_shader_parameter("blur", 6.0)
	await _wait(0.6)

	# detak jantung x2
	_play("boot_heart", 2.0, 1.0)
	_beat(0.0, 0.7)
	_beat(0.27, 0.5)
	await _wait(0.95)
	_beat(0.0, 0.8)
	_beat(0.27, 0.6)
	_play("boot_heart", 3.0, 0.9)
	await _wait(0.75)

	# mata terbuka: buka separuh -> kedip -> buka penuh, buram -> fokus
	_bg.visible = false
	get_tree().paused = false
	_play("boot_wake", 0.0, 1.0)
	var t := _tw()
	_tp(t, "lid", 0.0, 0.5, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tp(t, "lid", 0.5, 0.18, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tp(t, "lid", 0.18, 1.0, 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var b := _tw()
	_tp(b, "blur", 6.0, 4.0, 0.7)
	_tp(b, "blur", 4.0, 5.0, 0.22)
	_tp(b, "blur", 5.0, 0.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _wait(2.4)


# ---------- TEKS ----------
func _new_line(color: Color) -> Label:
	var l := _label_at(_x0, _y0 + _line * _lh, "", color)
	_line += 1
	return l


func _label_at(x: float, y: float, text: String, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", _fs)
	l.add_theme_color_override("font_color", color)
	l.text = text
	l.position = Vector2(x, y)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term.add_child(l)
	return l


## Label tepat di belakang teks label lain (satu baris)
func _label_after(l: Label, text: String, color: Color) -> Label:
	var w := _font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs).x
	return _label_at(l.position.x + w, l.position.y, text, color)


func _type(l: Label, s: String, cps: float, slow_tick: bool = false) -> void:
	_cur_label = l
	for i in s.length():
		if _skip:
			l.text = l.text + s.substr(i)
			return
		l.text += s[i]
		if i % 2 == 0 or slow_tick:
			_play("boot_tick", -13.0, randf_range(0.85, 1.15))
		_cursor_hold = 0.15
		await _wait(1.0 / (cps * type_speed) * randf_range(0.6, 1.5))


func _type_after(l: Label, s: String, color: Color, cps: float) -> void:
	var n := _label_after(l, "", color)
	await _type(n, s, cps)


## Baris "KUNCI .... NILAI". Mengembalikan label nilainya.
func _kv(key: String, value: String, vcolor: Color, cps: float = 90.0) -> Label:
	var k := _new_line(dim)
	await _type(k, key, cps)
	await _wait(0.12)
	var v := _label_at(_col2, k.position.y, "", vcolor)
	await _type(v, value, cps * 0.75)
	await _wait(0.12)
	return v


## Baris dengan progress bar segmen
func _bar_row(key: String, done_text: String) -> Label:
	var k := _new_line(dim)
	await _type(k, key, 90)
	var n := 20
	var seg_w := _cw * 0.8
	var step := seg_w + _cw * 0.25
	for i in n:
		if _skip:
			# sisa segmen langsung penuh
			for j in range(i, n):
				_bar_seg(k, j, seg_w, step)
			break
		_bar_seg(k, i, seg_w, step)
		if i % 2 == 0:
			_play("boot_tick", -12.0, 1.0 + i * 0.02)
		await _wait(randf_range(0.015, 0.05) / type_speed)
		if i == 13:
			await _wait(0.3)
	var v := _label_at(_col2 + n * step + _cw, k.position.y, "", ok_color)
	await _type(v, done_text, 70)
	await _wait(0.12)
	return v


func _bar_seg(k: Label, i: int, seg_w: float, step: float) -> void:
	var r := ColorRect.new()
	r.color = amber
	r.size = Vector2(seg_w, _fs * 0.7)
	r.position = Vector2(_col2 + i * step, k.position.y + _fs * 0.2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_term.add_child(r)


func _cls() -> void:
	_glitch_burst(0.8)
	for c in _term.get_children():
		c.queue_free()
	_line = 0
	_cur_label = null


# ---------- EFEK ----------
func _glitch_burst(strength: float, time: float = 0.35) -> void:
	_play("boot_glitch", -4.0, randf_range(0.9, 1.1))
	_mat.set_shader_parameter("glitch", strength)
	_tp(_tw(), "glitch", strength, 0.0, time)


## Denyut merah satu detak
func _beat(delay: float, amount: float) -> void:
	var t := _tw()
	if delay > 0.0:
		t.tween_interval(delay)
	_tp(t, "flash", 0.0, amount, 0.04)
	_tp(t, "flash", amount, 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Animasi parameter shader lewat set_shader_parameter (tween_property ke "shader_parameter/..." gak selalu terbaca)
func _tp(t: Tween, pname: String, from_v: float, to_v: float, dur: float) -> MethodTweener:
	return t.tween_method(func(v: float): _mat.set_shader_parameter(pname, v), from_v, to_v, dur)


func _wait(s: float) -> void:
	if _skip and _in_text:
		return
	await get_tree().create_timer(s, true, false, true).timeout


func _tw() -> Tween:
	var t := create_tween()
	t.set_ignore_time_scale(true)
	return t


func _play(sfx_name: String, db: float, pitch: float) -> void:
	if _skip and _in_text and sfx_name == "boot_tick":
		return
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
