extends Node3D
## Menu utama 3D: kamera masuk -> layar judul -> menu di depan pintu -> kredit di papan.
## Pasang di root menu_world.tscn. Jadikan menu_world.tscn sebagai Main Scene.

signal play_pressed
signal settings_pressed
signal archives_pressed

@export_file("*.tscn") var play_scene := "res://intro.tscn"
@export var font: Font
@export var intro_time := 5.5
@export var sway := 0.018
@export var parallax := 0.03              # kamera ikut gerak mouse sedikit (radian). 0 = mati
@export var ui_stagger := 0.07            # jeda antar elemen UI saat muncul / hilang (detik)
@export var ui_slide := 90.0              # jarak geser elemen UI saat muncul (piksel)
@export_group("Efek (kill switch)")
@export var crt_fx := true                # scanline, vignette, chromatic aberration, glitch, efek layar menyala
@export var crt_scan := 0.10
@export var crt_vignette := 0.35
@export var crt_chroma := 0.0012
@export var deco_fx := true               # siku sudut layar + teks terminal (jam, status)
@export var hover_fx := true              # target bracket + kilau saat tombol di-hover / fokus
@export var scramble_fx := true           # teks "mengacak" lalu terdekripsi

const ENTRIES := [
	{"title": "PROJECT REVENANT"},

	{"section": "DIREKSI & DESAIN"},
	{"role": "Game Designer", "name": "Randy Rahmatul Akbar"},

	{"section": "PEMROGRAMAN"},
	{"role": "Gameplay & Systems Programmer", "name": "Randy Rahmatul Akbar"},

	{"section": "LEVEL & LINGKUNGAN"},
	{"role": "Level Designers & Map Artists", "name": "M. Reno Alfian & Laura Aprilianza"},

	{"section": "ARTISTIK, VISUAL & AUDIO"},
	{"role": "UI/UX, 2D Artist & Audio Designer", "name": "Raevan Fadhillah"},

	{"section": "NARRATIVE & STORY"},
	{"role": "Storywriters & Narrative Designers", "name": "Laura Aprilianza & Raevan Fadhillah"},

	{"section": "KONTRIBUSI ASET PIHAK KETIGA"},
	{"sub": "Aset 3D & Lingkungan"},
	{"item": "Kenney.nl (Free 3D Assets & Game Assets)"},
	{"item": "Itch.io Creators (Community Assets)"},
	{"sub": "Audio & Sound Effects"},
	{"item": "YouTube Audio Library"},
	{"item": "Freesound.org & Itch.io Audio Assets"},
	{"item": "UI click sound - Universfield"},
	{"sub": "Font"},
	{"item": "Rajdhani - Indian Type Foundry"},

	{"section": "TERIMA KASIH KHUSUS"},
	{"item": "Guru Pembimbing - Pak Maul & Bu Annisa"},
	{"item": "SMKN 21 Jakarta"},
	{"item": "Komunitas Godot Engine Indonesia"},
]
@export var credits_speed := 34.0         # kecepatan credits bergulir otomatis (piksel/detik). 0 = tidak bergulir

enum S { INTRO, TITLE, BUSY, MENU, CREDITS, SETTINGS }
const RevSettings := preload("settings_store.gd")      # penyimpan setting (bukan autoload), taruh satu folder dengan file ini
var _state := S.INTRO
var _t := 0.0
var _rig: Node3D
var _cam: Camera3D
var _ui: CanvasLayer
var _fade: ColorRect
var _prompt: Control
var _menu: Control
var _credits_ui: Control
var _toast: Label
var _btn_play: NavBtn
var _btn_back: NavBtn
var _click: AudioStream
var _par := Vector2.ZERO
var _prompt_tw: Tween
var _toast_tw: Tween
var _crt_mat: ShaderMaterial
var _crt_layer: CanvasLayer
var _deco: Deco
var _head: Label
var _prompt_label: Label
var _cr_labels: Array[Label] = []
var _base_fov := 75.0
var _cr_scroll: ScrollContainer
var _cr_top: Control
var _cr_bottom: Control
var _cr_tw: Tween
var _set_ui: Control
var _set_screen: Panel
var _set_holder: Control
var _set_menu: Control
var _set_rect := Rect2()
var _wires: Wires
var _mon_mat: StandardMaterial3D
var _mon_orig: Material


const CRT_SHADER := """
shader_type canvas_item;
uniform sampler2D tex : hint_screen_texture, filter_linear_mipmap;
uniform float scan = 0.1;
uniform float vig = 0.35;
uniform float chroma = 0.0012;
uniform float glitch = 0.0;
uniform float power_on = 1.0;
float h1(float n) { return fract(sin(n * 91.7) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float opened = smoothstep(0.0, 1.0, power_on);
	float half_h = mix(0.003, 0.5, opened);
	if (abs(uv.y - 0.5) > half_h) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		float band = floor(uv.y * 26.0) + floor(TIME * 14.0);
		float r = h1(band);
		float sl = step(0.8, r) * glitch;
		uv.x += (r - 0.5) * 0.07 * sl;
		vec2 c = uv - 0.5;
		float ab = chroma + glitch * 0.012 + dot(c, c) * 0.004;
		vec3 col;
		col.r = texture(tex, uv + vec2(ab, 0.0)).r;
		col.g = texture(tex, uv).g;
		col.b = texture(tex, uv - vec2(ab, 0.0)).b;
		float scl = 0.5 + 0.5 * sin(uv.y / SCREEN_PIXEL_SIZE.y * 3.14159);
		col *= 1.0 - scan * scl;
		col *= 1.0 - vig * smoothstep(0.35, 0.95, length(c) * 1.25);
		col *= 1.0 + 0.012 * sin(TIME * 55.0);
		col += vec3(0.5, 0.75, 0.8) * glitch * sl * 0.25;
		float edg = smoothstep(0.0, 0.02, half_h - abs(uv.y - 0.5));
		col += vec3(0.8, 0.95, 1.0) * (1.0 - edg) * (1.0 - opened) * 2.0;
		COLOR = vec4(col, 1.0);
	}
}
"""
const SCRAMBLE_CHARS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#%&@$"


