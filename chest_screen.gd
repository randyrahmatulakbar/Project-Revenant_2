class_name ChestScreen
extends CanvasLayer
## UI CRATE, gaya sama dengan InventoryUI (RevUI.Chrome, panel, header, hint bawah, panel detail).
## Dibuat dari kode oleh LootChest (TIDAK perlu didaftarkan di Autoload).
## - Seret item antara CRATE dan ATTACHE CASE (dua arah). R = putar saat menyeret. Klik kanan = pindah otomatis.
## - Pertama dibuka: tiap item: SCAN (noise + bracket mengunci) -> DECODE kiri ke kanan -> impact frame / efek rarity.
## - Animasi tidak bisa dilewati. Kalau ditutup di tengah jalan, dilanjutkan saat dibuka lagi. Item yang sudah selesai bisa langsung diambil.
## - ESC / TAB = tutup.
## Semua animasi isi berjalan 12 FPS.

const COL_TEXT := Color("eadccf")
const COL_ACCENT := Color("dea68a")
const COL_DIM := Color("c99a7e")
const COL_RED := Color("c7332b")
const COL_LINE := Color(0.49, 0.388, 0.329, 0.4)
const COL_CELL := Color(0.045, 0.075, 0.08, 1.0)
const COL_GRID := Color(0.49, 0.388, 0.329, 0.26)
const COL_BORDER := Color("7d6354")
const COL_GOOD := Color("6fae8f")
const COL_BAD := Color("c0392b")
const COL_TEAL := Color(0.30, 0.55, 0.50)

const FPS := 12.0
const OPEN_DELAY := 0.75
const SCAN_DUR := 0.42
const FX_DUR := 0.5
const GAP_DUR := 0.06
const WIPE_BASE := 0.2
const WIPE_PER_CELL := 0.13

## Warna per rarity (placeholder). Indeks = LootChest.rarity_of()
const RARITY_COLORS := [Color("dea68a"), Color("6fae8f"), Color("6f9be6"), Color("c780f2")]

var _open := false
var _chest: LootChest = null

var _root: Control
var _dim: ColorRect
var _chrome: RevUI.Chrome
var _left: Control
var _right: Control
var _crate_grid: Control
var _inv_grid: Control
var _ghost: Control
var _cap: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _msg_label: Label
var _take_btn: RevUI.NavBtn
var _close_btn: RevUI.NavBtn
var _msg_tween: Tween
var _tw_in: Tween

var _cell := 56
var _anim := false
var _open_msec := 0
var _raw := 0.0
var _anim_total := 0.0
var _qt := 0.0                      # waktu animasi, dibulatkan ke 12 FPS

var _hover_kind := ""               # "crate" / "inv" / ""
var _hover_cell := Vector2i(-1, -1)
var _held: Variant = null           # entry yang diseret
var _held_src := ""
var _held_rot := 0
var _grab := Vector2i.ZERO
var _press_active := false
var _press_pos := Vector2.ZERO
var _moved := false
var _last_detail: Variant = null
var _last_can_take := false


func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()
	Inventory.inventory_changed.connect(_on_inv_changed)


# =================================================================== buka / tutup

func open_chest(chest: LootChest) -> void:
	if _open:
		return
	_chest = chest
	_open = true
	_held = null
	_press_active = false
	_moved = false
	_last_detail = null
	_last_can_take = false
	_take_btn.set_enabled(false)
	_hover_kind = ""
	_open_msec = Time.get_ticks_msec()
	_anim = not chest.opened_once and chest.contents.size() > 0
	if _anim:
		if not chest.anim_started:
			_start_anim()
		else:
			_anim_total = chest.anim_total                # lanjutkan animasi yang tadi ditinggal
			_qt = -1.0
	else:
		_finish_anim()
	var vs := get_viewport().get_visible_rect().size
	_cell = clampi(floori((vs.y - 430.0) / 10.0), 30, 56)
	_crate_grid.custom_minimum_size = Vector2(Inventory.cols, chest.chest_rows) * _cell
	_inv_grid.custom_minimum_size = Vector2(Inventory.cols, Inventory.rows) * _cell
	_crate_grid.size = _crate_grid.custom_minimum_size
	_inv_grid.size = _inv_grid.custom_minimum_size
	if _tw_in:
		_tw_in.kill()
	_root.modulate.a = 1.0
	_root.show()
	_left.modulate.a = 0.0
	_right.modulate.a = 0.0
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_detail(null)
	_on_inv_changed()
	_play_in()
	chest.opened.emit()


func _play_in() -> void:
	_dim.modulate.a = 0.0
	_chrome.reveal = 0.0
	await get_tree().process_frame
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
	if not _open:
		return
	_open = false
	_held = null
	_press_active = false
	if _chest != null:
		if _anim:
			_chest.anim_elapsed = maxf(_raw, 0.0)             # simpan posisi animasi, dilanjutkan saat dibuka lagi
		_chest.closed.emit()
	_chest = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _tw_in:
		_tw_in.kill()
	_tw_in = create_tween()
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


