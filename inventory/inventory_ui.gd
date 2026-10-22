extends CanvasLayer
## Autoload "InventoryUI". Layar inventory gaya RE4: case grid di kiri, detail item di kanan.
## Buka/tutup dengan action "inventory" (Tab). Game di-pause selama terbuka.
## Seluruh UI dibuat lewat kode, jadi tidak perlu scene.

const COL_TEXT := Color("e9dcc8")
const COL_ACCENT := Color("dba98c")
const COL_DIM := Color("6f6258")
const COL_RED := Color("c0392b")
const COL_LINE := Color(0.55, 0.42, 0.34, 0.35)

var _open := false
var _root: Control
var _grid: InventoryGrid
var _menu_entry = null               # entry yang menunya sedang terbuka
var _discard_armed := false

var _status: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _msg_label: Label
var _use_btn: Button
var _move_btn: Button
var _examine_btn: Button
var _discard_btn: Button
var _msg_tween: Tween

var _reader: Control
var _reader_title: Label
var _reader_body: Label
var _reader_close: Button


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Inventory.inventory_changed.connect(_refresh)
	Inventory.message.connect(_on_message)


# =================================================================== input

func _input(event: InputEvent) -> void:
	if InputMap.has_action("inventory") and event.is_action_pressed("inventory"):
		if _open:
			close()
		elif _can_open():
			open()
		else:
			return
		get_viewport().set_input_as_handled()
		return

	if not _open:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _reader.visible:
			_close_reader()
		elif _grid.is_holding():
			_grid.cancel_hold()
		elif _menu_entry != null:
			_close_menu()
		else:
			close()


func _can_open() -> bool:
	if get_tree().paused:                       # pause menu sedang aktif
		return false
	if get_tree().get_first_node_in_group("player") == null:
		return false                            # bukan di dalam game (mis. main menu)
	var hud = get_tree().get_first_node_in_group("hud")
	if hud and hud.get("intro_mode") == true:   # intro: belum punya senjata
		return false
	return true


func open() -> void:
	_open = true
	_root.show()
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_entry = null
	_discard_armed = false
	_discard_btn.text = "DISCARD"
	_grid.locked = false
	_grid.cancel_hold()
	if Inventory.entries.size() > 0:
		var e: Dictionary = Inventory.entries[0]
		_grid.cursor = Vector2i(e["x"], e["y"])
	else:
		_grid.cursor = Vector2i.ZERO
	_set_menu_buttons(null)
	_refresh()
	_grid.grab_focus()


func close() -> void:
	_open = false
	_grid.cancel_hold()
	_reader.hide()
	_root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =================================================================== bangun UI

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# ---- header
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "ATTACHE CASE"
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", COL_RED)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.add_theme_color_override("font_color", COL_ACCENT)
	_status.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(_status)
	vbox.add_child(_make_line())

	# ---- body
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	vbox.add_child(body)

	_grid = InventoryGrid.new()
	_grid.selection_changed.connect(_on_selection_changed)
	_grid.menu_requested.connect(_on_menu_requested)
	_grid.notice.connect(_on_message)
	body.add_child(_grid)

	var detail := VBoxContainer.new()
	detail.custom_minimum_size = Vector2(330, 0)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 8)
	body.add_child(detail)

	_name_label = Label.new()
	_name_label.theme_type_variation = &"HeaderLabel"
	_name_label.add_theme_font_size_override("font_size", 28)
	detail.add_child(_name_label)

	_type_label = Label.new()
	_type_label.add_theme_font_size_override("font_size", 16)
	_type_label.add_theme_color_override("font_color", COL_ACCENT)
	detail.add_child(_type_label)

	detail.add_child(_make_line())

	_desc_label = Label.new()
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc_label.add_theme_font_size_override("font_size", 18)
	detail.add_child(_desc_label)

	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 18)
	_msg_label.add_theme_color_override("font_color", COL_RED)
	_msg_label.modulate.a = 0.0
	detail.add_child(_msg_label)

	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 10)
	actions.add_theme_constant_override("v_separation", 8)
	detail.add_child(actions)
	_use_btn = _make_action_button("USE", _on_use_pressed)
	_move_btn = _make_action_button("MOVE", _on_move_pressed)
	_examine_btn = _make_action_button("EXAMINE", _on_examine_pressed)
	_discard_btn = _make_action_button("DISCARD", _on_discard_pressed)
	for b in [_use_btn, _move_btn, _examine_btn, _discard_btn]:
		actions.add_child(b)

	# ---- footer
	vbox.add_child(_make_line())
	var hint := Label.new()
	hint.text = "[SERET / ENTER] Pindah    [KLIK] Menu    [R] Putar    [ESC] Kembali    [TAB] Tutup"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(hint)

	_build_reader()


