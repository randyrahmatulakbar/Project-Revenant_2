extends Node
## Gaya main menu mengikuti UI HUD (panel gelap miring + strip salmon di kiri),
## layout rata kiri, dan animasi masuk.
## Cara pakai: lihat control.gd -> menu_style.setup(self), lalu play_intro() untuk memutar ulang.
## Scene (mainmenu.tscn) TIDAK perlu diubah: semua disusun lewat kode.

# ---------- Layout (px, desain 1152x648) ----------
const MARGIN_X := 72.0
const TITLE_SHIFT_Y := -30.0          # geser judul ke atas dari posisi lama
const MENU_Y := 340.0
const BTN_SIZE := Vector2(360, 50)
const SLIDE := 36.0                   # jarak geser tombol saat masuk
const BTN_GAP := 10
const SKEW := 14.0                    # kemiringan sisi panel
const TEXT_PAD := 38.0                # jarak teks dari tepi kiri tombol
const SHADE_WIDTH := 0.62             # lebar gradasi gelap di kiri (0..1 dari layar)

# ---------- Warna (diambil dari HUD) ----------
const COLOR_PANEL := Color("1c2828ee")
const COLOR_PANEL_HOVER := Color("2b3a37f2")
const COLOR_BORDER := Color("7d6354")
const COLOR_ACCENT := Color("dea68a")
const COLOR_TEXT := Color("eadccf")
const COLOR_TEXT_HOVER := Color("ffffff")
const COLOR_DIM := Color("c99a7e")

var menu: Control
var _titles: Array[Label] = []
var _title_pos: Array[Vector2] = []
var _buttons: Array[Button] = []
var _st := {}                         # Button -> {hover, reveal, flash, tween, box}
var _shade: TextureRect
var _intro_tween: Tween


func setup(m: Control) -> void:
	menu = m
	_build_shade()
	_layout_titles()
	_style_buttons()
	play_intro()


# =========================
# SUSUNAN LAYOUT
# =========================
func _build_shade() -> void:
	var bg: Control = menu.get_node("Background")
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.04, 0.06, 0.06, 0.93), Color(0.04, 0.06, 0.06, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 512
	tex.height = 8

	_shade = TextureRect.new()
	_shade.texture = tex
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_shade)
	bg.move_child(_shade, 0)          # di belakang judul
	_shade.anchor_left = 0.0
	_shade.anchor_top = 0.0
	_shade.anchor_right = SHADE_WIDTH
	_shade.anchor_bottom = 1.0
	_shade.offset_left = 0.0
	_shade.offset_top = 0.0
	_shade.offset_right = 0.0
	_shade.offset_bottom = 0.0


func _layout_titles() -> void:
	var l1: Label = menu.get_node("Background/Label")
	var l2: Label = menu.get_node("Background/Label2")
	_titles = [l1, l2]
	_title_pos.clear()
	for l in _titles:
		l.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector2(MARGIN_X, 0.0)
		l.size = Vector2(560, l.size.y)
	# pertahankan jarak vertikal asli antar judul (offset_top 90 dan 153 di scene)
	l1.position.y = 90.0 + TITLE_SHIFT_Y
	l2.position.y = 153.0 + TITLE_SHIFT_Y
	for l in _titles:
		_title_pos.append(l.position)


func _style_buttons() -> void:
	var vb: VBoxContainer = menu.vbox_container
	vb.set_anchors_preset(Control.PRESET_TOP_LEFT, true)
	vb.custom_maximum_size = Vector2(BTN_SIZE.x, -1)
	vb.custom_minimum_size = Vector2(BTN_SIZE.x, 0)
	vb.add_theme_constant_override("separation", BTN_GAP)
	vb.position = Vector2(MARGIN_X, MENU_Y)
	vb.size = Vector2(BTN_SIZE.x, 0)

	_buttons.clear()
	for child in vb.get_children():
		if child is Button:
			_style_one(child)
			_buttons.append(child)


