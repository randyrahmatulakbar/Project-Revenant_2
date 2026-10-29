class_name InventoryGrid
extends Control
## Tampilan dan input grid inventory gaya RE4.
## Mouse : tahan klik kiri lalu seret untuk memindah, lepas di tempat baru. Klik biasa / klik kanan = menu.
## Keyboard: panah gerakkan kursor, Enter = menu / taruh, R = putar item, Esc = batal (diurus UI).

signal menu_requested(entry)        # entry: Dictionary
signal selection_changed(entry)     # entry: Dictionary atau null
signal notice(text: String)

const CELL := 56
const COL_CELL := Color(0.045, 0.075, 0.08, 1.0)
const COL_GRID := Color(0.49, 0.388, 0.329, 0.26)
const COL_BORDER := Color("7d6354")
const COL_ACCENT := Color("dea68a")
const COL_TEXT := Color("eadccf")
const COL_GOOD := Color("6fae8f")
const COL_BAD := Color("c0392b")

var cursor := Vector2i.ZERO
var held = null                      # entry yang sedang dipegang, atau null
var held_rot: int = 0
var grab_offset := Vector2i.ZERO
var locked := false                  # true saat menu aksi terbuka

var _press_active := false           # sedang seret dengan mouse
var _press_cell := Vector2i(-1, -1)
var _moved := false
var _last_selected = null


func _ready() -> void:
	custom_minimum_size = Vector2(Inventory.cols, Inventory.rows) * CELL
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Inventory.inventory_changed.connect(_on_inventory_changed)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


# =================================================================== API

func is_holding() -> bool:
	return held != null


func current_entry():
	if held != null:
		return held
	return Inventory.entry_at(cursor.x, cursor.y)


func begin_hold(entry: Dictionary) -> void:
	held = entry
	held_rot = entry["rot"]
	cursor = Vector2i(entry["x"], entry["y"])
	grab_offset = Vector2i.ZERO
	_press_active = false
	_selection_update()
	grab_focus()


func cancel_hold() -> void:
	_clear_hold()


func _clear_hold() -> void:
	held = null
	held_rot = 0
	grab_offset = Vector2i.ZERO
	_press_active = false
	_moved = false
	_selection_update()


func _on_inventory_changed() -> void:
	if held != null and Inventory._index_of(held) == -1:
		_clear_hold()
	_selection_update()


# =================================================================== input

func _gui_input(event: InputEvent) -> void:
	if locked:
		return

	if event is InputEventMouseMotion:
		var c := _cell_from_pos(event.position)
		if c != cursor:
			cursor = c
			if _press_active and c != _press_cell:
				_moved = true
			_selection_update()
		accept_event()
		return

	if event is InputEventMouseButton:
		var c := _cell_from_pos(event.position)
		cursor = c
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_primary_press(c)
			else:
				_on_primary_release(c)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if held != null:
				_clear_hold()
			else:
				var e = Inventory.entry_at(c.x, c.y)
				if e != null:
					menu_requested.emit(e)
		_selection_update()
		accept_event()
		return

	if event.is_action_pressed("ui_left", true):
		_move_cursor(Vector2i(-1, 0))
	elif event.is_action_pressed("ui_right", true):
		_move_cursor(Vector2i(1, 0))
	elif event.is_action_pressed("ui_up", true):
		_move_cursor(Vector2i(0, -1))
	elif event.is_action_pressed("ui_down", true):
		_move_cursor(Vector2i(0, 1))
	elif event.is_action_pressed("ui_accept"):
		_on_accept()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
		rotate_item()
	else:
		return
	accept_event()


func _cell_from_pos(p: Vector2) -> Vector2i:
	return Vector2i(
		clampi(int(p.x / CELL), 0, Inventory.cols - 1),
		clampi(int(p.y / CELL), 0, Inventory.rows - 1))


func _move_cursor(d: Vector2i) -> void:
	cursor = Vector2i(
		clampi(cursor.x + d.x, 0, Inventory.cols - 1),
		clampi(cursor.y + d.y, 0, Inventory.rows - 1))
	_selection_update()