## Tombol gaya HUD: panel jajargenjang (sisi kanan miring), strip di kiri, nomor, "///" dan label seksi di atasnya.
## Yang sedang terpilih (hover / fokus keyboard) menyala: border salmon, strip melebar, kilau lewat sekali, penanda merah di kiri.
class NavBtn extends Button:
	const PANEL := Color(0.11, 0.157, 0.157, 0.92)
	const PANEL_HI := Color(0.168, 0.227, 0.216, 0.97)
	const BORDER := Color(0.49, 0.388, 0.329)
	const ACCENT := Color(0.871, 0.651, 0.541)
	const TEXT := Color(0.918, 0.863, 0.812)
	const DIM := Color(0.788, 0.604, 0.494)
	const RED := Color(0.78, 0.2, 0.17)
	var title := ""
	var subtitle := ""
	var num := ""
	var section := ""
	var big := false
	var locked := false
	var font: Font
	var fx_on := true
	var tick := Callable()
	var h := 0.0:
		set(v):
			h = v
			queue_redraw()
	var sheen := 1.0:
		set(v):
			sheen = v
			queue_redraw()
	var _tw: Tween

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var e := StyleBoxEmpty.new()
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(s, e)

	func _ready() -> void:
		mouse_entered.connect(grab_focus)                  # hover = fokus, jadi hanya satu tombol yang menyala
		focus_entered.connect(_hi.bind(true))
		focus_exited.connect(_hi.bind(false))
		resized.connect(queue_redraw)

	func _hi(on: bool) -> void:
		if _tw != null:
			_tw.kill()
		_tw = create_tween().set_parallel(true)
		if on:
			_tw.tween_property(self, "h", 1.0, 0.28).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			if fx_on:
				sheen = 0.0
				_tw.tween_property(self, "sheen", 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			if tick.is_valid():
				tick.call()
		else:
			_tw.tween_property(self, "h", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	func _draw() -> void:
		var w := size.x
		var ht := size.y
		var sk := ht * 0.13
		var f: Font = font if font else ThemeDB.fallback_font
		var a := 0.5 if locked else 1.0
		var poly := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - sk, ht), Vector2(0, ht)])
		var fill := PANEL.lerp(PANEL_HI, h)
		draw_colored_polygon(poly, Color(fill.r, fill.g, fill.b, fill.a * (0.8 if locked else 1.0)))
		var bc := (ACCENT.darkened(0.2) if big else BORDER).lerp(ACCENT, h)
		var outline := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - sk, ht), Vector2(0, ht), Vector2(0, 0)])
		draw_polyline(outline, Color(bc.r, bc.g, bc.b, a), 2.0 if big else 1.5, true)
		var bar := (6.0 if big else 0.0) + (2.0 if big else 4.0) * h
		if bar > 0.1:
			draw_rect(Rect2(0, 0, bar, ht), Color(ACCENT.r, ACCENT.g, ACCENT.b, a))
		if fx_on and sheen < 1.0:
			var bx := lerpf(-30.0, w + 30.0, sheen)
			var x0 := clampf(bx - 22.0, 0.0, w - sk)
			var x1 := clampf(bx + 22.0, 0.0, w - sk)
			if x1 - x0 > 2.0:
				draw_colored_polygon(PackedVector2Array([Vector2(x0 + sk, 0), Vector2(x1 + sk, 0), Vector2(x1, ht), Vector2(x0, ht)]),
						Color(1, 1, 1, 0.09 * (1.0 - absf(sheen - 0.5) * 1.4)))
		var pad := ht * (0.30 if big else 0.28) + 8.0 * h
		var ts := int(ht * (0.44 if big else 0.38))
		var ss := maxi(int(ht * (0.14 if big else 0.17)), 9)
		var ns := maxi(int(ht * 0.15), 9)
		var tcol := TEXT.lerp(Color.WHITE, h * 0.6)
		draw_string(f, Vector2(pad, ht * (0.60 if big else 0.58)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, Color(tcol.r, tcol.g, tcol.b, a))
		draw_string(f, Vector2(pad, ht * 0.86), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(DIM.r, DIM.g, DIM.b, 0.8 * a))
		if num != "":
			draw_string(f, Vector2(0, ht * 0.30), num, HORIZONTAL_ALIGNMENT_RIGHT, w - ht * 0.34, ns, Color(DIM.r, DIM.g, DIM.b, 0.85 * a))
		var sc := Color(bc.r, bc.g, bc.b, a)
		for i in 3:
			var sx := w - ht * 0.62 + float(i) * ht * 0.1
			draw_line(Vector2(sx, ht * 0.88), Vector2(sx + ht * 0.1, ht * 0.66), sc, 1.5)
		if section != "":
			draw_string(f, Vector2(0, -ht * 0.10), section, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(ht * 0.12), 9), Color(DIM.r, DIM.g, DIM.b, 0.8 * a))
		if h > 0.01:                                       # penanda segitiga merah di kiri tombol terpilih
			var g := ht * 0.2 * h
			draw_colored_polygon(PackedVector2Array([Vector2(-g * 1.5, ht * 0.5 - g * 0.5), Vector2(-g * 1.5, ht * 0.5 + g * 0.5), Vector2(-g * 0.4, ht * 0.5)]),
					Color(RED.r, RED.g, RED.b, h))


## Garis penghubung antar tombol (jalur siku tipis ala diagram). Titik dalam fraksi layar; digambar bertahap saat menu muncul.
class Wires extends Control:
	var paths: Array = []
	var col := Color(0.49, 0.388, 0.329, 0.6)
	var reveal := 0.0:
		set(v):
			reveal = v
			queue_redraw()

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _draw() -> void:
		if reveal <= 0.001:
			return
		var n := paths.size()
		for i in n:
			var p := clampf(reveal * float(n) - float(i), 0.0, 1.0)
			if p <= 0.0:
				continue
			var src: PackedVector2Array = paths[i]
			var pts := PackedVector2Array()
			for q in src:
				pts.append(Vector2(q.x * size.x, q.y * size.y))
			var total := 0.0
			for k in range(pts.size() - 1):
				total += pts[k].distance_to(pts[k + 1])
			var want := total * p
			var acc := 0.0
			var drawn := PackedVector2Array([pts[0]])
			for k in range(pts.size() - 1):
				var seg := pts[k].distance_to(pts[k + 1])
				if acc + seg <= want:
					drawn.append(pts[k + 1])
					acc += seg
				else:
					drawn.append(pts[k].lerp(pts[k + 1], (want - acc) / maxf(seg, 0.001)))
					break
			if drawn.size() >= 2:
				draw_polyline(drawn, col, 1.0, true)
			draw_rect(Rect2(pts[0] - Vector2(2, 2), Vector2(4, 4)), col)
			if p >= 1.0:
				draw_rect(Rect2(pts[pts.size() - 1] - Vector2(2, 2), Vector2(4, 4)), col)