func _make_line() -> ColorRect:
	var line := ColorRect.new()
	line.color = COL_LINE
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _make_panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", RevUI.panel_box())
	parent.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	return vbox


func _make_nav(title: String, sub: String, callback: Callable) -> RevUI.NavBtn:
	var b := RevUI.NavBtn.new()
	b.title = title
	b.subtitle = sub
	b.big = false
	b.font = RevUI.font()
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	return b


func _make_grid(kind: String) -> Control:
	var c := Control.new()
	c.set_meta("kind", kind)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	c.draw.connect(_draw_grid.bind(c))
	c.gui_input.connect(_grid_input.bind(c))
	return c


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
	_chrome.mode_text = "CRATE"
	_chrome.status_text = "SESSION SUSPENDED"
	_chrome.center_text = "WORLD STATE HELD"
	_chrome.hints = [["DRAG", "MOVE"], ["R", "ROTATE"], ["RMB", "QUICK MOVE"], ["ESC", "CLOSE"]]
	_root.add_child(_chrome)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	center.add_child(body)

	# ---- panel kiri: crate + inventory
	var lv := _make_panel(body)
	_left = lv.get_parent()
	var header := HBoxContainer.new()
	lv.add_child(header)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	header.add_child(hv)
	hv.add_child(_label("// STORAGE", 11, COL_DIM))
	hv.add_child(_title("CRATE", 34))
	hv.add_child(_red_line())
	lv.add_child(_make_line())

	var gm := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm.add_theme_constant_override(k, 6)
	lv.add_child(gm)
	_crate_grid = _make_grid("crate")
	gm.add_child(_crate_grid)

	var header2 := HBoxContainer.new()
	lv.add_child(header2)
	var hv2 := VBoxContainer.new()
	hv2.add_theme_constant_override("separation", 2)
	header2.add_child(hv2)
	hv2.add_child(_label("// INVENTORY", 11, COL_DIM))
	hv2.add_child(_title("ATTACHE CASE", 24))
	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header2.add_child(spacer2)
	_cap = _label("", 15, COL_ACCENT)
	_cap.size_flags_vertical = Control.SIZE_SHRINK_END
	header2.add_child(_cap)

	var gm2 := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		gm2.add_theme_constant_override(k, 6)
	lv.add_child(gm2)
	_inv_grid = _make_grid("inv")
	gm2.add_child(_inv_grid)

	# ---- panel kanan: detail
	var detail := _make_panel(body)
	_right = detail.get_parent()
	detail.custom_minimum_size = Vector2(340, 380)
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

	var desc_holder := Control.new()
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

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	detail.add_child(actions)
	_take_btn = _make_nav("TAKE ALL", "MOVE TO CASE", _take_all)
	_close_btn = _make_nav("CLOSE", "BACK TO GAME", close)
	actions.add_child(_take_btn)
	actions.add_child(_close_btn)

	# lapisan paling atas untuk item yang sedang diseret
	_ghost = Control.new()
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ghost.draw.connect(_draw_ghost)
	_root.add_child(_ghost)


# =================================================================== animasi isi

func _start_anim() -> void:
	var t := 0.0
	for e in _chest.contents:
		var w: int = Inventory.footprint(e["data"], e["rot"]).x
		e["st"] = 0
		e["wipe"] = 0.0
		e["fx"] = 0.0
		e["scan"] = 0.0
		e["t_scan"] = t
		t += SCAN_DUR
		e["t_wipe"] = t
		e["d_wipe"] = WIPE_PER_CELL * w + WIPE_BASE
		t += e["d_wipe"]
		e["t_fx"] = t
		t += FX_DUR
		e["t_end"] = t
		t += GAP_DUR
	_anim_total = t
	_qt = -1.0
	_chest.anim_started = true
	_chest.anim_total = t
	_chest.anim_elapsed = 0.0


func _finish_anim() -> void:
	_anim = false
	if _chest != null:
		_chest.opened_once = true
	for e in _chest.contents:
		e["st"] = 4
		e["wipe"] = 1.0
		e["fx"] = 1.0


