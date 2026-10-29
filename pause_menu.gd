extends CanvasLayer
## Pause menu bergaya terminal Revenant (tombol jajargenjang + garis penghubung + header/footer).
## UI dibangun lewat kode, jadi pause_menu.tscn cukup berisi PanelControl + SettingsMenu.

const MAIN_MENU_SCENE = "res://main menu/mainmenu.tscn"

@export var font: Font
@export var ui_stagger := 0.07                 # jeda antar elemen saat muncul / hilang (detik)
@export var ui_slide := 90.0                   # jarak geser elemen saat muncul (piksel)
@export var fx_enabled := true                 # kilau tombol + siku/header/footer layar (kill switch)
@export var dim_alpha := 0.78                  # gelapnya layar di belakang menu

enum V { MENU, SETTINGS }

@onready var _root: Control = $PanelControl
@onready var settings_menu = $SettingsMenu

var _view := V.MENU
var _busy := false
var _dim: ColorRect
var _chrome: RevUI.Chrome
var _menu: Control
var _wires: RevUI.Wires
var _resume: RevUI.NavBtn
var _info_name: Label
var _info_time: Label
var _t0 := 0
var _tw_dim: Tween
var _tw_chrome: Tween
var _tw_wires: Tween
var _crosshair_was_visible := true
var _hud_was_visible := true


func _ready():
	get_tree().paused = false
	hide()
	_t0 = Time.get_ticks_msec()
	if font == null and ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		font = load("res://font/Rajdhani-Bold.ttf")
	settings_menu.hide()
	settings_menu.back_pressed.connect(_close_settings)
	settings_menu.sensitivity_changed.connect(_apply_sensitivity)

	_build()

	# Terapkan setting tersimpan saat level dimulai
	SettingsMenu.apply_saved()
	_apply_sensitivity.call_deferred(SettingsMenu.get_sensitivity())


func _unhandled_input(event):
	if event.is_action_pressed("ui_cancel"):
		if _busy:
			return
		if settings_menu.visible:
			if settings_menu.get_child_count() > 1:
				return                                   # sub-menu keybind sedang terbuka, biar ia yang menangani ESC
			_close_settings()
		else:
			toggle_pause()


func toggle_pause():
	var is_paused = !get_tree().paused
	get_tree().paused = is_paused

	var crosshair = get_tree().root.find_child("crosshair", true, false)
	if crosshair:
		if is_paused:
			_crosshair_was_visible = crosshair.visible
			crosshair.visible = false
		else:
			crosshair.visible = _crosshair_was_visible

	var hud = get_tree().root.find_child("HUD", true, false)
	if hud:
		if is_paused:
			_hud_was_visible = hud.visible
			hud.visible = false
		else:
			hud.visible = _hud_was_visible

	if is_paused:
		_open()
	else:
		_close()


# ---------- membangun UI ----------
func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _frac(c: Control, l: float, t: float, r: float, b: float) -> void:
	c.anchor_left = l
	c.anchor_top = t
	c.anchor_right = r
	c.anchor_bottom = b
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _btn(title: String, sub: String, box: Vector4, num: String, section: String, big := false) -> RevUI.NavBtn:
	var b := RevUI.NavBtn.new()
	b.title = title
	b.subtitle = sub
	b.num = num
	b.section = section
	b.big = big
	b.font = font
	b.fx_on = fx_enabled
	_frac(b, box.x, box.y, box.z, box.w)
	_menu.add_child(b)
	b.pressed.connect(_pulse.bind(b))
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


