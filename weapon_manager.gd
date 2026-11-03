extends CanvasLayer
## WEAPON MANAGER: strip UI senjata di bawah layar + pergantian senjata.
##   - Revolver selalu ada. MP5 / Shotgun baru muncul setelah itemnya ada di Inventory (id "mp5" / "shotgun").
##   - Ganti senjata: tombol 1 / 2 / 3 atau scroll mouse. Ditolak saat reload / nembak / charge shot / inventory terbuka.
##   - Tiap senjata ingat sisa peluru di magazine-nya sendiri.
## Dipasang otomatis oleh player-test.gd (anak dari player). Taruh file ini di res://, sama seperti charge_shot.gd.
##
## Sprite: kalau ada res://tangan/mp5_frames.tres atau res://tangan/shotgun_frames.tres (SpriteFrames dengan animasi
## idle / walk / sprint / shoot / reload seperti revolver), otomatis dipakai. Kalau belum ada, sprite revolver
## dipakai sementara dengan warna berbeda (placeholder).

signal weapon_changed(id: StringName)

const COL_BG := Color(0.07, 0.10, 0.11, 0.92)
const COL_EDGE := Color(0.87, 0.65, 0.54)
const COL_CREAM := Color(0.92, 0.86, 0.8)
const COL_DARK := Color(0.07, 0.10, 0.11)

@export var start_loaded := true           # senjata baru didapat langsung terisi penuh magazine-nya
@export var wheel_switch := true           # scroll mouse untuk ganti senjata
@export var bottom_margin := 26.0          # jarak strip dari tepi bawah layar
@export var slot_width := 126.0            # lebar tiap slot (3 slot harus muat di antara panel HP dan panel AMMO)
@export var shift_x := 24.0                # geser strip ke kanan (+) / kiri (-) dari tengah layar
@export var draw_down := 260.0             # senjata turun sejauh ini (piksel) saat ganti
@export var draw_time_out := 0.10
@export var draw_time_in := 0.18

## key = tombol angka. mag = isi magazine. tint = warna placeholder sprite (putih = apa adanya).
## Revolver memakai sistem tembak lama di player (charge shot, dll), angka tembaknya tidak dipakai.
## interval = jeda antar tembakan (detik). auto = tahan tombol untuk terus menembak. pellets = jumlah peluru per tembakan.
## spread_deg = sebaran peluru (derajat). damage_mult = pengali dari gun_damage player (jadi Parry Sigil tetap berpengaruh).
## recoil_px / recoil_fov = hentakan sprite senjata dan FOV tiap tembakan.
const WEAPONS := [
	{"id": &"revolver", "name": "REVOLVER", "item": &"", "key": 1, "ammo_type": &"pistol", "mag": 6,
		"tint": Color(1, 1, 1), "interval": 0.5, "auto": false, "pellets": 1, "spread_deg": 0.0,
		"damage_mult": 1.0, "recoil_px": 0.0, "recoil_fov": 0.0},
	{"id": &"mp5", "name": "MP5", "item": &"mp5", "key": 2, "ammo_type": &"smg", "mag": 30,
		"tint": Color(0.75, 0.9, 1.0), "interval": 0.09, "auto": true, "pellets": 1, "spread_deg": 1.2,
		"damage_mult": 0.4, "recoil_px": 10.0, "recoil_fov": 0.6},
	{"id": &"shotgun", "name": "SHOTGUN", "item": &"shotgun", "key": 3, "ammo_type": &"shotgun", "mag": 8,
		"tint": Color(1.0, 0.82, 0.65), "interval": 0.85, "auto": false, "pellets": 8, "spread_deg": 4.5,
		"damage_mult": 0.6, "recoil_px": 34.0, "recoil_fov": 3.0},
]