func _update_anim() -> void:
	var since := float(Time.get_ticks_msec() - _open_msec) / 1000.0 - OPEN_DELAY
	var saved: float = _chest.anim_elapsed
	var adv: float = since if saved <= 0.0 else maxf(since, 0.0)
	_raw = saved + adv
	_qt = floorf(_raw * FPS) / FPS
	if _qt >= _anim_total:
		_finish_anim()
		return
	for e in _chest.contents:
		if not e.has("t_scan"):                              # item yang dimasukkan pemain, tidak ikut animasi
			continue
		if _qt < e["t_scan"]:
			e["st"] = 0
		elif _qt < e["t_wipe"]:
			e["st"] = 1
			e["scan"] = clampf((_qt - e["t_scan"]) / SCAN_DUR, 0.0, 1.0)
		elif _qt < e["t_fx"]:
			e["st"] = 2
			e["wipe"] = clampf((_qt - e["t_wipe"]) / e["d_wipe"], 0.0, 1.0)
		elif _qt < e["t_end"]:
			e["st"] = 3
			e["wipe"] = 1.0
			e["fx"] = clampf((_qt - e["t_fx"]) / FX_DUR, 0.0, 1.0)
		else:
			e["st"] = 4
			e["wipe"] = 1.0
			e["fx"] = 1.0


# =================================================================== proses / input

func _process(_delta: float) -> void:
	if not _open or _chest == null:
		return
	if _anim:
		_update_anim()
	_update_hover()
	if _held != null and not _moved and get_viewport().get_mouse_position().distance_to(_press_pos) > 6.0:
		_moved = true
	var cur: Variant = _held if _held != null else _hovered_entry()
	var changed := false
	if cur == null:
		changed = _last_detail != null
	else:
		changed = _last_detail == null or not is_same(cur, _last_detail)
	if changed:
		_last_detail = cur
		_show_detail(cur)
	var can_take := _any_takeable()
	if can_take != _last_can_take:
		_last_can_take = can_take
		_take_btn.set_enabled(can_take)
	_crate_grid.queue_redraw()
	_inv_grid.queue_redraw()
	_ghost.queue_redraw()


func _update_hover() -> void:
	var mp := get_viewport().get_mouse_position()
	_hover_kind = ""
	_hover_cell = Vector2i(-1, -1)
	for g in [_crate_grid, _inv_grid]:
		var gc: Control = g
		var gr := gc.get_global_rect()
		if gr.has_point(mp):
			_hover_kind = String(gc.get_meta("kind"))
			var q := (mp - gr.position) / float(_cell)
			_hover_cell = Vector2i(
				clampi(int(q.x), 0, Inventory.cols - 1),
				clampi(int(q.y), 0, _rows_of(_hover_kind) - 1))
			return


func _rows_of(kind: String) -> int:
	return _chest.chest_rows if kind == "crate" else Inventory.rows


func _input(event: InputEvent) -> void:
	if not _open:
		return
	var close_pressed: bool = event.is_action_pressed("ui_cancel") \
		or (InputMap.has_action("inventory") and event.is_action_pressed("inventory"))
	if close_pressed:
		if _held != null:
			_cancel_hold()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if _held != null and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		var d: ItemData = _held["data"]
		if Inventory.can_rotate(d):
			_held_rot = Inventory.next_rot(d, _held_rot)
			_moved = true
		get_viewport().set_input_as_handled()


func _grid_input(ev: InputEvent, g: Control) -> void:
	if not _open or not (ev is InputEventMouseButton):
		return
	var kind := String(g.get_meta("kind"))
	if ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_update_hover()
			_press(kind)
		else:
			_release()
	elif ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
		if _held != null:
			_cancel_hold()
		else:
			_update_hover()
			var e: Variant = _entry_at(kind, _hover_cell)
			if e != null:
				_quick_move(kind, e)
	g.accept_event()


func _press(kind: String) -> void:
	if _hover_kind != kind:
		return
	var e: Variant = _entry_at(kind, _hover_cell)
	if e == null:
		return
	_held = e
	_held_src = kind
	_held_rot = int(e["rot"])
	_grab = _hover_cell - Vector2i(e["x"], e["y"])
	_press_active = true
	_press_pos = get_viewport().get_mouse_position()
	_moved = false


func _cancel_hold() -> void:
	_held = null
	_press_active = false
	_moved = false


func _release() -> void:
	if not _press_active or _held == null:
		_cancel_hold()
		return
	var e: Dictionary = _held
	var src := _held_src
	var moved := _moved
	_update_hover()
	var plan := _plan_drop()
	var rot := _held_rot
	_cancel_hold()
	if not moved:
		return
	var st := String(plan.get("state", "none"))
	if st == "none":
		return
	if st == "invalid":
		_say("DOESN'T FIT")
		return
	_execute(e, src, plan, rot)


# =================================================================== logika seret / pindah

func _entry_at(kind: String, c: Vector2i) -> Variant:
	if c.x < 0:
		return null
	if kind == "inv":
		return Inventory.entry_at(c.x, c.y)
	for e in _chest.contents:
		if int(e.get("st", 4)) < 3:
			continue
		var o := Vector2i(e["x"], e["y"])
		for cc in Inventory.cells_of(e["data"], e["rot"]):
			if o + cc == c:
				return e
	return null


func _hovered_entry() -> Variant:
	if _hover_kind == "":
		return null
	return _entry_at(_hover_kind, _hover_cell)


func _any_takeable() -> bool:
	for e in _chest.contents:
		if int(e.get("st", 4)) >= 3:
			return true
	return false


