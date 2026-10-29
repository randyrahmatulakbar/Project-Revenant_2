class_name RevUI
extends RefCounted
## Gaya UI Revenant yang dipakai bersama: pause menu, Settings, Keybinds.
## Isi: NavBtn (tombol), Wires (garis penghubung), Chrome (header/footer/siku layar),
##      animasi masuk/keluar bertahap (show_in / hide_out), dan skin untuk SettingsMenu.
## Taruh di res:// (satu folder dengan settings_menu.gd). Tidak perlu autoload.

const PANEL := Color(0.11, 0.157, 0.157, 0.92)
const PANEL_HI := Color(0.168, 0.227, 0.216, 0.97)
const BORDER := Color(0.49, 0.388, 0.329)
const ACCENT := Color(0.871, 0.651, 0.541)
const TEXT := Color(0.918, 0.863, 0.812)
const DIM := Color(0.788, 0.604, 0.494)
const RED := Color(0.78, 0.2, 0.17)


const FONT_PATH := "res://font/Rajdhani-Bold.ttf"
static var _font: Font


## Font Rajdhani Bold project (null kalau filenya tidak ada).
static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


## Tombol panel jajargenjang (sisi kanan miring) + strip kiri + nomor + "///" + label seksi di atasnya.
## Yang terpilih (hover / fokus) menyala: border salmon, strip melebar, kilau lewat sekali, penanda merah di kiri.
class NavBtn extends Button:
	var title := ""
	var subtitle := ""
	var num := ""
	var section := ""
	var big := false
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

	## Aktif / mati (mati = redup, tidak bisa diklik).
	func set_enabled(on: bool) -> void:
		disabled = not on
		self_modulate = Color(1, 1, 1, 1.0 if on else 0.4)

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
		var poly := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - sk, ht), Vector2(0, ht)])
		var fill := RevUI.PANEL.lerp(RevUI.PANEL_HI, h)
		draw_colored_polygon(poly, fill)
		var bc := (RevUI.ACCENT.darkened(0.2) if big else RevUI.BORDER).lerp(RevUI.ACCENT, h)
		var outline := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w - sk, ht), Vector2(0, ht), Vector2(0, 0)])
		draw_polyline(outline, bc, 2.0 if big else 1.5, true)
		var bar := (6.0 if big else 0.0) + (2.0 if big else 4.0) * h
		if bar > 0.1:
			draw_rect(Rect2(0, 0, bar, ht), RevUI.ACCENT)
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
		draw_string(f, Vector2(pad, ht * (0.60 if big else 0.58)), title, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, RevUI.TEXT.lerp(Color.WHITE, h * 0.6))
		draw_string(f, Vector2(pad, ht * 0.86), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, ss, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.8))
		if num != "":
			draw_string(f, Vector2(0, ht * 0.30), num, HORIZONTAL_ALIGNMENT_RIGHT, w - ht * 0.34, ns, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85))
		for i in 3:
			var sx := w - ht * 0.62 + float(i) * ht * 0.1
			draw_line(Vector2(sx, ht * 0.88), Vector2(sx + ht * 0.1, ht * 0.66), bc, 1.5)
		if section != "":
			draw_string(f, Vector2(0, -ht * 0.10), section, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(int(ht * 0.12), 9), Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.8))
		if h > 0.01:                                       # penanda segitiga merah di kiri tombol terpilih
			var g := ht * 0.2 * h
			draw_colored_polygon(PackedVector2Array([Vector2(-g * 1.5, ht * 0.5 - g * 0.5), Vector2(-g * 1.5, ht * 0.5 + g * 0.5), Vector2(-g * 0.4, ht * 0.5)]),
					Color(RevUI.RED.r, RevUI.RED.g, RevUI.RED.b, h))


## Garis penghubung antar tombol (jalur siku tipis). Titik dalam fraksi layar; digambar bertahap.
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