var current: StringName = &"revolver"
var _owned: Array = [&"revolver"]
var _mags := {}                    # id -> sisa peluru di magazine saat senjata disimpan
var _player
var _hud
var _root: Control
var _row: HBoxContainer
var _slots := {}                   # id -> Slot
var _font: Font
var _base_frames: SpriteFrames
var _switching := false
var _announce := false
var _recoil_tw: Tween
var _sync_t := 0.0
var _stats_warned := false


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS               # tetap jalan saat game dijeda, supaya strip bisa disembunyikan di menu pause
	_player = get_parent()
	_get_hud()
	_font = load("res://font/Rajdhani-Bold.ttf") if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf") else ThemeDB.fallback_font

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 2)
	_row.anchor_left = 0.5
	_row.anchor_right = 0.5
	_row.anchor_top = 1.0
	_row.anchor_bottom = 1.0
	_row.offset_bottom = -bottom_margin
	_row.offset_left = shift_x
	_row.offset_right = shift_x
	_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_child(_row)

	print("[weapon_manager] aktif | slot_width=", slot_width, " shift_x=", shift_x)    # cek file yang jalan itu versi terbaru
	Inventory.inventory_changed.connect(_on_inventory_changed)
	_refresh_owned()
	_set_stats_max.call_deferred(int(_player.max_ammo_per_clip))
	_announce = true                                   # pengumuman "didapat" hanya untuk yang datang belakangan


func _get_hud():
	if _hud == null or not is_instance_valid(_hud):
		_hud = get_tree().get_first_node_in_group("hud")
		if _hud != null and "gun" in _hud and _hud.gun != null and _base_frames == null:
			_base_frames = _hud.gun.sprite_frames
	return _hud


# ---------------------------------------------------------------- API untuk player

func is_revolver() -> bool:
	return current == &"revolver"


func is_auto() -> bool:
	return bool(_def(current).auto)


func active_def() -> Dictionary:
	return _def(current)