func _pulse(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	var tw := create_tween()
	tw.tween_property(c, "scale", Vector2(0.96, 0.96), 0.06).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _build() -> void:
	_dim = ColorRect.new()
	_full(_dim)
	_dim.color = Color(0.01, 0.03, 0.035, dim_alpha)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)
	_root.move_child(_dim, 0)

	_chrome = RevUI.Chrome.new()
	_chrome.font = font
	_chrome.visible = fx_enabled
	_root.add_child(_chrome)
	_root.move_child(_chrome, 1)

	_menu = Control.new()
	_full(_menu)
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.visible = false
	_root.add_child(_menu)
	_root.move_child(_menu, 2)

	var kick := _label("// FIELD OPERATIONS / LOCAL SESSION", 10, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85))
	_frac(kick, 0.057, 0.135, 0.5, 0.17)
	_menu.add_child(kick)
	var title := _label("PAUSED", 96, RevUI.TEXT)
	_frac(title, 0.055, 0.165, 0.5, 0.32)
	_menu.add_child(title)
	var rl := ColorRect.new()
	rl.color = RevUI.RED
	rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frac(rl, 0.058, 0.318, 0.098, 0.318)
	rl.offset_bottom = 2.0
	_menu.add_child(rl)
	var tg := _label("THE FACILITY CAN WAIT.", 9, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85))
	_frac(tg, 0.109, 0.307, 0.45, 0.329)
	tg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_menu.add_child(tg)

	_resume = _btn("RESUME", "RETURN TO THE FACILITY", Vector4(0.09, 0.43, 0.476, 0.58), "[ ESC ]", "01 / CONTINUE", true)
	var st := _btn("SETTINGS", "AUDIO · VIDEO · CONTROLS", Vector4(0.573, 0.267, 0.79, 0.361), "02", "02 / CONFIGURE")
	var rs := _btn("RESTART", "RELOAD THIS LEVEL", Vector4(0.651, 0.516, 0.916, 0.61), "03", "03 / RECOVER")
	var mm := _btn("MAIN MENU", "LEAVE CURRENT SESSION", Vector4(0.424, 0.729, 0.633, 0.825), "04", "")
	var ex := _btn("EXIT GAME", "RETURN TO DESKTOP", Vector4(0.705, 0.789, 0.896, 0.885), "05", "")
	_resume.pressed.connect(_on_resume_pressed)
	rs.pressed.connect(_on_restart_pressed)
	st.pressed.connect(_on_settings_pressed)
	mm.pressed.connect(_on_main_menu_pressed)
	ex.pressed.connect(_on_exit_pressed)
	_nb(_resume, "right", st)
	_nb(_resume, "bottom", mm)
	_nb(st, "left", _resume)
	_nb(st, "bottom", rs)
	_nb(rs, "top", st)
	_nb(rs, "left", _resume)
	_nb(rs, "bottom", ex)
	_nb(ex, "top", rs)
	_nb(ex, "left", mm)
	_nb(mm, "top", _resume)
	_nb(mm, "right", ex)

	_wires = RevUI.Wires.new()                              # jalur siku antar tombol
	_wires.paths = [
		PackedVector2Array([Vector2(0.056, 0.34), Vector2(0.42, 0.34), Vector2(0.48, 0.246), Vector2(0.572, 0.246)]),
		PackedVector2Array([Vector2(0.605, 0.365), Vector2(0.605, 0.428), Vector2(0.65, 0.51)]),
		PackedVector2Array([Vector2(0.69, 0.625), Vector2(0.645, 0.705), Vector2(0.628, 0.735)]),
		PackedVector2Array([Vector2(0.474, 0.825), Vector2(0.474, 0.877), Vector2(0.672, 0.877), Vector2(0.705, 0.85)]),
	]
	_wires.visible = fx_enabled
	_menu.add_child(_wires)

	var ik := _label("// SESSION", 9, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85))
	_frac(ik, 0.058, 0.735, 0.34, 0.765)
	_menu.add_child(ik)
	_info_name = _label("", 26, RevUI.TEXT)
	_frac(_info_name, 0.058, 0.765, 0.36, 0.825)
	_menu.add_child(_info_name)
	_info_time = _label("", 9, Color(RevUI.DIM.r, RevUI.DIM.g, RevUI.DIM.b, 0.85))
	_frac(_info_time, 0.058, 0.825, 0.34, 0.855)
	_menu.add_child(_info_time)
	var il := ColorRect.new()
	il.color = Color(RevUI.BORDER.r, RevUI.BORDER.g, RevUI.BORDER.b, 0.5)
	il.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frac(il, 0.058, 0.862, 0.27, 0.862)
	il.offset_bottom = 1.0
	_menu.add_child(il)


func _update_info() -> void:
	var sc := get_tree().current_scene
	_info_name.text = (sc.name if sc != null else "LEVEL").to_upper()
	var secs := int((Time.get_ticks_msec() - _t0) / 1000.0)
	_info_time.text = "ELAPSED  %02d:%02d:%02d" % [floori(secs / 3600.0), floori(secs / 60.0) % 60, secs % 60]


func _set_hints(items: Array, mode: String, status: String) -> void:
	_chrome.hints = items
	_chrome.mode_text = mode
	_chrome.status_text = status
	var secs := int((Time.get_ticks_msec() - _t0) / 1000.0)
	_chrome.right_text = "RUN TIME  %02d:%02d:%02d" % [floori(secs / 3600.0), floori(secs / 60.0) % 60, secs % 60]


