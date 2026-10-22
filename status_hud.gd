extends Node
## INDIKATOR STATUS (buff / debuff) di kiri bawah: ikon bulat + ring waktu + nama + sisa detik.
## Sekarang: POISON (terdeteksi otomatis saat player kena racun). Efek lain tinggal didaftarkan di STATUS.
##
## Pasang: tambah Node biasa bernama StatusHUD (mis. di intro.tscn atau scene player), pasang script ini.
## Efek lain dari mana saja (tanpa referensi class):
##     get_tree().call_group("status", "apply_status", "burn", 4.0)     # id harus ada di STATUS
##     get_tree().call_group("status", "clear_status", "burn")

@export_group("KILL SWITCH")
@export var enabled := true
@export_group("Pengaturan")
@export var margin_left := 50.0              # jarak dari tepi kiri
@export var margin_bottom := 168.0           # jarak dari tepi bawah (di atas panel HP)
@export var entry_width := 188.0
@export var entry_height := 42.0
@export var poison_default_time := 3.0       # dipakai kalau waktu racun asli tidak bisa dibaca
@export var poll_interval := 0.12
@export var debug_print := false             # cetak ke panel Output saat aktif / saat racun terdeteksi (matikan kalau sudah beres)

## Daftar efek. icon = bentuk gambar yang digambar lewat kode.
const STATUS := {
	"poison": {"name": "Poison", "color": Color(0.6, 0.82, 0.3), "icon": "drop"},
	"burn": {"name": "Burning", "color": Color(0.93, 0.5, 0.2), "icon": "flame"},
	"adrenaline": {"name": "Adrenaline", "color": Color(0.87, 0.45, 0.5), "icon": "bolt"},
	"slow": {"name": "Slowed", "color": Color(0.5, 0.65, 0.8), "icon": "slow"},
}
const TIME_PROPS := ["time_left", "remaining", "time_remaining", "left", "duration_left"]