func _on_primary_press(c: Vector2i) -> void:
	if held != null:                       # mode "pegang" (dari MOVE / Enter)
		_try_drop(false)
		return
	var e = Inventory.entry_at(c.x, c.y)
	if e == null:
		return
	held = e
	held_rot = e["rot"]
	grab_offset = c - Vector2i(e["x"], e["y"])
	_press_active = true
	_press_cell = c
	_moved = false


func _on_primary_release(c: Vector2i) -> void:
	if not _press_active:
		return
	_press_active = false
	if not _moved and c == _press_cell:    # klik biasa tanpa geser -> buka menu
		var e = held
		_clear_hold()
		menu_requested.emit(e)
	else:
		_try_drop(true)


func _on_accept() -> void:
	if held != null:
		_try_drop(false)
	else:
		var e = Inventory.entry_at(cursor.x, cursor.y)
		if e != null:
			menu_requested.emit(e)


func rotate_item() -> void:
	if held != null:
		var d: ItemData = held["data"]
		if Inventory.can_rotate(d):
			held_rot = Inventory.next_rot(d, held_rot)
			_moved = true
		return
	var e = Inventory.entry_at(cursor.x, cursor.y)
	if e == null:
		return
	var item: ItemData = e["data"]
	if not Inventory.can_rotate(item):
		return
	if not Inventory.move_entry(e, e["x"], e["y"], Inventory.next_rot(item, e["rot"])):
		notice.emit("Tidak muat kalau diputar")


# =================================================================== taruh

func _anchor() -> Vector2i:
	if held == null:
		return cursor
	var s: Vector2i = Inventory.footprint(held["data"], held_rot)
	var a := cursor - grab_offset
	a.x = clampi(a.x, 0, maxi(Inventory.cols - s.x, 0))
	a.y = clampi(a.y, 0, maxi(Inventory.rows - s.y, 0))
	return a


func _drop_state() -> String:
	if held == null:
		return ""
	var target = Inventory.entry_at(cursor.x, cursor.y)
	if target != null and not is_same(target, held) \
			and target["data"].id == held["data"].id and held["data"].stackable \
			and target["amount"] < target["data"].max_stack:
		return "merge"
	var a := _anchor()
	if Inventory.can_place(held["data"], a.x, a.y, held_rot, held):
		return "place"
	return "invalid"


func _try_drop(revert_on_fail: bool) -> void:
	var e = held
	match _drop_state():
		"merge":
			var target = Inventory.entry_at(cursor.x, cursor.y)
			Inventory.merge_entries(e, target)
			_clear_hold()
		"place":
			var a := _anchor()
			Inventory.move_entry(e, a.x, a.y, held_rot)
			_clear_hold()
		_:
			notice.emit("Tidak muat di sini")
			if revert_on_fail:
				_clear_hold()


func _same(a, b) -> bool:
	if a == null or b == null:
		return a == null and b == null
	return is_same(a, b)


func _selection_update() -> void:
	var e = current_entry()
	if _same(e, _last_selected):
		return
	_last_selected = e
	selection_changed.emit(e)


# =================================================================== gambar

func _entry_rect(e: Dictionary) -> Rect2:
	var r: Rect2i = Inventory.rect_of(e)
	return Rect2(Vector2(r.position) * CELL, Vector2(r.size) * CELL)


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