func _style_one(b: Button) -> void:
	b.custom_minimum_size = BTN_SIZE
	b.size_flags_vertical = Control.SIZE_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", COLOR_TEXT_HOVER)
	b.add_theme_color_override("font_focus_color", COLOR_TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", COLOR_ACCENT)

	# kotak bawaan dikosongkan, tampilannya digambar oleh "decor" di belakang teks
	var box := StyleBoxEmpty.new()
	box.content_margin_left = TEXT_PAD
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, box)

	_st[b] = {"hover": 0.0, "reveal": 1.0, "flash": 0.0, "tween": null, "box": box}

	var decor := Control.new()
	decor.name = "HudDecor"
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.show_behind_parent = true
	b.add_child(decor)
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	decor.draw.connect(_draw_button.bind(decor, b))
	_st[b]["decor"] = decor

	b.mouse_entered.connect(_hover.bind(b, true))
	b.mouse_exited.connect(_hover.bind(b, false))
	b.focus_entered.connect(_hover.bind(b, true))
	b.focus_exited.connect(_hover.bind(b, false))
	b.button_down.connect(_flash.bind(b))


# =========================
# GAMBAR TOMBOL (gaya panel HUD)
# =========================
func _draw_button(decor: Control, b: Button) -> void:
	var st: Dictionary = _st[b]
	var w := decor.size.x
	var h := decor.size.y
	var rv: float = st.reveal
	if rv <= 0.001 or w <= 1.0:
		return
	var hv: float = st.hover

	decor.draw_set_transform(Vector2(-SLIDE * (1.0 - rv), 0.0), 0.0, Vector2.ONE)

	var s := SKEW
	var body := PackedVector2Array([Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)])
	var fill := COLOR_PANEL.lerp(COLOR_PANEL_HOVER, hv).lerp(Color.WHITE, float(st.flash) * 0.55)
	decor.draw_colored_polygon(body, fill)
	decor.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]),
		COLOR_BORDER.lerp(COLOR_ACCENT, hv), 1.5, true)

	# strip salmon di kiri (melebar saat hover)
	var bw := lerpf(7.0, 16.0, hv)
	decor.draw_colored_polygon(PackedVector2Array([
		Vector2(s, 0), Vector2(s + bw, 0), Vector2(bw, h), Vector2(0, h)]), COLOR_ACCENT)

	# "///" kecil di kanan, kayak panel INTERAKSI
	var tick_col := COLOR_DIM
	tick_col.a = lerpf(0.35, 0.95, hv)
	for i in 3:
		var x := w - 34.0 + i * 9.0
		decor.draw_line(Vector2(x + 5.0, h * 0.30), Vector2(x, h * 0.70), tick_col, 2.5, true)


# =========================
# HOVER / KLIK
# =========================
func _hover(b: Button, on: bool) -> void:
	var st: Dictionary = _st[b]
	if st.tween:
		st.tween.kill()
	var tw := create_tween()
	st.tween = tw
	tw.tween_method(_set_st.bind(b, "hover"), float(st.hover), 1.0 if on else 0.0, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _flash(b: Button) -> void:
	var tw := create_tween()
	tw.tween_method(_set_st.bind(b, "flash"), 0.8, 0.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_st(v: float, b: Button, key: String) -> void:
	if not is_instance_valid(b):
		return
	_st[b][key] = v
	_refresh(b)


func _refresh(b: Button) -> void:
	var st: Dictionary = _st[b]
	var rv: float = st.reveal
	# teks ikut geser bareng panel, dan sedikit maju saat hover
	st.box.content_margin_left = TEXT_PAD - SLIDE * (1.0 - rv) + 6.0 * float(st.hover)
	b.modulate.a = clampf(rv * 1.6, 0.0, 1.0)
	st.decor.queue_redraw()

# =========================
# ANIMASI MASUK
# =========================
func play_intro() -> void:
	if _intro_tween and _intro_tween.is_valid():
		_intro_tween.kill()
	var t := create_tween().set_parallel(true)
	_intro_tween = t

	_shade.modulate.a = 0.0
	t.tween_property(_shade, "modulate:a", 1.0, 0.9) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for i in _titles.size():
		var l := _titles[i]
		l.position = _title_pos[i] + Vector2(-50, 0)
		l.modulate.a = 0.0
		var d := 0.1 + i * 0.15
		t.tween_property(l, "position", _title_pos[i], 0.9).set_delay(d) \
			.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.tween_property(l, "modulate:a", 1.0, 0.7).set_delay(d) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	for i in _buttons.size():
		var b := _buttons[i]
		var st: Dictionary = _st[b]
		st.reveal = 0.0
		st.flash = 0.7
		st.hover = 0.0
		_refresh(b)

		var d := 0.45 + i * 0.1
		t.tween_method(_set_st.bind(b, "reveal"), 0.0, 1.0, 0.8).set_delay(d) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_method(_set_st.bind(b, "flash"), 0.7, 0.0, 0.8).set_delay(d + 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
