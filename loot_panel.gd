extends PanelContainer
## Daftar loot kecil di sisi kanan layar (muncul otomatis saat dekat tumpukan loot, game TIDAK dijeda).
## Dikendalikan LootManager (refresh dipanggil tiap frame, tapi tampilan hanya dibangun ulang kalau isinya berubah). Tiap kotak: ikon bentuk grid item, nama, jumlah + ukuran.

const ItemDB = preload("res://item_db.gd")


## Ikon kecil: bentuk item di grid (kotak-kotak), jadi L dan T kelihatan bentuknya
class Icon extends Control:
	var cells: Array = []
	var col := Color.WHITE

	func _init(c: Array, color: Color) -> void:
		cells = c
		col = color
		custom_minimum_size = Vector2(30, 30)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var mx := 1
		var my := 1
		for c in cells:
			mx = maxi(mx, c.x + 1)
			my = maxi(my, c.y + 1)
		var cs := clampi(int(25.0 / float(maxi(mx, my))), 4, 10)
		var off := (size - Vector2(mx, my) * float(cs)) * 0.5
		for c in cells:
			var r := Rect2(off + Vector2(c.x, c.y) * float(cs), Vector2(cs - 1, cs - 1))
			draw_rect(r, col.darkened(0.45))
			draw_rect(r, col, false, 1.0)


## Posisi TETAP (titik kiri-atas panel dikunci ke persentase layar), lebar tetap, satu kolom.
## Kalau barangnya banyak, yang tampil cuma max_rows sekaligus dan daftar bergulir mengikuti pilihan.
var anchor_x := 0.60             # posisi kiri panel, 0..1 dari lebar layar (makin kecil = makin ke tengah)
var anchor_y := 0.40             # posisi atas panel, 0..1 dari tinggi layar
var panel_width := 190.0
var max_rows := 5

var _inv: Node
var _box: VBoxContainer
var _grid: VBoxContainer
var _up: Label
var _dn: Label
var _hint: Label
var _bar: ColorRect
var _bar_back: Control
var _msg: Label
var _font: Font
var _key := "E"
var _msg_t := 0.0
var _isig := ""
var _start := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_font = load("res://font/Rajdhani-Bold.ttf")
	custom_minimum_size = Vector2(panel_width, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 3)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_up = _small("", Color(0.75, 0.7, 0.65, 0.8))
	_box.add_child(_up)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", 3)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_grid)
	_dn = _small("", Color(0.75, 0.7, 0.65, 0.8))
	_box.add_child(_dn)
	_msg = _small("", Color(1.0, 0.4, 0.3))
	_box.add_child(_msg)
	_hint = _small("", Color(0.78, 0.74, 0.7, 0.85))
	_hint.custom_minimum_size = Vector2(panel_width, 28)
	_box.add_child(_hint)
	_bar_back = Control.new()
	_bar_back.custom_minimum_size = Vector2(0, 3)
	_bar_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_bar_back)
	_bar = ColorRect.new()
	_bar.color = Color(0.95, 0.3, 0.2)
	_bar.size = Vector2(0, 3)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_back.add_child(_bar)


func _small(t: String, col: Color) -> Label:
	var l := _label(t, 12, col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true                                  # teks panjang tidak boleh melebarkan panel
	l.custom_minimum_size = Vector2(panel_width, 14)
	return l


func _label(t: String, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font:
		l.add_theme_font_override("font", _font)
	return l


func _process(delta: float) -> void:
	var vp := get_viewport_rect().size
	position = Vector2(vp.x * anchor_x, vp.y * anchor_y)    # titik kiri-atas selalu sama
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0 and _msg:
			_msg.text = ""


func set_keys(k: String) -> void:
	_key = k
	_isig = ""


func set_hold(f: float) -> void:
	if _bar_back:
		_bar.size = Vector2(_bar_back.size.x * clampf(f, 0.0, 1.0), 3)


func flash(text: String) -> void:
	if _msg:
		_msg.text = text.to_upper()
		_msg_t = 1.4


func refresh(items: Array, inv: Node, sel: int) -> void:
	if _grid == null:
		return
	_inv = inv
	var fits_list: Array = []
	var sig := str(sel) + "|"
	for it in items:
		var f: bool = inv.can_fit(it.id) if inv else true
		fits_list.append(f)
		sig += "%s:%d:%s," % [it.id, it.amount, str(f)]
	if sig == _isig:
		return
	_isig = sig
	var n := items.size()
	if sel < _start:
		_start = sel
	elif sel >= _start + max_rows:
		_start = sel - max_rows + 1
	_start = clampi(_start, 0, maxi(n - max_rows, 0))
	_rebuild(items, fits_list, sel)


func _rebuild(items: Array, fits_list: Array, sel: int) -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var n := items.size()
	var last := mini(n, _start + max_rows)
	for i in range(_start, last):
		var it: Dictionary = items[i]
		var d := ItemDB.get_item(it.id)
		var fits: bool = fits_list[i]
		var on := i == sel
		var col: Color = d.color if fits else Color(0.4, 0.37, 0.37)
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(panel_width, 40)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_theme_stylebox_override("panel", _tile_style(col, on))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(hb)
		hb.add_child(Icon.new(d.cells, col))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -4)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)
		var nm := _label(str(d.name).to_upper(), 13, Color(0.96, 0.94, 0.9) if fits else Color(0.5, 0.46, 0.46))
		nm.clip_text = true
		vb.add_child(nm)
		var amt := ("x%d   " % it.amount) if int(it.amount) > 1 else ""
		vb.add_child(_label(("%s%s" % [amt, _size_text(d)]) if fits else "TIDAK MUAT", 10,
				Color(0.65, 0.6, 0.58) if fits else Color(1.0, 0.4, 0.3)))
		_grid.add_child(p)
	_up.text = ("+ %d LAGI" % _start) if _start > 0 else ""
	_dn.text = ("+ %d LAGI" % (n - last)) if last < n else ""
	_hint.text = ("[%s] AMBIL   TAHAN [%s]: SEMUA\nSCROLL: PILIH   %d / %d" % [_key, _key, sel + 1, n]) if n > 1 else ("[%s] AMBIL" % _key)
	call_deferred("reset_size")


func _tile_style(col: Color, on: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.1, 0.07, 0.07, 0.92) if on else Color(0.04, 0.035, 0.035, 0.82)
	s.border_color = col if on else col.darkened(0.65)
	s.set_border_width_all(2 if on else 1)
	s.border_width_left = 5 if on else 3
	s.set_content_margin_all(4)
	return s


func _size_text(d: Dictionary) -> String:
	var mx := 0
	var my := 0
	for c in d.cells:
		mx = maxi(mx, c.x + 1)
		my = maxi(my, c.y + 1)
	var n: int = d.cells.size()
	return ("%dx%d" % [mx, my]) if mx * my == n else ("%d kotak" % n)
