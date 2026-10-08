extends Control

@export var action_name: String = "interact"
@export var action_text: String = "MULAI"
@export var font: Font   # kosongin = font bawaan, isi pakai font pixel kamu biar makin nyatu

const PANEL_SIZE := Vector2(250, 48)
const SLANT := 10.0
const Y_OFFSET := 70.0   # jarak di bawah tengah layar (crosshair)

const COL_PANEL := Color("1c2422")
const COL_BORDER := Color("7b5e4c")
const COL_ACCENT := Color("dba98c")
const COL_TEXT := Color("e9dcc8")
const COL_DARK := Color("1c2422")

var _active := false
var _t := 0.0       # 0 = sembunyi, 1 = tampil penuh
var _flash := 0.0
var _press := 0.0   # BARU: 1 = baru ditekan, turun ke 0
var _time := 0.0
var _key_text := "E"
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x / 2.0
	offset_right = PANEL_SIZE.x / 2.0
	offset_top = Y_OFFSET
	offset_bottom = Y_OFFSET + PANEL_SIZE.y
	pivot_offset = PANEL_SIZE / 2.0
	modulate.a = 0.0
	visible = false
	set_process(false)


func set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on

	if _tween:
		_tween.kill()
	_tween = create_tween()

	if on:
		_key_text = _get_key_text()
		visible = true
		set_process(true)
		_flash = 1.0
		_tween.set_parallel(true)
		_tween.tween_property(self, "_t", 1.0, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "_flash", 0.0, 0.3)
	else:
		_tween.tween_property(self, "_t", 0.0, 0.12)
		_tween.tween_callback(_on_hidden)


func _on_hidden() -> void:
	if not _active:
		_press = 0.0   # BARU
		visible = false
		set_process(false)


func _process(delta: float) -> void:
	_time += delta

	# BARU: deteksi tombol interaksi ditekan
	if _active and Input.is_action_just_pressed(action_name):
		_press = 1.0
	_press = move_toward(_press, 0.0, delta * 4.0)
	var punch := 1.0 - 0.07 * _press

	modulate.a = clampf(_t, 0.0, 1.0)
	scale = Vector2(lerpf(0.88, 1.0, _t), lerpf(0.6, 1.0, _t)) * punch
	queue_redraw()


func _get_key_text() -> String:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			var code = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(code)
	return "E"


func _draw() -> void:
	var w := PANEL_SIZE.x
	var h := PANEL_SIZE.y
	var s := SLANT
	var f: Font = font if font else ThemeDB.fallback_font
	var fl := maxf(_flash, _press)   # BARU: kilatan dari muncul ATAU ditekan

	draw_set_transform(Vector2(0, (1.0 - _t) * 14.0))

	# Panel miring
	var pts := PackedVector2Array([
		Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)
	])
	draw_colored_polygon(pts, Color(COL_PANEL, 0.88))

	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, COL_BORDER.lerp(Color.WHITE, fl), 2.0)

	# Garis aksen kiri
	draw_colored_polygon(PackedVector2Array([
		Vector2(s, 0), Vector2(s + 7, 0), Vector2(7, h), Vector2(0, h)
	]), COL_ACCENT.lerp(Color.WHITE, fl))

	# Kotak tombol (berdenyut, ketekan ke bawah saat ditekan)
	var ks := 30.0
	var kx := 26.0
	var ky := (h - ks) / 2.0
	var kdy := 3.0 * _press   # BARU: seberapa dalam ketekan
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)

	draw_rect(Rect2(kx, ky + 3.0, ks, ks), COL_BORDER)   # BARU: dasar tombol
	draw_rect(Rect2(kx, ky + kdy, ks, ks),
		COL_ACCENT.lerp(Color.WHITE, pulse * 0.25 + fl * 0.6))
	draw_rect(Rect2(kx + 3, ky + 3 + kdy, ks - 6, ks - 6), COL_DARK, false, 2.0)

	var key_size := 18
	var key_w := f.get_string_size(_key_text, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size).x
	var key_y := ky + ks * 0.5 + (f.get_ascent(key_size) - f.get_descent(key_size)) * 0.5 + kdy
	draw_string(f, Vector2(kx + (ks - key_w) / 2.0, key_y), _key_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, key_size, COL_DARK)

	# Teks aksi
	var txt_size := 20
	var txt_y := h * 0.5 + (f.get_ascent(txt_size) - f.get_descent(txt_size)) * 0.5
	draw_string(f, Vector2(kx + ks + 16, txt_y), action_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, txt_size, COL_TEXT.lerp(Color.WHITE, _press))

	# Strip kanan (berkedip bergantian)
	for i in 3:
		var a := 0.25 + 0.75 * maxf(0.0, sin(_time * 6.0 - i * 0.9))
		var bx := w - 44.0 + i * 10.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx + 4, h * 0.3), Vector2(bx + 8, h * 0.3),
			Vector2(bx + 4, h * 0.7), Vector2(bx, h * 0.7)
		]), Color(COL_ACCENT, a))

	# BARU: gelombang garis tepi yang melebar saat ditekan
	if _press > 0.0:
		var grow := 1.0 + 0.3 * (1.0 - _press)
		var c := Vector2(w, h) / 2.0
		var ring := PackedVector2Array()
		for p in pts:
			ring.append(c + (p - c) * grow)
		ring.append(ring[0])
		draw_polyline(ring, Color(COL_ACCENT, _press), 2.0)