func _draw() -> void:
	var cols: int = Inventory.cols
	var rows: int = Inventory.rows
	draw_rect(Rect2(Vector2.ZERO, Vector2(cols, rows) * CELL), COL_CELL)
	for x in range(cols + 1):
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, rows * CELL), COL_GRID, 1.0)
	for y in range(rows + 1):
		draw_line(Vector2(0, y * CELL), Vector2(cols * CELL, y * CELL), COL_GRID, 1.0)

	var full := Rect2(Vector2.ZERO, Vector2(cols, rows) * CELL)
	draw_rect(full, Color(COL_BORDER, 0.55), false, 1.0)
	_brackets(full.grow(4.0), Color(COL_ACCENT, 0.9), 16.0, 2.0)          # siku di empat sudut grid

	for e in Inventory.entries:
		var faded: bool = held != null and is_same(e, held)
		_draw_entry(e, _entry_rect(e), 0.25 if faded else 1.0, e["rot"])

	var pulse := 0.65 + 0.35 * sin(Time.get_ticks_msec() / 160.0)
	if held == null:
		var hover = Inventory.entry_at(cursor.x, cursor.y)
		if hover != null and Inventory.is_shaped(hover["data"]):
			_outline_cells(Vector2(hover["x"], hover["y"]) * CELL, Inventory.cells_of(hover["data"], hover["rot"]),
					Color(COL_ACCENT, pulse), 2.0)
		else:
			var r := Rect2(Vector2(cursor) * CELL, Vector2(CELL, CELL))
			if hover != null:
				r = _entry_rect(hover)
			draw_rect(r.grow(-1), Color(COL_ACCENT, 0.07 + 0.05 * pulse))
			draw_rect(r.grow(-1), Color(COL_ACCENT, 0.45), false, 1.0)
			_brackets(r.grow(-1), Color(COL_ACCENT, pulse), 11.0, 2.5)
	else:
		var a := _anchor()
		var s: Vector2i = Inventory.footprint(held["data"], held_rot)
		var rr := Rect2(Vector2(a) * CELL, Vector2(s) * CELL)
		var tint := COL_GOOD
		match _drop_state():
			"invalid":
				tint = COL_BAD
			"merge":
				tint = COL_ACCENT
		var hd: ItemData = held["data"]
		if Inventory.is_shaped(hd):
			var cells: Array = Inventory.cells_of(hd, held_rot)
			for c in cells:
				draw_rect(Rect2(rr.position + Vector2(c) * CELL, Vector2(CELL, CELL)), Color(tint, 0.28))
			_draw_entry(held, rr, 0.9, held_rot)
			_outline_cells(rr.position, cells, Color(tint, pulse), 2.0)
		else:
			draw_rect(rr, Color(tint, 0.28))
			_draw_entry(held, rr, 0.9, held_rot)
			draw_rect(rr.grow(-1), Color(tint, pulse), false, 2.0)


## Empat siku sudut (target bracket) di sekeliling sebuah kotak.
func _brackets(r: Rect2, col: Color, l: float, w: float) -> void:
	var tl := r.position
	var tr_ := Vector2(r.end.x, r.position.y)
	var bl := Vector2(r.position.x, r.end.y)
	var br := r.end
	draw_line(tl, tl + Vector2(l, 0), col, w)
	draw_line(tl, tl + Vector2(0, l), col, w)
	draw_line(tr_, tr_ + Vector2(-l, 0), col, w)
	draw_line(tr_, tr_ + Vector2(0, l), col, w)
	draw_line(bl, bl + Vector2(l, 0), col, w)
	draw_line(bl, bl + Vector2(0, -l), col, w)
	draw_line(br, br + Vector2(-l, 0), col, w)
	draw_line(br, br + Vector2(0, -l), col, w)


## Garis tepi luar sebuah bentuk (hanya sisi yang tidak bersebelahan dengan kotak lain milik bentuk itu)
func _outline_cells(origin: Vector2, cells: Array, col: Color, w: float) -> void:
	var occ := {}
	for c in cells:
		occ[c] = true
	for c in cells:
		var p: Vector2 = origin + Vector2(c) * CELL
		if not occ.has(c + Vector2i(0, -1)):
			draw_line(p, p + Vector2(CELL, 0), col, w)
		if not occ.has(c + Vector2i(0, 1)):
			draw_line(p + Vector2(0, CELL), p + Vector2(CELL, CELL), col, w)
		if not occ.has(c + Vector2i(-1, 0)):
			draw_line(p, p + Vector2(0, CELL), col, w)
		if not occ.has(c + Vector2i(1, 0)):
			draw_line(p + Vector2(CELL, 0), p + Vector2(CELL, CELL), col, w)