func _plan_drop() -> Dictionary:
	if _held == null or _hover_kind == "":
		return {"state": "none"}
	var item: ItemData = _held["data"]
	var fp := Inventory.footprint(item, _held_rot)
	var gx := Vector2i(clampi(_grab.x, 0, fp.x - 1), clampi(_grab.y, 0, fp.y - 1))
	var a := _hover_cell - gx
	a.x = clampi(a.x, 0, maxi(Inventory.cols - fp.x, 0))
	a.y = clampi(a.y, 0, maxi(_rows_of(_hover_kind) - fp.y, 0))
	var tgt: Variant = _entry_at(_hover_kind, _hover_cell)
	if tgt != null and not is_same(tgt, _held) and tgt["data"].id == item.id and item.stackable \
			and int(tgt["amount"]) < item.max_stack:
		return {"state": "merge", "anchor": a, "target": tgt}
	var ignore: Variant = _held if _held_src == _hover_kind else null
	var ok := false
	if _hover_kind == "inv":
		ok = Inventory.can_place(item, a.x, a.y, _held_rot, ignore)
	else:
		ok = _chest.fits(item, a.x, a.y, _held_rot, ignore)
	return {"state": "place" if ok else "invalid", "anchor": a, "target": null}


func _remove_from_crate(entry: Dictionary) -> void:
	for i in _chest.contents.size():
		if is_same(_chest.contents[i], entry):
			_chest.contents.remove_at(i)
			return


func _strip(e: Dictionary) -> void:
	for k in ["st", "wipe", "fx", "scan", "t_scan", "t_wipe", "d_wipe", "t_fx", "t_end"]:
		e.erase(k)


func _execute(e: Dictionary, src: String, plan: Dictionary, rot: int) -> void:
	var dst := _hover_kind
	var item: ItemData = e["data"]
	var a: Vector2i = plan["anchor"]
	if String(plan["state"]) == "merge":
		var tgt: Dictionary = plan["target"]
		var moved := mini(item.max_stack - int(tgt["amount"]), int(e["amount"]))
		tgt["amount"] = int(tgt["amount"]) + moved
		if src == "inv":
			Inventory.remove_entry(e, moved)
		else:
			e["amount"] = int(e["amount"]) - moved
			if int(e["amount"]) <= 0:
				_remove_from_crate(e)
		Inventory.inventory_changed.emit()
		return
	if src == dst:
		if src == "inv":
			Inventory.move_entry(e, a.x, a.y, rot)
		else:
			e["x"] = a.x
			e["y"] = a.y
			e["rot"] = rot
		return
	var amount := int(e["amount"])
	if src == "crate":                                  # crate -> case
		_remove_from_crate(e)
		_strip(e)
		e["x"] = a.x
		e["y"] = a.y
		e["rot"] = rot
		Inventory.entries.append(e)
		Inventory.item_added.emit(item, amount)
		Inventory.inventory_changed.emit()
		_say("TAKEN: %s" % item.display_name.to_upper())
	else:                                               # case -> crate
		Inventory.remove_entry(e, amount)
		e["amount"] = amount
		e["x"] = a.x
		e["y"] = a.y
		e["rot"] = rot
		e["st"] = 4
		e["wipe"] = 1.0
		e["fx"] = 1.0
		_chest.contents.append(e)
		Inventory.inventory_changed.emit()
		_say("STORED: %s" % item.display_name.to_upper())


## Klik kanan: pindahkan ke tempat kosong pertama di sisi lain.
func _quick_move(kind: String, e: Dictionary) -> bool:
	var item: ItemData = e["data"]
	var amount := int(e["amount"])
	if kind == "crate":
		if int(e.get("st", 4)) < 3:
			return false
		if Inventory.add_item(item, amount, int(e.get("rounds", -1))):
			_remove_from_crate(e)
			_say("TAKEN: %s" % item.display_name.to_upper())
			return true
		_say("INVENTORY FULL")
		return false
	var spot := _chest.find_spot(item)
	if spot.is_empty():
		_say("CRATE FULL")
		return false
	Inventory.remove_entry(e, amount)
	e["amount"] = amount
	e["x"] = spot["x"]
	e["y"] = spot["y"]
	e["rot"] = spot["rot"]
	e["st"] = 4
	e["wipe"] = 1.0
	e["fx"] = 1.0
	_chest.contents.append(e)
	Inventory.inventory_changed.emit()
	_say("STORED: %s" % item.display_name.to_upper())
	return true


func _take_all() -> void:
	if _chest == null:
		return
	var left := 0
	for e in _chest.contents.duplicate():
		if int(e.get("st", 4)) < 3:
			continue
		if not _quick_move("crate", e):
			left += 1
	if left > 0:
		_say("INVENTORY FULL  /  %d LEFT" % left)


# =================================================================== panel detail

