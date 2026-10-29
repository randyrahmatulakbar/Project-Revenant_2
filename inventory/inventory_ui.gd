extends CanvasLayer
## Autoload "InventoryUI". Layar inventory gaya RE4: case grid di kiri, detail item di kanan.
## Buka/tutup dengan action "inventory" (Tab). Game di-pause selama terbuka.
## Seluruh UI dibuat lewat kode, jadi tidak perlu scene.

const COL_TEXT := Color("eadccf")
const COL_ACCENT := Color("dea68a")
const COL_DIM := Color("c99a7e")
const COL_RED := Color("c7332b")
const COL_LINE := Color(0.49, 0.388, 0.329, 0.4)

signal opened                                        # dipakai GrenadeHand: buka inventory = simpan granat
var _open := false
var _root: Control
var _grid: InventoryGrid
var _menu_entry = null               # entry yang menunya sedang terbuka
var _discard_armed := false

var _dim: ColorRect
var _chrome: RevUI.Chrome
var _left: Control
var _right: Control
var _cap: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _msg_label: Label
var _use_btn: RevUI.NavBtn
var _examine_btn: RevUI.NavBtn
var _discard_btn: RevUI.NavBtn
var _msg_tween: Tween
var _tw_in: Tween

var _reader: Control
var _reader_title: Label
var _reader_body: Label
var _reader_close: RevUI.NavBtn


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
	opened.emit()
	if _tw_in:
		_tw_in.kill()
	_root.modulate.a = 1.0
	_root.show()
	_left.modulate.a = 0.0
	_right.modulate.a = 0.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu_entry = null
	_set_discard(false)
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
	_play_in()