func _draw_entry(e: Dictionary, rect: Rect2, alpha: float, rot: int) -> void:
	var item: ItemData = e["data"]
	var has_icon := item.icon != null
	var fill := Color(_type_color(item.type), (0.5 if has_icon else 0.92) * alpha)    # item bergambar: latar tipis supaya grid kelihatan
	var border := Color(COL_BORDER, alpha)
	var inner := rect.grow(-2)                             # area untuk nama / ikon / angka
	if Inventory.is_shaped(item):
		inner = _draw_shape(item, rect, rot, fill, border)
	else:
		draw_rect(inner, fill)
		draw_rect(inner, border, false, 2.0)
	if has_icon:                                           # garis kotak di dalam item = ukuran visualnya
		for c in Inventory.cells_of(item, rot):
			var cell := Rect2(rect.position + Vector2(c) * CELL, Vector2(CELL, CELL)).grow(-1.0)
			draw_rect(cell, Color(COL_BORDER, 0.4 * alpha), false, 1.0)
	var font := get_theme_default_font()
	var odd := posmod(rot, 2) == 1

	if item.icon != null:
		var tex: Texture2D = item.icon
		var tsz := tex.get_size()
		var area := rect.grow(-2)                          # kotak pembatas seluruh item (juga untuk bentuk L / T)
		var fit := area.size - Vector2(4, 4)
		if odd:
			fit = Vector2(fit.y, fit.x)
		var sc := maxf(1.0, floorf(minf(fit.x / tsz.x, fit.y / tsz.y)))
		var dsz := tsz * sc
		draw_set_transform(area.get_center(), float(posmod(rot, 4)) * PI / 2.0, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-dsz / 2.0, dsz), false, Color(1, 1, 1, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_multiline_string(font, inner.position + Vector2(6, 18), item.display_name,
			HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 12, 14, -1, Color(COL_TEXT, alpha))

	var label := ""
	if item.type == ItemData.Type.AMMO:
		label = str(e.get("rounds", item.mag_rounds))          # isi magazine
	elif e["amount"] > 1:
		label = "x%d" % e["amount"]
	if label != "":
		var txt := label
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		draw_string(font, Vector2(inner.end.x - w - 5, inner.end.y - 6), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(COL_ACCENT, alpha))


## Gambar item berbentuk khusus (L, T, ...) kotak demi kotak, bingkai hanya di tepi luar.
## Mengembalikan area baris terlebar untuk tempat nama / ikon.
func _draw_shape(item: ItemData, rect: Rect2, rot: int, fill: Color, border: Color) -> Rect2:
	var cells: Array = Inventory.cells_of(item, rot)
	var occ := {}
	for c in cells:
		occ[c] = true
	for c in cells:
		var top: bool = not occ.has(c + Vector2i(0, -1))
		var bottom: bool = not occ.has(c + Vector2i(0, 1))
		var left: bool = not occ.has(c + Vector2i(-1, 0))
		var right: bool = not occ.has(c + Vector2i(1, 0))
		var cr := Rect2(rect.position + Vector2(c) * CELL, Vector2(CELL, CELL))
		var fr := Rect2(cr.position + Vector2(2.0 if left else 0.0, 2.0 if top else 0.0),
				cr.size - Vector2((2.0 if left else 0.0) + (2.0 if right else 0.0), (2.0 if top else 0.0) + (2.0 if bottom else 0.0)))
		draw_rect(fr, fill)
		if top:
			draw_rect(Rect2(fr.position, Vector2(fr.size.x, 2.0)), border)
		if bottom:
			draw_rect(Rect2(fr.position.x, fr.end.y - 2.0, fr.size.x, 2.0), border)
		if left:
			draw_rect(Rect2(fr.position, Vector2(2.0, fr.size.y)), border)
		if right:
			draw_rect(Rect2(fr.end.x - 2.0, fr.position.y, 2.0, fr.size.y), border)
	# baris terlebar (untuk teks)
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
	return Rect2(rect.position + Vector2(min_x, best_y) * CELL, Vector2(best_n * CELL, CELL)).grow(-2)