## Hiasan layar: siku sudut, header (merek | mode | status), footer (petunjuk tombol | teks tengah | teks kanan).
class Chrome extends Control:
	var reveal := 0.0
	var font: Font
	var t := 0.0
	var hints: Array = []
	var mode_text := "PAUSE INTERFACE"
	var status_text := "SESSION SUSPENDED"
	var center_text := "WORLD STATE HELD // AWAITING INPUT"
	var right_text := ""                                   # kosong = jam berjalan
	var edge_mark := true                                  # tanda merah kecil di tepi kiri
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
		var ta := reveal
		var c := Color(col.r, col.g, col.b, 0.9 * ta)
		var f: Font = font if font else ThemeDB.fallback_font
		draw_line(Vector2(m, m), Vector2(m + l, m), c, 2.0)
		draw_line(Vector2(m, m), Vector2(m, m + l), c, 2.0)
		draw_line(Vector2(w - m, m), Vector2(w - m - l, m), c, 2.0)
		draw_line(Vector2(w - m, m), Vector2(w - m, m + l), c, 2.0)
		draw_line(Vector2(m, h - m), Vector2(m + l, h - m), c, 2.0)
		draw_line(Vector2(m, h - m), Vector2(m, h - m - l), c, 2.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m - l, h - m), c, 2.0)
		draw_line(Vector2(w - m, h - m), Vector2(w - m, h - m - l), c, 2.0)
		if edge_mark:
			draw_rect(Rect2(m - 24.0, h * 0.19, 3.0, h * 0.1 * reveal), Color(RevUI.RED.r, RevUI.RED.g, RevUI.RED.b, ta))
		var x0 := m + 34.0
		var x1 := w - m - 34.0
		var line_c := Color(RevUI.BORDER.r, RevUI.BORDER.g, RevUI.BORDER.b, 0.4 * ta)
		var hy := m + 42.0
		var by := m + 30.0
		draw_line(Vector2(x0, hy), Vector2(x0 + (x1 - x0) * reveal, hy), line_c, 1.0)
		var w1 := f.get_string_size("PROJECT ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var w2 := f.get_string_size("REVENANT", HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(f, Vector2(x0, by), "PROJECT ", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(RevUI.TEXT.r, RevUI.TEXT.g, RevUI.TEXT.b, ta))
		draw_string(f, Vector2(x0 + w1, by), "REVENANT", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(RevUI.RED.r, RevUI.RED.g, RevUI.RED.b, ta))
		var sx := x0 + w1 + w2 + 14.0
		draw_line(Vector2(sx, by - 13.0), Vector2(sx, by + 1.0), line_c, 1.0)
		draw_string(f, Vector2(sx + 12.0, by - 2.0), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85 * ta))
		var stw := f.get_string_size(status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(f, Vector2(x1 - stw, by - 2.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85 * ta))
		var blink := 0.55 + 0.45 * sin(t * 3.0)
		draw_rect(Rect2(x1 - stw - 14.0, by - 9.0, 5, 5), Color(RevUI.RED.r, RevUI.RED.g, RevUI.RED.b, blink * ta))
		var fy := h - m - 42.0
		draw_line(Vector2(x0, fy), Vector2(x0 + (x1 - x0) * reveal, fy), line_c, 1.0)
		var cx := x0
		for hnt in hints:
			var key: String = hnt[0]
			var lab: String = hnt[1]
			var kw := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
			draw_rect(Rect2(cx, fy + 10.0, kw, 18.0), Color(RevUI.BORDER.r, RevUI.BORDER.g, RevUI.BORDER.b, 0.8 * ta), false, 1.0)
			draw_string(f, Vector2(cx + 7.0, fy + 23.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RevUI.TEXT.r, RevUI.TEXT.g, RevUI.TEXT.b, ta))
			cx += kw + 8.0
			draw_string(f, Vector2(cx, fy + 23.0), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85 * ta))
			cx += f.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 24.0
		draw_string(f, Vector2(0, fy + 23.0), center_text, HORIZONTAL_ALIGNMENT_CENTER, w, 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.6 * ta))
		var rt := right_text
		if rt == "":
			var secs := int(t)
			rt = "T+ %02d:%02d:%02d" % [floori(secs / 3600.0), floori(secs / 60.0) % 60, secs % 60]
		draw_string(f, Vector2(x1 - 240.0, fy + 23.0), rt, HORIZONTAL_ALIGNMENT_RIGHT, 240.0, 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85 * ta))


# ---------- animasi masuk / keluar bertahap ----------
# Tiap anak Control di container muncul satu per satu (atas ke bawah): geser masuk dari sisinya sambil membesar halus
# dan memudar masuk. Saat hilang kebalikannya. Posisi asli disimpan di meta, jadi tidak melenceng.
static func _base(o: Control) -> Dictionary:
	if not o.has_meta("ui_base"):
		o.set_meta("ui_base", {"l": o.offset_left, "t": o.offset_top, "r": o.offset_right, "b": o.offset_bottom, "a": o.modulate.a})
	return o.get_meta("ui_base")