func _say(text: String) -> void:
	_msg_label.text = text
	if _msg_tween:
		_msg_tween.kill()
	_msg_label.modulate.a = 1.0
	_msg_tween = create_tween()
	_msg_tween.tween_interval(1.5)
	_msg_tween.tween_property(_msg_label, "modulate:a", 0.0, 0.4)


func _on_inv_changed() -> void:
	if not _open:
		return
	var used := 0
	for e in Inventory.entries:
		var it: ItemData = e["data"]
		used += Inventory.cells_of(it, e["rot"]).size()
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
	_last_detail = null
	_show_detail(_held if _held != null else _hovered_entry())


func _type_name(t: int) -> String:
	match t:
		ItemData.Type.KEY:
			return "KEY ITEM"
		ItemData.Type.DOCUMENT:
			return "DOCUMENT"
		ItemData.Type.CONSUMABLE:
			return "RECOVERY"
		ItemData.Type.AMMO:
			return "AMMO"
		ItemData.Type.EQUIPMENT:
			return "EQUIPMENT"
		ItemData.Type.WEAPON:
			return "WEAPON"
	return ""


func _show_detail(entry: Variant) -> void:
	if entry == null:
		_name_label.text = "-"
		_type_label.text = ""
		_desc_label.text = "Hover an item to inspect it.\nDrag items between the crate and your case."
		return
	var item: ItemData = entry["data"]
	var size: Vector2i = Inventory.footprint(item, entry["rot"])
	_name_label.text = item.display_name.to_upper()
	if item.type == ItemData.Type.AMMO:
		_name_label.text += "  (%d ROUNDS)" % int(entry.get("rounds", item.mag_rounds))
	elif entry["amount"] > 1:
		_name_label.text += "  x%d" % entry["amount"]
	if Inventory.is_shaped(item):
		_type_label.text = "%s      %d SLOTS" % [_type_name(item.type), item.shape.size()]
	else:
		_type_label.text = "%s      %d x %d" % [_type_name(item.type), size.x, size.y]
	_desc_label.text = item.description


# =================================================================== gambar grid

func _hash(a: int, b: int, c: int) -> float:
	return fposmod(sin(float(a) * 12.9898 + float(b) * 78.233 + float(c) * 37.719) * 43758.5453, 1.0)


func _draw_grid(g: Control) -> void:
	if not _open or _chest == null:
		return
	var kind := String(g.get_meta("kind"))
	var cols := Inventory.cols
	var rows := _rows_of(kind)
	var cs := float(_cell)
	var full := Rect2(Vector2.ZERO, Vector2(cols, rows) * cs)
	g.draw_rect(full, COL_CELL)
	for x in range(cols + 1):
		g.draw_line(Vector2(x * cs, 0), Vector2(x * cs, rows * cs), COL_GRID, 1.0)
	for y in range(rows + 1):
		g.draw_line(Vector2(0, y * cs), Vector2(cols * cs, y * cs), COL_GRID, 1.0)
	g.draw_rect(full, Color(COL_BORDER, 0.55), false, 1.0)
	_brackets(g, full.grow(4.0), Color(COL_ACCENT, 0.9), 16.0, 2.0)

	var list: Array = _chest.contents if kind == "crate" else Inventory.entries
	for e in list:
		var st := int(e.get("st", 4))
		if st == 0:
			continue
		var rect := _entry_rect(e)
		if st == 1:
			_draw_scan(g, e, rect)
			continue
		var faded: bool = _held != null and is_same(e, _held)
		_draw_entry(g, e, rect, 0.25 if faded else 1.0, int(e["rot"]))
		if st == 2:
			_draw_decode(g, e, rect)
		elif st == 3:
			_draw_impact(g, e, rect)
		elif st == 4 and kind == "crate":
			var rar := clampi(LootChest.rarity_of(e["data"]), 0, RARITY_COLORS.size() - 1)
			if rar > 0:
				_outline_cells(g, rect.position, Inventory.cells_of(e["data"], e["rot"]), Color(RARITY_COLORS[rar], 0.85), 2.0)

	# sorotan kursor
	if _hover_kind == kind and _held == null:
		var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
		var hover: Variant = _entry_at(kind, _hover_cell)
		if hover != null and Inventory.is_shaped(hover["data"]):
			_outline_cells(g, Vector2(hover["x"], hover["y"]) * cs, Inventory.cells_of(hover["data"], hover["rot"]),
					Color(COL_ACCENT, pulse), 2.0)
		else:
			var r := Rect2(Vector2(_hover_cell) * cs, Vector2(cs, cs))
			if hover != null:
				r = _entry_rect(hover)
			g.draw_rect(r.grow(-1), Color(COL_ACCENT, 0.07 + 0.05 * pulse))
			g.draw_rect(r.grow(-1), Color(COL_ACCENT, 0.45), false, 1.0)
			_brackets(g, r.grow(-1), Color(COL_ACCENT, pulse), 11.0, 2.5)


