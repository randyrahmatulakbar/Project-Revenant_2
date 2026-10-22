extends CanvasLayer
## Menu daftar loot: pilih barang yang mau diambil (atau TAKE ALL). Game dijeda selama menu terbuka.
## Kontrol: mouse klik, atau panah atas/bawah + Enter / tombol interact. Esc / tombol interact di luar daftar = tutup.

const ItemDB = preload("res://item_db.gd")

signal closed(drop: Node)

var _drop: Node
var _inv: Node
var _list: VBoxContainer
var _prev_mouse := Input.MOUSE_MODE_CAPTURED
var _font: Font
var _msg: Label
var _was_paused := false


func open(drop: Node, inv: Node) -> void:
	_drop = drop
	_inv = inv
	layer = 70
	process_mode = Node.PROCESS_MODE_ALWAYS
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_font = load("res://font/Rajdhani-Bold.ttf")
	_was_paused = get_tree().paused
	get_tree().paused = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_refresh()


func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.028, 0.028, 0.97)
	sb.border_color = Color(0.55, 0.08, 0.08)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "LOOT"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.2, 0.15))
	_style(title)
	vb.add_child(title)
	vb.add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	vb.add_child(_list)
	_msg = Label.new()
	_msg.add_theme_font_size_override("font_size", 15)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	_style(_msg)
	vb.add_child(_msg)
	var hint := Label.new()
	hint.text = "Atas / Bawah: pilih   |   Enter / klik: ambil   |   Esc: tutup"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.55))
	_style(hint)
	vb.add_child(hint)


func _style(c: Control) -> void:
	if _font:
		c.add_theme_font_override("font", _font)


func _row_style(border: Color, bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_content_margin_all(10)
	return s


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var items: Array = _drop.items
	if items.is_empty():
		close()
		return
	var first: Button = null
	for i in items.size():
		var it: Dictionary = items[i]
		var d := ItemDB.get_item(it.id)
		var fits: bool = _inv.can_fit(it.id)
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sz := _size_text(d)
		var amt := ("  x%d" % it.amount) if int(it.amount) > 1 else ""
		b.text = "%s%s      [%s]%s" % [d.name, amt, sz, "" if fits else "      TIDAK MUAT"]
		b.add_theme_font_size_override("font_size", 20)
		_style(b)
		var col: Color = d.color
		b.add_theme_color_override("font_color", col if fits else Color(0.45, 0.4, 0.4))
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _row_style(col.darkened(0.6), Color(0.07, 0.055, 0.055)))
		b.add_theme_stylebox_override("hover", _row_style(col, Color(0.12, 0.08, 0.08)))
		b.add_theme_stylebox_override("focus", _row_style(col, Color(0.12, 0.08, 0.08)))
		b.add_theme_stylebox_override("pressed", _row_style(col, Color(0.18, 0.1, 0.1)))
		b.tooltip_text = d.desc
		b.pressed.connect(_take_one.bind(i))
		_list.add_child(b)
		if first == null:
			first = b
	if items.size() > 1:
		var all := Button.new()
		all.text = "TAKE ALL"
		all.add_theme_font_size_override("font_size", 20)
		_style(all)
		all.add_theme_color_override("font_color", Color(0.95, 0.85, 0.7))
		all.add_theme_stylebox_override("normal", _row_style(Color(0.5, 0.2, 0.15), Color(0.1, 0.05, 0.05)))
		all.add_theme_stylebox_override("hover", _row_style(Color(0.95, 0.3, 0.2), Color(0.18, 0.07, 0.07)))
		all.add_theme_stylebox_override("focus", _row_style(Color(0.95, 0.3, 0.2), Color(0.18, 0.07, 0.07)))
		all.pressed.connect(_take_all)
		_list.add_child(all)
	if first:
		first.call_deferred("grab_focus")


func _size_text(d: Dictionary) -> String:
	var mx := 0
	var my := 0
	for c in d.cells:
		mx = maxi(mx, c.x + 1)
		my = maxi(my, c.y + 1)
	var n: int = d.cells.size()
	return ("%dx%d" % [mx, my]) if mx * my == n else ("%d kotak" % n)


func _take_one(i: int) -> void:
	if i < 0 or i >= _drop.items.size():
		return
	var it: Dictionary = _drop.items[i]
	var left: int = _inv.add_item(it.id, int(it.amount))
	if left >= int(it.amount):
		_msg.text = "Tidak muat di inventory."
		return
	_msg.text = ""
	if left <= 0:
		_drop.items.remove_at(i)
	else:
		it.amount = left
	_refresh()


func _take_all() -> void:
	var i := 0
	var any := false
	while i < _drop.items.size():
		var it: Dictionary = _drop.items[i]
		var left: int = _inv.add_item(it.id, int(it.amount))
		if left < int(it.amount):
			any = true
		if left <= 0:
			_drop.items.remove_at(i)
		else:
			it.amount = left
			i += 1
	_msg.text = "" if any or _drop.items.is_empty() else "Tidak ada yang muat."
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("interact") and event.is_action_pressed("interact"):
		var f := get_viewport().gui_get_focus_owner()
		if f is Button:
			(f as Button).pressed.emit()
		get_viewport().set_input_as_handled()


func close() -> void:
	if not is_inside_tree():
		return
	get_tree().paused = _was_paused
	Input.mouse_mode = _prev_mouse
	closed.emit(_drop)
	queue_free()