func _fresh(old: Tween) -> void:
	if old != null:
		old.kill()


# ---------- buka / tutup ----------
func _open() -> void:
	show()
	_busy = false
	_view = V.MENU
	settings_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_update_info()
	_set_hints([["ARROWS", "NAVIGATE"], ["ENTER", "SELECT"], ["ESC", "RESUME"]], "PAUSE INTERFACE", "SESSION SUSPENDED")
	_fresh(_tw_dim)
	_dim.modulate.a = 0.0
	_tw_dim = create_tween()
	_tw_dim.tween_property(_dim, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_fresh(_tw_chrome)
	_chrome.reveal = 0.0
	_tw_chrome = create_tween()
	_tw_chrome.tween_property(_chrome, "reveal", 1.0, 1.1).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_show_menu(0.05)


func _show_menu(delay: float) -> void:
	RevUI.show_in(self, _menu, delay, ui_stagger, ui_slide)
	_fresh(_tw_wires)
	_wires.reveal = 0.0
	_tw_wires = create_tween()
	_tw_wires.tween_property(_wires, "reveal", 1.0, 1.4).set_delay(delay + 0.4).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_resume.grab_focus.call_deferred()


func _close() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_busy = false
	_fresh(_tw_dim)
	_tw_dim = create_tween()
	_tw_dim.tween_property(_dim, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fresh(_tw_chrome)
	_tw_chrome = create_tween()
	_tw_chrome.tween_property(_chrome, "reveal", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	if settings_menu.visible:
		settings_menu.hide()
		_menu.hide()
		_finish_close()
	else:
		RevUI.hide_out(self, _menu, _finish_close, ui_stagger, ui_slide)


func _finish_close() -> void:
	if not get_tree().paused:
		hide()


# ---------- tombol ----------
func _on_resume_pressed():
	toggle_pause()


func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_settings_pressed():
	if _busy:
		return
	_busy = true
	_view = V.SETTINGS
	_set_hints([["MOUSE", "ADJUST"], ["ESC", "BACK"]], "SYSTEM CONFIG", "SESSION SUSPENDED")
	RevUI.hide_out(self, _menu, _show_settings, ui_stagger, ui_slide)


func _show_settings() -> void:
	if _view != V.SETTINGS or not get_tree().paused:
		_busy = false
		return
	settings_menu.show()
	var p := settings_menu.get_node("Panel") as Control
	await get_tree().process_frame                         # tunggu layout supaya pivot tepat di tengah panel
	p.pivot_offset = p.size * 0.5
	p.modulate.a = 0.0
	p.scale = Vector2(1.0, 0.02)                           # panel membuka dari garis tipis, seperti layar menyala
	var tw := create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(p, "scale:y", 1.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_settings_ready)


func _settings_ready() -> void:
	_busy = false
	var f := settings_menu.find_child("MasterSlider", true, false) as Control
	if f != null:
		f.grab_focus()


func _close_settings():
	if _busy or _view != V.SETTINGS:
		return
	_busy = true
	var p := settings_menu.get_node("Panel") as Control
	p.pivot_offset = p.size * 0.5
	var tw := create_tween()
	tw.tween_property(p, "scale:y", 0.02, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "modulate:a", 0.0, 0.28).set_delay(0.08)
	tw.tween_callback(_settings_left)


func _settings_left() -> void:
	settings_menu.hide()
	var p := settings_menu.get_node("Panel") as Control
	p.scale = Vector2.ONE
	p.modulate.a = 1.0
	_view = V.MENU
	_busy = false
	_set_hints([["ARROWS", "NAVIGATE"], ["ENTER", "SELECT"], ["ESC", "RESUME"]], "PAUSE INTERFACE", "SESSION SUSPENDED")
	_show_menu(0.0)


func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_exit_pressed():
	get_tree().quit()


# --- Sensitivitas ---
# Slider adalah pengali (default 1.0) dari nilai bawaan player,
# jadi nilai asli di script player tetap jadi acuan.
func _apply_sensitivity(multiplier: float):
	var player = get_tree().root.find_child("Player", true, false)
	if not player:
		return
	for prop in ["SENSITIVITY", "mouse_sensitivity"]:
		if prop in player:
			var meta_key = "base_" + prop
			if not player.has_meta(meta_key):
				player.set_meta(meta_key, player.get(prop))
			player.set(prop, player.get_meta(meta_key) * multiplier)
			return