func _entry_rect(e: Dictionary) -> Rect2:
	var r: Rect2i = Inventory.rect_of(e)
	return Rect2(Vector2(r.position) * float(_cell), Vector2(r.size) * float(_cell))


func _draw_ghost() -> void:
	if not _open or _held == null or not _moved:
		return
	var item: ItemData = _held["data"]
	var cs := float(_cell)
	var cells: Array = Inventory.cells_of(item, _held_rot)
	var fp := Inventory.footprint(item, _held_rot)
	var gx := Vector2i(clampi(_grab.x, 0, fp.x - 1), clampi(_grab.y, 0, fp.y - 1))
	var pos := _ghost.get_local_mouse_position() - (Vector2(gx) + Vector2(0.5, 0.5)) * cs
	var tint := COL_DIM
	var plan := _plan_drop()
	var st := String(plan.get("state", "none"))
	if st != "none":
		var grid: Control = _crate_grid if _hover_kind == "crate" else _inv_grid
		var a: Vector2i = plan["anchor"]
		pos = grid.get_global_rect().position - _ghost.get_global_rect().position + Vector2(a) * cs
		tint = COL_GOOD
		if st == "invalid":
			tint = COL_BAD
		elif st == "merge":
			tint = COL_ACCENT
	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
	for c in cells:
		_ghost.draw_rect(Rect2(pos + Vector2(c) * cs, Vector2(cs, cs)), Color(tint, 0.28))
	_draw_entry(_ghost, _held, Rect2(pos, Vector2(fp) * cs), 0.9, _held_rot)
	_outline_cells(_ghost, pos, cells, Color(tint, pulse), 2.0)


# ---- animasi reveal -------------------------------------------------

## Tahap 1: noise "belum terbaca" + bracket yang mengunci.
func _draw_scan(g: Control, e: Dictionary, rect: Rect2) -> void:
	var cs := float(_cell)
	var f := int(_qt * FPS)
	var cells: Array = Inventory.cells_of(e["data"], e["rot"])
	for c in cells:
		var cp := rect.position + Vector2(c) * cs
		g.draw_rect(Rect2(cp, Vector2(cs, cs)), COL_CELL)
		_noise(g, cp, Vector2i(int(e["x"]) + c.x, int(e["y"]) + c.y), 0.0, f, 0.0)
	var steps := int(float(e["scan"]) * 4.0)
	var grow := float(maxi(3 - steps, 0)) * 9.0
	var on := f % 2 == 0
	_brackets(g, rect.grow(grow), Color(COL_ACCENT, 1.0 if on else 0.55), 12.0, 3.0)
	if steps >= 3:
		_outline_cells(g, rect.position, cells, Color(COL_ACCENT, 0.9), 2.0)


## Tahap 2: sisi kanan masih noise, sisi kiri sudah terbaca; garis penyapu patah-patah.
func _draw_decode(g: Control, e: Dictionary, rect: Rect2) -> void:
	var cs := float(_cell)
	var f := int(_qt * FPS)
	var blk := float(maxi(4, _cell / 7))
	var rx := floorf(float(e["wipe"]) * rect.size.x / blk) * blk          # lompat per blok
	var edge_x := rect.position.x + rx
	# scanline di bagian yang sudah terbaca
	var yy := 0.0
	while yy < rect.size.y:
		g.draw_rect(Rect2(rect.position.x, rect.position.y + yy, rx, 1.0), Color(0, 0, 0, 0.22))
		yy += 4.0
	# bagian yang belum terbaca
	var cells: Array = Inventory.cells_of(e["data"], e["rot"])
	for c in cells:
		var cp := rect.position + Vector2(c) * cs
		var vx := maxf(edge_x, cp.x)
		var vw := cp.x + cs - vx
		if vw <= 0.0:
			continue
		g.draw_rect(Rect2(Vector2(vx, cp.y), Vector2(vw, cs)), COL_CELL)
		g.draw_rect(Rect2(Vector2(vx, cp.y), Vector2(vw, cs)), Color(COL_GRID, 0.5), false, 1.0)
		_noise(g, cp, Vector2i(int(e["x"]) + c.x, int(e["y"]) + c.y), edge_x, f, 0.0)
	# garis penyapu bergerigi
	var n := int(ceilf(rect.size.y / blk))
	for i in n:
		var jit := floorf((_hash(i, f, 7) - 0.5) * 3.0) * 4.0
		var seg := Rect2(edge_x - 3.0 + jit, rect.position.y + i * blk, 4.0, minf(blk, rect.size.y - i * blk))
		g.draw_rect(seg, Color("fff1de") if _hash(i, f, 3) > 0.7 else COL_ACCENT)
		g.draw_rect(Rect2(seg.position.x - 8.0, seg.position.y, 6.0, seg.size.y), Color(COL_ACCENT, 0.25))