# Panel membuka dari garis tipis (seperti layar menyala), kiri dulu lalu kanan; header/footer digambar bertahap.
func _play_in() -> void:
	_dim.modulate.a = 0.0
	_chrome.reveal = 0.0
	await get_tree().process_frame                         # tunggu layout supaya pivot tepat di tengah panel
	if not _open:
		return
	_tw_in = create_tween().set_parallel(true)
	_tw_in.tween_property(_dim, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	_tw_in.tween_property(_chrome, "reveal", 1.0, 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var i := 0
	for p in [_left, _right]:
		var c: Control = p
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2(1.0, 0.02)
		var dl := 0.05 + 0.09 * float(i)
		_tw_in.tween_property(c, "modulate:a", 1.0, 0.12).set_delay(dl)
		_tw_in.tween_property(c, "scale:y", 1.0, 0.6).set_delay(dl).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		i += 1


func close() -> void:
	_open = false
	_grid.cancel_hold()
	_reader.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _tw_in:
		_tw_in.kill()
	_tw_in = create_tween()                                # game langsung jalan, UI memudar sebentar
	_tw_in.tween_property(_root, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tw_in.tween_callback(_finish_close)


func _finish_close() -> void:
	if not _open:
		_root.hide()
		_root.modulate.a = 1.0


# =================================================================== bangun UI

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _title(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", COL_TEXT)
	return l


func _red_line() -> ColorRect:
	var ln := ColorRect.new()
	ln.color = COL_RED
	ln.custom_minimum_size = Vector2(64, 3)
	ln.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ln


func _make_panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RevUI.panel_box())
	parent.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	return vbox


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.03, 0.035, 0.86)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	_chrome = RevUI.Chrome.new()
	_chrome.font = RevUI.font()
	_chrome.mode_text = "INVENTORY"
	_chrome.status_text = "SESSION SUSPENDED"
	_chrome.center_text = "WORLD STATE HELD"
	_chrome.hints = [["DRAG", "MOVE"], ["CLICK", "MENU"], ["R", "ROTATE"], ["ESC", "BACK"], ["TAB", "CLOSE"]]
	_root.add_child(_chrome)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	center.add_child(body)

	# ---- panel kiri: judul + grid
	var lv := _make_panel(body)
	_left = lv.get_parent()
	var header := HBoxContainer.new()
	lv.add_child(header)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	header.add_child(hv)
	hv.add_child(_label("// INVENTORY", 11, COL_DIM))
	hv.add_child(_title("ATTACHE CASE", 34))
	hv.add_child(_red_line())
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_cap = _label("", 15, COL_ACCENT)
	_cap.size_flags_vertical = Control.SIZE_SHRINK_END
	header.add_child(_cap)
	lv.add_child(_make_line())

	var gm := MarginContainer.new()                        # ruang kecil supaya siku sudut grid tidak terpotong
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(k, 6)
	lv.add_child(gm)
	_grid = InventoryGrid.new()
	_grid.selection_changed.connect(_on_selection_changed)
	_grid.menu_requested.connect(_on_menu_requested)
	_grid.notice.connect(_on_message)
	gm.add_child(_grid)

	# ---- panel kanan: detail item
	var detail := _make_panel(body)
	_right = detail.get_parent()
	detail.custom_minimum_size = Vector2(340, 380)         # ukuran TETAP, tidak ikut panjang teks
	detail.add_theme_constant_override("separation", 8)
	detail.add_child(_label("// ITEM", 11, COL_DIM))

	_name_label = _title("-", 28)
	_name_label.clip_text = true
	_name_label.custom_minimum_size = Vector2(0, 40)
	detail.add_child(_name_label)

	_type_label = _label("", 15, COL_ACCENT)
	_type_label.clip_text = true
	_type_label.custom_minimum_size = Vector2(0, 22)
	detail.add_child(_type_label)

	detail.add_child(_make_line())

	var desc_holder := Control.new()                      # teks deskripsi di dalam kotak tetap (kelebihan dipotong)
	desc_holder.custom_minimum_size = Vector2(0, 100)
	desc_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc_holder.clip_contents = true
	detail.add_child(desc_holder)
	_desc_label = _label("", 17, COL_TEXT)
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	desc_holder.add_child(_desc_label)

	_msg_label = _label("", 17, COL_RED)
	_msg_label.modulate.a = 0.0
	_msg_label.clip_text = true
	_msg_label.custom_minimum_size = Vector2(0, 26)
	detail.add_child(_msg_label)

	var actions := VBoxContainer.new()                    # baris 1: examine + discard, baris 2: use (lebar)
	actions.add_theme_constant_override("separation", 12)
	detail.add_child(actions)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	actions.add_child(row1)
	_examine_btn = _make_nav("EXAMINE", "READ DETAILS", _on_examine_pressed, false)
	_discard_btn = _make_nav("DISCARD", "DROP ON FLOOR", _on_discard_pressed, false)
	_use_btn = _make_nav("USE", "CONSUME / APPLY", _on_use_pressed, true)
	row1.add_child(_examine_btn)
	row1.add_child(_discard_btn)
	actions.add_child(_use_btn)

	_build_reader()


func _build_reader() -> void:
	_reader = Control.new()
	_reader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reader.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_reader)
	_reader.hide()

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.03, 0.035, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reader.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reader.add_child(center)

	var vbox := _make_panel(center)
	vbox.get_parent().custom_minimum_size = Vector2(620, 420)
	vbox.add_theme_constant_override("separation", 12)
	vbox.add_child(_label("// EXAMINE", 11, COL_DIM))
	_reader_title = _title("", 32)
	vbox.add_child(_reader_title)
	vbox.add_child(_red_line())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_reader_body = _label("", 19, COL_TEXT)
	_reader_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reader_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_reader_body)

	_reader_close = _make_nav("CLOSE", "BACK TO INVENTORY", _close_reader, false)
	_reader_close.custom_minimum_size = Vector2(260, 52)
	_reader_close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(_reader_close)