static func _is_full(o: Control) -> bool:
	return o.anchor_right - o.anchor_left > 0.9 and o.anchor_bottom - o.anchor_top > 0.9


static func _slide_dir(o: Control) -> Vector2:
	if _is_full(o):
		return Vector2.ZERO
	var cx := (o.anchor_left + o.anchor_right) * 0.5
	if cx < 0.4:
		return Vector2(-1, 0)
	if cx > 0.6:
		return Vector2(1, 0)
	return Vector2(0, 1)


static func _kids(c: Control) -> Array:
	var out: Array = []
	for n in c.get_children():
		if n is Control:
			out.append(n)
	out.sort_custom(_cmp_ui)
	return out


static func _cmp_ui(x: Control, y: Control) -> bool:
	var cy1 := (x.anchor_top + x.anchor_bottom) * 0.5
	var cy2 := (y.anchor_top + y.anchor_bottom) * 0.5
	if absf(cy1 - cy2) > 0.001:
		return cy1 < cy2
	return x.anchor_left < y.anchor_left


static func _gen(c: Control) -> int:
	var g: int = int(c.get_meta("ui_gen", 0)) + 1
	c.set_meta("ui_gen", g)
	return g


static func show_in(host: Node, c: Control, delay := 0.0, stagger := 0.07, slide := 90.0) -> void:
	_gen(c)
	c.visible = true
	c.modulate.a = 1.0
	var i := 0
	for k in _kids(c):
		var o: Control = k
		var base := _base(o)
		var off := _slide_dir(o) * slide
		var full := _is_full(o)
		var dl := delay + float(i) * stagger
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
		var tw := host.create_tween().set_parallel(true)
		o.set_meta("ui_tw", tw)
		tw.tween_property(o, "offset_left", base.l, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_right", base.r, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_top", base.t, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "offset_bottom", base.b, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "scale", Vector2.ONE, 0.75).set_delay(dl).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(o, "modulate:a", float(base.a), 0.5).set_delay(dl).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		i += 1


static func hide_out(host: Node, c: Control, done := Callable(), stagger := 0.07, slide := 90.0) -> void:
	var g := _gen(c)
	var i := 0
	for k in _kids(c):
		var o: Control = k
		var base := _base(o)
		var off := _slide_dir(o) * slide * 0.6
		var dl := float(i) * stagger * 0.5
		var old = o.get_meta("ui_tw", null)
		if old is Tween and old.is_valid():
			old.kill()
		var tw := host.create_tween().set_parallel(true)
		o.set_meta("ui_tw", tw)
		tw.tween_property(o, "offset_left", base.l + off.x, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_right", base.r + off.x, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_top", base.t + off.y * 0.5, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "offset_bottom", base.b + off.y * 0.5, 0.36).set_delay(dl).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(o, "modulate:a", 0.0, 0.3).set_delay(dl).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		i += 1
	var fin := host.create_tween()
	fin.tween_interval(0.4 + float(i) * stagger * 0.5)
	fin.tween_callback(_finish_hide.bind(c, g, done))


static func _finish_hide(c: Control, g: int, done: Callable) -> void:
	if not is_instance_valid(c) or int(c.get_meta("ui_gen", 0)) != g:
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
	if done.is_valid():
		done.call()


# ---------- skin Settings / Keybinds ----------
static func box(bg: Color, border: Color, bw := 1, mx := 8.0, my := 4.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


## Panel gelap, border tipis salmon, strip tebal di kiri (seperti tombol RESUME).
static func panel_box() -> StyleBoxFlat:
	var sb := box(Color(0.075, 0.11, 0.11, 0.97), ACCENT.darkened(0.15), 1, 22.0, 14.0)
	sb.border_width_left = 6
	sb.content_margin_right = 16.0
	return sb


static func _grab(w: int, h: int, c: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


static func style_slider(s: HSlider) -> void:
	var track := box(Color(0.06, 0.13, 0.14, 1), Color(BORDER.r, BORDER.g, BORDER.b, 0.7), 1, 0.0, 3.0)
	var fill := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85), Color(0, 0, 0, 0), 0, 0.0, 3.0)
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	s.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.6), 1, 0.0, 0.0))
	s.add_theme_icon_override("grabber", _grab(6, 22, TEXT))
	s.add_theme_icon_override("grabber_highlight", _grab(6, 22, ACCENT))
	s.add_theme_icon_override("grabber_disabled", _grab(6, 22, Color(0.4, 0.45, 0.45)))