## Noise blok piksel. clip_x = hanya gambar di kanan x ini.
func _noise(g: Control, cp: Vector2, id: Vector2i, clip_x: float, f: int, _unused: float) -> void:
	var cs := float(_cell)
	var blk := float(maxi(4, _cell / 7))
	var n := int(ceilf(cs / blk))
	for by in n:
		for bx in n:
			var bp := cp + Vector2(bx, by) * blk
			var bw := minf(blk, cp.x + cs - bp.x)
			var bh := minf(blk, cp.y + cs - bp.y)
			if bp.x + bw <= clip_x:
				continue
			if bp.x < clip_x:
				bw -= clip_x - bp.x
				bp.x = clip_x
			var h := _hash(id.x * 37 + bx, id.y * 91 + by, f)
			var col := Color(0, 0, 0, 0)
			if h > 0.84:
				col = Color(COL_ACCENT, 0.6)
			elif h > 0.66:
				col = Color(COL_TEAL, 0.4)
			elif h > 0.5:
				col = Color(COL_ACCENT, 0.12)
			if col.a > 0.0:
				g.draw_rect(Rect2(bp, Vector2(bw, bh)), col)


## Tahap 3: impact frame bergaya game (6 langkah, tanpa tween halus).
func _draw_impact(g: Control, e: Dictionary, rect: Rect2) -> void:
	var step := clampi(int(float(e["fx"]) * 6.0), 0, 5)
	var rar := clampi(LootChest.rarity_of(e["data"]), 0, RARITY_COLORS.size() - 1)
	var col: Color = RARITY_COLORS[rar]
	var cells: Array = Inventory.cells_of(e["data"], e["rot"])
	var cs := float(_cell)
	if step == 0:                                        # frame negatif: bentuk item jadi blok terang
		for c in cells:
			g.draw_rect(Rect2(rect.position + Vector2(c) * cs, Vector2(cs, cs)).grow(-1.0), Color(COL_ACCENT, 0.92))
		return
	if step == 1:
		for c in cells:
			g.draw_rect(Rect2(rect.position + Vector2(c) * cs, Vector2(cs, cs)).grow(-1.0), Color("fff1de", 0.35))
	var grow: float = [0.0, 3.0, 9.0, 15.0, 20.0, 23.0][step]
	var alpha: float = [1.0, 1.0, 0.9, 0.7, 0.45, 0.25][step]
	_brackets(g, rect.grow(grow), Color(col, alpha), 14.0, 3.0)
	if step <= 3:
		g.draw_rect(rect.grow(grow * 0.5), Color(col, alpha * 0.8), false, 2.0)
	# serpihan piksel
	var count := 5 + rar * 3
	for i in count:
		var ang := (float(i) + _hash(i, 5, 1)) / float(count) * TAU
		var dist := (float(step) * 0.55 + 0.3) * (rect.size.length() * 0.32 + 8.0)
		var p: Vector2 = rect.get_center() + Vector2(cos(ang) * rect.size.x * 0.5, sin(ang) * rect.size.y * 0.5).normalized() * dist
		p = (p / 2.0).floor() * 2.0
		g.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(col, alpha))


# ---- port dari InventoryGrid (supaya tampilan item identik) -----------

func _brackets(g: Control, r: Rect2, col: Color, l: float, w: float) -> void:
	var tl := r.position
	var tr_ := Vector2(r.end.x, r.position.y)
	var bl := Vector2(r.position.x, r.end.y)
	var br := r.end
	g.draw_line(tl, tl + Vector2(l, 0), col, w)
	g.draw_line(tl, tl + Vector2(0, l), col, w)
	g.draw_line(tr_, tr_ + Vector2(-l, 0), col, w)
	g.draw_line(tr_, tr_ + Vector2(0, l), col, w)
	g.draw_line(bl, bl + Vector2(l, 0), col, w)
	g.draw_line(bl, bl + Vector2(0, -l), col, w)
	g.draw_line(br, br + Vector2(-l, 0), col, w)
	g.draw_line(br, br + Vector2(0, -l), col, w)


func _outline_cells(g: Control, origin: Vector2, cells: Array, col: Color, w: float) -> void:
	var cs := float(_cell)
	var occ := {}
	for c in cells:
		occ[c] = true
	for c in cells:
		var p: Vector2 = origin + Vector2(c) * cs
		if not occ.has(c + Vector2i(0, -1)):
			g.draw_line(p, p + Vector2(cs, 0), col, w)
		if not occ.has(c + Vector2i(0, 1)):
			g.draw_line(p + Vector2(0, cs), p + Vector2(cs, cs), col, w)
		if not occ.has(c + Vector2i(-1, 0)):
			g.draw_line(p, p + Vector2(0, cs), col, w)
		if not occ.has(c + Vector2i(1, 0)):
			g.draw_line(p + Vector2(cs, 0), p + Vector2(cs, cs), col, w)