func _make_nav(title: String, sub: String, callback: Callable, big: bool) -> RevUI.NavBtn:
	var b := RevUI.NavBtn.new()
	b.title = title
	b.subtitle = sub
	b.big = big
	b.font = RevUI.font()
	b.custom_minimum_size = Vector2(0, 62 if big else 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(callback)
	return b


func _set_discard(armed: bool) -> void:
	_discard_armed = armed
	_discard_btn.title = "YAKIN?" if armed else "DISCARD"
	_discard_btn.subtitle = "KLIK LAGI UNTUK BUANG" if armed else "DROP ON FLOOR"
	_discard_btn.queue_redraw()


func _make_line() -> ColorRect:
	var line := ColorRect.new()
	line.color = COL_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


# =================================================================== isi / refresh

func _refresh() -> void:
	_update_status()
	_show_detail(_menu_entry if _menu_entry != null else _grid.current_entry())


func _update_status() -> void:
	var used := 0
	for e in Inventory.entries:
		var it: ItemData = e["data"]
		if Inventory.is_shaped(it):
			used += it.shape.size()
		else:
			var fp: Vector2i = Inventory.footprint(it, e["rot"])
			used += fp.x * fp.y
	_cap.text = "SLOTS  %d / %d" % [used, Inventory.cols * Inventory.rows]
	var player = get_tree().get_first_node_in_group("player")
	var txt := ""
	if player != null:
		var parts: Array[String] = []
		var h = player.get_node_or_null("Health")
		if h:
			parts.append("HP %d / %d" % [int(h.current_health), int(h.max_health)])
			if "armor" in h and h.armor > 0:
				parts.append("ARMOR %d / %d" % [int(h.armor), int(h.max_armor)])
		txt = "   ".join(parts)
	_chrome.status_text = txt if txt != "" else "SESSION SUSPENDED"


func _show_detail(entry) -> void:
	if entry == null:
		_name_label.text = "-"
		_type_label.text = ""
		_desc_label.text = "Arahkan kursor ke item.\nSeret untuk memindah, klik untuk membuka menu."
		return
	var item: ItemData = entry["data"]
	var size: Vector2i = Inventory.footprint(item, entry["rot"])
	_name_label.text = item.display_name.to_upper()
	if item.type == ItemData.Type.AMMO:
		_name_label.text += "  (%d PELURU)" % int(entry.get("rounds", item.mag_rounds))
	elif entry["amount"] > 1:
		_name_label.text += "  x%d" % entry["amount"]
	if Inventory.is_shaped(item):
		_type_label.text = "%s      %d KOTAK" % [_type_name(item.type), item.shape.size()]
	else:
		_type_label.text = "%s      %d x %d" % [_type_name(item.type), size.x, size.y]
	_desc_label.text = item.description


func _set_menu_buttons(entry) -> void:
	if entry == null:
		for b in [_use_btn, _examine_btn, _discard_btn]:
			b.set_enabled(false)
		return
	var item: ItemData = entry["data"]
	_use_btn.set_enabled(item.type == ItemData.Type.CONSUMABLE)
	_examine_btn.set_enabled(not (item.description == "" and item.content == ""))
	_discard_btn.set_enabled(true)


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
		ItemData.Type.EQUIPMENT:
			return "EQUIPMENT"
		ItemData.Type.WEAPON:
			return "SENJATA"
	return ""


# =================================================================== menu aksi

func _on_selection_changed(entry) -> void:
	if _menu_entry == null:
		_show_detail(entry)


func _on_menu_requested(entry) -> void:
	_menu_entry = entry
	_grid.locked = true
	_set_discard(false)
	_show_detail(entry)
	_set_menu_buttons(entry)
	if not _use_btn.disabled:
		_use_btn.grab_focus()
	else:
		_examine_btn.grab_focus()


func _close_menu() -> void:
	_menu_entry = null
	_set_discard(false)
	_set_menu_buttons(null)
	_grid.locked = false
	_grid.grab_focus()
	_show_detail(_grid.current_entry())


func _on_use_pressed() -> void:
	if _menu_entry == null:
		return
	Inventory.use_entry(_menu_entry)
	_close_menu()


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
		_set_discard(true)
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