## Tombol biasa bergaya HUD ringan (dipakai untuk kotak pilihan: tombol keybind, OptionButton).
static func style_choice_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", box(Color(0.05, 0.1, 0.11, 0.95), Color(BORDER.r, BORDER.g, BORDER.b, 0.8), 1, 12.0, 4.0))
	b.add_theme_stylebox_override("hover", box(Color(0.1, 0.17, 0.17, 0.98), ACCENT, 1, 12.0, 4.0))
	b.add_theme_stylebox_override("pressed", box(ACCENT.darkened(0.6), ACCENT, 1, 12.0, 4.0))
	b.add_theme_stylebox_override("hover_pressed", box(ACCENT.darkened(0.5), ACCENT, 1, 12.0, 4.0))
	b.add_theme_stylebox_override("focus", box(Color(0, 0, 0, 0), ACCENT, 2, 12.0, 4.0))
	b.add_theme_stylebox_override("disabled", box(Color(0.05, 0.08, 0.08, 0.7), Color(BORDER.r, BORDER.g, BORDER.b, 0.3), 1, 12.0, 4.0))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, TEXT)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


## Garis merah pendek di bawah judul (dipasang sekali).
static func title_line(title: Control) -> void:
	var p := title.get_parent()
	if p == null or p.has_meta("rev_title_line"):
		return
	p.set_meta("rev_title_line", true)
	var ln := ColorRect.new()
	ln.color = RED
	ln.custom_minimum_size = Vector2(64, 3)
	ln.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(ln)
	p.move_child(ln, title.get_index() + 1)


## Pasang skin ke SettingsMenu (dipanggil dari settings_menu.gd). Aman dipanggil berkali-kali.
static func style_settings(sm: Control) -> void:
	if sm.has_meta("rev_styled"):
		return
	sm.set_meta("rev_styled", true)
	var panel := sm.get_node_or_null("Panel") as PanelContainer
	if panel != null:
		panel.add_theme_stylebox_override("panel", panel_box())
	var title := sm.get_node_or_null("Panel/Margin/VBox/Title") as Label
	if title != null:
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.add_theme_color_override("font_color", TEXT)
		title_line(title)
	for n in sm.find_children("*", "HSeparator", true, false):
		var sep := n as HSeparator
		var ln := StyleBoxLine.new()
		ln.color = Color(BORDER.r, BORDER.g, BORDER.b, 0.55)
		ln.thickness = 1
		sep.add_theme_stylebox_override("separator", ln)
	for n in sm.find_children("*", "Label", true, false):
		var lb := n as Label
		if lb.text.begins_with("//"):
			lb.add_theme_color_override("font_color", ACCENT)             # judul seksi
		elif lb.name.ends_with("Value"):
			lb.add_theme_color_override("font_color", ACCENT)             # angka di samping slider
		elif lb != title:
			lb.add_theme_color_override("font_color", TEXT)
	for n in sm.find_children("*", "HSlider", true, false):
		style_slider(n as HSlider)
	for n in sm.find_children("*", "OptionButton", true, false):
		var ob := n as OptionButton
		style_choice_button(ob)
		var pm := ob.get_popup()
		pm.add_theme_stylebox_override("panel", box(Color(0.06, 0.1, 0.1, 0.99), ACCENT.darkened(0.2), 1, 6.0, 6.0))
		pm.add_theme_stylebox_override("hover", box(Color(0.17, 0.23, 0.22, 1), Color(0, 0, 0, 0), 0, 8.0, 4.0))
		pm.add_theme_color_override("font_color", TEXT)
		pm.add_theme_color_override("font_hover_color", Color.WHITE)
	for n in sm.find_children("*", "CheckBox", true, false):
		(n as CheckBox).mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var skin_sz := {"BackButton": Vector2(180, 44), "ResetButton": Vector2(240, 44), "KeybindsButton": Vector2(0, 38)}
	for nm in skin_sz:
		var b := sm.find_child(nm, true, false) as Button
		if b != null:
			HudSkin.skin_button(b, skin_sz[nm], 20, nm != "KeybindsButton")
