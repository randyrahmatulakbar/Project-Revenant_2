extends Control

@export var font: Font              # kosongin = font bawaan, isi font pixel kamu biar nyatu
@export var clip_size: int = 6      # samain dengan max_ammo_per_clip di player
@export var margin := Vector2(28, 28)

const SLANT := 10.0
const COL_PANEL := Color("1c2422")
const COL_BORDER := Color("7b5e4c")
const COL_ACCENT := Color("dba98c")
const COL_TEXT := Color("e9dcc8")
const COL_DIM := Color("4a403a")
const COL_TRACK := Color("0f1514")
const COL_HP := Color("b83b2a")
const COL_HP_HOT := Color("ee6a48")

# health
var _hp := 100
var _hp_target := 1.0
var _hp_fill := 1.0
var _hp_trail := 1.0
var _trail_delay := 0.0
var _hp_flash := 0.0
var _hp_shake := 0.0
var _hp_ready := false

# ammo
var _ammo := 0
var _reserve := 0
var _ammo_ready := false
var _ammo_flash := 0.0
var _flash_from := 0
var _flash_to := 0
var _ammo_punch := 0.0

var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func update_health(current: int, max_hp: int) -> void:
	var new_target := clampf(float(current) / maxf(float(max_hp), 1.0), 0.0, 1.0)
	if not _hp_ready:
		_hp_ready = true
		_hp_fill = new_target
		_hp_trail = new_target
	elif current < _hp:
		_trail_delay = 0.45
		_hp_flash = 1.0
		_hp_shake = 1.0
	_hp = current
	_hp_target = new_target


func update_ammo(current: int, reserve: int) -> void:
	clip_size = maxi(clip_size, current)
	if _ammo_ready:
		if current < _ammo:
			_flash_from = current
			_flash_to = _ammo
			_ammo_flash = 1.0
			_ammo_punch = 1.0
		elif current > _ammo:
			_flash_from = _ammo
			_flash_to = current
			_ammo_flash = 1.0
			_ammo_punch = 0.6
	_ammo_ready = true
	_ammo = current
	_reserve = reserve


func _process(delta: float) -> void:
	_time += delta
	_hp_fill = lerpf(_hp_fill, _hp_target, 1.0 - exp(-delta * 18.0))
	if _trail_delay > 0.0:
		_trail_delay -= delta
	else:
		_hp_trail = move_toward(_hp_trail, _hp_fill, delta * 0.5)
	_hp_trail = maxf(_hp_trail, _hp_fill)
	_hp_flash = move_toward(_hp_flash, 0.0, delta * 3.5)
	_hp_shake = move_toward(_hp_shake, 0.0, delta * 4.0)
	_ammo_flash = move_toward(_ammo_flash, 0.0, delta * 3.0)
	_ammo_punch = move_toward(_ammo_punch, 0.0, delta * 5.0)
	queue_redraw()


func _para(x: float, y: float, w: float, h: float, sl: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x + sl, y), Vector2(x + w + sl, y),
		Vector2(x + w, y + h), Vector2(x, y + h)
	])


func _panel(sz: Vector2, border: Color, accent: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(SLANT, 0), Vector2(sz.x, 0),
		Vector2(sz.x - SLANT, sz.y), Vector2(0, sz.y)
	])
	draw_colored_polygon(pts, Color(COL_PANEL, 0.88))
	var outline := PackedVector2Array(pts)
	outline.append(pts[0])
	draw_polyline(outline, border, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(SLANT, 0), Vector2(SLANT + 7, 0),
		Vector2(7, sz.y), Vector2(0, sz.y)
	]), accent)


func _draw() -> void:
	var f: Font = font if font else ThemeDB.fallback_font
	_draw_health(f)
	_draw_ammo(f)