## Satu baris status, digambar dengan bahasa visual HUD-mu: panel miring (skew), border tipis, aksen krem di kiri,
## ikon pixel, huruf Rajdhani, bar tipis bersegmen di bawah. Tanpa ring, tanpa gradien.
class Entry extends Control:
	const SKEW := 10.0
	const PANEL := Color("1c2828ee")
	const BORDER := Color("7d6354")
	const ACCENT := Color("dea68a")
	const TEXT := Color("eadccf")
	const ICONS := {
		"drop": ["...XX...", "...XX...", "..XXXX..", ".XXXXXX.", "XXHXXXXX", "XHXXXXXX", ".XXXXXX.", "..XXXX.."],
		"flame": ["....X...", "...XX...", "..XXXX.X", ".XXXXXXX", ".XXHXXXX", "XXXHXXXX", ".XXXXXX.", "..XXXX.."],
		"bolt": ["....XXX.", "...XXX..", "..XXX...", ".XXXXXX.", "..XXXX..", "...XX...", "..XX....", ".X......"],
		"slow": ["...XX...", "...XX...", "...XX...", "XXXXXXXX", ".XXXXXX.", "..XXXX..", "...XX...", "........"],
	}

	var col := Color.WHITE
	var icon := "drop"
	var title := ""
	var time_text := ""
	var frac := 1.0
	var pulse := false
	var reveal := 0.0
	var left := 99.0
	var font: Font
	var shown := 1.0              # frac yang digambar (dihaluskan)
	var flash := 0.0              # kilatan saat efek diperbarui
	var _t := 0.0

	func kick() -> void:
		flash = 1.0

	func _init(w: float, h: float) -> void:
		custom_minimum_size = Vector2(w, h)
		size = Vector2(w, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_t += delta
		var target := 1.0 if pulse else frac
		shown += (target - shown) * minf(1.0, delta * (16.0 if target > shown else 10.0))   # naik cepat, turun halus
		flash = maxf(flash - delta * 3.2, 0.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var sk := SKEW
		draw_set_transform(Vector2(-24.0 * (1.0 - reveal), 0.0), 0.0, Vector2.ONE)
		var body := PackedVector2Array([Vector2(sk, 0), Vector2(w, 0), Vector2(w - sk, h), Vector2(0, h)])
		draw_colored_polygon(body, PANEL.lerp(Color(1, 1, 1, 0.95), flash * 0.3))
		draw_polyline(PackedVector2Array([body[0], body[1], body[2], body[3], body[0]]), BORDER.lerp(ACCENT, flash), 1.5, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(sk, 0), Vector2(sk + 6.0, 0), Vector2(6.0, h), Vector2(0, h)]), ACCENT)
		# ikon pixel
		var ic := Color(col.r, col.g, col.b, 0.88 + 0.12 * sin(_t * 3.0))
		var rows: Array = ICONS.get(icon, ICONS["drop"])
		var px := 3.0
		var ix := sk + 16.0
		var iy := (h - 8.0 * px) * 0.5 - 3.0
		for y in rows.size():
			var line: String = rows[y]
			for x in line.length():
				var ch := line[x]
				if ch == "X":
					draw_rect(Rect2(ix + x * px, iy + y * px, px, px), ic)
				elif ch == "H":
					draw_rect(Rect2(ix + x * px, iy + y * px, px, px), col.lightened(0.55))
		# teks
		var f: Font = font if font else ThemeDB.fallback_font
		var tx := ix + 8.0 * px + 10.0
		draw_string(f, Vector2(tx, 20.0), title.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, TEXT)
		draw_string(f, Vector2(0.0, 20.0), time_text, HORIZONTAL_ALIGNMENT_RIGHT, w - sk - 10.0, 18, col.lightened(0.15))
		# bar tipis bersegmen
		var bx0 := ix
		var bx1 := w - sk - 10.0
		var by := h - 9.0
		var bh := 3.0
		draw_rect(Rect2(bx0, by, bx1 - bx0, bh), Color(0, 0, 0, 0.55))
		var a := 1.0
		var f2 := shown
		if pulse:
			a = 0.55 + 0.45 * sin(_t * 4.0)
		elif left < 1.0:
			a = 0.6 + 0.4 * sin(_t * 18.0)                    # hampir habis -> berkedip
		draw_rect(Rect2(bx0, by, (bx1 - bx0) * f2, bh), Color(col.r, col.g, col.b, a))
		for i in range(1, 4):
			var cx := bx0 + (bx1 - bx0) * float(i) / 4.0
			draw_line(Vector2(cx + 2.0, by), Vector2(cx - 2.0, by + bh), PANEL, 1.5)


var _layer: CanvasLayer
var _root: Control
var _rows := {}              # id -> {"entry", "left", "total", "node", "known"}
var _player: Node
var _poll := 0.0
var _font: Font


func _ready() -> void:
	if not enabled:
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("status")
	if ResourceLoader.exists("res://font/Rajdhani-Bold.ttf"):
		_font = load("res://font/Rajdhani-Bold.ttf")
	_layer = CanvasLayer.new()
	_layer.layer = 48
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	if debug_print:
		print("StatusHUD: aktif")


# ---------- API ----------
func apply_status(id: String, duration: float) -> void:
	if not STATUS.has(id):
		push_warning("StatusHUD: efek '%s' belum didaftarkan di STATUS" % id)
		return
	var e := _ensure(id)
	if e.left > 0.0 and duration > e.left + 0.3:
		e.entry.kick()
	e.left = duration
	e.total = duration
	e["dying"] = false
	e.node = null
	e.known = true


func clear_status(id: String) -> void:
	if _rows.has(id):
		_remove(id)