# Hentakan sprite senjata + FOV + suara. Dipanggil player tiap MP5 / Shotgun menembak.
func fire_fx(d: Dictionary) -> void:
	get_tree().call_group("sfx", "play", "gun_shot", 1.0 if d.pellets > 1 else -4.0, 0.06)
	var hud = _get_hud()
	if hud != null and hud.gun != null and not _switching:
		var gun: AnimatedSprite2D = hud.gun
		if _recoil_tw != null and _recoil_tw.is_valid():
			_recoil_tw.kill()
		var base: Vector2 = gun.get_meta("base_pos", gun.position)
		gun.set_meta("base_pos", base)
		gun.position = base + Vector2(0, float(d.recoil_px))
		_recoil_tw = create_tween()
		_recoil_tw.tween_property(gun, "position", base, minf(float(d.interval) * 0.9, 0.22)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _player != null and _player.camera != null:
		_player.camera.fov -= float(d.recoil_fov)


# Cadangan peluru senjata aktif. Revolver = player.reserve_ammo (diurus sistem lama, tidak disentuh di sini).
# MP5 / Shotgun = semua magazine bertipe itu di Inventory (player.reserve_ammo TIDAK diubah, supaya cadangan revolver aman).
func reserve_now() -> int:
	if is_revolver() or _player == null:
		return _player.reserve_ammo if _player != null else 0
	return Inventory.count_rounds(_def(current).ammo_type)


# Dipanggil player setelah reload mengambil n peluru: kurangi magazine di Inventory.
func consume_reserve(n: int) -> void:
	Inventory.take_rounds(_def(current).ammo_type, n)
	_player._update_ammo_ui()


# Panel AMMO di HUD bisa ditimpa script lain dengan angka revolver: samakan lagi kalau beda (kecuali lagi animasi reload).
func _sync_reserve() -> void:
	if is_revolver() or _player == null:
		return
	var hud = _get_hud()
	if hud == null or hud.is_busy or not ("ammo_label" in hud) or hud.ammo_label == null:
		return
	if hud.ammo_label.text != "%d / %d" % [_player.current_ammo, reserve_now()]:
		_player._update_ammo_ui()


func _on_inventory_changed() -> void:
	_refresh_owned()
	_sync_reserve()


func _def(id: StringName) -> Dictionary:
	for d in WEAPONS:
		if d.id == id:
			return d
	return WEAPONS[0]


# ---------------------------------------------------------------- kepemilikan

func _refresh_owned() -> void:
	var now: Array = []
	for d in WEAPONS:
		if d.item == &"" or Inventory.has_item(d.item):
			now.append(d.id)
	if now == _owned:
		return
	for d in WEAPONS:
		if now.has(d.id) and not _owned.has(d.id) and _announce:
			Inventory.message.emit("%s didapat  [tekan %d]" % [d.name, d.key])
		if _owned.has(d.id) and not now.has(d.id):
			_mags.erase(d.id)                           # senjata dibuang -> sisa magazine hilang
	_owned = now
	if not _owned.has(current):
		_apply(&"revolver")                             # senjata aktif hilang dari inventory -> balik ke revolver
	_rebuild()


# ---------------------------------------------------------------- UI

# Satu slot senjata: panel miring ala HUD, nomor tombol, nama, "isi magazine / total cadangan",
# dan bar segmen sebanyak isi magazine senjata itu.
class Slot extends Control:
	const SKEW := 9.0
	const BODY_H := 56.0
	const BG := Color(0.07, 0.10, 0.11, 0.92)
	const EDGE := Color(0.87, 0.65, 0.54)
	const CREAM := Color(0.92, 0.86, 0.8)
	const DARK := Color(0.07, 0.10, 0.11)
	const RED := Color(0.9, 0.3, 0.24)
	const RED_ON_PEACH := Color(0.6, 0.1, 0.07)

	var font: Font
	var wname := ""
	var key := 1
	var mag := 6
	var ammo := -1
	var reserve := -1
	var active := false
	var lift := 0.0:
		set(v):
			lift = v
			queue_redraw()
	var flash := 0.0:
		set(v):
			flash = v
			queue_redraw()

	func _init() -> void:
		font = ThemeDB.fallback_font

	func set_state(a: int, r: int, act: bool) -> void:
		if a == ammo and r == reserve and act == active:
			return
		ammo = a
		reserve = r
		active = act
		modulate = Color(1, 1, 1, 1.0 if act else 0.8)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var oy := 10.0 - 8.0 * lift                       # slot aktif terangkat
		var pts := PackedVector2Array([
			Vector2(SKEW, oy), Vector2(w, oy), Vector2(w - SKEW, oy + BODY_H), Vector2(0.0, oy + BODY_H)])
		draw_colored_polygon(pts, EDGE if active else BG)
		var closed: PackedVector2Array = pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, EDGE, 2.0, true)
		if flash > 0.0:
			draw_colored_polygon(pts, Color(1, 1, 1, 0.4 * flash))

		var fg: Color = DARK if active else CREAM
		var accent: Color = DARK if active else EDGE
		# nomor tombol
		draw_string(font, Vector2(13.0, oy + BODY_H * 0.5 + 9.0), str(key), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, accent)
		draw_line(Vector2(38.0, oy + 9.0), Vector2(33.0, oy + BODY_H - 9.0), Color(fg, 0.3), 1.5)
		# nama
		draw_string(font, Vector2(45.0, oy + 21.0), wname, HORIZONTAL_ALIGNMENT_LEFT, w - 45.0 - SKEW - 4.0, 15, fg)
		# isi magazine / total cadangan
		var mag_col: Color = fg
		if ammo <= 0:
			mag_col = RED_ON_PEACH if active else RED
		var res_col := Color(fg, 0.75)
		if reserve <= 0:
			res_col = RED_ON_PEACH if active else RED
		var ms := str(maxi(ammo, 0))
		var mw := font.get_string_size(ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		draw_string(font, Vector2(45.0, oy + 42.0), ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, mag_col)
		draw_string(font, Vector2(45.0 + mw + 4.0, oy + 42.0), "/ " + str(maxi(reserve, 0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, res_col)
		# bar segmen: jumlah garis = isi magazine senjata ini
		var x0 := 45.0
		var x1 := w - SKEW - 9.0
		var n := maxi(mag, 1)
		var gap := 1.0 if n > 12 else 2.0
		var sw := (x1 - x0 - gap * float(n - 1)) / float(n)
		var by := oy + BODY_H - 9.0
		for i in n:
			var c: Color = fg if i < ammo else Color(fg, 0.22)
			draw_rect(Rect2(x0 + float(i) * (sw + gap), by, maxf(sw, 1.0), 3.0), c)


func _rebuild() -> void:
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	_slots.clear()
	for d in WEAPONS:
		if not _owned.has(d.id):
			continue
		var sl := Slot.new()
		sl.font = _font
		sl.wname = d.name
		sl.key = int(d.key)
		sl.mag = int(d.mag)
		sl.custom_minimum_size = Vector2(slot_width, 66)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(sl)
		_slots[d.id] = sl
	_mark_active(false)
	_update_slots()


# Slot aktif terangkat + berkedip sebentar.
func _mark_active(animate: bool) -> void:
	for id in _slots:
		var sl: Slot = _slots[id]
		var target := 1.0 if id == current else 0.0
		var old = sl.get_meta("tw", null)
		if old is Tween and old.is_valid():
			old.kill()
		if animate:
			var tw := create_tween()
			tw.tween_property(sl, "lift", target, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			sl.set_meta("tw", tw)
			if id == current:
				sl.flash = 1.0
				create_tween().tween_property(sl, "flash", 0.0, 0.28)
		else:
			sl.lift = target


# Angka tiap slot: [isi magazine, total cadangan peluru senjata itu]
func _slot_numbers(id: StringName) -> Array:
	var d := _def(id)
	if id == current:
		return [_player.current_ammo, reserve_now()]
	var m := int(_mags.get(id, d.mag if start_loaded else 0))
	var r: int
	if id == &"revolver":
		r = _player.reserve_ammo                          # revolver tidak aktif: cadangannya tetap dipegang sistem lama
	else:
		r = Inventory.count_rounds(d.ammo_type)
	return [m, r]


func _update_slots() -> void:
	for id in _slots:
		var n := _slot_numbers(id)
		_slots[id].set_state(int(n[0]), int(n[1]), id == current)


func _process(_delta: float) -> void:
	var hud = _get_hud()
	var show: bool = hud != null and hud.visible and not hud.intro_mode and not get_tree().paused
	_root.visible = show
	if not show or _player == null:
		return
	_sync_t -= _delta
	if _sync_t <= 0.0:
		_sync_t = 0.15
		_sync_reserve()                                 # jaga cadangan tetap = peluru senjata aktif di Inventory
	_update_slots()


# ---------------------------------------------------------------- input

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		for d in WEAPONS:
			if int(e.physical_keycode) == KEY_1 + int(d.key) - 1:
				select(d.id)
				return
	elif wheel_switch and e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle(-1)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle(1)


func _cycle(dir: int) -> void:
	if _owned.size() < 2:
		return
	var i := _owned.find(current)
	var n: int = (i + dir + _owned.size()) % _owned.size()
	select(_owned[n])


# ---------------------------------------------------------------- panel AMMO HUD

# Jumlah garis di panel AMMO (hud_stats.gd) harus = isi magazine senjata aktif. Nama variabel "max peluru" di hud_stats.gd
# belum kulihat, jadi dicari otomatis dengan dua cara:
#   1. variabel angka yang namanya mengandung max/cap/slots/dll bersama ammo/mag/clip,
#   2. variabel angka bernama berbau ammo/max yang nilainya masih sama dengan isi magazine senjata sebelumnya
#      (itu tanda angka lama yang nyangkut, mis. 30 dari MP5 saat sekarang pegang revolver).
# Yang diubah dicetak di Output Godot ([weapon_manager] panel AMMO: ...).
func _set_stats_max(n: int, old: int = -1) -> void:
	var hud = _get_hud()
	if hud == null or not ("stats" in hud) or hud.stats == null:
		return
	var st = hud.stats
	var changed: Array = []
	var all_vars: Array = []
	for pr in st.get_property_list():
		if (int(pr.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var t := int(pr.type)
		if t != TYPE_INT and t != TYPE_FLOAT:
			continue
		var raw: String = String(pr.name)
		var nm := raw.to_lower()
		all_vars.append(raw)
		if nm.contains("reveal") or nm.contains("flash") or nm.contains("alpha") or nm.contains("hp") \
				or nm.contains("health") or nm.contains("reserve") or nm.contains("time"):
			continue
		var about_ammo := nm.contains("ammo") or nm.contains("mag") or nm.contains("clip") or nm.contains("bullet")
		var about_max := nm.contains("max") or nm.contains("cap") or nm.contains("slots") or nm.contains("cells") \
			or nm.contains("segments") or nm.contains("pips") or nm.contains("total") or nm.contains("size")
		var cur = st.get(pr.name)
		var by_name: bool = about_ammo and about_max
		var by_stale: bool = old > 0 and old != n and (about_ammo or about_max) and int(cur) == old
		if by_name or by_stale:
			st.set(pr.name, n if t == TYPE_INT else float(n))
			changed.append("%s: %s -> %d" % [raw, str(cur), n])
	if st.has_method("queue_redraw"):
		st.queue_redraw()
	if not changed.is_empty():
		print("[weapon_manager] panel AMMO: ", changed)
	elif not _stats_warned:
		_stats_warned = true
		print("[weapon_manager] variabel 'max peluru' di hud_stats.gd tidak ketemu otomatis. Variabel angka di sana: ", all_vars)


# ---------------------------------------------------------------- ganti senjata

func _blocked() -> bool:
	if _switching or get_tree().paused:
		return true
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:      # inventory / menu lagi terbuka
		return true
	var hud = _get_hud()
	if hud == null or hud.intro_mode or hud.is_busy:       # is_busy = lagi reload / animasi tembak
		return true
	var ch = _player.get("_charge")
	if ch != null and bool(ch.get("_charging")):           # lagi menahan charge Trigger (bukan sekadar item-nya dipakai)
		return true
	return false


func select(id: StringName) -> void:
	if id == current or not _owned.has(id) or _blocked():
		return
	var hud = _get_hud()
	_switching = true
	hud.is_busy = true                                      # nembak / reload / parry otomatis keblok selama animasi
	_mags[current] = _player.current_ammo

	var gun: AnimatedSprite2D = hud.gun
	if _recoil_tw != null and _recoil_tw.is_valid():
		_recoil_tw.kill()
	var base: Vector2 = gun.get_meta("base_pos", gun.position)    # posisi diam (bukan posisi tengah hentakan)
	gun.set_meta("base_pos", base)
	gun.position = base
	var tw := create_tween()
	tw.tween_property(gun, "position", base + Vector2(0, draw_down), draw_time_out).set_ease(Tween.EASE_IN)
	await tw.finished

	_apply(id)
	get_tree().call_group("sfx", "play", "gun_draw", -6.0)
	var tw2 := create_tween()
	tw2.tween_property(gun, "position", base, draw_time_in).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw2.finished

	if gun.sprite_frames != null and gun.sprite_frames.has_animation("idle"):
		gun.play("idle")
	hud.is_busy = false
	_switching = false



# Pasang senjata: magazine, sprite, UI. player.reserve_ammo tidak disentuh (lihat reserve_now()).
func _apply(id: StringName) -> void:
	var d := _def(id)
	current = id
	var old_mag: int = int(_player.max_ammo_per_clip)
	_player.max_ammo_per_clip = int(d.mag)
	_set_stats_max(int(d.mag), old_mag)
	_player.current_ammo = clampi(int(_mags.get(id, d.mag if start_loaded else 0)), 0, int(d.mag))
	if _player.has_method("_update_ammo_ui"):
		_player._update_ammo_ui()

	var hud = _get_hud()
	if hud != null and hud.gun != null:
		var p := "res://tangan/%s_frames.tres" % str(id)
		if id != &"revolver" and ResourceLoader.exists(p):
			hud.gun.sprite_frames = load(p)
			hud.gun.self_modulate = Color.WHITE
		else:
			if _base_frames != null:
				hud.gun.sprite_frames = _base_frames
			hud.gun.self_modulate = d.tint                  # placeholder: warna beda per senjata
	_mark_active(true)
	weapon_changed.emit(id)