func _type_color(t: int) -> Color:
	match t:
		ItemData.Type.KEY:
			return Color(0.22, 0.18, 0.12)
		ItemData.Type.DOCUMENT:
			return Color(0.2, 0.2, 0.18)
		ItemData.Type.CONSUMABLE:
			return Color(0.1, 0.22, 0.19)
		ItemData.Type.AMMO:
			return Color(0.22, 0.1, 0.09)
		ItemData.Type.EQUIPMENT:
			return Color(0.17, 0.12, 0.24)
		ItemData.Type.WEAPON:
			return Color(0.14, 0.16, 0.2)
	return Color(0.15, 0.15, 0.15)


func _draw_entry(g: Control, e: Dictionary, rect: Rect2, alpha: float, rot: int) -> void:
	var cs := float(_cell)
	var item: ItemData = e["data"]
	var has_icon := item.icon != null
	var fill := Color(_type_color(item.type), (0.5 if has_icon else 0.92) * alpha)
	var border := Color(COL_BORDER, alpha)
	var inner := rect.grow(-2)
	if Inventory.is_shaped(item):
		inner = _draw_shape(g, item, rect, rot, fill, border)
	else:
		g.draw_rect(inner, fill)
		g.draw_rect(inner, border, false, 2.0)
	if has_icon:
		for c in Inventory.cells_of(item, rot):
			var cell := Rect2(rect.position + Vector2(c) * cs, Vector2(cs, cs)).grow(-1.0)
			g.draw_rect(cell, Color(COL_BORDER, 0.4 * alpha), false, 1.0)
	var font := g.get_theme_default_font()
	var odd := posmod(rot, 2) == 1

	if item.icon != null:
		var tex: Texture2D = item.icon
		var tsz := tex.get_size()
		var area := rect.grow(-2)
		var fit := area.size - Vector2(4, 4)
		if odd:
			fit = Vector2(fit.y, fit.x)
		var sc := maxf(1.0, floorf(minf(fit.x / tsz.x, fit.y / tsz.y)))
		var dsz := tsz * sc
		g.draw_set_transform(area.get_center(), float(posmod(rot, 4)) * PI / 2.0, Vector2.ONE)
		g.draw_texture_rect(tex, Rect2(-dsz / 2.0, dsz), false, Color(1, 1, 1, alpha))
		g.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		g.draw_multiline_string(font, inner.position + Vector2(6, 18), item.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 12, 14, -1, Color(COL_TEXT, alpha))

	var label := ""
	if item.type == ItemData.Type.AMMO:
		label = str(e.get("rounds", item.mag_rounds))
	elif e["amount"] > 1:
		label = "x%d" % e["amount"]
	if label != "":
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		g.draw_string(font, Vector2(inner.end.x - w - 5, inner.end.y - 6), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(COL_ACCENT, alpha))


func _draw_shape(g: Control, item: ItemData, rect: Rect2, rot: int, fill: Color, border: Color) -> Rect2:
	var cs := float(_cell)
	var cells: Array = Inventory.cells_of(item, rot)
	var occ := {}
	for c in cells:
		occ[c] = true
	for c in cells:
		var top: bool = not occ.has(c + Vector2i(0, -1))
		var bottom: bool = not occ.has(c + Vector2i(0, 1))
		var left: bool = not occ.has(c + Vector2i(-1, 0))
		var right: bool = not occ.has(c + Vector2i(1, 0))
		var cr := Rect2(rect.position + Vector2(c) * cs, Vector2(cs, cs))
		var fr := Rect2(cr.position + Vector2(2.0 if left else 0.0, 2.0 if top else 0.0),
				cr.size - Vector2((2.0 if left else 0.0) + (2.0 if right else 0.0), (2.0 if top else 0.0) + (2.0 if bottom else 0.0)))
		g.draw_rect(fr, fill)
		if top:
			g.draw_rect(Rect2(fr.position, Vector2(fr.size.x, 2.0)), border)
		if bottom:
			g.draw_rect(Rect2(fr.position.x, fr.end.y - 2.0, fr.size.x, 2.0), border)
		if left:
			g.draw_rect(Rect2(fr.position, Vector2(2.0, fr.size.y)), border)
		if right:
			g.draw_rect(Rect2(fr.end.x - 2.0, fr.position.y, 2.0, fr.size.y), border)
	var rows := {}
	for c in cells:
		rows[c.y] = int(rows.get(c.y, 0)) + 1
	var best_y := 0
	var best_n := -1
	for y in rows:
		if int(rows[y]) > best_n:
			best_n = int(rows[y])
			best_y = y
	var min_x := 9999
	for c in cells:
		if c.y == best_y:
			min_x = mini(min_x, c.x)
	return Rect2(rect.position + Vector2(min_x, best_y) * cs, Vector2(best_n * cs, cs)).grow(-2)