# ---------- internal ----------
func _ensure(id: String) -> Dictionary:
	if _rows.has(id):
		return _rows[id]
	var def: Dictionary = STATUS[id]
	var en := Entry.new(entry_width, entry_height)
	en.col = def.color
	en.icon = def.icon
	en.title = str(def.name)
	en.font = _font
	_root.add_child(en)
	en.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(en, "reveal", 1.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(en, "modulate:a", 1.0, 0.2)
	en.kick()
	var e := {"entry": en, "left": 0.0, "total": 0.0, "node": null, "known": false, "placed": false}
	_rows[id] = e
	return e


func _remove(id: String) -> void:
	if not _rows.has(id):
		return
	var e: Dictionary = _rows[id]
	if e.node != null or e.left > 0.0:                   # kena efek lagi sebelum sempat dihapus
		e["dying"] = false
		return
	_rows.erase(id)
	var en: Control = e.entry
	var tw := create_tween().set_parallel(true)
	tw.tween_property(en, "reveal", 0.0, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(en, "modulate:a", 0.0, 0.28)
	tw.chain().tween_callback(en.queue_free)


func _process(delta: float) -> void:
	_layer.visible = not get_tree().paused               # tidak tampil di atas menu pause
	if get_tree().paused:
		return
	_poll -= delta
	if _poll <= 0.0:
		_poll = poll_interval
		_scan_player()
	var vp := get_viewport().get_visible_rect().size
	var y := vp.y - margin_bottom
	for id in _rows.keys():
		var e: Dictionary = _rows[id]
		# efek yang dipantau lewat node: hilang saat node hilang
		if e.node != null:
			if not is_instance_valid(e.node) or not e.node.is_inside_tree():
				e.node = null
				e.left = 0.0
			else:
				var t := _probe_time(e.node)
				if t >= 0.0:
					if t > e.left + 0.3 and e.known:
						e.entry.kick()                          # racun diperbarui -> kilat
					e.left = t
					e.total = maxf(e.total, t)
					e.known = true
				else:
					e.left = maxf(e.left - delta, 0.0)        # waktu asli tidak terbaca -> hitung mundur perkiraan
					e.known = e.left > 0.0                     # lewat perkiraan tapi racun masih ada -> ring berdenyut
		elif e.left > 0.0:
			e.left -= delta
		var en: Entry = e.entry
		en.left = e.left
		if e.node != null and not e.known:
			en.pulse = true
			en.time_text = ""
		else:
			en.pulse = false
			en.frac = clampf(e.left / maxf(e.total, 0.01), 0.0, 1.0)
			en.time_text = "%.1fs" % maxf(e.left, 0.0)
		if e.node == null and e.left <= 0.0 and not e.get("dying", false):
			e["dying"] = true
			call_deferred("_remove", id)
	# susun dari bawah ke atas, tetap di tempat yang sama
	var idx := 0
	for id in _rows.keys():
		var e2: Dictionary = _rows[id]
		var row: Control = e2.entry
		var ty := y - float(idx + 1) * (entry_height + 6.0)
		if not e2.placed:
			row.position = Vector2(margin_left, ty)
			e2.placed = true
		else:
			row.position = Vector2(margin_left, lerpf(row.position.y, ty, 1.0 - exp(-delta * 14.0)))
		idx += 1


## Cari efek racun di player (node anak yang namanya / scriptnya mengandung "poison"), tanpa mengubah poison_dot.gd
func _scan_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			if debug_print:
				print("StatusHUD: player (group \"player\") tidak ketemu")
				debug_print = false
			return
	var found: Node = null
	var cands: Array = _player.get_children()
	var h := _player.get_node_or_null("Health")
	if h:
		cands.append_array(h.get_children())
	for n in cands:
		if _is_poison(n):
			found = n
			break
	if found:
		var e := _ensure("poison")
		if e.node != found:
			if debug_print:
				print("StatusHUD: racun terdeteksi (", found.name, ")")
			e.node = found
			e.left = poison_default_time
			e.total = poison_default_time
			e["dying"] = false
	elif _rows.has("poison") and _rows["poison"].node != null:
		_rows["poison"].node = null                       # node sudah hilang -> biarkan sisa waktu habis / hilang


func _is_poison(n: Node) -> bool:
	if "poison" in str(n.name).to_lower():
		return true
	var sc: Script = n.get_script()
	return sc != null and "poison" in sc.resource_path.to_lower()


## Coba baca sisa waktu dari node racun. -1 = tidak bisa dibaca.
func _probe_time(n: Node) -> float:
	if n is Timer:
		return (n as Timer).time_left
	for p in TIME_PROPS:
		if p in n:
			var v = n.get(p)
			if v is float or v is int:
				return maxf(float(v), 0.0)
	for c in n.get_children():
		if c is Timer:
			return (c as Timer).time_left
	return -1.0
