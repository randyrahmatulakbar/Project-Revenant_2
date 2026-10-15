class_name HudSkin
extends RefCounted
## Skin tombol gaya HUD (panel miring + strip salmon di kiri + "///" di kanan).
## Dipakai ulang di Settings, Credit, Pause. Semua static, tinggal:
##   HudSkin.skin_button(tombol, Vector2(200, 48), 22)
##   HudSkin.play_in([tombol1, tombol2], 0.2)        # animasi masuk (opsional)

const META := "hud_skin"
const SKEW := 14.0
const TEXT_PAD := 38.0
const SLIDE := 36.0

const COLOR_PANEL := Color("1c2828ee")
const COLOR_PANEL_HOVER := Color("2b3a37f2")
const COLOR_BORDER := Color("7d6354")
const COLOR_ACCENT := Color("dea68a")
const COLOR_TEXT := Color("eadccf")
const COLOR_TEXT_HOVER := Color("ffffff")
const COLOR_DIM := Color("c99a7e")


static func skin_button(b: Button, min_size := Vector2.ZERO, font_size := 24, uppercase := true) -> void:
	if b.has_meta(META):
		return
	if min_size != Vector2.ZERO:
		b.custom_minimum_size = min_size
	if uppercase:
		b.text = b.text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", COLOR_TEXT)
	b.add_theme_color_override("font_hover_color", COLOR_TEXT_HOVER)
	b.add_theme_color_override("font_focus_color", COLOR_TEXT_HOVER)
	b.add_theme_color_override("font_pressed_color", COLOR_ACCENT)

	# kotak bawaan theme dikosongkan; tampilan digambar oleh "decor" di belakang teks
	var box := StyleBoxEmpty.new()
	box.content_margin_left = TEXT_PAD
	box.content_margin_right = 44.0
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(s, box)

	var decor := Control.new()
	decor.name = "HudDecor"
	decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	decor.show_behind_parent = true
	b.add_child(decor)
	decor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	b.set_meta(META, {"hover": 0.0, "reveal": 1.0, "flash": 0.0, "tween": null, "box": box, "decor": decor})

	decor.draw.connect(Callable(HudSkin, "_paint").bind(decor, b))
	b.mouse_entered.connect(Callable(HudSkin, "_hover").bind(b, true))
	b.mouse_exited.connect(Callable(HudSkin, "_hover").bind(b, false))
	b.focus_entered.connect(Callable(HudSkin, "_hover").bind(b, true))
	b.focus_exited.connect(Callable(HudSkin, "_hover").bind(b, false))
	b.button_down.connect(Callable(HudSkin, "_flash").bind(b))


## Animasi masuk: panel + teks geser dari kiri, satu-satu, dengan kilatan putih.
static func play_in(buttons: Array, start_delay := 0.0, step := 0.1) -> void:
	for i in buttons.size():
		var b: Button = buttons[i]
		if not is_instance_valid(b) or not b.has_meta(META):
			continue
		var st: Dictionary = b.get_meta(META)
		if st.tween:
			st.tween.kill()
		st.reveal = 0.0
		st.flash = 0.7
		st.hover = 0.0
		_refresh(b)

		var d := start_delay + i * step
		var t := b.create_tween().set_parallel(true)
		t.tween_method(Callable(HudSkin, "_put").bind(b, "reveal"), 0.0, 1.0, 0.8).set_delay(d) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		t.tween_method(Callable(HudSkin, "_put").bind(b, "flash"), 0.7, 0.0, 0.8).set_delay(d + 0.1) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Gradasi gelap di sisi kiri (supaya teks kebaca di atas background).
static func make_shade(parent: Control, width_frac := 0.6, alpha := 0.9) -> TextureRect:
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(0.04, 0.06, 0.06, alpha), Color(0.04, 0.06, 0.06, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 512
	tex.height = 8

	var shade := TextureRect.new()
	shade.texture = tex
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(shade)
	parent.move_child(shade, 0)
	shade.anchor_left = 0.0
	shade.anchor_top = 0.0
	shade.anchor_right = width_frac
	shade.anchor_bottom = 1.0
	shade.offset_left = 0.0
	shade.offset_top = 0.0
	shade.offset_right = 0.0
	shade.offset_bottom = 0.0
	return shade


# ---------- internal ----------

static func _paint(decor: Control, b: Button) -> void:
	var st: Dictionary = b.get_meta(META)
	var w := decor.size.x
	var h := decor.size.y
	var rv: float = st.reveal
	if rv <= 0.001 or w <= 1.0:
		return
	var hv: float = st.hover
	if b.disabled:
		hv = 0.0

	decor.draw_set_transform(Vector2(-SLIDE * (1.0 - rv), 0.0), 0.0, Vector2.ONE)

	var s := SKEW
	var body := PackedVector2Array([Vector2(s, 0), Vector2(w, 0), Vector2(w - s, h), Vector2(0, h)])
	var fill := COLOR_PANEL.lerp(COLOR_PANEL_HOVER, hv).lerp(Color.WHITE, float(st.flash) * 0.55)
	decor.draw_colored_polygon(body, fill)
	decor.draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]),
		COLOR_BORDER.lerp(COLOR_ACCENT, hv), 1.5, true)

	var bw := lerpf(7.0, 16.0, hv)
	decor.draw_colored_polygon(PackedVector2Array([
		Vector2(s, 0), Vector2(s + bw, 0), Vector2(bw, h), Vector2(0, h)]), COLOR_ACCENT)

	var tick_col := COLOR_DIM
	tick_col.a = lerpf(0.35, 0.95, hv)
	for i in 3:
		var x := w - 34.0 + i * 9.0
		decor.draw_line(Vector2(x + 5.0, h * 0.30), Vector2(x, h * 0.70), tick_col, 2.5, true)