## Hiasan terminal: siku sudut layar, header (merek + status), footer (petunjuk tombol + jam).
class Deco extends Control:
	const TEXT := Color(0.918, 0.863, 0.812)
	const DIM := Color(0.788, 0.604, 0.494)
	const BORDER := Color(0.49, 0.388, 0.329)
	const RED := Color(0.78, 0.2, 0.17)
	var reveal := 0.0
	var font: Font
	var t := 0.0
	var hints: Array = []
	var mode_text := "MAIN TERMINAL"
	var col := Color(0.45, 0.68, 0.72)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	func _process(d: float) -> void:
		t += d
		if reveal > 0.001:
			queue_redraw()

	func _draw() -> void:
		if reveal <= 0.001:
			return
		var w := size.x
		var h := size.y
		var m := 26.0
		var l := 48.0 * reveal
		var c := Color(col.r, col.g, col.b, 0.9 * reveal)
		var f: Font = font if font else ThemeDB.fallback_font
		var ta := reveal
		draw_line(Vector2(m, m), Vector2(m + l, m), c, 2.0)
		draw_line(Vector2(m, m), Vector2(m, m + l), c, 2.0)
		draw_line(Vector2(w - m, m), Vector2(w - m - l, m), c, 2.0)
		draw_line(Vector2(w - m, m), Vector2(w - m, m + l), c, 2.0)
		draw_line(Vector2(m, h - m), Vector2(m + l, h - m), c, 2.0)
		draw_line(Vector2(m, h - m), Vector2(m, h - m - l), c, 2.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m - l, h - m), c, 2.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m, h - m - l), c, 2.0)
		var x0 := m + 34.0
		var x1 := w - m - 34.0
		var line_c := Color(BORDER.r, BORDER.g, BORDER.b, 0.4 * ta)
		# header
		var hy := m + 42.0
		var by := m + 30.0
		draw_line(Vector2(x0, hy), Vector2(x0 + (x1 - x0) * reveal, hy), line_c, 1.0)
		var a1 := "PROJECT "
		var a2 := "REVENANT"
		var w1 := f.get_string_size(a1, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var w2 := f.get_string_size(a2, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, Vector2(x0, by), a1, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(TEXT.r, TEXT.g, TEXT.b, ta))
		draw_string(f, Vector2(x0 + w1, by), a2, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(RED.r, RED.g, RED.b, ta))
		var sx := x0 + w1 + w2 + 14.0
		draw_line(Vector2(sx, by - 13.0), Vector2(sx, by + 1.0), line_c, 1.0)
		draw_string(f, Vector2(sx + 12.0, by - 2.0), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(DIM.r, DIM.g, DIM.b, 0.85 * ta))
		var st := "FACILITY LINK STABLE"
		var stw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2(x1 - stw, by - 2.0), st, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(DIM.r, DIM.g, DIM.b, 0.85 * ta))
		var blink := 0.55 + 0.45 * sin(t * 3.0)
		draw_rect(Rect2(x1 - stw - 14.0, by - 9.0, 5, 5), Color(RED.r, RED.g, RED.b, blink * ta))
		# footer
		var fy := h - m - 42.0
		draw_line(Vector2(x0, fy), Vector2(x0 + (x1 - x0) * reveal, fy), line_c, 1.0)
		var cx := x0
		for hnt in hints:
			var key: String = hnt[0]
			var lab: String = hnt[1]
			var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
			draw_rect(Rect2(cx, fy + 10.0, kw, 18.0), Color(BORDER.r, BORDER.g, BORDER.b, 0.8 * ta), false, 1.0)
			draw_string(f, Vector2(cx + 7.0, fy + 23.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(TEXT.r, TEXT.g, TEXT.b, ta))
			cx += kw + 8.0
			draw_string(f, Vector2(cx, fy + 23.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(DIM.r, DIM.g, DIM.b, 0.85 * ta))
			cx += f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 24.0
		draw_string(f, Vector2(0, fy + 23.0), "AWAITING INPUT", HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(DIM.r, DIM.g, DIM.b, 0.6 * ta))
		var secs := int(t)
		var clock := "T+ %02d:%02d:%02d" % [floori(secs / 3600.0), floori(secs / 60.0) % 60, secs % 60]
		draw_string(f, Vector2(x1 - 200.0, fy + 23.0), clock, HORIZONTAL_ALIGNMENT_RIGHT, 200.0, 10, Color(DIM.r, DIM.g, DIM.b, 0.85 * ta))


class DottedBox extends Control:
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var c := Color(0.35, 0.65, 0.75, 0.9)
		var tr_ := Vector2(r.end.x, r.position.y)
		var bl := Vector2(r.position.x, r.end.y)
		draw_dashed_line(r.position, tr_, c, 1.5, 4.0)
		draw_dashed_line(tr_, r.end, c, 1.5, 4.0)
		draw_dashed_line(r.end, bl, c, 1.5, 4.0)
		draw_dashed_line(bl, r.position, c, 1.5, 4.0)


func _ready() -> void:
	_rig = $CamRig
	_cam = $CamRig/Camera3D
	if ResourceLoader.exists("res://sfx/click.mp3"):
		_click = load("res://sfx/click.mp3")
	_start_ambience()
	RevSettings.apply_saved()
	if font:
		($Hall/SignSub as Label3D).font = font
		($Hall/SignTitle as Label3D).font = font
	_build_ui()
	_base_fov = _cam.fov
	_rig.global_transform = ($Poses/Intro as Node3D).global_transform
	_sign_alpha(0.0)
	if crt_fx:
		_build_crt()
		_fade.color.a = 0.0
		_crt_mat.set_shader_parameter("power_on", 0.0)           # layar menyala seperti monitor CRT
		var pw := create_tween()
		pw.tween_interval(0.25)
		pw.tween_method(func(v: float) -> void: _crt_mat.set_shader_parameter("power_on", v), 0.0, 1.0, 1.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		pw.tween_callback(_glitch.bind(0.8, 0.5))
	else:
		_fade.color.a = 1.0
		create_tween().tween_property(_fade, "color:a", 0.0, 1.6)
	var tf := create_tween()
	tf.tween_interval(1.8)
	tf.tween_callback(_flicker_sign)
	_move_to($Poses/Title, intro_time, Tween.TRANS_QUART, Tween.EASE_OUT).finished.connect(_enter_title)


func _process(delta: float) -> void:
	_t += delta
	var sw := sway * (0.15 if _state == S.SETTINGS else 1.0)      # di depan monitor kamera hampir diam supaya teks stabil
	_cam.position = Vector3(sin(_t * 0.6), sin(_t * 0.45) * 0.6, 0.0) * sw
	_cam.rotation = Vector3(sin(_t * 0.3) * 0.3, sin(_t * 0.37) * 0.4, 0.0) * sw
	if parallax > 0.0:                                  # kamera mengikuti mouse dengan lembut
		var vp := get_viewport()
		var m := vp.get_mouse_position() / vp.get_visible_rect().size - Vector2(0.5, 0.5)
		var w := 1.0 if (_state == S.MENU or _state == S.CREDITS or _state == S.TITLE) else 0.0
		_par = _par.lerp(m.clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5)) * w, 1.0 - exp(-delta * 3.0))
		_cam.rotation += Vector3(-_par.y, -_par.x, 0.0) * parallax * 2.0
	if _state == S.SETTINGS and _set_ui != null:
		_fit_screen()                                       # panel menempel di monitor walau kamera bergoyang


func _unhandled_input(event: InputEvent) -> void:
	if _state == S.TITLE and event.is_pressed() and not event.is_echo():
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
			_go_menu()
	elif _state == S.CREDITS and event.is_action_pressed("ui_cancel"):
		_back()
	elif _state == S.SETTINGS and event.is_action_pressed("ui_cancel"):
		if _set_menu != null and _set_menu.get_child_count() > 1:
			return                                       # sub-menu keybind sedang terbuka, biar ia yang menangani ESC
		get_viewport().set_input_as_handled()
		_settings_back()


# ---------- kamera ----------
func _move_to(pose: Node3D, time: float, trans := Tween.TRANS_CUBIC, ease_ := Tween.EASE_IN_OUT) -> Tween:
	var from := _rig.global_transform
	var to := pose.global_transform
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: _rig.global_transform = from.interpolate_with(to, w), 0.0, 1.0, time).set_trans(trans).set_ease(ease_)
	return tw