func _build_reader() -> void:
	_reader = Control.new()
	_reader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reader.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_reader)
	_reader.hide()

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reader.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reader.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 400)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_reader_title = Label.new()
	_reader_title.theme_type_variation = &"HeaderLabel"
	_reader_title.add_theme_font_size_override("font_size", 32)
	_reader_title.add_theme_color_override("font_color", COL_RED)
	vbox.add_child(_reader_title)
	vbox.add_child(_make_line())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_reader_body = Label.new()
	_reader_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reader_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reader_body.add_theme_font_size_override("font_size", 20)
	scroll.add_child(_reader_body)

	_reader_close = _make_action_button("TUTUP", _close_reader)
	_reader_close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_reader_close)


func _make_action_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(callback)
	return b


func _make_line() -> ColorRect:
	var line := ColorRect.new()
	line.color = COL_LINE
	line.custom_minimum_size = Vector2(0, 1)
	return line


# =================================================================== isi / refresh

func _refresh() -> void:
	_update_status()
	_show_detail(_menu_entry if _menu_entry != null else _grid.current_entry())


func _update_status() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if player == null:
		_status.text = ""
		return
	var parts: Array[String] = []
	var h = player.get_node_or_null("Health")
	if h:
		parts.append("HP %d / %d" % [int(h.current_health), int(h.max_health)])
		if "armor" in h and h.armor > 0:
			parts.append("ARMOR %d / %d" % [int(h.armor), int(h.max_armor)])
	var cur = player.get("current_ammo")
	var res = player.get("reserve_ammo")
	if cur != null and res != null:
		parts.append("PELURU %d / %d" % [int(cur), int(res)])
	_status.text = "      ".join(parts)


func _show_detail(entry) -> void:
	if entry == null:
		_name_label.text = "-"
		_type_label.text = ""
		_desc_label.text = "Arahkan kursor ke item.\nSeret untuk memindah, klik untuk membuka menu."
		return
	var item: ItemData = entry["data"]
	var size := Inventory.footprint(item, entry["rot"])
	_name_label.text = item.display_name.to_upper()
	if entry["amount"] > 1:
		_name_label.text += "  x%d" % entry["amount"]
	_type_label.text = "%s      %d x %d" % [_type_name(item.type), size.x, size.y]
	_desc_label.text = item.description


func _set_menu_buttons(entry) -> void:
	if entry == null:
		for b in [_use_btn, _move_btn, _examine_btn, _discard_btn]:
			b.disabled = true
		return
	var item: ItemData = entry["data"]
	_use_btn.disabled = item.type != ItemData.Type.CONSUMABLE
	_move_btn.disabled = false
	_examine_btn.disabled = item.description == "" and item.content == ""
	_discard_btn.disabled = false


func _type_name(t: int) -> String:
	match t:
		ItemData.Type.KEY:
			return "KEY ITEM"
		ItemData.Type.DOCUMENT:
			return "DOKUMEN"
		ItemData.Type.CONSUMABLE:
			return "PEMULIHAN"
		ItemData.Type.AMMO:
			return "AMUNISI"
	return ""


# =================================================================== menu aksi

func _on_selection_changed(entry) -> void:
	if _menu_entry == null:
		_show_detail(entry)


func _on_menu_requested(entry) -> void:
	_menu_entry = entry
	_grid.locked = true
	_discard_armed = false
	_discard_btn.text = "DISCARD"
	_show_detail(entry)
	_set_menu_buttons(entry)
	if not _use_btn.disabled:
		_use_btn.grab_focus()
	else:
		_move_btn.grab_focus()


func _close_menu() -> void:
	_menu_entry = null
	_discard_armed = false
	_discard_btn.text = "DISCARD"
	_set_menu_buttons(null)
	_grid.locked = false
	_grid.grab_focus()
	_show_detail(_grid.current_entry())


func _on_use_pressed() -> void:
	if _menu_entry == null:
		return
	Inventory.use_entry(_menu_entry)
	_close_menu()


func _on_move_pressed() -> void:
	if _menu_entry == null:
		return
	var e = _menu_entry
	_close_menu()
	_grid.begin_hold(e)


func _on_examine_pressed() -> void:
	if _menu_entry == null:
		return
	var item: ItemData = _menu_entry["data"]
	_reader_title.text = item.display_name.to_upper()
	_reader_body.text = item.content if item.content != "" else item.description
	_reader.show()
	_reader_close.grab_focus()


func _on_discard_pressed() -> void:
	if _menu_entry == null:
		return
	if not _discard_armed:
		_discard_armed = true
		_discard_btn.text = "YAKIN?"
		return
	Inventory.discard_entry(_menu_entry)
	_close_menu()


func _close_reader() -> void:
	_reader.hide()
	if _menu_entry != null:
		_examine_btn.grab_focus()
	else:
		_grid.grab_focus()


func _on_message(text: String) -> void:
	if not _open:
		return
	_msg_label.text = text
	if _msg_tween:
		_msg_tween.kill()
	_msg_label.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.5)
	_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.4)
