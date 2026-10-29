extends PanelContainer
## Menu Keybind. Dibuka dari SettingsMenu (tombol "Keybinds"), tampil di tempat panel Settings.
## Perubahan ditampung dulu (pending). Baru berlaku & tersimpan setelah SAVE.
##   Reset : isi pending dengan tombol bawaan project (tetap perlu SAVE)
##   Back  : kalau ada perubahan belum disimpan, muncul peringatan (Save & Back / Discard / Cancel)

signal back_pressed

var _pending := {}                     # action -> InputEvent (atau null)
var _capturing := ""
var _buttons := {}                     # action -> Button
var _font_size := 18
var _unsaved: Label
var _save_btn: Button
var _confirm: Control
var _skin = null                       # HudSkin (kalau ada)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var host := get_parent()
	var host_panel: Control = host.get_node_or_null("Panel") if host else null
	custom_minimum_size = host_panel.custom_minimum_size if host_panel else Vector2(560, 600)
	if host_panel:
		add_theme_stylebox_override("panel", host_panel.get_theme_stylebox("panel"))
	if host and "font_size" in host:
		_font_size = host.font_size
	if ResourceLoader.exists("res://hud_skin.gd"):
		_skin = load("res://hud_skin.gd")

	# data awal: tombol yang sedang aktif
	for entry in SettingsMenu.KEY_ACTIONS:
		var a: String = entry[0]
		if InputMap.has_action(a):
			_pending[a] = SettingsMenu.clone_binding(SettingsMenu.get_binding(a))

	_build_ui(host)
	_refresh()


func _build_ui(host: Node) -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)

	# judul: salin gaya judul Settings
	var title := Label.new()
	title.text = "KEYBINDS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var src: Label = host.get_node_or_null("Panel/Margin/VBox/Title") if host else null
	if src:
		title.theme_type_variation = src.theme_type_variation
		title.add_theme_font_size_override("font_size", src.get_theme_font_size("font_size"))
		title.add_theme_color_override("font_color", src.get_theme_color("font_color"))
		title.add_theme_font_override("font", src.get_theme_font("font"))
		title.horizontal_alignment = src.horizontal_alignment
	else:
		title.add_theme_font_size_override("font_size", 36)
	vb.add_child(title)
	RevUI.title_line(title)

	_unsaved = Label.new()
	_unsaved.text = "* UNSAVED CHANGES"
	_unsaved.add_theme_color_override("font_color", RevUI.ACCENT)
	_unsaved.add_theme_font_size_override("font_size", _font_size - 3)
	vb.add_child(_unsaved)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for entry in SettingsMenu.KEY_ACTIONS:
		var action: String = entry[0]
		if not _pending.has(action):
			continue
		var l := Label.new()
		l.text = entry[1]
		l.custom_minimum_size.x = 170
		l.add_theme_font_size_override("font_size", _font_size)
		l.add_theme_color_override("font_color", RevUI.TEXT)
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", _font_size)
		RevUI.style_choice_button(b)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(_begin_capture.bind(action))
		grid.add_child(b)
		_buttons[action] = b

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	vb.add_child(foot)
	_save_btn = _footer_button(foot, "Save", _on_save)
	_footer_button(foot, "Reset", _on_reset)
	_footer_button(foot, "Back", _on_back)

	_build_confirm()


func _footer_button(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", _font_size + 2)
	b.pressed.connect(cb)
	parent.add_child(b)
	if _skin:
		_skin.skin_button(b, Vector2(120, 48), 22)
	return b


# ---------- Peringatan belum disimpan ----------

func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.visible = false
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_confirm)                                  # anak PanelContainer: memenuhi panel, di atas isi

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm.add_child(center)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.11, 0.98)
	sb.border_color = Color("dea68a")
	sb.border_width_left = 6
	sb.content_margin_left = 22
	sb.content_margin_right = 20
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	box.add_theme_stylebox_override("panel", sb)
	center.add_child(box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var t := Label.new()
	t.text = "UNSAVED CHANGES"
	t.add_theme_font_size_override("font_size", _font_size + 4)
	t.add_theme_color_override("font_color", Color("dea68a"))
	v.add_child(t)
	var m := Label.new()
	m.text = "Your keybind changes have not been saved."
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	m.add_theme_font_size_override("font_size", _font_size)
	v.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_footer_button(row, "Save & Back", _on_confirm_save)
	_footer_button(row, "Discard", _on_confirm_discard)
	_footer_button(row, "Cancel", _on_confirm_cancel)


func _on_confirm_save() -> void:
	_commit()
	_confirm.visible = false
	back_pressed.emit()


func _on_confirm_discard() -> void:
	_confirm.visible = false
	back_pressed.emit()


func _on_confirm_cancel() -> void:
	_confirm.visible = false


# ---------- Tombol footer ----------

func _on_save() -> void:
	_commit()
	_refresh()


func _on_reset() -> void:
	_capturing = ""
	for action in _pending:
		_pending[action] = SettingsMenu.default_binding(action)
	_refresh()


func _on_back() -> void:
	_capturing = ""
	if _is_dirty():
		_confirm.visible = true
	else:
		back_pressed.emit()


func _commit() -> void:
	SettingsMenu.commit_bindings(_pending)


func _is_dirty() -> bool:
	for action in _pending:
		if not SettingsMenu.same_binding(_pending[action], SettingsMenu.get_binding(action)):
			return true
	return false


func _refresh() -> void:
	for action in _buttons:
		var b: Button = _buttons[action]
		if action == _capturing:
			b.text = "Press a key...   (Esc = cancel)"
		else:
			b.text = SettingsMenu.event_text(_pending.get(action))
	var dirty := _is_dirty()
	_unsaved.visible = dirty
	if _save_btn:
		_save_btn.disabled = not dirty


# ---------- Rebind ----------

func _begin_capture(action: String) -> void:
	if _confirm.visible:
		return
	_capturing = action
	_refresh()


func _input(event: InputEvent) -> void:
	if _capturing == "":
		return
	var ev: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_capturing = ""
			_refresh()
			return
		ev = event
	elif event is InputEventMouseButton and event.pressed and event.button_index in [1, 2, 3, 8, 9]:
		ev = event
	if ev == null:
		return
	get_viewport().set_input_as_handled()
	var action := _capturing
	_capturing = ""
	_assign(action, SettingsMenu.clone_binding(ev))
	_refresh()


## Tombol yang sudah dipakai action lain: kedua action saling tukar.
func _assign(action: String, fresh: InputEvent) -> void:
	var old: InputEvent = _pending.get(action)
	for other in _pending:
		if other == action:
			continue
		if SettingsMenu.same_binding(_pending[other], fresh) and fresh != null:
			_pending[other] = SettingsMenu.clone_binding(old)
	_pending[action] = fresh