func _draw_health(f: Font) -> void:
	var sz := Vector2(320, 64)
	var origin := Vector2(margin.x, size.y - margin.y - sz.y)
	origin += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 4.0 * _hp_shake
	draw_set_transform(origin)

	var low := _hp_target <= 0.25
	var pulse := 0.5 + 0.5 * sin(_time * 8.0)
	var border := COL_BORDER.lerp(Color.WHITE, _hp_flash)
	var accent := COL_ACCENT.lerp(Color.WHITE, _hp_flash)
	if low:
		border = border.lerp(COL_HP_HOT, pulse * 0.7)

	_panel(sz, border, accent)

	draw_string(f, Vector2(24, 22), "HP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)
	var num_col := COL_TEXT
	if low:
		num_col = COL_TEXT.lerp(COL_HP_HOT, pulse)
	draw_string(f, Vector2(24, sz.y - 12), str(_hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, num_col)

	var bx := 92.0
	var by := 20.0
	var bw := sz.x - bx - 26.0
	var bh := 24.0
	var sl := 7.0

	var track := _para(bx, by, bw, bh, sl)
	draw_colored_polygon(track, COL_TRACK)

	if _hp_trail > 0.001:
		draw_colored_polygon(_para(bx, by, bw * _hp_trail, bh, sl), COL_ACCENT)

	if _hp_fill > 0.001:
		var fill_col := COL_HP
		if low:
			fill_col = fill_col.lerp(COL_HP_HOT, pulse * 0.6)
		fill_col = fill_col.lerp(Color.WHITE, _hp_flash * 0.5)
		draw_colored_polygon(_para(bx, by, bw * _hp_fill, bh, sl), fill_col)

	for i in range(1, 4):
		var x := bx + bw * i / 4.0
		draw_line(Vector2(x + sl, by), Vector2(x, by + bh), COL_TRACK, 2.0)

	var tout := PackedVector2Array(track)
	tout.append(track[0])
	draw_polyline(tout, COL_BORDER, 1.5)


func _draw_ammo(f: Font) -> void:
	var sz := Vector2(260, 64)
	var origin := Vector2(size.x - margin.x - sz.x, size.y - margin.y - sz.y)
	draw_set_transform(origin)

	var empty := _ammo <= 0
	var blink := 0.5 + 0.5 * sin(_time * 10.0)
	var border := COL_BORDER.lerp(Color.WHITE, _ammo_flash * 0.8)
	var accent := COL_ACCENT.lerp(Color.WHITE, _ammo_flash)
	if empty:
		border = border.lerp(COL_HP_HOT, blink * 0.7)

	_panel(sz, border, accent)

	draw_string(f, Vector2(24, 22), "AMMO", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, accent)

	# angka magazen (mentul pas berubah)
	var num_col := COL_TEXT
	if empty:
		num_col = COL_TEXT.lerp(COL_HP_HOT, blink)
	var scl := 1.0 + 0.3 * _ammo_punch
	draw_set_transform(origin + Vector2(24, sz.y - 12), 0.0, Vector2(scl, scl))
	var cur_txt := str(_ammo)
	draw_string(f, Vector2.ZERO, cur_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, num_col)
	draw_set_transform(origin)

	# cadangan
	var cw := f.get_string_size(cur_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	var res_col := COL_TEXT.darkened(0.4)
	if _reserve <= 0:
		res_col = COL_HP
	draw_string(f, Vector2(24 + cw + 6, sz.y - 14), "/ %d" % _reserve,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, res_col)

	# kotak peluru
	var step := minf(16.0, 112.0 / float(maxi(clip_size, 1)))
	var pw := step * 0.62
	var ph := 28.0
	var px0 := sz.x - 24.0 - step * clip_size
	var py := (sz.y - ph) * 0.5
	for i in clip_size:
		var col := COL_ACCENT if i < _ammo else COL_DIM
		if i >= _flash_from and i < _flash_to:
			col = col.lerp(Color.WHITE, _ammo_flash)
		draw_colored_polygon(_para(px0 + i * step, py, pw, ph, 4.0), col)