func _sign_alpha(a: float) -> void:
	($Hall/SignSub as Label3D).modulate.a = a
	($Hall/SignTitle as Label3D).modulate.a = a
	($Lights/SignGlow as OmniLight3D).light_energy = 1.6 * a


func _flicker_sign() -> void:
	var tw := create_tween()
	for a in [0.0, 0.8, 0.1, 1.0, 0.3, 1.0]:
		tw.tween_callback(_sign_alpha.bind(a))
		tw.tween_interval(randf_range(0.05, 0.16))


func _enter_title() -> void:
	_state = S.TITLE
	_prompt.modulate.a = 1.0
	_show(_prompt)
	_set_hints([["ANY KEY", "START"]], "MAIN TERMINAL")
	_scramble(_prompt_label, "press anything to start", 0.8, 0.2)
	if _deco != null:
		create_tween().tween_property(_deco, "reveal", 1.0, 1.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_prompt_tw = create_tween().set_loops()               # "bernapas" lembut
	_prompt_tw.tween_property(_prompt, "modulate:a", 0.4, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_prompt_tw.tween_property(_prompt, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------- alur menu ----------
func _go_menu() -> void:
	_state = S.BUSY
	_click_sfx()
	if _prompt_tw != null:
		_prompt_tw.kill()
	_prompt.modulate.a = 1.0
	_hide(_prompt)
	_move_to($Poses/Menu, 2.8, Tween.TRANS_QUINT, Tween.EASE_IN_OUT).finished.connect(_menu_ready)


func _menu_ready() -> void:
	_show(_menu, 0.1)
	_set_hints([["ARROWS", "NAVIGATE"], ["ENTER", "SELECT"]], "MAIN TERMINAL")
	if _wires != null:
		_wires.reveal = 0.0
		create_tween().tween_property(_wires, "reveal", 1.0, 1.5).set_delay(0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_state = S.MENU
	_btn_play.grab_focus()


func _play() -> void:
	if _state != S.MENU:
		return
	_state = S.BUSY
	_click_sfx()
	play_pressed.emit()
	_hide(_menu)
	var dl := $Door/DoorL as Node3D
	var dr := $Door/DoorR as Node3D
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dl, "position:x", dl.position.x - 3.1, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(dr, "position:x", dr.position.x + 3.1, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property($Lights/DoorGlow, "light_energy", 5.0, 2.2)
	_move_to($Poses/Door, 3.2, Tween.TRANS_CUBIC, Tween.EASE_IN).finished.connect(_fade_then_play)


func _fade_then_play() -> void:
	_fade_to(1.0, 0.6, _load_play)


func _load_play() -> void:
	if ResourceLoader.exists(play_scene):
		get_tree().change_scene_to_file(play_scene)
	else:
		push_warning("MenuWorld: play_scene tidak ketemu: " + play_scene)
		_fade.color.a = 0.0
		_state = S.MENU


func _open_credits() -> void:
	if _state != S.MENU:
		return
	_state = S.BUSY
	_click_sfx()
	_hide(_menu)
	create_tween().tween_property($Lights/BoardLight, "light_energy", 7.0, 1.8)
	_move_to($Poses/Credits, 2.2, Tween.TRANS_QUINT, Tween.EASE_IN_OUT).finished.connect(_credits_ready)


func _credits_ready() -> void:
	_show(_credits_ui, 0.1)
	_start_credits_scroll()
	_set_hints([["WHEEL", "SCROLL"], ["ESC", "BACK"]], "PERSONNEL ROSTER")
	for i in _cr_labels.size():
		_scramble(_cr_labels[i], _cr_labels[i].get_meta("final"), 0.8, 0.15 + 0.1 * i)
	_state = S.CREDITS
	_btn_back.grab_focus()


func _back() -> void:
	if _state != S.CREDITS:
		return
	_state = S.BUSY
	_stop_credits_scroll()
	_click_sfx()
	_hide(_credits_ui)
	create_tween().tween_property($Lights/BoardLight, "light_energy", 1.2, 1.4)
	_move_to($Poses/Menu, 2.2, Tween.TRANS_QUINT, Tween.EASE_IN_OUT).finished.connect(_menu_ready)


# ---------- settings (di monitor) ----------
# Isinya SettingsMenu in-game yang sama persis (res://settings_menu.tscn): slider, toggle, keybind, simpan, reset.
# Ditaruh di dalam layar monitor dan diskalakan supaya pas.
const SETTINGS_SCENE := "res://settings_menu.tscn"
const SET_W := 860.0                                     # lebar desain panel (tinggi menyesuaikan rasio layar monitor)
const SCREEN_INSET := Vector2(0.074, 0.062)              # bagian bingkai monitor yang tidak dipakai (fraksi kotak monitor)


const DOOR_OPEN := 1.75                                 # sudut buka pintu kaca booth (radian). + = membuka ke luar (ke lorong), - = ke dalam booth
var _door_a := 0.0


func _pose(nm: String) -> Node3D:
	return get_node_or_null("Poses/" + nm) as Node3D


# Pintu kaca booth berayun di engselnya (sisi +Z). Node "Props/door" dan "Props/knoob" diputar mengelilingi engsel itu.
func _swing_door(open: bool, time := 0.9) -> Tween:
	var tw := create_tween()
	tw.tween_method(_set_door_angle, _door_a, DOOR_OPEN if open else 0.0, time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return tw


func _set_door_angle(a: float) -> void:
	_door_a = a
	var d := get_node_or_null("Props/door") as CSGBox3D
	if d == null:
		return
	if not d.has_meta("t0"):
		d.set_meta("t0", d.transform)
		var kn0 := get_node_or_null("Props/knoob") as Node3D
		if kn0 != null:
			kn0.set_meta("t0", kn0.transform)
		d.set_meta("hinge", Vector3(d.position.x, 0.0, d.position.z + d.size.z * 0.5))
	var hinge: Vector3 = d.get_meta("hinge")
	_rot_about(d, hinge, a)
	var kn := get_node_or_null("Props/knoob") as Node3D
	if kn != null and kn.has_meta("t0"):
		_rot_about(kn, hinge, a)


func _rot_about(n: Node3D, hinge: Vector3, a: float) -> void:
	var t0: Transform3D = n.get_meta("t0")
	var b := Basis(Vector3.UP, a)
	n.transform = Transform3D(b * t0.basis, hinge + b * (t0.origin - hinge))


# Satu gerakan mulus tanpa berhenti: menu -> pintu booth -> masuk -> jalan menghadap monitor -> zoom ke monitor ke-3.
func _settings() -> void:
	if _state != S.MENU:
		return
	_state = S.BUSY
	_click_sfx()
	settings_pressed.emit()
	_hide(_menu)
	var path := _settings_path()
	if path.is_empty():                                        # scene lama tanpa marker: langsung ke monitor
		_move_to($Poses/Settings, 2.4, Tween.TRANS_QUINT, Tween.EASE_IN_OUT).finished.connect(_settings_ready)
		return
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void: _swing_door(true, 0.7))   # pintu terbuka saat kamera mendekat
	tw.tween_interval(1.5)
	tw.tween_callback(func() -> void: _swing_door(false, 0.6))  # menutup setelah kamera lewat
	_move_path([_rig.global_transform] + path, 4.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT).finished.connect(_settings_ready)


# Titik-titik jalur dari depan pintu sampai monitor. Kosong kalau marker belum ada.
func _settings_path() -> Array:
	var door := _pose("SettingsDoor")
	var walk: Array = []
	for nm in ["setting walk", "setting walk2", "setting walk3"]:
		var m := _pose(nm)
		if m != null:
			walk.append(m)
	if door == null or walk.is_empty():
		return []
	var inside: Transform3D = door.global_transform                 # lurus lewat pintu dulu, baru belok ke jalur monitor
	inside.origin.x = (walk[0] as Node3D).global_position.x
	return [door, inside] + walk + [$Poses/Settings]


# Jalan mulus menyusuri beberapa titik (marker atau Transform3D) dalam satu tween.
var _path_xs: Array[Transform3D] = []
var _path_cum: Array[float] = []


func _move_path(poses: Array, time: float, trans := Tween.TRANS_SINE, ease_ := Tween.EASE_IN_OUT) -> Tween:
	_path_xs.clear()
	_path_cum = [0.0]
	for p in poses:
		_path_xs.append((p as Node3D).global_transform if p is Node3D else p)
	for k in range(1, _path_xs.size()):
		_path_cum.append(_path_cum[k - 1] + _path_xs[k].origin.distance_to(_path_xs[k - 1].origin))
	var tw := create_tween()
	tw.tween_method(_path_step, 0.0, 1.0, time).set_trans(trans).set_ease(ease_)
	return tw


func _path_step(w: float) -> void:
	var n := _path_xs.size()
	var d: float = w * maxf(_path_cum[n - 1], 0.001)
	var i := 1
	while i < n - 1 and d > _path_cum[i]:
		i += 1
	var seg: float = maxf(_path_cum[i] - _path_cum[i - 1], 0.0001)
	var f: float = clampf((d - _path_cum[i - 1]) / seg, 0.0, 1.0)
	var t1 := _path_xs[i - 1]
	var t2 := _path_xs[i]
	var t0 := _path_xs[maxi(i - 2, 0)]
	var t3 := _path_xs[mini(i + 1, n - 1)]
	# Catmull-Rom: lintasan melengkung halus lewat semua titik (tanpa sudut kaku), rotasi ikut melengkung
	var pos := t1.origin.cubic_interpolate(t2.origin, t0.origin, t3.origin, f)
	var q1 := t1.basis.get_rotation_quaternion()
	var q2 := t2.basis.get_rotation_quaternion()
	var q0 := t0.basis.get_rotation_quaternion()
	var q3 := t3.basis.get_rotation_quaternion()
	var q := q1.spherical_cubic_interpolate(q2, q0, q3, f)
	_rig.global_transform = Transform3D(Basis(q), pos)


# Kamera sudah sampai: monitor menyala, layar langsung terbuka.
func _settings_ready() -> void:
	_mon_glow(true)
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(_settings_screen_on)


func _settings_screen_on() -> void:
	if _set_ui == null:
		_build_settings()
	_state = S.SETTINGS
	_set_hints([["MOUSE", "ADJUST"], ["ESC", "BACK"]], "SYSTEM CONFIG")
	_fit_screen(true)
	_set_ui.visible = true
	_set_screen.modulate.a = 0.0
	_set_screen.scale = Vector2(1.0, 0.02)                 # layar membuka dari garis tipis, seperti CRT menyala
	var tw := create_tween()
	tw.tween_property(_set_screen, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_set_screen, "scale:y", 1.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_settings_focus)
	_glitch(0.6, 0.4)


func _settings_focus() -> void:
	if _set_menu == null:
		return
	var f := _set_menu.find_child("MasterSlider", true, false) as Control
	if f != null:
		f.grab_focus()


func _settings_back() -> void:
	if _state != S.SETTINGS:
		return
	_state = S.BUSY
	_click_sfx()
	var tw := create_tween()
	tw.tween_property(_set_screen, "scale:y", 0.02, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_set_screen, "modulate:a", 0.0, 0.28).set_delay(0.08)
	tw.tween_callback(_settings_leave)


# Jalur keluar: sama dengan jalur masuk dibalik, tapi kamera menghadap arah jalan (lurus ke depan), bukan mundur menghadap monitor.
func _exit_path(path: Array) -> Array:
	var pts: Array[Transform3D] = []
	for k in range(path.size() - 2, -1, -1):                  # lewati monitor (kamera sudah di sana), balik: walk3 ... inside, door
		pts.append((path[k] as Node3D).global_transform if path[k] is Node3D else path[k])
	var out: Array = []
	for k in pts.size():
		var o := pts[k].origin
		var dir: Vector3
		if k < pts.size() - 2:
			dir = pts[k + 1].origin - o                        # menuju titik berikutnya
		else:
			dir = Vector3(-1, 0, 0)                            # dekat pintu: menghadap keluar ke lorong
		dir.y = 0.0
		out.append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), o))
	return out


# Keluar: layar & monitor mati, lalu satu gerakan mulus mundur lewat jalur yang sama, keluar pintu, kembali ke menu.
func _settings_leave() -> void:
	_set_ui.visible = false
	_mon_glow(false)
	var path := _settings_path()
	if path.is_empty():
		_move_to($Poses/Menu, 2.4, Tween.TRANS_QUINT, Tween.EASE_IN_OUT).finished.connect(_menu_ready)
		return
	path = _exit_path(path)
	var tw := create_tween()
	tw.tween_callback(func() -> void: _swing_door(true, 0.6))
	tw.tween_interval(2.3)
	tw.tween_callback(func() -> void: _swing_door(false, 0.6))
	_move_path([_rig.global_transform] + path + [$Poses/Menu], 4.0, Tween.TRANS_SINE, Tween.EASE_IN_OUT).finished.connect(_menu_ready)


func _build_settings() -> void:
	_set_ui = Control.new()
	_full(_set_ui)
	_set_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_ui.visible = false
	_ui.add_child(_set_ui)
	_ui.move_child(_set_ui, _toast.get_index())            # di bawah toast & fade
	var scr := Panel.new()
	scr.clip_contents = true
	scr.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.06, 0.07, 0.98)
	bg.border_color = Color(0.36, 0.52, 0.55, 0.7)
	bg.set_border_width_all(2)
	scr.add_theme_stylebox_override("panel", bg)
	_set_ui.add_child(scr)
	_set_screen = scr
	_fit_screen(true)
	var dh := SET_W * _set_rect.size.y / maxf(_set_rect.size.x, 1.0)
	_set_holder = Control.new()
	_set_holder.size = Vector2(SET_W, dh)
	_set_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scr.add_child(_set_holder)
	_fit_screen(true)
	if not ResourceLoader.exists(SETTINGS_SCENE):
		_set_holder.add_child(_label("settings_menu.tscn tidak ketemu (SETTINGS_SCENE)", 20, Color(0.9, 0.5, 0.4)))
		return
	var sm := (load(SETTINGS_SCENE) as PackedScene).instantiate() as Control
	sm.set("panel_size", Vector2(SET_W, dh))              # harus diisi sebelum masuk tree (dipakai di _ready-nya)
	sm.set("font_size", 17)
	sm.set("title_size", 30)
	sm.set("label_width", 200.0)
	sm.connect("back_pressed", _settings_back)
	if font:
		var th := Theme.new()
		th.default_font = font
		sm.theme = th
	_set_holder.add_child(sm)
	_set_menu = sm
	_skin_settings(sm)


func _skin_settings(sm: Control) -> void:
	# Gaya panel/tombol/slider sudah dipasang oleh settings_menu.gd sendiri (RevUI). Di sini cuma merapatkan margin untuk layar monitor.
	var margin := sm.get_node_or_null("Panel/Margin") as MarginContainer
	if margin != null:
		for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			margin.add_theme_constant_override(k, 4)


func _monitor_node() -> CSGBox3D:
	return get_node_or_null("Props/Monitor2") as CSGBox3D


# Kotak layar monitor di layar (hasil proyeksi kamera). Ganti "Monitor2" di atas untuk pindah ke monitor lain
# (jangan lupa pindahkan marker Poses/Settings di depan monitor itu).
func _monitor_rect() -> Rect2:
	var m := _monitor_node()
	if m == null:
		return Rect2()
	var sz := m.size
	var t := m.global_transform
	var first := true
	var r := Rect2()
	for sgn in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
		var p: Vector3 = t * Vector3(-0.5 * sz.x, 0.5 * sgn.y * sz.y, 0.5 * sgn.x * sz.z)
		var q := _cam.unproject_position(p)
		if first:
			r = Rect2(q, Vector2.ZERO)
			first = false
		else:
			r = r.expand(q)
	return r


func _screen_rect() -> Rect2:
	var r := _monitor_rect()
	if r.size.x < 8.0:
		return r
	var pad := Vector2(r.size.x * SCREEN_INSET.x, r.size.y * SCREEN_INSET.y)
	r = r.grow_individual(-pad.x, -pad.y, -pad.x, -pad.y)
	r.position = r.position.round()
	r.size = r.size.round()
	return r


func _fit_screen(force := false) -> void:
	var r := _screen_rect()
	if r.size.x < 8.0:
		return
	if not force and r.position.distance_to(_set_rect.position) < 0.5 and r.size.distance_to(_set_rect.size) < 0.5:
		return
	_set_rect = r
	_set_screen.offset_left = r.position.x
	_set_screen.offset_top = r.position.y
	_set_screen.offset_right = r.end.x
	_set_screen.offset_bottom = r.end.y
	_set_screen.pivot_offset = r.size * 0.5
	if _set_holder != null:
		_set_holder.scale = Vector2.ONE * (r.size.x / SET_W)


func _mon_glow(on: bool) -> void:
	var m := _monitor_node()
	var booth := get_node_or_null("Lights/Booth") as OmniLight3D
	if m == null:
		return
	if _mon_mat == null:
		_mon_mat = StandardMaterial3D.new()
		_mon_mat.albedo_color = Color(0.02, 0.08, 0.09)
		_mon_mat.emission_enabled = true
		_mon_mat.emission = Color(0.25, 0.9, 0.85)
		_mon_mat.emission_energy_multiplier = 0.0
		_mon_orig = m.material
	var tw := create_tween().set_parallel(true)
	if on:
		m.material = _mon_mat
		tw.tween_property(_mon_mat, "emission_energy_multiplier", 1.1, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		if booth != null:
			tw.tween_property(booth, "light_energy", 3.0, 1.2).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_property(_mon_mat, "emission_energy_multiplier", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		if booth != null:
			tw.tween_property(booth, "light_energy", 1.6, 1.2).set_trans(Tween.TRANS_SINE)
		tw.chain().tween_callback(_mon_restore)


func _mon_restore() -> void:
	var m := _monitor_node()
	if m != null and _state != S.SETTINGS and _state != S.BUSY or (m != null and _mon_mat != null and _mon_mat.emission_energy_multiplier <= 0.01):
		m.material = _mon_orig


func _quit() -> void:
	if _state != S.MENU:
		return
	_state = S.BUSY
	_click_sfx()
	_fade_to(1.0, 0.6, get_tree().quit)


# ---------- util UI ----------
# Setiap anak Control di container muncul satu per satu (berurutan dari atas ke bawah): geser masuk dari sisinya
# sambil membesar halus dan memudar masuk. Saat hilang kebalikannya. Posisi asli disimpan di meta supaya tidak melenceng.
func _base(o: Control) -> Dictionary:
	if not o.has_meta("ui_base"):
		o.set_meta("ui_base", {"l": o.offset_left, "t": o.offset_top, "r": o.offset_right, "b": o.offset_bottom, "a": o.modulate.a})
	return o.get_meta("ui_base")


func _is_full(o: Control) -> bool:
	return o.anchor_right - o.anchor_left > 0.9 and o.anchor_bottom - o.anchor_top > 0.9


func _slide_dir(o: Control) -> Vector2:
	if _is_full(o):
		return Vector2.ZERO
	var cx := (o.anchor_left + o.anchor_right) * 0.5
	if cx < 0.4:
		return Vector2(-1, 0)
	if cx > 0.6:
		return Vector2(1, 0)
	return Vector2(0, 1)


func _kids(c: Control) -> Array:
	var out: Array = []
	for n in c.get_children():
		if n is Control:
			out.append(n)
	out.sort_custom(_cmp_ui)
	return out


func _cmp_ui(x: Control, y: Control) -> bool:
	var cy1 := (x.anchor_top + x.anchor_bottom) * 0.5
	var cy2 := (y.anchor_top + y.anchor_bottom) * 0.5
	if absf(cy1 - cy2) > 0.001:
		return cy1 < cy2
	return x.anchor_left < y.anchor_left


func _gen(c: Control) -> int:
	var g: int = int(c.get_meta("ui_gen", 0)) + 1
	c.set_meta("ui_gen", g)
	return g


func _show(c: Control, delay := 0.0) -> void:
	_gen(c)
	c.visible = true
	c.modulate.a = 1.0
	var i := 0
	for k in _kids(c):
		var o: Control = k
		var base := _base(o)
		var d := _slide_dir(o)
		var full := _is_full(o)
		var off := d * ui_slide
		var dl := delay + float(i) * ui_stagger
		o.offset_left = base.l + off.x
		o.offset_right = base.r + off.x
		o.offset_top = base.t + off.y * 0.5
		o.offset_bottom = base.b + off.y * 0.5
		o.modulate.a = 0.0
		o.pivot_offset = o.size * 0.5
		o.scale = Vector2.ONE if full else Vector2(0.94, 0.94)
		var old = o.get_meta("ui_tw", null)
		if old is Tween and old.is_valid():
			old.kill()
		var tw := create_tween().set_parallel(true)
		o.set_meta("ui_tw", tw)
		tw.tween_property(o, "offset_left", base.l, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_right", base.r, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_top", base.t, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_bottom", base.b, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "scale", Vector2.ONE, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "modulate:a", float(base.a), 0.5).set_delay(dl).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		i += 1


func _hide(c: Control) -> void:
	var g := _gen(c)
	var kids := _kids(c)
	var i := 0
	for k in kids:
		var o: Control = k
		var base := _base(o)
		var d := _slide_dir(o)
		var off := d * ui_slide * 0.6
		var dl := float(i) * ui_stagger * 0.5
		var old = o.get_meta("ui_tw", null)
		if old is Tween and old.is_valid():
			old.kill()
		var tw := create_tween().set_parallel(true)
		o.set_meta("ui_tw", tw)
		tw.tween_property(o, "offset_left", base.l + off.x, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_right", base.r + off.x, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_top", base.t + off.y * 0.5, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_bottom", base.b + off.y * 0.5, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "modulate:a", 0.0, 0.3).set_delay(dl).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		i += 1
	var done := create_tween()
	done.tween_interval(0.4 + float(i) * ui_stagger * 0.5)
	done.tween_callback(_finish_hide.bind(c, g))


func _finish_hide(c: Control, g: int) -> void:
	if int(c.get_meta("ui_gen", 0)) != g:
		return                                           # sempat ditampilkan lagi -> jangan disembunyikan
	c.hide()
	for k in c.get_children():
		if k is Control:
			var o: Control = k
			var base := _base(o)
			o.offset_left = base.l
			o.offset_right = base.r
			o.offset_top = base.t
			o.offset_bottom = base.b
			o.modulate.a = float(base.a)
			o.scale = Vector2.ONE


func _pulse(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(0.96, 0.96), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade_to(a: float, time: float, then: Callable) -> void:
	if crt_fx and _crt_mat != null and a >= 0.99:                  # monitor "mati": layar menyempit jadi garis
		create_tween().tween_method(func(v: float) -> void: _crt_mat.set_shader_parameter("power_on", v), 1.0, 0.0, time).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		_glitch(0.7, time)
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(then)


func _show_toast(text: String) -> void:
	_toast.text = text
	if _toast_tw != null:
		_toast_tw.kill()
	var base := _base(_toast)
	_toast.offset_top = base.t + 16.0
	_toast.offset_bottom = base.b + 16.0
	_toast.modulate.a = 0.0
	_toast_tw = create_tween()
	_toast_tw.set_parallel(true)
	_toast_tw.tween_property(_toast, "offset_top", base.t, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_property(_toast, "offset_bottom", base.b, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_toast_tw.tween_property(_toast, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	_toast_tw.chain().tween_interval(1.4)
	_toast_tw.chain().tween_property(_toast, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _click_sfx() -> void:
	_glitch(0.55, 0.35)
	_kick()
	if _click == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = _click
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _start_ambience() -> void:
	var path := "res://sfx/ambient_drone.wav"
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer.new()
	p.stream = load(path)
	p.volume_db = -14.0
	add_child(p)
	p.finished.connect(p.play)
	p.play()


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _frac(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_btn(parent: Control, title: String, sub: String, box: Vector4, num := "", section := "", big := false, locked := false) -> NavBtn:
	var b := NavBtn.new()
	b.title = title
	b.subtitle = sub
	b.num = num
	b.section = section
	b.big = big
	b.locked = locked
	b.font = font
	b.fx_on = hover_fx
	b.tick = _tick
	_frac(b, box.x, box.y, box.z, box.w)
	parent.add_child(b)
	b.pressed.connect(_pulse.bind(b))                    # kedutan kecil saat ditekan
	return b


func _nb(from: Control, dir: String, to: Control) -> void:
	var path := from.get_path_to(to)
	match dir:
		"top":
			from.focus_neighbor_top = path
		"bottom":
			from.focus_neighbor_bottom = path
		"left":
			from.focus_neighbor_left = path
		"right":
			from.focus_neighbor_right = path


func _set_hints(items: Array, mode: String) -> void:
	if _deco != null:
		_deco.hints = items
		_deco.mode_text = mode


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	if deco_fx:
		var dc := Deco.new()
		dc.font = font
		_deco = dc
		_ui.add_child(_deco)
	_credits_ui = _make_credits()
	_credits_ui.visible = false
	_ui.add_child(_credits_ui)

	_menu = Control.new()
	_full(_menu)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_ui.add_child(_menu)

	var c := _make_btn(_menu, "CREDITS", "PERSONNEL ROSTER", Vector4(0.04, 0.56, 0.25, 0.65), "03", "03 / PERSONNEL")
	_btn_play = _make_btn(_menu, "PLAY", "BEGIN THE DESCENT", Vector4(0.33, 0.43, 0.67, 0.61), "[ ENTER ]", "01 / BEGIN", true)
	var s := _make_btn(_menu, "SETTINGS", "AUDIO · VIDEO · CONTROLS", Vector4(0.72, 0.36, 0.95, 0.45), "02", "02 / CONFIGURE")
	var q := _make_btn(_menu, "QUIT", "LEAVE THE FACILITY", Vector4(0.74, 0.73, 0.91, 0.81), "04", "04 / EXIT")
	s.pressed.connect(_settings)
	c.pressed.connect(_open_credits)
	_btn_play.pressed.connect(_play)
	q.pressed.connect(_quit)
	_nb(_btn_play, "left", c)
	_nb(_btn_play, "right", s)
	_nb(_btn_play, "bottom", q)
	_nb(c, "right", _btn_play)
	_nb(s, "left", _btn_play)
	_nb(s, "bottom", q)
	_nb(q, "top", s)
	_nb(q, "left", _btn_play)

	var wr := Wires.new()                                  # garis dari tiap tombol ke tombol PLAY
	wr.paths = [
		PackedVector2Array([Vector2(0.243, 0.605), Vector2(0.29, 0.605), Vector2(0.29, 0.52), Vector2(0.33, 0.52)]),
		PackedVector2Array([Vector2(0.72, 0.405), Vector2(0.695, 0.405), Vector2(0.695, 0.50), Vector2(0.668, 0.50)]),
		PackedVector2Array([Vector2(0.74, 0.77), Vector2(0.60, 0.77), Vector2(0.60, 0.61)]),
	]
	_wires = wr
	_menu.add_child(wr)

	_prompt = Control.new()
	_full(_prompt)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_ui.add_child(_prompt)
	var box := DottedBox.new()
	_frac(box, 0.32, 0.84, 0.68, 0.92)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(box)
	var pl := _label("press anything to start", 13, Color(0.8, 0.88, 0.9))
	_frac(pl, 0.32, 0.84, 0.68, 0.92)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt.add_child(pl)
	_prompt_label = pl

	_toast = _label("", 15, Color(0.95, 0.6, 0.2))
	_frac(_toast, 0.3, 0.83, 0.7, 0.89)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_ui.add_child(_toast)

	_fade = ColorRect.new()
	_full(_fade)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(_fade)


func _make_credits() -> Control:
	var root := Control.new()
	_full(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	_full(dim)
	dim.color = Color(0, 0.02, 0.03, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	var title := _label("CREDITS", 72, Color(0.95, 0.9, 0.84))
	_frac(title, 0.05, 0.14, 0.34, 0.30)
	root.add_child(title)
	_cr_labels.append(title)
	title.set_meta("final", "CREDITS")
	var tag := _label("Every descent begins\nwith those who build it.", 22, Color(0.9, 0.9, 0.9))
	_frac(tag, 0.05, 0.32, 0.33, 0.45)
	root.add_child(tag)
	_cr_labels.append(tag)
	tag.set_meta("final", tag.text)
	var small := _label("The creative and technical staff\nbehind Project Revenant.", 11, Color(0.6, 0.72, 0.74))
	_frac(small, 0.05, 0.46, 0.3, 0.56)
	root.add_child(small)
	root.add_child(_make_credits_list())
	_btn_back = _make_btn(root, "BACK", "RETURN TO TERMINAL", Vector4(0.05, 0.80, 0.24, 0.88), "ESC", "// RETURN")
	_btn_back.pressed.connect(_back)
	return root


func _make_credits_list() -> Control:
	var sc := ScrollContainer.new()
	_frac(sc, 0.37, 0.12, 0.96, 0.88)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER          # roda mouse tetap bisa menggulung
	sc.gui_input.connect(_credits_input)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	sc.add_child(col)
	_cr_top = Control.new()
	col.add_child(_cr_top)
	var teal := Color(0.55, 0.75, 0.78)
	for e in ENTRIES:
		if e.has("title"):
			var t := _label(e.title, 44, Color(0.95, 0.9, 0.84))
			col.add_child(t)
			col.add_child(_credit_line(Color(0.9, 0.25, 0.2, 0.9), 2))
		elif e.has("section"):
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 22)
			col.add_child(gap)
			col.add_child(_label(e.section, 14, Color(0.9, 0.25, 0.2)))
			col.add_child(_credit_line(Color(0.36, 0.52, 0.55, 0.6), 1))
		elif e.has("role"):
			col.add_child(_label(e.role, 13, Color(0.85, 0.86, 0.86)))
			var pc := PanelContainer.new()
			pc.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(0.9, 0.5, 0.12)
			sb.set_border_width_all(1)
			sb.content_margin_left = 8
			sb.content_margin_right = 8
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			pc.add_theme_stylebox_override("panel", sb)
			pc.add_child(_label(e.name, 17, Color(0.95, 0.6, 0.2)))
			col.add_child(pc)
		elif e.has("sub"):
			var g2 := Control.new()
			g2.custom_minimum_size = Vector2(0, 6)
			col.add_child(g2)
			col.add_child(_label(e.sub, 14, teal))
		elif e.has("item"):
			col.add_child(_label("·  " + str(e.item), 14, Color(0.82, 0.84, 0.84)))
	_cr_bottom = Control.new()
	col.add_child(_cr_bottom)
	_cr_scroll = sc
	return sc


func _credit_line(c: Color, h: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.custom_minimum_size = Vector2(0, h)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _credits_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_stop_credits_scroll()                                   # pengguna menggulung sendiri


func _start_credits_scroll() -> void:
	_stop_credits_scroll()
	if _cr_scroll == null:
		return
	_cr_top.custom_minimum_size = Vector2(0, _cr_scroll.size.y * 0.55)     # teks masuk dari bawah
	_cr_bottom.custom_minimum_size = Vector2(0, _cr_scroll.size.y * 0.45)
	_cr_scroll.scroll_vertical = 0
	await get_tree().process_frame
	await get_tree().process_frame
	if _state != S.CREDITS or credits_speed <= 0.0:
		return
	var bar := _cr_scroll.get_v_scroll_bar()
	var maxv := bar.max_value - bar.page
	if maxv <= 0.0:
		return
	_cr_tw = create_tween()
	_cr_tw.tween_interval(0.8)
	_cr_tw.tween_property(_cr_scroll, "scroll_vertical", int(maxv), maxv / credits_speed)


func _stop_credits_scroll() -> void:
	if _cr_tw != null and _cr_tw.is_valid():
		_cr_tw.kill()


# ---------- efek ----------
func _build_crt() -> void:
	_crt_layer = CanvasLayer.new()
	_crt_layer.layer = 30                                  # di atas UI (20): scanline & glitch kena semuanya
	add_child(_crt_layer)
	_crt_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = CRT_SHADER
	_crt_mat.shader = sh
	_crt_mat.set_shader_parameter("scan", crt_scan)
	_crt_mat.set_shader_parameter("vig", crt_vignette)
	_crt_mat.set_shader_parameter("chroma", crt_chroma)
	_crt_mat.set_shader_parameter("glitch", 0.0)
	_crt_mat.set_shader_parameter("power_on", 1.0)
	var r := ColorRect.new()
	_full(r)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.material = _crt_mat
	_crt_layer.add_child(r)


func _glitch(power := 1.0, dur := 0.35) -> void:
	if _crt_mat == null:
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _crt_mat.set_shader_parameter("glitch", v), power, 0.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)


func _kick() -> void:
	var tw := create_tween()
	tw.tween_property(_cam, "fov", _base_fov - 3.0, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cam, "fov", _base_fov, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _scramble(l: Label, final: String, time := 0.8, delay := 0.0) -> void:
	if l == null:
		return
	if not scramble_fx:
		l.text = final
		return
	l.text = ""
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_method(_scramble_step.bind(l, final), 0.0, 1.0, time)


func _scramble_step(p: float, l: Label, final: String) -> void:
	var n := final.length()
	var k := int(p * float(n))
	var out := ""
	for i in n:
		var ch := final[i]
		if i < k or ch == " " or ch == "\n":
			out += ch
		else:
			out += SCRAMBLE_CHARS[randi() % SCRAMBLE_CHARS.length()]
	l.text = out


func _tick() -> void:
	if _click == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = _click
	p.pitch_scale = 1.9
	p.volume_db = -20.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