static func _hover(b: Button, on: bool) -> void:
	var st: Dictionary = b.get_meta(META)
	if st.tween:
		st.tween.kill()
	var tw := b.create_tween()
	st.tween = tw
	tw.tween_method(Callable(HudSkin, "_put").bind(b, "hover"), float(st.hover), 1.0 if on else 0.0, 0.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func _flash(b: Button) -> void:
	var tw := b.create_tween()
	tw.tween_method(Callable(HudSkin, "_put").bind(b, "flash"), 0.8, 0.0, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


static func _put(v: float, b: Button, key: String) -> void:
	if not is_instance_valid(b):
		return
	var st: Dictionary = b.get_meta(META)
	st[key] = v
	_refresh(b)


static func _refresh(b: Button) -> void:
	var st: Dictionary = b.get_meta(META)
	var rv: float = st.reveal
	st.box.content_margin_left = TEXT_PAD - SLIDE * (1.0 - rv) + 6.0 * float(st.hover)
	b.modulate.a = clampf(rv * 1.6, 0.0, 1.0)
	st.decor.queue_redraw()


# ---------- Halaman Settings ----------
const FONT_PATH := "res://font/Rajdhani-Bold.ttf"
const SETTINGS_MARGIN_X := 72.0
const SETTINGS_PANEL := Vector2(560, 430)

## Restyle SettingsMenu (rata kiri, panel gaya HUD, judul merah, tombol Back HUD, animasi masuk).
## Cukup dipanggil dari luar: HudSkin.style_settings(settings_menu)
## Tidak bergantung pada script yang menempel di node SettingsMenu.
static func style_settings(menu: Control) -> void:
	if menu.has_meta("hud_settings"):
		return
	menu.set_meta("hud_settings", true)

	var panel: PanelContainer = menu.get_node("Panel")
	var title: Label = menu.get_node("Panel/Margin/VBox/Title")
	var back: Button = menu.get_node("Panel/Margin/VBox/BackButton")

	# Rata kiri: CenterContainer dipersempit sehingga panel (yang selalu di tengahnya)
	# jatuh di sisi kiri layar.
	panel.custom_minimum_size = SETTINGS_PANEL
	menu.anchor_left = 0.0
	menu.anchor_right = 0.0
	menu.anchor_top = 0.0
	menu.anchor_bottom = 1.0
	menu.offset_left = 0.0
	menu.offset_right = SETTINGS_PANEL.x + SETTINGS_MARGIN_X * 2.0
	menu.offset_top = 0.0
	menu.offset_bottom = 0.0

	# Panel: gelap + strip salmon di kiri (tanpa border lain)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("141c1cf2")
	sb.border_color = COLOR_ACCENT
	sb.border_width_left = 8
	sb.content_margin_left = 32.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 20.0
	sb.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", sb)

	# Judul
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_color", Color("c0392b"))
	title.add_theme_font_size_override("font_size", 44)
	if ResourceLoader.exists(FONT_PATH):
		title.add_theme_font_override("font", load(FONT_PATH))

	# Tombol Back
	skin_button(back, Vector2(200, 48), 22)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	menu.visibility_changed.connect(Callable(HudSkin, "_settings_in").bind(menu))
	if menu.visible:
		_settings_in(menu)


static func _settings_in(menu: Control) -> void:
	if not menu.visible:
		return
	var p: Control = menu.get_node("Panel")
	p.pivot_offset = Vector2(0.0, p.size.y / 2.0)
	p.modulate.a = 0.0
	p.scale = Vector2(0.97, 0.97)
	var t := menu.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "modulate:a", 1.0, 0.45)
	t.tween_property(p, "scale", Vector2.ONE, 0.7)
	play_in([menu.get_node("Panel/Margin/VBox/BackButton")], 0.25)
